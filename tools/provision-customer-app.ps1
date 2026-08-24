[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ShopId,

    [string]$ShopName,
    [string]$ProjectId = "barbero-88d00",
    [string]$TemplatePath = "C:\Users\mypc2\Documents\Barberin Customer App Template",
    [string]$OutputRoot = "C:\Users\mypc2\Documents\Customer Apps",
    [ValidateSet("separate")]
    [string]$CustomerAppMode = "separate",
    [string]$LogoPath,
    [string]$IconPath,
    [switch]$SkipFirebaseRegistration,
    [switch]$SkipDatabaseUpdate,
    [switch]$SkipReleaseBuild,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $directory = Split-Path -Parent $Path
    if ($directory) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    [System.IO.File]::WriteAllText(
        $Path,
        $Content,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Invoke-Firebase {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $firebaseCommand = if ($env:OS -eq "Windows_NT") { "firebase.cmd" } else { "firebase" }
    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    try {
        $argumentString = ($Arguments | ForEach-Object {
            $argument = [string]$_
            if ($argument -match '[\s"]') {
                '"' + $argument.Replace('"', '\\"') + '"'
            } else {
                $argument
            }
        }) -join ' '
        $process = Start-Process -FilePath $firebaseCommand `
            -ArgumentList $argumentString `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath `
            -NoNewWindow -Wait -PassThru
        $output = if (Test-Path -LiteralPath $stdoutPath) {
            @(Get-Content -LiteralPath $stdoutPath)
        } else {
            @()
        }
        $stderr = if (Test-Path -LiteralPath $stderrPath) {
            @(Get-Content -LiteralPath $stderrPath)
        } else {
            @()
        }
        if ($process.ExitCode -ne 0) {
            throw "Firebase command failed: $firebaseCommand $($Arguments -join ' ')`n$($output + $stderr -join "`n")"
        }
        return ($output -join "`n")
    } finally {
        Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

function ConvertFrom-FirebaseJson {
    param([Parameter(Mandatory = $true)][string]$Output)

    $jsonText = $Output.TrimStart([char]0xFEFF).Trim()
    $jsonStart = $jsonText.IndexOf("{")
    if ($jsonStart -lt 0) {
        throw "Firebase did not return JSON. Output was:`n$Output"
    }

    $depth = 0
    $insideString = $false
    $escaped = $false
    $jsonEnd = -1
    for ($index = $jsonStart; $index -lt $jsonText.Length; $index++) {
        $character = $jsonText[$index]
        if ($insideString) {
            if ($escaped) {
                $escaped = $false
            } elseif ($character -eq '\') {
                $escaped = $true
            } elseif ($character -eq '"') {
                $insideString = $false
            }
            continue
        }
        if ($character -eq '"') {
            $insideString = $true
        } elseif ($character -eq '{') {
            $depth++
        } elseif ($character -eq '}') {
            $depth--
            if ($depth -eq 0) {
                $jsonEnd = $index
                break
            }
        }
    }
    if ($jsonEnd -lt $jsonStart) {
        throw "Firebase returned incomplete JSON. Output was:`n$Output"
    }

    $parsed = $jsonText.Substring($jsonStart, $jsonEnd - $jsonStart + 1) | ConvertFrom-Json
    if ($null -ne $parsed.result) {
        return $parsed.result
    }
    return $parsed
}

function Get-FirebaseJson {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    return ConvertFrom-FirebaseJson (Invoke-Firebase -Arguments $Arguments)
}

function Get-FirebaseAppByIdentifier {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("ANDROID", "IOS")][string]$Platform,
        [Parameter(Mandatory = $true)][string]$Identifier
    )

    $apps = Get-FirebaseJson -Arguments @("apps:list", $Platform, "--project", $ProjectId, "--json")
    foreach ($app in @($apps)) {
        if ($Platform -eq "ANDROID" -and "$($app.packageName)" -eq $Identifier) {
            return $app
        }
        if ($Platform -eq "IOS" -and "$($app.bundleId)" -eq $Identifier) {
            return $app
        }
    }
    return $null
}

function New-AsciiSlug {
    param([Parameter(Mandatory = $true)][string]$Value)

    $normalized = $Value.Normalize([Text.NormalizationForm]::FormD)
    $withoutMarks = [Text.RegularExpressions.Regex]::Replace(
        $normalized,
        "\p{Mn}",
        ""
    )
    $slug = [Text.RegularExpressions.Regex]::Replace(
        $withoutMarks.ToLowerInvariant(),
        "[^a-z0-9]+",
        ""
    )
    if ([string]::IsNullOrWhiteSpace($slug)) {
        return "shop"
    }
    return $slug.Substring(0, [Math]::Min(24, $slug.Length))
}

function New-ShortHash {
    param([Parameter(Mandatory = $true)][string]$Value)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant().Substring(0, 8)
    } finally {
        $sha.Dispose()
    }
}

