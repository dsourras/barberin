[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectId = "demo-barberin-e2e"
$root = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $root ".firebase"
$stdoutLog = Join-Path $logDir "e2e-emulators.stdout.log"
$stderrLog = Join-Path $logDir "e2e-emulators.stderr.log"
$firebaseCli = Join-Path $env:APPDATA "npm\firebase.cmd"

if (-not (Test-Path -LiteralPath $firebaseCli)) {
  throw "Firebase CLI was not found at $firebaseCli"
}

New-Item -ItemType Directory -Force -Path $logDir | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue $stdoutLog, $stderrLog

function Test-TcpPort {
  param([int]$Port)

  $client = [System.Net.Sockets.TcpClient]::new()
  try {
    $async = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
    return $async.AsyncWaitHandle.WaitOne(500) -and $client.Connected
  } finally {
    $client.Close()
  }
}

$emulatorProcess = Start-Process `
  -FilePath $firebaseCli `
  -ArgumentList @(
    "emulators:start",
    "--only",
    "auth,database,functions",
    "--project",
    $projectId,
    "--log-verbosity",
    "INFO"
  ) `
  -WorkingDirectory $root `
  -RedirectStandardOutput $stdoutLog `
  -RedirectStandardError $stderrLog `
  -PassThru `
  -WindowStyle Hidden

try {
  $ready = $false
  for ($attempt = 0; $attempt -lt 90; $attempt++) {
    Start-Sleep -Seconds 2
    if ($emulatorProcess.HasExited) {
      break
    }
    if ((Test-TcpPort 9099) -and (Test-TcpPort 9000) -and (Test-TcpPort 5001)) {
      $ready = $true
      break
    }
  }

  if (-not $ready) {
    Write-Output "E2E emulators did not become ready."
    if (Test-Path -LiteralPath $stdoutLog) {
      Get-Content -LiteralPath $stdoutLog -Tail 80
    }
    if (Test-Path -LiteralPath $stderrLog) {
      Get-Content -LiteralPath $stderrLog -Tail 80
    }
    exit 1
  }

  $functionsReady = $false
  for ($attempt = 0; $attempt -lt 90; $attempt++) {
    Start-Sleep -Seconds 1
    if ($emulatorProcess.HasExited) {
      break
    }
    if ((Test-Path -LiteralPath $stdoutLog) -and
        (Select-String -Path $stdoutLog -Pattern "Loaded functions definitions" -Quiet)) {
      $functionsReady = $true
      break
    }
  }
  if (-not $functionsReady) {
    Write-Output "Functions emulator did not finish loading definitions."
    if (Test-Path -LiteralPath $stdoutLog) {
      Get-Content -LiteralPath $stdoutLog -Tail 120
    }
    if (Test-Path -LiteralPath $stderrLog) {
      Get-Content -LiteralPath $stderrLog -Tail 120
    }
    exit 1
  }

  $env:GCLOUD_PROJECT = $projectId
  $env:GCP_PROJECT = $projectId
  $env:FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099"
  $env:FIREBASE_DATABASE_EMULATOR_HOST = "127.0.0.1:9000"
  $env:FUNCTIONS_EMULATOR = "true"

  Push-Location $root
  try {
    & npm --prefix functions run test:e2e
    if ($LASTEXITCODE -ne 0) {
      exit $LASTEXITCODE
    }
  } finally {
    Pop-Location
  }
} finally {
  & $firebaseCli emulators:stop --project $projectId 2>$null | Out-Null
  if (-not $emulatorProcess.HasExited) {
    Stop-Process -Id $emulatorProcess.Id -Force -ErrorAction SilentlyContinue
  }

  # The CLI can leave its Node/Java children behind when startup fails.
  $firebaseProcesses = @(Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -and
    $_.CommandLine -like "*firebase-tools*firebase.js*emulators:start*" -and
    $_.CommandLine -like "*$projectId*"
  })
  $firebaseProcessIds = @($firebaseProcesses | Select-Object -ExpandProperty ProcessId)
  if ($firebaseProcessIds.Count -gt 0) {
    Get-CimInstance Win32_Process | Where-Object {
      $firebaseProcessIds -contains $_.ParentProcessId
    } | ForEach-Object {
      Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
    $firebaseProcessIds | ForEach-Object {
      Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
    }
  }
}