function ConvertTo-DartString {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return ""
    }
    return $Value.Replace("\", "\\").Replace("'", "\'").Replace("`r", "").Replace("`n", "\n")
}

function Replace-InFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Replacement
    )

    $content = Get-Content -Raw -LiteralPath $Path
    $updated = $content -replace $Pattern, $Replacement
    if ($updated -eq $content) {
        throw "Expected text was not found in ${Path}: $Pattern"
    }
    Write-Utf8NoBom -Path $Path -Content $updated
}

function Copy-BrandAsset {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if ([string]::IsNullOrWhiteSpace($Source)) {
        return $false
    }
    $directory = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    if ($Source -match '^https?://') {
        Invoke-WebRequest -Uri $Source -OutFile $Destination -UseBasicParsing
    } elseif (Test-Path -LiteralPath $Source) {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    } else {
        throw "Brand asset was not found: $Source"
    }
    return $true
}

function Get-PlainText {
    param([Parameter(Mandatory = $true)][Security.SecureString]$SecureValue)

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

if ([string]::IsNullOrWhiteSpace($ShopId)) {
    throw "ShopId cannot be empty."
}
if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
    throw "Firebase CLI was not found in PATH."
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Flutter CLI was not found in PATH."
}
if (-not (Test-Path -LiteralPath $TemplatePath)) {
    throw "Customer app template was not found: $TemplatePath"
}

$shop = $null
if (-not $SkipDatabaseUpdate -or [string]::IsNullOrWhiteSpace($ShopName)) {
    $shop = Get-FirebaseJson -Arguments @(
        "database:get",
        "/shops/$ShopId",
        "--project",
        $ProjectId,
        "--json"
    )
    $ShopName = "$($shop.shopName)".Trim()
    if ([string]::IsNullOrWhiteSpace($ShopName)) {
        $ShopName = "$($shop.name)".Trim()
    }
}
if ([string]::IsNullOrWhiteSpace($ShopName)) {
    $ShopName = "Barber Shop"
}
$shopAddress = if ($null -ne $shop) { "$($shop.address)".Trim() } else { "" }
$shopPhone = if ($null -ne $shop) { "$($shop.ownerPhone)".Trim() } else { "" }
$shopEmail = if ($null -ne $shop) { "$($shop.ownerEmail)".Trim() } else { "" }
$shopLogoUrl = if ($null -ne $shop) {
    "$($shop.shopLogoUrl)".Trim()
} else {
    ""
}
$shopIconUrl = if ($null -ne $shop) {
    "$($shop.shopIconUrl)".Trim()
} else {
    ""
}

$existingCustomerApp = $null
if ($null -ne $shop -and $null -ne $shop.customerApp) {
    $existingCustomerApp = $shop.customerApp
}
$shopAccessToken = if ($null -ne $existingCustomerApp) {
    "$($existingCustomerApp.accessToken)".Trim()
} else {
    ""
}
if ($CustomerAppMode -eq "separate" -and
    [string]::IsNullOrWhiteSpace($shopAccessToken) -and
    -not $SkipReleaseBuild) {
    throw "Separate customer app is missing its shop access token. Run the owner provisioning/link flow first, then rerun this build."
}
$slug = New-AsciiSlug -Value $ShopName
$stableSlug = New-AsciiSlug -Value $ShopId
$hash = New-ShortHash -Value $ShopId
$generatedIdentifier = "com.barberin.customer.app$stableSlug$hash"
$packageName = if ($null -ne $existingCustomerApp -and "$($existingCustomerApp.packageName)".Trim()) {
    "$($existingCustomerApp.packageName)".Trim()
} else {
    $generatedIdentifier
}
$bundleId = if ($null -ne $existingCustomerApp -and "$($existingCustomerApp.bundleId)".Trim()) {
    "$($existingCustomerApp.bundleId)".Trim()
} else {
    $packageName
}
$workspaceName = "${slug}_${hash}_customer_app"
$outputPath = Join-Path $OutputRoot $workspaceName
$workspacePath = $outputPath
$buildVersion = ""
$aabPath = ""
$displayName = $ShopName.Trim()
$safeDisplayName = [Security.SecurityElement]::Escape($displayName)

if (Test-Path -LiteralPath $outputPath) {
    if (-not $Force) {
        throw "Output already exists: $outputPath. Use -Force only when you intentionally want to rebuild it."
    }
    Remove-Item -LiteralPath $outputPath -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$robocopyArguments = @(
    $TemplatePath,
    $outputPath,
    "/E",
    "/XD",
    ".dart_tool",
    "build",
    "windows",
    "linux",
    "macos",
    ".gradle",
    "/NFL",
    "/NDL",
    "/NJH",
    "/NJS",
    "/NP"
)
& robocopy @robocopyArguments | Out-Null
if ($LASTEXITCODE -ge 8) {
    throw "Could not copy the customer app template. Robocopy exit code: $LASTEXITCODE"
}

$configPath = Join-Path $outputPath "lib\app_config.dart"
$config = Get-Content -Raw -LiteralPath $configPath
$config = $config -replace "static const String shopId = '[^']*';", "static const String shopId = '$(ConvertTo-DartString $ShopId)';"
$config = $config -replace "static const String shopName = '[^']*';", "static const String shopName = '$(ConvertTo-DartString $displayName)';"
$config = $config -replace "static const String appDisplayName = '[^']*';", "static const String appDisplayName = '$(ConvertTo-DartString $displayName)';"
$config = $config -replace "static const String legalDisplayName = '[^']*';", "static const String legalDisplayName = '$(ConvertTo-DartString $displayName)';"
$config = $config -replace "static const String shopAddress = '[^']*';", "static const String shopAddress = '$(ConvertTo-DartString $shopAddress)';"
$config = $config -replace "static const String shopPhone = '[^']*';", "static const String shopPhone = '$(ConvertTo-DartString $shopPhone)';"
$config = $config -replace "static const String shopEmail = '[^']*';", "static const String shopEmail = '$(ConvertTo-DartString $shopEmail)';"
$config = $config -replace "static const String customerAppMode = '[^']*';", "static const String customerAppMode = '$(ConvertTo-DartString $CustomerAppMode)';"
$config = $config -replace "static const String shopAccessToken = '[^']*';", "static const String shopAccessToken = '$(ConvertTo-DartString $shopAccessToken)';"
Write-Utf8NoBom -Path $configPath -Content $config

$logoDestination = Join-Path $outputPath "assets\images\customer_app_logo.png"
$iconDestination = Join-Path $outputPath "assets\images\customer_app_icon.png"
$logoSource = if (-not [string]::IsNullOrWhiteSpace($LogoPath)) {
    $LogoPath
} else {
    $shopLogoUrl
}
$iconSource = if (-not [string]::IsNullOrWhiteSpace($IconPath)) {
    $IconPath
} else {
    $shopIconUrl
}
$logoCopied = $false
if (-not [string]::IsNullOrWhiteSpace($logoSource)) {
    $logoCopied = Copy-BrandAsset -Source $logoSource -Destination $logoDestination
}
if (-not [string]::IsNullOrWhiteSpace($iconSource)) {
    Copy-BrandAsset -Source $iconSource -Destination $iconDestination | Out-Null
} elseif ($logoCopied) {
    Copy-Item -LiteralPath $logoDestination -Destination $iconDestination -Force
}

$pubspecPath = Join-Path $outputPath "pubspec.yaml"
Replace-InFile -Path $pubspecPath -Pattern "(?m)^name:.*$" -Replacement "name: $workspaceName"
$pubspecContent = Get-Content -Raw -LiteralPath $pubspecPath
$versionMatch = [regex]::Match($pubspecContent, '(?m)^version:\s*([^\r\n]+)')
if ($versionMatch.Success) {
    $buildVersion = $versionMatch.Groups[1].Value.Trim()
}
$testRoot = Join-Path $outputPath "test"
if (Test-Path -LiteralPath $testRoot) {
    Get-ChildItem -LiteralPath $testRoot -Recurse -Filter "*.dart" -File | ForEach-Object {
        $testPath = $_.FullName
        $testContent = Get-Content -Raw -LiteralPath $testPath
        $testContent = $testContent.Replace(
            "package:barberin_customer_app_template/",
            "package:$workspaceName/"
        )
        Write-Utf8NoBom -Path $testPath -Content $testContent
    }
}

$gradlePath = Join-Path $outputPath "android\app\build.gradle.kts"
Replace-InFile -Path $gradlePath -Pattern 'namespace = "[^"]+"' -Replacement "namespace = `"$packageName`""
Replace-InFile -Path $gradlePath -Pattern 'applicationId = "[^"]+"' -Replacement "applicationId = `"$packageName`""

$manifestPath = Join-Path $outputPath "android\app\src\main\AndroidManifest.xml"
$manifestLabelReplacement = 'android:label="' + $safeDisplayName + '"'
Replace-InFile -Path $manifestPath -Pattern 'android:label="[^"]*"' -Replacement $manifestLabelReplacement

$kotlinRoot = Join-Path $outputPath "android\app\src\main\kotlin"
$oldActivity = Get-ChildItem -LiteralPath $kotlinRoot -Recurse -Filter "MainActivity.kt" -File | Select-Object -First 1
if ($null -eq $oldActivity) {
    throw "MainActivity.kt was not found in the customer app template."
}
$oldActivityPath = $oldActivity.FullName
$oldActivityDir = Split-Path -Parent $oldActivityPath
$newPackagePath = $packageName.Replace(".", "\")
$newActivityDir = Join-Path $outputPath "android\app\src\main\kotlin\$newPackagePath"
$newActivityPath = Join-Path $newActivityDir "MainActivity.kt"
New-Item -ItemType Directory -Force -Path $newActivityDir | Out-Null
Move-Item -LiteralPath $oldActivityPath -Destination $newActivityPath
Remove-Item -LiteralPath $oldActivityDir -Force -ErrorAction SilentlyContinue
$activity = Get-Content -Raw -LiteralPath $newActivityPath
$activity = $activity -replace "^package\s+[^\r\n]+", "package $packageName"
Write-Utf8NoBom -Path $newActivityPath -Content $activity

$pbxprojPath = Join-Path $outputPath "ios\Runner.xcodeproj\project.pbxproj"
$pbxproj = Get-Content -Raw -LiteralPath $pbxprojPath
$knownBundleIds = @(
    "com.thecutsociety.thecutsociety",
    "com.barberin.customer.template"
)
foreach ($knownBundleId in $knownBundleIds) {
    $pbxproj = $pbxproj.Replace(
        "$knownBundleId.RunnerTests",
        "$bundleId.RunnerTests"
    )
    $pbxproj = $pbxproj.Replace($knownBundleId, $bundleId)
}
Write-Utf8NoBom -Path $pbxprojPath -Content $pbxproj
$infoPath = Join-Path $outputPath "ios\Runner\Info.plist"
$info = Get-Content -Raw -LiteralPath $infoPath
$info = [regex]::Replace(
    $info,
    '(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)',
    { param($match) $match.Groups[1].Value + $safeDisplayName + $match.Groups[2].Value }
)
$info = [regex]::Replace(
    $info,
    '(<key>CFBundleName</key>\s*<string>)[^<]*(</string>)',
    { param($match) $match.Groups[1].Value + $slug + $match.Groups[2].Value }
)
Write-Utf8NoBom -Path $infoPath -Content $info

$firebaseAndroidAppId = ""
$firebaseIosAppId = ""
if (-not $SkipFirebaseRegistration) {
    $androidApp = Get-FirebaseAppByIdentifier -Platform ANDROID -Identifier $packageName
    if ($null -eq $androidApp) {
        Invoke-Firebase -Arguments @("apps:create", "android", $displayName, "-a", $packageName, "--project", $ProjectId) | Out-Null
        $androidApp = Get-FirebaseAppByIdentifier -Platform ANDROID -Identifier $packageName
    }
    if ($null -eq $androidApp) {
        throw "Firebase Android app was not found after creation: $packageName"
    }
    $firebaseAndroidAppId = "$($androidApp.appId)"
    Invoke-Firebase -Arguments @(
        "apps:sdkconfig",
        "ANDROID",
        $firebaseAndroidAppId,
        "-o",
        (Join-Path $outputPath "android\app\google-services.json")
    ) | Out-Null

    $iosApp = Get-FirebaseAppByIdentifier -Platform IOS -Identifier $bundleId
    if ($null -eq $iosApp) {
        Invoke-Firebase -Arguments @("apps:create", "ios", $displayName, "-b", $bundleId, "--project", $ProjectId) | Out-Null
        $iosApp = Get-FirebaseAppByIdentifier -Platform IOS -Identifier $bundleId
    }
    if ($null -eq $iosApp) {
        throw "Firebase iOS app was not found after creation: $bundleId"
    }
    $firebaseIosAppId = "$($iosApp.appId)"
    Invoke-Firebase -Arguments @(
        "apps:sdkconfig",
        "IOS",
        $firebaseIosAppId,
        "-o",
        (Join-Path $outputPath "ios\Runner\GoogleService-Info.plist")
    ) | Out-Null
}

$manifestPath = Join-Path $outputPath "customer-app-manifest.json"
$now = (Get-Date).ToUniversalTime().ToString("o")
$initialStatus = if ($SkipReleaseBuild) { "configured" } else { "provisioning" }
$manifest = [ordered]@{
    schemaVersion = 1
    shopId = $ShopId
    shopName = $displayName
    shopAddress = $shopAddress
    shopPhone = $shopPhone
    shopEmail = $shopEmail
    appDisplayName = $displayName
    mode = $CustomerAppMode
    packageName = $packageName
    bundleId = $bundleId
    firebaseProjectId = $ProjectId
    firebaseAndroidAppId = $firebaseAndroidAppId
    firebaseIosAppId = $firebaseIosAppId
    workspaceName = $workspaceName
    template = "barberin_customer_app"
    templateVersion = "1"
    status = $initialStatus
    createdAt = $now
    updatedAt = $now
    aabPath = ""
} | ConvertTo-Json -Depth 5
Write-Utf8NoBom -Path $manifestPath -Content $manifest

function Update-ShopCustomerAppMetadata {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [string]$Phase = "",
        [int]$ProgressPercent = 0,
        [string]$ErrorReason = "",
        [string]$AabPath = "",
        [string]$BuildVersion = ""
    )

    $updatedAt = (Get-Date).ToUniversalTime().ToString("o")
    $safeProgress = [Math]::Min(100, [Math]::Max(0, $ProgressPercent))
    $requestId = if ($null -ne $existingCustomerApp) {
        "$($existingCustomerApp.provisioningRequestId)".Trim()
    } else {
        ""
    }
    $attempt = 0
    $retryCount = 0
    if ($null -ne $existingCustomerApp) {
        [int]::TryParse(
            "$($existingCustomerApp.provisioningAttempt)",
            [ref]$attempt
        ) | Out-Null
        [int]::TryParse(
            "$($existingCustomerApp.retryCount)",
            [ref]$retryCount
        ) | Out-Null
    }
    $resolvedAabPath = if ($AabPath) { $AabPath } elseif ($null -ne $existingCustomerApp) {
        "$($existingCustomerApp.aabPath)".Trim()
    } else { "" }
    $resolvedBuildVersion = if ($BuildVersion) { $BuildVersion } elseif ($null -ne $existingCustomerApp) {
        "$($existingCustomerApp.buildVersion)".Trim()
    } else { "" }
    $safeErrorReason = if ($ErrorReason.Length -gt 512) {
        $ErrorReason.Substring(0, 512)
    } else {
        $ErrorReason
    }
    $metadataObject = [ordered]@{
        status = $Status
        shopId = $ShopId
        displayName = $displayName
        legalDisplayName = $displayName
        shopAddress = $shopAddress
        shopPhone = $shopPhone
        shopEmail = $shopEmail
        mode = $CustomerAppMode
        packageName = $packageName
        bundleId = $bundleId
        firebaseAndroidAppId = $firebaseAndroidAppId
        firebaseIosAppId = $firebaseIosAppId
        workspaceName = $workspaceName
        workspacePath = $workspacePath
        template = "barberin_customer_app"
        templateVersion = "1"
        provisioningRequestId = $requestId
        provisioningPhase = $Phase
        provisioningProgressPercent = $safeProgress
        provisioningErrorReason = $safeErrorReason
        provisioningAttempt = $attempt
        retryCount = $retryCount
        buildVersion = $resolvedBuildVersion
        aabPath = $resolvedAabPath
        provisionedAt = if ($null -ne $existingCustomerApp -and $existingCustomerApp.provisionedAt) {
            "$($existingCustomerApp.provisionedAt)"
        } else { $updatedAt }
        lastBuildAt = if ($Status -eq "built") { $updatedAt } elseif ($null -ne $existingCustomerApp) {
            "$($existingCustomerApp.lastBuildAt)".Trim()
        } else { "" }
        lastReleaseAt = if ($null -ne $existingCustomerApp) {
            "$($existingCustomerApp.lastReleaseAt)".Trim()
        } else { "" }
        createdAt = if ($null -ne $existingCustomerApp -and $existingCustomerApp.createdAt) {
            "$($existingCustomerApp.createdAt)"
        } else { $updatedAt }
        updatedAt = $updatedAt
    }
    $metadataPath = Join-Path $outputPath "customer-app-metadata.json"
    Write-Utf8NoBom -Path $metadataPath -Content ($metadataObject | ConvertTo-Json -Depth 5)
    if ($SkipDatabaseUpdate) {
        return
    }
    Invoke-Firebase -Arguments @(
        "database:update",
        "/shops/$ShopId/customerApp",
        $metadataPath,
        "--project",
        $ProjectId,
        "--force"
    ) | Out-Null
    if ($requestId) {
        $queueState = [ordered]@{
            requestId = $requestId
            shopId = $ShopId
            displayName = $displayName
            status = $Status
            phase = $Phase
            progressPercent = $safeProgress
            errorReason = $safeErrorReason
            workspacePath = $workspacePath
            aabPath = $resolvedAabPath
            buildVersion = $resolvedBuildVersion
            attempt = $attempt
            retryCount = $retryCount
            updatedAt = $updatedAt
        }
        $queuePath = Join-Path $outputPath "customer-app-provisioning-state.json"
        Write-Utf8NoBom -Path $queuePath -Content ($queueState | ConvertTo-Json -Depth 5)
        Invoke-Firebase -Arguments @(
            "database:update",
            "/customerAppProvisioningQueue/$requestId",
            $queuePath,
            "--project",
            $ProjectId,
            "--force"
        ) | Out-Null
        Invoke-Firebase -Arguments @(
            "database:update",
            "/shops/$ShopId/customerApp/provisioningHistory/$requestId",
            $queuePath,
            "--project",
            $ProjectId,
            "--force"
        ) | Out-Null
    }
}

trap {
    $failureReason = "$($_.Exception.Message)"
    try {
        Update-ShopCustomerAppMetadata `
            -Status "failed" `
            -Phase "failed" `
            -ProgressPercent 0 `
            -ErrorReason $failureReason
    } catch {
        Write-Warning "Could not persist provisioning failure: $($_.Exception.Message)"
    }
    throw
}

if (-not $SkipDatabaseUpdate) {
    $initialPhase = if ($SkipReleaseBuild) { "configured" } else { "workspace" }
    $initialProgress = if ($SkipReleaseBuild) { 100 } else { 10 }
    Update-ShopCustomerAppMetadata `
        -Status $initialStatus `
        -Phase $initialPhase `
        -ProgressPercent $initialProgress
}

if (-not $SkipReleaseBuild) {
    if (-not $SkipDatabaseUpdate) {
        Update-ShopCustomerAppMetadata `
            -Status "provisioning" `
            -Phase "signing" `
            -ProgressPercent 65 `
            -BuildVersion $buildVersion
    }
    if (-not (Get-Command keytool -ErrorAction SilentlyContinue)) {
        throw "keytool was not found in PATH. Install/configure the JDK before creating a release build."
    }

    $securePassword = Read-Host "Enter a password for the new upload keystore" -AsSecureString
    $keystorePassword = Get-PlainText -SecureValue $securePassword
    $keystoreFileName = "$workspaceName-upload.jks"
    $keystorePath = Join-Path $outputPath "android\$keystoreFileName"
    & keytool -genkeypair -v -keystore $keystorePath -storepass $keystorePassword -alias upload -keypass $keystorePassword -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=$displayName, OU=Barberin, O=Barberin, L=Larisa, ST=Thessaly, C=GR" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "keytool could not create the upload keystore."
    }

    $keyProperties = @(
        "storePassword=$keystorePassword",
        "keyPassword=$keystorePassword",
        "keyAlias=upload",
        "storeFile=$keystoreFileName"
    ) -join "`n"
    Write-Utf8NoBom -Path (Join-Path $outputPath "android\key.properties") -Content $keyProperties

    if (-not $SkipDatabaseUpdate) {
        Update-ShopCustomerAppMetadata `
            -Status "provisioning" `
            -Phase "building" `
            -ProgressPercent 80 `
            -BuildVersion $buildVersion
    }

    Push-Location $outputPath
    try {
        & flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed." }
        & dart run flutter_launcher_icons
        if ($LASTEXITCODE -ne 0) { throw "flutter_launcher_icons failed." }
        & flutter analyze
        if ($LASTEXITCODE -ne 0) { throw "flutter analyze failed." }
        & flutter build appbundle --release
        if ($LASTEXITCODE -ne 0) { throw "flutter build appbundle --release failed." }
    } finally {
        Pop-Location
    }

    $aabPath = Join-Path $outputPath "build\app\outputs\bundle\release\app-release.aab"
    $manifestObject = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    $manifestObject.status = "built"
    $manifestObject.updatedAt = (Get-Date).ToUniversalTime().ToString("o")
    $manifestObject.aabPath = $aabPath
    Write-Utf8NoBom -Path $manifestPath -Content ($manifestObject | ConvertTo-Json -Depth 5)
    if (-not $SkipDatabaseUpdate) {
        Update-ShopCustomerAppMetadata `
            -Status "built" `
            -Phase "complete" `
            -ProgressPercent 100 `
            -AabPath $aabPath `
            -BuildVersion $buildVersion
    }
}

Write-Host "Customer app workspace: $outputPath"
Write-Host "Android package: $packageName"
Write-Host "iOS bundle: $bundleId"
if ($SkipReleaseBuild) {
    Write-Host "Status: configured (release build skipped)"
} else {
    Write-Host "AAB: $(Join-Path $outputPath 'build\app\outputs\bundle\release\app-release.aab')"
}
$global:LASTEXITCODE = 0
