part of 'main.dart';

const String barberinPlatformAdminRole = 'platform_admin';

final ValueNotifier<bool> currentBarberinPlatformAdmin = ValueNotifier<bool>(
  false,
);

bool get isBarberinPlatformAdmin {
  return currentBarberinPlatformAdmin.value;
}

bool _hasBarberinPlatformAdminClaim(Map<String, dynamic>? claims) {
  final roles = claims?['roles'];
  return claims?['platformRole'] == barberinPlatformAdminRole ||
      claims?['platformAdmin'] == true ||
      roles is Map && roles['platformAdmin'] == true;
}

Future<bool> refreshBarberinPlatformAdminRole({
  bool forceRefresh = false,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    currentBarberinPlatformAdmin.value = false;
    return false;
  }

  final token = await user.getIdTokenResult(forceRefresh);
  final isAdmin = _hasBarberinPlatformAdminClaim(token.claims);
  currentBarberinPlatformAdmin.value = isAdmin;
  return isAdmin;
}

class PlatformAdminShopSummary {
  const PlatformAdminShopSummary({
    required this.shopId,
    required this.archivedForTesting,
    required this.shopName,
    required this.ownerName,
    required this.ownerEmail,
    required this.billingStatus,
    required this.billingPlan,
    required this.billingPlatform,
    required this.trialEndsAt,
    required this.currentPeriodEnd,
    required this.appMode,
    required this.appStatus,
    required this.packageName,
    required this.bundleId,
    required this.workspaceName,
    required this.templateVersion,
    required this.provisionedAt,
    required this.lastBuildAt,
    required this.lastReleaseAt,
    required this.updatedAt,
    required this.alertCount,
  });

  final String shopId;
  final bool archivedForTesting;
  final String shopName;
  final String ownerName;
  final String ownerEmail;
  final String billingStatus;
  final String billingPlan;
  final String billingPlatform;
  final String trialEndsAt;
  final String currentPeriodEnd;
  final String appMode;
  final String appStatus;
  final String packageName;
  final String bundleId;
  final String workspaceName;
  final String templateVersion;
  final String provisionedAt;
  final String lastBuildAt;
  final String lastReleaseAt;
  final String updatedAt;
  final int alertCount;

  factory PlatformAdminShopSummary.fromJson(Map<String, dynamic> json) {
    final billing = json['billing'] is Map
        ? (json['billing'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final app = json['customerApp'] is Map
        ? (json['customerApp'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return PlatformAdminShopSummary(
      shopId: '${json['shopId'] ?? ''}'.trim(),
      archivedForTesting: json['archivedForTesting'] == true,
      shopName: '${json['shopName'] ?? ''}'.trim(),
      ownerName: '${json['ownerName'] ?? ''}'.trim(),
      ownerEmail: '${json['ownerEmail'] ?? ''}'.trim(),
      billingStatus:
          '${billing['status'] ?? json['billingStatus'] ?? 'setup_required'}'
              .trim(),
      billingPlan:
          '${billing['plan'] ?? billing['selectedPlan'] ?? billing['storeProductId'] ?? ''}'
              .trim(),
      billingPlatform: '${billing['platform'] ?? ''}'.trim(),
      trialEndsAt: '${billing['trialEndsAt'] ?? ''}'.trim(),
      currentPeriodEnd: '${billing['currentPeriodEnd'] ?? ''}'.trim(),
      appMode: '${app['mode'] ?? 'separate'}'.trim(),
      appStatus: '${app['status'] ?? 'provisioning_required'}'.trim(),
      packageName: '${app['packageName'] ?? ''}'.trim(),
      bundleId: '${app['bundleId'] ?? ''}'.trim(),
      workspaceName: '${app['workspaceName'] ?? ''}'.trim(),
      templateVersion: '${app['templateVersion'] ?? ''}'.trim(),
      provisionedAt: '${app['provisionedAt'] ?? ''}'.trim(),
      lastBuildAt: '${app['lastBuildAt'] ?? ''}'.trim(),
      lastReleaseAt: '${app['lastReleaseAt'] ?? ''}'.trim(),
      updatedAt: '${app['updatedAt'] ?? ''}'.trim(),
      alertCount: json['alerts'] is List ? (json['alerts'] as List).length : 0,
    );
  }
}

class PlatformAdminDashboard {
  const PlatformAdminDashboard({
    required this.generatedAt,
    required this.totals,
    required this.shops,
    required this.activity,
    required this.provisioningQueue,
  });

  final String generatedAt;
  final Map<String, dynamic> totals;
  final List<PlatformAdminShopSummary> shops;
  final List<Map<String, dynamic>> activity;
  final List<PlatformAdminProvisioningItem> provisioningQueue;

  factory PlatformAdminDashboard.fromJson(Map<String, dynamic> json) {
    final rawShops = json['shops'] is List ? json['shops'] as List : const [];
    final rawActivity = json['activity'] is List
        ? json['activity'] as List
        : const [];
    final rawQueue = json['provisioningQueue'] is List
        ? json['provisioningQueue'] as List
        : const [];
    return PlatformAdminDashboard(
      generatedAt: '${json['generatedAt'] ?? ''}'.trim(),
      totals: json['totals'] is Map
          ? (json['totals'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{},
      shops: rawShops
          .whereType<Map>()
          .map(
            (item) =>
                PlatformAdminShopSummary.fromJson(item.cast<String, dynamic>()),
          )
          .toList(),
      activity: rawActivity
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList(),
      provisioningQueue: rawQueue
          .whereType<Map>()
          .map(
            (item) => PlatformAdminProvisioningItem.fromJson(
              item.cast<String, dynamic>(),
            ),
          )
          .toList(),
    );
  }

  int total(String key) => int.tryParse('${totals[key] ?? 0}') ?? 0;

  String totalLabel(String key) => '${totals[key] ?? 0}'.trim();
}

class PlatformAdminProvisioningItem {
  const PlatformAdminProvisioningItem({
    required this.requestId,
    required this.shopId,
    required this.displayName,
    required this.status,
    required this.phase,
    required this.progressPercent,
    required this.errorReason,
    required this.workspacePath,
    required this.aabPath,
    required this.buildVersion,
    required this.attempt,
    required this.retryCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final String requestId;
  final String shopId;
  final String displayName;
  final String status;
  final String phase;
  final int progressPercent;
  final String errorReason;
  final String workspacePath;
  final String aabPath;
  final String buildVersion;
  final int attempt;
  final int retryCount;
  final String createdAt;
  final String updatedAt;

  factory PlatformAdminProvisioningItem.fromJson(Map<String, dynamic> json) {
    int intValue(String key) => int.tryParse('${json[key] ?? 0}') ?? 0;
    return PlatformAdminProvisioningItem(
      requestId: '${json['requestId'] ?? json['id'] ?? ''}'.trim(),
      shopId: '${json['shopId'] ?? ''}'.trim(),
      displayName: '${json['displayName'] ?? json['shopName'] ?? ''}'.trim(),
      status: '${json['status'] ?? 'queued'}'.trim(),
      phase: '${json['phase'] ?? 'queued'}'.trim(),
      progressPercent: intValue('progressPercent'),
      errorReason: '${json['errorReason'] ?? ''}'.trim(),
      workspacePath: '${json['workspacePath'] ?? ''}'.trim(),
      aabPath: '${json['aabPath'] ?? ''}'.trim(),
      buildVersion: '${json['buildVersion'] ?? ''}'.trim(),
      attempt: intValue('attempt'),
      retryCount: intValue('retryCount'),
      createdAt: '${json['createdAt'] ?? ''}'.trim(),
      updatedAt: '${json['updatedAt'] ?? ''}'.trim(),
    );
  }
}

class PlatformAdminShopDetail {
  const PlatformAdminShopDetail({
    required this.shopId,
    required this.shopName,
    required this.address,
    required this.city,
    required this.ownerName,
    required this.ownerEmail,
    required this.ownerPhone,
    required this.createdAt,
    required this.updatedAt,
    required this.billingStatus,
    required this.billingPlan,
    required this.billingPlatform,
    required this.trialEndsAt,
    required this.currentPeriodEnd,
    required this.appStatus,
    required this.packageName,
    required this.bundleId,
    required this.workspaceName,
    required this.templateVersion,
    required this.provisionedAt,
    required this.lastBuildAt,
    required this.lastReleaseAt,
    required this.barberCount,
    required this.customerCount,
    required this.serviceCount,
    required this.appointmentCount,
    required this.notificationTokenCount,
    required this.barbers,
    required this.customers,
    required this.services,
    required this.appointments,
  });

  final String shopId;
  final String shopName;
  final String address;
  final String city;
  final String ownerName;
  final String ownerEmail;
  final String ownerPhone;
  final String createdAt;
  final String updatedAt;
  final String billingStatus;
  final String billingPlan;
  final String billingPlatform;
  final String trialEndsAt;
  final String currentPeriodEnd;
  final String appStatus;
  final String packageName;
  final String bundleId;
  final String workspaceName;
  final String templateVersion;
  final String provisionedAt;
  final String lastBuildAt;
  final String lastReleaseAt;
  final int barberCount;
  final int customerCount;
  final int serviceCount;
  final int appointmentCount;
  final int notificationTokenCount;
  final List<Map<String, dynamic>> barbers;
  final List<Map<String, dynamic>> customers;
  final List<Map<String, dynamic>> services;
  final List<Map<String, dynamic>> appointments;

  factory PlatformAdminShopDetail.fromJson(Map<String, dynamic> json) {
    final shop = json['shop'] is Map
        ? (json['shop'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final billing = shop['billing'] is Map
        ? (shop['billing'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final app = shop['customerApp'] is Map
        ? (shop['customerApp'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    List<Map<String, dynamic>> listValue(String key) {
      final raw = shop[key];
      if (raw is! List) return const <Map<String, dynamic>>[];
      return raw
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
    }

    final barbers = listValue('barbers');
    final customers = listValue('customers');
    final services = listValue('services');
    final appointments = listValue('appointments');
    return PlatformAdminShopDetail(
      shopId: '${json['shopId'] ?? ''}'.trim(),
      shopName: '${shop['shopName'] ?? ''}'.trim(),
      address: '${shop['address'] ?? ''}'.trim(),
      city: '${shop['city'] ?? ''}'.trim(),
      ownerName: '${shop['ownerName'] ?? ''}'.trim(),
      ownerEmail: '${shop['ownerEmail'] ?? ''}'.trim(),
      ownerPhone: '${shop['ownerPhone'] ?? ''}'.trim(),
      createdAt: '${shop['createdAt'] ?? ''}'.trim(),
      updatedAt: '${shop['updatedAt'] ?? ''}'.trim(),
      billingStatus: '${billing['status'] ?? 'setup_required'}'.trim(),
      billingPlan:
          '${billing['plan'] ?? billing['selectedPlan'] ?? billing['storeProductId'] ?? ''}'
              .trim(),
      billingPlatform: '${billing['platform'] ?? ''}'.trim(),
      trialEndsAt: '${billing['trialEndsAt'] ?? ''}'.trim(),
      currentPeriodEnd: '${billing['currentPeriodEnd'] ?? ''}'.trim(),
      appStatus: '${app['status'] ?? 'provisioning_required'}'.trim(),
      packageName: '${app['packageName'] ?? ''}'.trim(),
      bundleId: '${app['bundleId'] ?? ''}'.trim(),
      workspaceName: '${app['workspaceName'] ?? ''}'.trim(),
      templateVersion: '${app['templateVersion'] ?? ''}'.trim(),
      provisionedAt: '${app['provisionedAt'] ?? ''}'.trim(),
      lastBuildAt: '${app['lastBuildAt'] ?? ''}'.trim(),
      lastReleaseAt: '${app['lastReleaseAt'] ?? ''}'.trim(),
      barberCount: barbers.length,
      customerCount: customers.length,
      serviceCount: services.length,
      appointmentCount: appointments.length,
      notificationTokenCount:
          int.tryParse('${shop['notificationTokenCount'] ?? 0}') ?? 0,
      barbers: barbers,
      customers: customers,
      services: services,
      appointments: appointments,
    );
  }
}

class _PlatformShopDraft {
  const _PlatformShopDraft({
    required this.shopName,
    required this.ownerName,
    required this.ownerPhone,
    required this.ownerEmail,
    required this.address,
    required this.city,
    this.logoBase64,
    this.logoContentType,
    this.iconBase64,
    this.iconContentType,
  });

  final String shopName;
  final String ownerName;
  final String ownerPhone;
  final String ownerEmail;
  final String address;
  final String city;
  final String? logoBase64;
  final String? logoContentType;
  final String? iconBase64;
  final String? iconContentType;
}

class PlatformAdminRepository {
  static const String _functionsBaseUrl =
      'https://europe-west1-barbero-88d00.cloudfunctions.net';

  Future<String> _idToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !isBarberinPlatformAdmin) {
      throw Exception('platform-admin-only');
    }
    return (await user.getIdToken()) ?? '';
  }

  Future<PlatformAdminDashboard> loadDashboard() async {
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoGetPlatformAdminSummary'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'idToken': await _idToken()}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('platform-admin-summary-failed');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('platform-admin-summary-failed');
    }
    return PlatformAdminDashboard.fromJson(decoded);
  }

  Future<PlatformAdminShopDetail> loadShopDetail(String shopId) async {
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoGetPlatformShopDetail'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'idToken': await _idToken(), 'shopId': shopId}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('platform-shop-detail-failed');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('platform-shop-detail-failed');
    }
    return PlatformAdminShopDetail.fromJson(decoded);
  }

  Future<String> _createShop(_PlatformShopDraft draft) async {
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoCreatePlatformShop'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': await _idToken(),
        'shopName': draft.shopName,
        'ownerName': draft.ownerName,
        'ownerPhone': draft.ownerPhone,
        'ownerEmail': draft.ownerEmail,
        'address': draft.address,
        'city': draft.city,
        if (draft.logoBase64 != null) 'logoBase64': draft.logoBase64,
        if (draft.logoContentType != null)
          'logoContentType': draft.logoContentType,
        if (draft.iconBase64 != null) 'iconBase64': draft.iconBase64,
        if (draft.iconContentType != null)
          'iconContentType': draft.iconContentType,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('platform-shop-create-failed');
    }
    final decoded = jsonDecode(response.body);
    final shopId = decoded is Map ? '${decoded['shopId'] ?? ''}'.trim() : '';
    if (shopId.isEmpty) {
      throw Exception('platform-shop-create-failed');
    }
    return shopId;
  }

  Future<void> manageCustomerApp({
    required String shopId,
    required String action,
    String? status,
    String? displayName,
    String? packageName,
    String? bundleId,
    String? workspaceName,
    String? templateVersion,
  }) async {
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoManagePlatformCustomerApp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': await _idToken(),
        'shopId': shopId,
        'action': action,
        'status': ?status,
        'displayName': ?displayName,
        'packageName': ?packageName,
        'bundleId': ?bundleId,
        'workspaceName': ?workspaceName,
        'templateVersion': ?templateVersion,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('platform-customer-app-action-failed');
    }
  }
}

class PlatformAdminPage extends StatefulWidget {
  const PlatformAdminPage({super.key});

  @override
  State<PlatformAdminPage> createState() => _PlatformAdminPageState();
}

class _PlatformAdminPageState extends State<PlatformAdminPage> {
  final PlatformAdminRepository _repository = PlatformAdminRepository();
  final TextEditingController _searchController = TextEditingController();
  List<PlatformAdminShopSummary> _shops = const [];
  PlatformAdminDashboard? _dashboard;
  bool _loading = true;
  String? _error;
  String _billingFilter = 'all';
  String _appFilter = 'all';
  String _sortMode = 'updated';
  int _adminSectionIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dashboard = await _repository.loadDashboard();
      if (!mounted) return;
      setState(() {
        _dashboard = dashboard;
        _shops = dashboard.shops
            .where((shop) => !shop.archivedForTesting)
            .toList(growable: false);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Δεν ήταν δυνατή η φόρτωση του admin overview.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _dashboardValue(String key) {
    final value = _dashboard?.totals[key];
    return value == null ? '0' : '$value';
  }

  List<PlatformAdminShopSummary> get _visibleShops {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _shops.where((shop) {
      if (shop.archivedForTesting) return false;
      final searchable = [
        shop.shopName,
        shop.ownerName,
        shop.ownerEmail,
        shop.shopId,
        shop.packageName,
        shop.workspaceName,
        shop.billingPlan,
        shop.billingPlatform,
      ].join(' ').toLowerCase();
      final matchesQuery = query.isEmpty || searchable.contains(query);
      final matchesBilling =
          _billingFilter == 'all' || shop.billingStatus == _billingFilter;
      final matchesApp = _appFilter == 'all' || shop.appStatus == _appFilter;
      return matchesQuery && matchesBilling && matchesApp;
    }).toList();

    filtered.sort((left, right) {
      switch (_sortMode) {
        case 'name':
          return left.shopName.toLowerCase().compareTo(
            right.shopName.toLowerCase(),
          );
        case 'billing':
          return left.billingStatus.compareTo(right.billingStatus);
        case 'app':
          return left.appStatus.compareTo(right.appStatus);
        default:
          return right.updatedAt.compareTo(left.updatedAt);
      }
    });
    return filtered;
  }

  String _billingLabel(String value) {
    switch (value) {
      case 'active':
        return 'Ενεργά';
      case 'trialing':
        return 'Σε δοκιμή';
      case 'grace_period':
        return 'Περίοδος χάριτος';
      case 'expired':
        return 'Ληγμένα';
      case 'setup_required':
        return 'Χωρίς billing';
      default:
        return 'Όλα τα billing';
    }
  }

  String _billingStatusLabel(String value) {
    switch (value) {
      case 'active':
        return 'Ενεργή';
      case 'trialing':
        return 'Σε trial';
      case 'grace_period':
        return 'Σε περίοδο χάριτος';
      case 'expired':
        return 'Ληγμένη';
      case 'setup_required':
        return 'Δεν έχει ρυθμιστεί';
      default:
        return value.isEmpty ? '—' : value;
    }
  }

  String _appFilterLabel(String value) {
    switch (value) {
      case 'provisioning_required':
        return 'Αναμονή';
      case 'provisioning':
        return 'Σε δημιουργία';
      case 'configured':
        return 'Ρυθμισμένη';
      case 'built':
        return 'Έτοιμη';
      case 'released':
        return 'Δημοσιευμένη';
      case 'failed':
        return 'Αποτυχία';
      default:
        return 'Όλες οι εφαρμογές';
    }
  }

  String _sortLabel(String value) {
    switch (value) {
      case 'name':
        return 'Όνομα';
      case 'billing':
        return 'Συνδρομή';
      case 'app':
        return 'Κατάσταση εφαρμογής';
      default:
        return 'Πρόσφατη ενημέρωση';
    }
  }

  Future<void> _showShopDetail(PlatformAdminShopSummary shop) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlatformAdminShopDetailPage(
          repository: _repository,
          shopId: shop.shopId,
          fallbackName: shop.shopName,
        ),
      ),
    );
  }

  String _provisioningPhaseLabel(String phase) {
    switch (phase) {
      case 'workspace':
        return 'Δημιουργία workspace';
      case 'signing':
        return 'Signing';
      case 'building':
        return 'Build';
      case 'complete':
        return 'Ολοκληρώθηκε';
      case 'failed':
        return 'Απέτυχε';
      case 'configured':
        return 'Ρυθμισμένο';
      default:
        return 'Σε αναμονή';
    }
  }

  Future<void> _showProvisioningDetail(
    PlatformAdminProvisioningItem item,
  ) async {
    final shop = _shops.cast<PlatformAdminShopSummary?>().firstWhere(
      (candidate) => candidate?.shopId == item.shopId,
      orElse: () => null,
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.barberinSurface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.displayName.isEmpty ? item.shopId : item.displayName,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: context.barberinTextPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Provisioning attempt ${item.attempt == 0 ? '—' : item.attempt}',
                style: TextStyle(
                  fontSize: 11,
                  color: context.barberinTextSecondary,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '${_provisioningPhaseLabel(item.phase)} · ${item.progressPercent}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.barberinTextPrimary,
                ),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (item.progressPercent.clamp(0, 100)) / 100,
                color: context.barberinAccent,
                backgroundColor: context.barberinBorder,
              ),
              const SizedBox(height: 14),
              _AdminDetailSection(
                title: 'Κατάσταση',
                values: [
                  _AdminDetailRow(label: 'Status', value: item.status),
                  _AdminDetailRow(
                    label: 'Phase',
                    value: _provisioningPhaseLabel(item.phase),
                  ),
                  _AdminDetailRow(
                    label: 'Retry count',
                    value: '${item.retryCount}',
                  ),
                  _AdminDetailRow(label: 'Request ID', value: item.requestId),
                  _AdminDetailRow(label: 'Updated', value: item.updatedAt),
                ],
              ),
              _AdminDetailSection(
                title: 'Build artifacts',
                values: [
                  _AdminDetailRow(
                    label: 'Workspace path',
                    value: item.workspacePath,
                  ),
                  _AdminDetailRow(
                    label: 'Build version',
                    value: item.buildVersion,
                  ),
                  _AdminDetailRow(label: 'AAB path', value: item.aabPath),
                ],
              ),
              if (item.errorReason.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Blocker / error reason',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  item.errorReason,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.barberinTextPrimary,
                  ),
                ),
              ],
              if (shop != null &&
                  (item.status == 'failed' || item.phase == 'failed')) ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      await _runAction(shop, action: 'request_provisioning');
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Επανάληψη provisioning'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createShop(_PlatformShopDraft draft) async {
    setState(() => _loading = true);
    try {
      final shopId = await _repository._createShop(draft);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Το shop δημιουργήθηκε με ID $shopId και μπήκε σε provisioning.',
          ),
        ),
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Δεν ήταν δυνατή η δημιουργία του shop.')),
      );
    }
  }

  Future<void> _showCreateShopDialog() async {
    final shopNameController = TextEditingController();
    final ownerNameController = TextEditingController();
    final ownerPhoneController = TextEditingController();
    final ownerEmailController = TextEditingController();
    final addressController = TextEditingController();
    final cityController = TextEditingController();
    try {
      final draft = await showDialog<_PlatformShopDraft>(
        context: context,
        builder: (dialogContext) {
          XFile? logoFile;
          XFile? iconFile;
          String? errorText;
          var saving = false;

          Future<XFile?> pickBrandAsset() async {
            final file = await openFile(
              acceptedTypeGroups: const [
                XTypeGroup(label: 'Images', extensions: ['png', 'jpg', 'jpeg']),
              ],
            );
            if (file == null) return null;
            if (await file.length() > 5 * 1024 * 1024) {
              errorText = 'Κάθε εικόνα πρέπει να είναι έως 5 MB.';
              return null;
            }
            return file;
          }

          String contentTypeFor(XFile file) {
            final name = file.name.toLowerCase();
            return name.endsWith('.png') ? 'image/png' : 'image/jpeg';
          }

          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Νέο shop'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: shopNameController,
                        decoration: const InputDecoration(
                          labelText: 'Όνομα shop *',
                        ),
                      ),
                      TextField(
                        controller: ownerNameController,
                        decoration: const InputDecoration(
                          labelText: 'Όνομα owner *',
                        ),
                      ),
                      TextField(
                        controller: ownerPhoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Τηλέφωνο owner *',
                        ),
                      ),
                      TextField(
                        controller: ownerEmailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email owner *',
                        ),
                      ),
                      TextField(
                        controller: addressController,
                        decoration: const InputDecoration(
                          labelText: 'Διεύθυνση *',
                        ),
                      ),
                      TextField(
                        controller: cityController,
                        decoration: const InputDecoration(labelText: 'Πόλη *'),
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.image_outlined),
                        title: const Text('Logo shop'),
                        subtitle: Text(
                          logoFile?.name ?? 'PNG ή JPEG, έως 5 MB',
                        ),
                        trailing: TextButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  final file = await pickBrandAsset();
                                  if (file == null) {
                                    setDialogState(() {});
                                    return;
                                  }
                                  setDialogState(() => logoFile = file);
                                },
                          child: const Text('Επιλογή'),
                        ),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.apps_outlined),
                        title: const Text('App icon'),
                        subtitle: Text(
                          iconFile?.name ?? 'Προαιρετικό PNG ή JPEG, έως 5 MB',
                        ),
                        trailing: TextButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  final file = await pickBrandAsset();
                                  if (file == null) {
                                    setDialogState(() {});
                                    return;
                                  }
                                  setDialogState(() => iconFile = file);
                                },
                          child: const Text('Επιλογή'),
                        ),
                      ),
                      if (errorText != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            errorText!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Άκυρο'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final values = [
                            shopNameController,
                            ownerNameController,
                            ownerPhoneController,
                            ownerEmailController,
                            addressController,
                            cityController,
                          ];
                          if (values.any(
                            (controller) => controller.text.trim().isEmpty,
                          )) {
                            setDialogState(
                              () => errorText =
                                  'Συμπλήρωσε όλα τα υποχρεωτικά πεδία.',
                            );
                            return;
                          }
                          setDialogState(() {
                            saving = true;
                            errorText = null;
                          });
                          final logoBytes = logoFile == null
                              ? null
                              : base64Encode(await logoFile!.readAsBytes());
                          final iconBytes = iconFile == null
                              ? null
                              : base64Encode(await iconFile!.readAsBytes());
                          if (!dialogContext.mounted) return;
                          Navigator.of(dialogContext).pop(
                            _PlatformShopDraft(
                              shopName: shopNameController.text.trim(),
                              ownerName: ownerNameController.text.trim(),
                              ownerPhone: ownerPhoneController.text.trim(),
                              ownerEmail: ownerEmailController.text.trim(),
                              address: addressController.text.trim(),
                              city: cityController.text.trim(),
                              logoBase64: logoBytes,
                              logoContentType: logoFile == null
                                  ? null
                                  : contentTypeFor(logoFile!),
                              iconBase64: iconBytes,
                              iconContentType: iconFile == null
                                  ? null
                                  : contentTypeFor(iconFile!),
                            ),
                          );
                        },
                  child: const Text('Δημιουργία shop'),
                ),
              ],
            ),
          );
        },
      );
      if (draft != null && mounted) {
        await _createShop(draft);
      }
    } finally {
      shopNameController.dispose();
      ownerNameController.dispose();
      ownerPhoneController.dispose();
      ownerEmailController.dispose();
      addressController.dispose();
      cityController.dispose();
    }
  }

  Future<void> _runAction(
    PlatformAdminShopSummary shop, {
    required String action,
    String? status,
    String? packageName,
    String? bundleId,
    String? workspaceName,
    String? templateVersion,
  }) async {
    try {
      await _repository.manageCustomerApp(
        shopId: shop.shopId,
        action: action,
        status: status,
        displayName: shop.shopName,
        packageName: packageName,
        bundleId: bundleId,
        workspaceName: workspaceName,
        templateVersion: templateVersion,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'request_provisioning'
                ? 'Το αίτημα δημιουργίας εφαρμογής καταχωρίστηκε.'
                : 'Η κατάσταση της εφαρμογής του shop ενημερώθηκε.',
          ),
        ),
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Δεν ήταν δυνατή η ενημέρωση της εφαρμογής του shop.'),
        ),
      );
    }
  }

  Future<void> _showShopActions(PlatformAdminShopSummary shop) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.barberinSurface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                shop.shopName,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: context.barberinTextPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Εφαρμογή shop',
                style: TextStyle(color: context.barberinTextSecondary),
              ),
              const SizedBox(height: 18),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.insights_outlined),
                title: const Text('Προβολή στοιχείων shop'),
                subtitle: const Text(
                  'Metrics, ομάδα, πελάτες, υπηρεσίες και ραντεβού.',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _showShopDetail(shop);
                },
              ),
              if (shop.appStatus == 'provisioning_required' ||
                  shop.appStatus == 'failed')
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.rocket_launch_outlined),
                  title: const Text('Δημιουργία εφαρμογής shop'),
                  subtitle: const Text(
                    'Καταχωρίζει αίτημα για δημιουργία του app.',
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _runAction(shop, action: 'request_provisioning');
                  },
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sync_rounded),
                title: const Text('Συγχρονισμός υπάρχοντος app'),
                subtitle: const Text(
                  'Καταχώρισε package, workspace και build status.',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _showSyncDialog(shop);
                },
              ),
              if (shop.appStatus == 'built')
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.publish_outlined),
                  title: const Text('Σήμανση ως released'),
                  subtitle: const Text(
                    'Χρησιμοποίησέ το μόνο αφού ανέβει σε store track.',
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _runAction(
                      shop,
                      action: 'set_status',
                      status: 'released',
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSyncDialog(PlatformAdminShopSummary shop) async {
    final packageController = TextEditingController(text: shop.packageName);
    final bundleController = TextEditingController(text: shop.bundleId);
    final workspaceController = TextEditingController(text: shop.workspaceName);
    final templateController = TextEditingController(
      text: shop.templateVersion.isEmpty ? '1' : shop.templateVersion,
    );
    var status = shop.appStatus == 'released' ? 'released' : 'built';
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Συγχρονισμός υπάρχοντος app'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: packageController,
                    decoration: const InputDecoration(
                      labelText: 'Android package name',
                    ),
                  ),
                  TextField(
                    controller: bundleController,
                    decoration: const InputDecoration(
                      labelText: 'iOS bundle ID',
                    ),
                  ),
                  TextField(
                    controller: workspaceController,
                    decoration: const InputDecoration(
                      labelText: 'Workspace name',
                    ),
                  ),
                  TextField(
                    controller: templateController,
                    decoration: const InputDecoration(
                      labelText: 'Template version',
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Κατάσταση'),
                    items: const [
                      DropdownMenuItem(
                        value: 'configured',
                        child: Text('Configured'),
                      ),
                      DropdownMenuItem(value: 'built', child: Text('Built')),
                      DropdownMenuItem(
                        value: 'released',
                        child: Text('Released'),
                      ),
                    ],
                    onChanged: (value) {
                      setDialogState(() => status = value ?? 'built');
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Άκυρο'),
              ),
              FilledButton(
                onPressed: () {
                  if (packageController.text.trim().isEmpty ||
                      bundleController.text.trim().isEmpty ||
                      workspaceController.text.trim().isEmpty) {
                    return;
                  }
                  Navigator.of(dialogContext).pop();
                  _runAction(
                    shop,
                    action: 'sync_existing',
                    status: status,
                    packageName: packageController.text.trim(),
                    bundleId: bundleController.text.trim(),
                    workspaceName: workspaceController.text.trim(),
                    templateVersion: templateController.text.trim(),
                  );
                },
                child: const Text('Συγχρονισμός'),
              ),
            ],
          ),
        ),
      );
    } finally {
      packageController.dispose();
      bundleController.dispose();
      workspaceController.dispose();
      templateController.dispose();
    }
  }

  String _appStatusLabel(String status) {
    switch (status) {
      case 'released':
        return 'Δημοσιευμένο';
      case 'built':
        return 'Έτοιμο build';
      case 'configured':
        return 'Ρυθμισμένο';
      case 'provisioning':
        return 'Σε δημιουργία';
      case 'failed':
        return 'Αποτυχία';
      default:
        return 'Αναμονή δημιουργίας';
    }
  }

  Color _appStatusColor(BuildContext context, String status) {
    switch (status) {
      case 'released':
        return const Color(0xFF2D7A58);
      case 'built':
        return const Color(0xFF476D9C);
      case 'configured':
        return const Color(0xFF6B657D);
      case 'failed':
        return const Color(0xFFAE5656);
      default:
        return context.barberinTextSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isBarberinPlatformAdmin) {
      return const SizedBox.shrink();
    }

    final useDesktopShell = _useDesktopBarberShell(context);
    final workspace = _buildAdminWorkspace(context, useDesktopShell);
    if (useDesktopShell) {
      return _PlatformAdminDesktopShell(
        currentIndex: _adminSectionIndex,
        onTabTap: (index) => setState(() => _adminSectionIndex = index),
        onBack: () => Navigator.of(context).maybePop(),
        child: workspace,
      );
    }

    return Scaffold(
      backgroundColor: context.barberinBackground,
      body: SafeArea(
        child: Column(
          children: [
            _PlatformAdminMobileHeader(
              onMenu: () => _showAdminNavigationSheet(context),
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(child: workspace),
          ],
        ),
      ),
      bottomNavigationBar: _PlatformAdminBottomBar(
        currentIndex: _adminSectionIndex,
        onTap: (index) => setState(() => _adminSectionIndex = index),
      ),
    );
  }

  Widget _buildAdminWorkspace(BuildContext context, bool desktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (desktop) _buildAdminHeader(context),
        Expanded(child: _buildAdminSection(context)),
      ],
    );
  }

  Widget _buildAdminHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _adminSectionTitle(_adminSectionIndex),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: context.barberinTextPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Κεντρική διαχείριση καταστημάτων και εφαρμογών πελατών.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: context.barberinTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Νέο κατάστημα',
            onPressed: _loading ? null : _showCreateShopDialog,
            icon: const Icon(Icons.add_business_outlined),
            color: context.barberinTextPrimary,
          ),
          IconButton(
            tooltip: 'Ανανέωση',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            color: context.barberinTextPrimary,
          ),
        ],
      ),
    );
  }

  String _adminSectionTitle(int index) {
    switch (index) {
      case 1:
        return 'Καταστήματα';
      case 2:
        return 'Δημιουργία εφαρμογών';
      case 3:
        return 'Συνδρομές';
      case 4:
        return 'Δραστηριότητα';
      default:
        return 'Επισκόπηση';
    }
  }

  Widget _buildAdminSection(BuildContext context) {
    if (_loading && _dashboard == null) {
      return Center(
        child: CircularProgressIndicator(color: context.barberinAccent),
      );
    }
    if (_error != null && _dashboard == null) {
      return Center(
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.barberinTextSecondary),
        ),
      );
    }
    final dashboard = _dashboard;
    if (dashboard == null) {
      return const SizedBox.shrink();
    }

    switch (_adminSectionIndex) {
      case 1:
        return _buildAdminShops(context);
      case 2:
        return _buildAdminProvisioning(context, dashboard);
      case 3:
        return _buildAdminBilling(context);
      case 4:
        return _buildAdminActivity(context, dashboard);
      default:
        return _buildAdminOverview(context, dashboard);
    }
  }

  Widget _buildAdminOverview(
    BuildContext context,
    PlatformAdminDashboard dashboard,
  ) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        Wrap(
          spacing: 28,
          runSpacing: 16,
          children: [
            _AdminMetric(
              label: 'Καταστήματα',
              value: _dashboardValue('shopCount'),
            ),
            _AdminMetric(
              label: 'Ραντεβού',
              value: _dashboardValue('totalAppointments'),
            ),
            _AdminMetric(
              label: 'Έσοδα',
              value: _dashboardValue('actualRevenue'),
            ),
            _AdminMetric(
              label: 'Πληρότητα',
              value: '${_dashboardValue('occupancyPercent')}%',
            ),
            _AdminMetric(
              label: 'Εφαρμογές σε αναμονή',
              value: _dashboardValue('appsPending'),
            ),
            _AdminMetric(
              label: 'Ειδοποιήσεις',
              value: _dashboardValue('alerts'),
            ),
          ],
        ),
        _AdminDashboardSections(
          dashboard: dashboard,
          onOpenProvisioning: _showProvisioningDetail,
        ),
        _AdminSectionTitle(title: 'Γρήγορες ενέργειες'),
        _AdminFeedRow(
          leading: 'Προβολή όλων των καταστημάτων',
          detail: '${_shops.length}',
          onTap: () => setState(() => _adminSectionIndex = 1),
        ),
        _AdminFeedRow(
          leading: 'Ουρά δημιουργίας εφαρμογών',
          detail: '${dashboard.provisioningQueue.length}',
          onTap: () => setState(() => _adminSectionIndex = 2),
        ),
      ],
    );
  }

  Widget _buildAdminShops(BuildContext context) {
    final visibleShops = _visibleShops;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Αναζήτηση καταστήματος, ιδιοκτήτη ή email',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Καθαρισμός',
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        _buildAdminFilters(context),
        const SizedBox(height: 12),
        Text(
          '${visibleShops.length} από ${_shops.length} καταστήματα',
          style: TextStyle(fontSize: 11, color: context.barberinTextSecondary),
        ),
        const SizedBox(height: 8),
        if (visibleShops.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Text(
              _shops.isEmpty
                  ? 'Δεν υπάρχουν καταχωρισμένα καταστήματα.'
                  : 'Δεν βρέθηκαν καταστήματα με αυτά τα κριτήρια.',
              style: TextStyle(color: context.barberinTextSecondary),
            ),
          )
        else
          for (var index = 0; index < visibleShops.length; index++) ...[
            if (index > 0) Divider(height: 1, color: context.barberinBorder),
            _buildAdminShopRow(context, visibleShops[index]),
          ],
      ],
    );
  }

  Widget _buildAdminFilters(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        _AdminFilterDropdown(
          width: 180,
          label: 'Συνδρομή',
          value: _billingFilter,
          items: const [
            'all',
            'active',
            'trialing',
            'grace_period',
            'expired',
            'setup_required',
          ],
          labelBuilder: _billingLabel,
          onChanged: (value) => setState(() => _billingFilter = value),
        ),
        _AdminFilterDropdown(
          width: 190,
          label: 'Εφαρμογή',
          value: _appFilter,
          items: const [
            'all',
            'provisioning_required',
            'provisioning',
            'configured',
            'built',
            'released',
            'failed',
          ],
          labelBuilder: _appFilterLabel,
          onChanged: (value) => setState(() => _appFilter = value),
        ),
        _AdminFilterDropdown(
          width: 190,
          label: 'Ταξινόμηση',
          value: _sortMode,
          items: const ['updated', 'name', 'billing', 'app'],
          labelBuilder: _sortLabel,
          onChanged: (value) => setState(() => _sortMode = value),
        ),
      ],
    );
  }

  Widget _buildAdminShopRow(
    BuildContext context,
    PlatformAdminShopSummary shop,
  ) {
    final statusColor = _appStatusColor(context, shop.appStatus);
    return InkWell(
      onTap: () => _showShopDetail(shop),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shop.shopName.isEmpty
                        ? 'Κατάστημα χωρίς όνομα'
                        : shop.shopName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.barberinTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    shop.ownerEmail.isEmpty ? shop.shopId : shop.ownerEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.barberinTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 5,
                    children: [
                      _AdminMeta(
                        label: 'Συνδρομή',
                        value: _billingStatusLabel(shop.billingStatus),
                      ),
                      _AdminMeta(
                        label: 'Πλάνο',
                        value: shop.billingPlan.isEmpty
                            ? '—'
                            : shop.billingPlan,
                      ),
                      _AdminMeta(
                        label: 'Πλατφόρμα',
                        value: shop.billingPlatform.isEmpty
                            ? '—'
                            : shop.billingPlatform,
                      ),
                      _AdminMeta(
                        label: 'Εφαρμογή',
                        value: _appStatusLabel(shop.appStatus),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.chevron_right_rounded, color: statusColor, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminProvisioning(
    BuildContext context,
    PlatformAdminDashboard dashboard,
  ) {
    final queue = dashboard.provisioningQueue;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _AdminSectionLine(
          title: 'Ουρά εφαρμογών',
          values: [
            _AdminStatusValue(label: 'σύνολο', value: '${queue.length}'),
            _AdminStatusValue(
              label: 'σε αναμονή',
              value: '${queue.where((item) => item.status == 'queued').length}',
            ),
          ],
        ),
        if (queue.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 26),
            child: Text(
              'Δεν υπάρχουν αιτήματα provisioning.',
              style: TextStyle(color: context.barberinTextSecondary),
            ),
          )
        else
          for (final item in queue)
            _AdminFeedRow(
              leading: item.displayName.isEmpty
                  ? item.shopId
                  : item.displayName,
              detail:
                  '${_provisioningPhaseLabel(item.phase)} · ${item.progressPercent}%',
              onTap: () => _showProvisioningDetail(item),
            ),
      ],
    );
  }

  Widget _buildAdminBilling(BuildContext context) {
    final shops = [
      ..._visibleShops,
    ]..sort((left, right) => left.billingStatus.compareTo(right.billingStatus));
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _AdminSectionLine(
          title: 'Συνδρομές',
          values: [
            _AdminStatusValue(
              label: 'ενεργές',
              value: _dashboardValue('activeShops'),
            ),
            _AdminStatusValue(
              label: 'trial',
              value: _dashboardValue('trialingShops'),
            ),
            _AdminStatusValue(
              label: 'ληγμένες',
              value: _dashboardValue('expiredShops'),
            ),
          ],
        ),
        for (var index = 0; index < shops.length; index++) ...[
          if (index > 0) Divider(height: 1, color: context.barberinBorder),
          _buildAdminBillingRow(context, shops[index]),
        ],
      ],
    );
  }

  Widget _buildAdminBillingRow(
    BuildContext context,
    PlatformAdminShopSummary shop,
  ) {
    return InkWell(
      onTap: () => _showShopDetail(shop),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shop.shopName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.barberinTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 16,
                    runSpacing: 5,
                    children: [
                      _AdminMeta(
                        label: 'Πλάνο',
                        value: shop.billingPlan.isEmpty
                            ? '—'
                            : shop.billingPlan,
                      ),
                      _AdminMeta(
                        label: 'Πλατφόρμα',
                        value: shop.billingPlatform.isEmpty
                            ? '—'
                            : shop.billingPlatform,
                      ),
                      _AdminMeta(
                        label: 'Trial έως',
                        value: shop.trialEndsAt.isEmpty
                            ? '—'
                            : shop.trialEndsAt,
                      ),
                      _AdminMeta(
                        label: 'Περίοδος έως',
                        value: shop.currentPeriodEnd.isEmpty
                            ? '—'
                            : shop.currentPeriodEnd,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _billingStatusLabel(shop.billingStatus),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.barberinTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminActivity(
    BuildContext context,
    PlatformAdminDashboard dashboard,
  ) {
    final activity = dashboard.activity;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _AdminSectionLine(
          title: 'Πρόσφατη δραστηριότητα',
          values: [
            _AdminStatusValue(label: 'καταγραφές', value: '${activity.length}'),
          ],
        ),
        if (activity.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 26),
            child: Text(
              'Δεν υπάρχει πρόσφατη δραστηριότητα.',
              style: TextStyle(color: context.barberinTextSecondary),
            ),
          )
        else
          for (final item in activity)
            _AdminFeedRow(
              leading: _feedShopName(item),
              detail: _feedActivity(item),
            ),
      ],
    );
  }

  String _feedShopName(Map<String, dynamic> item) {
    final name = '${item['shopName'] ?? item['displayName'] ?? ''}'.trim();
    final shopId = '${item['shopId'] ?? ''}'.trim();
    return name.isNotEmpty ? name : shopId;
  }

  String _feedActivity(Map<String, dynamic> item) {
    final action = '${item['action'] ?? 'Ενημέρωση'}'.trim();
    final status = '${item['status'] ?? ''}'.trim();
    return status.isEmpty ? action : '$action · $status';
  }

  Future<void> _showAdminNavigationSheet(BuildContext context) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: context.barberinSurface,
      showDragHandle: true,
      builder: (_) =>
          _PlatformAdminNavigationSheet(currentIndex: _adminSectionIndex),
    );
    if (mounted && selected != null) {
      setState(() => _adminSectionIndex = selected);
    }
  }

  // Kept temporarily for backwards comparison while the shell is rolled out.
  // ignore: unused_element
  Widget _buildLegacyAdminBody(BuildContext context) {
    if (!isBarberinPlatformAdmin) {
      return const SizedBox.shrink();
    }
    final visibleShops = _visibleShops;
    return Scaffold(
      backgroundColor: context.barberinBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AuthTopBar(onBack: () => Navigator.of(context).maybePop()),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Barberin Admin',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: context.barberinTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Δημιουργία και παρακολούθηση ξεχωριστής εφαρμογής για κάθε shop.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: context.barberinTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Νέο shop',
                    onPressed: _loading ? null : _showCreateShopDialog,
                    icon: const Icon(Icons.add_business_outlined),
                    color: context.barberinTextPrimary,
                  ),
                  IconButton(
                    tooltip: 'Ανανέωση',
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh_rounded),
                    color: context.barberinTextPrimary,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Διαχειριστής πλατφόρμας',
                style: TextStyle(
                  fontSize: 12,
                  color: context.barberinTextSecondary,
                ),
              ),
              if (_dashboard != null) ...[
                const SizedBox(height: 18),
                Text(
                  'Επισκόπηση',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .5,
                    color: context.barberinTextSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AdminMetric(
                        label: 'Shops',
                        value: _dashboardValue('shopCount'),
                      ),
                      _AdminMetric(
                        label: 'Ραντεβού',
                        value: _dashboardValue('totalAppointments'),
                      ),
                      _AdminMetric(
                        label: 'Έσοδα',
                        value: _dashboardValue('actualRevenue'),
                      ),
                      _AdminMetric(
                        label: 'Πληρότητα',
                        value: '${_dashboardValue('occupancyPercent')}%',
                      ),
                      _AdminMetric(
                        label: 'Apps σε αναμονή',
                        value: _dashboardValue('appsPending'),
                      ),
                      _AdminMetric(
                        label: 'Alerts',
                        value: _dashboardValue('alerts'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                _AdminDashboardSections(
                  dashboard: _dashboard!,
                  onOpenProvisioning: _showProvisioningDetail,
                ),
              ],
              const SizedBox(height: 18),
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Αναζήτηση shop, owner, email ή package',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Καθαρισμός',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _AdminFilterDropdown(
                    width: 180,
                    label: 'Billing',
                    value: _billingFilter,
                    items: const [
                      'all',
                      'active',
                      'trialing',
                      'grace_period',
                      'expired',
                      'setup_required',
                    ],
                    labelBuilder: _billingLabel,
                    onChanged: (value) => setState(() {
                      _billingFilter = value;
                    }),
                  ),
                  _AdminFilterDropdown(
                    width: 190,
                    label: 'Εφαρμογή',
                    value: _appFilter,
                    items: const [
                      'all',
                      'provisioning_required',
                      'provisioning',
                      'configured',
                      'built',
                      'released',
                      'failed',
                    ],
                    labelBuilder: _appFilterLabel,
                    onChanged: (value) => setState(() {
                      _appFilter = value;
                    }),
                  ),
                  _AdminFilterDropdown(
                    width: 190,
                    label: 'Ταξινόμηση',
                    value: _sortMode,
                    items: const ['updated', 'name', 'billing', 'app'],
                    labelBuilder: _sortLabel,
                    onChanged: (value) => setState(() {
                      _sortMode = value;
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${visibleShops.length} από ${_shops.length} shops',
                style: TextStyle(
                  fontSize: 11,
                  color: context.barberinTextSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: context.barberinAccent,
                        ),
                      )
                    : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.barberinTextSecondary,
                          ),
                        ),
                      )
                    : visibleShops.isEmpty
                    ? Center(
                        child: Text(
                          _shops.isEmpty
                              ? 'Δεν υπάρχουν καταχωρισμένα καταστήματα.'
                              : 'Δεν βρέθηκαν shops με αυτά τα κριτήρια.',
                          style: TextStyle(
                            color: context.barberinTextSecondary,
                          ),
                        ),
                      )
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        itemCount: visibleShops.length,
                        separatorBuilder: (_, index) =>
                            Divider(height: 1, color: context.barberinBorder),
                        itemBuilder: (context, index) {
                          final shop = visibleShops[index];
                          final statusColor = _appStatusColor(
                            context,
                            shop.appStatus,
                          );
                          return InkWell(
                            onTap: () => _showShopDetail(shop),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          shop.shopName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                            color: context.barberinTextPrimary,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _appStatusLabel(shop.appStatus),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: statusColor,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Διαχείριση εφαρμογής shop',
                                        onPressed: () => _showShopActions(shop),
                                        icon: const Icon(
                                          Icons.more_horiz_rounded,
                                        ),
                                        color: context.barberinTextPrimary,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    shop.shopId,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: context.barberinTextSecondary,
                                    ),
                                  ),
                                  if (shop.ownerEmail.isNotEmpty) ...[
                                    const SizedBox(height: 5),
                                    Text(
                                      shop.ownerEmail,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: context.barberinTextSecondary,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 16,
                                    runSpacing: 6,
                                    children: [
                                      _AdminMeta(
                                        label: 'Package',
                                        value: shop.packageName.isEmpty
                                            ? 'pending'
                                            : shop.packageName,
                                      ),
                                      _AdminMeta(
                                        label: 'Mode',
                                        value: shop.appMode,
                                      ),
                                      _AdminMeta(
                                        label: 'Billing',
                                        value: _billingStatusLabel(
                                          shop.billingStatus,
                                        ),
                                      ),
                                      _AdminMeta(
                                        label: 'Plan',
                                        value: shop.billingPlan.isEmpty
                                            ? '—'
                                            : shop.billingPlan,
                                      ),
                                      _AdminMeta(
                                        label: 'Platform',
                                        value: shop.billingPlatform.isEmpty
                                            ? '—'
                                            : shop.billingPlatform,
                                      ),
                                      _AdminMeta(
                                        label: 'Trial end',
                                        value: shop.trialEndsAt.isEmpty
                                            ? '—'
                                            : shop.trialEndsAt,
                                      ),
                                      _AdminMeta(
                                        label: 'Period end',
                                        value: shop.currentPeriodEnd.isEmpty
                                            ? '—'
                                            : shop.currentPeriodEnd,
                                      ),
                                      _AdminMeta(
                                        label: 'Template',
                                        value: shop.templateVersion.isEmpty
                                            ? '1'
                                            : shop.templateVersion,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlatformAdminDesktopShell extends StatelessWidget {
  const _PlatformAdminDesktopShell({
    required this.currentIndex,
    required this.onTabTap,
    required this.onBack,
    required this.child,
  });

  final int currentIndex;
  final ValueChanged<int> onTabTap;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.barberinBackground,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PlatformAdminSidebar(
              currentIndex: currentIndex,
              onTabTap: onTabTap,
              onBack: onBack,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(30, 24, 30, 26),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1540),
                    child: SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlatformAdminSidebar extends StatelessWidget {
  const _PlatformAdminSidebar({
    required this.currentIndex,
    required this.onTabTap,
    required this.onBack,
  });

  final int currentIndex;
  final ValueChanged<int> onTabTap;
  final VoidCallback onBack;

  static const navigation = <_PlatformAdminNavigationItem>[
    _PlatformAdminNavigationItem('Επισκόπηση', Icons.dashboard_outlined, 0),
    _PlatformAdminNavigationItem('Καταστήματα', Icons.storefront_outlined, 1),
    _PlatformAdminNavigationItem(
      'Δημιουργία εφαρμογών',
      Icons.auto_awesome_motion_outlined,
      2,
    ),
    _PlatformAdminNavigationItem('Συνδρομές', Icons.payments_outlined, 3),
    _PlatformAdminNavigationItem('Δραστηριότητα', Icons.history_rounded, 4),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 264,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(right: BorderSide(color: context.barberinBorder)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BrandWordmark(width: 144),
            const SizedBox(height: 14),
            Text(
              'ΔΙΑΧΕΙΡΙΣΗ ΠΛΑΤΦΟΡΜΑΣ',
              style: TextStyle(
                color: context.barberinTextSecondary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.3,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.barberinBorder),
                ),
              ),
              child: Text(
                'Barberin Admin',
                style: TextStyle(
                  color: context.barberinTextPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final item in navigation)
                    _PlatformAdminSidebarRow(
                      item: item,
                      selected: currentIndex == item.index,
                      onTap: () => onTabTap(item.index),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: context.barberinBorder),
            const SizedBox(height: 10),
            _PlatformAdminSidebarRow(
              item: const _PlatformAdminNavigationItem(
                'Επιστροφή',
                Icons.arrow_back_rounded,
                -1,
              ),
              onTap: onBack,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlatformAdminSidebarRow extends StatelessWidget {
  const _PlatformAdminSidebarRow({
    required this.item,
    required this.onTap,
    this.selected = false,
  });

  final _PlatformAdminNavigationItem item;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? context.barberinAccent
        : context.barberinTextPrimary;
    return Material(
      color: selected ? context.barberinAccentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.barberinBorder)),
          ),
          child: Row(
            children: [
              Icon(item.icon, size: 18, color: foreground),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (selected)
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: context.barberinAccent,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlatformAdminNavigationItem {
  const _PlatformAdminNavigationItem(this.label, this.icon, this.index);

  final String label;
  final IconData icon;
  final int index;
}

class _PlatformAdminMobileHeader extends StatelessWidget {
  const _PlatformAdminMobileHeader({
    required this.onMenu,
    required this.onBack,
  });

  final VoidCallback onMenu;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Μενού',
            onPressed: onMenu,
            icon: const Icon(Icons.menu_rounded),
            color: context.barberinAccent,
          ),
          const Expanded(child: Center(child: BrandWordmark(width: 116))),
          IconButton(
            tooltip: 'Επιστροφή',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            color: context.barberinTextPrimary,
          ),
        ],
      ),
    );
  }
}

class _PlatformAdminBottomBar extends StatelessWidget {
  const _PlatformAdminBottomBar({
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: context.barberinBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (final item in _PlatformAdminSidebar.navigation)
              Expanded(
                child: InkWell(
                  onTap: () => onTap(item.index),
                  child: SizedBox(
                    height: 48,
                    child: Center(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: item.index == currentIndex
                              ? context.barberinAccent
                              : context.barberinTextSecondary,
                          fontSize: 9,
                          fontWeight: item.index == currentIndex
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlatformAdminNavigationSheet extends StatelessWidget {
  const _PlatformAdminNavigationSheet({required this.currentIndex});

  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in _PlatformAdminSidebar.navigation)
              _PlatformAdminSidebarRow(
                item: item,
                selected: currentIndex == item.index,
                onTap: () => Navigator.of(context).pop(item.index),
              ),
          ],
        ),
      ),
    );
  }
}

class PlatformAdminShopDetailPage extends StatefulWidget {
  const PlatformAdminShopDetailPage({
    super.key,
    required this.repository,
    required this.shopId,
    required this.fallbackName,
  });

  final PlatformAdminRepository repository;
  final String shopId;
  final String fallbackName;

  @override
  State<PlatformAdminShopDetailPage> createState() =>
      _PlatformAdminShopDetailPageState();
}

class _PlatformAdminShopDetailPageState
    extends State<PlatformAdminShopDetailPage> {
  late Future<PlatformAdminShopDetail> _detailFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _detailFuture = widget.repository.loadShopDetail(widget.shopId);
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'released':
        return 'Δημοσιευμένο';
      case 'built':
        return 'Έτοιμο build';
      case 'configured':
        return 'Ρυθμισμένο';
      case 'provisioning':
        return 'Σε δημιουργία';
      case 'failed':
        return 'Αποτυχία';
      default:
        return 'Αναμονή δημιουργίας';
    }
  }

  String _billingStatusLabel(String status) {
    switch (status) {
      case 'active':
        return 'Ενεργή';
      case 'trialing':
        return 'Σε trial';
      case 'grace_period':
        return 'Σε περίοδο χάριτος';
      case 'expired':
        return 'Ληγμένη';
      case 'setup_required':
        return 'Δεν έχει ρυθμιστεί';
      default:
        return status.isEmpty ? '—' : status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailBody = FutureBuilder<PlatformAdminShopDetail>(
      future: _detailFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: CircularProgressIndicator(color: context.barberinAccent),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return _AdminDetailError(onRetry: () => setState(_load));
        }
        return _buildDetail(context, snapshot.data!);
      },
    );

    if (_useDesktopBarberShell(context)) {
      return _PlatformAdminDesktopShell(
        currentIndex: 1,
        onTabTap: (_) => Navigator.of(context).pop(),
        onBack: () => Navigator.of(context).pop(),
        child: Column(children: [Expanded(child: detailBody)]),
      );
    }

    return Scaffold(
      backgroundColor: context.barberinBackground,
      body: SafeArea(
        child: Column(
          children: [
            _PlatformAdminMobileHeader(
              onMenu: () => _showDetailNavigation(context),
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(child: detailBody),
          ],
        ),
      ),
      bottomNavigationBar: _PlatformAdminBottomBar(
        currentIndex: 1,
        onTap: (_) => Navigator.of(context).pop(),
      ),
    );
  }

  Future<void> _showDetailNavigation(BuildContext context) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: context.barberinSurface,
      showDragHandle: true,
      builder: (_) => const _PlatformAdminNavigationSheet(currentIndex: 1),
    );
    if (!mounted) return;
    if (selected != null && selected != 1) {
      Navigator.of(this.context).pop();
    }
  }

  Widget _buildDetail(BuildContext context, PlatformAdminShopDetail detail) {
    final displayName = detail.shopName.isEmpty
        ? widget.fallbackName
        : detail.shopName;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      children: [
        Text(
          displayName,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: context.barberinTextPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          detail.shopId,
          style: TextStyle(fontSize: 11, color: context.barberinTextSecondary),
        ),
        const SizedBox(height: 22),
        _AdminDetailSection(
          title: 'Στοιχεία shop',
          values: [
            _AdminDetailRow(label: 'Ιδιοκτήτης', value: detail.ownerName),
            _AdminDetailRow(label: 'Email', value: detail.ownerEmail),
            _AdminDetailRow(label: 'Τηλέφωνο', value: detail.ownerPhone),
            _AdminDetailRow(
              label: 'Τοποθεσία',
              value: [
                detail.address,
                detail.city,
              ].where((value) => value.isNotEmpty).join(', '),
            ),
            _AdminDetailRow(label: 'Δημιουργήθηκε', value: detail.createdAt),
            _AdminDetailRow(label: 'Ενημερώθηκε', value: detail.updatedAt),
          ],
        ),
        _AdminDetailSection(
          title: 'Συνδρομή',
          values: [
            _AdminDetailRow(
              label: 'Κατάσταση',
              value: _billingStatusLabel(detail.billingStatus),
            ),
            _AdminDetailRow(
              label: 'Πλάνο',
              value: detail.billingPlan.isEmpty ? '—' : detail.billingPlan,
            ),
            _AdminDetailRow(
              label: 'Πλατφόρμα',
              value: detail.billingPlatform.isEmpty
                  ? '—'
                  : detail.billingPlatform,
            ),
            _AdminDetailRow(
              label: 'Λήξη trial',
              value: detail.trialEndsAt.isEmpty ? '—' : detail.trialEndsAt,
            ),
            _AdminDetailRow(
              label: 'Λήξη περιόδου',
              value: detail.currentPeriodEnd.isEmpty
                  ? '—'
                  : detail.currentPeriodEnd,
            ),
          ],
        ),
        _AdminDetailSection(
          title: 'Customer app',
          values: [
            _AdminDetailRow(
              label: 'Κατάσταση',
              value: _statusLabel(detail.appStatus),
            ),
            _AdminDetailRow(
              label: 'Android package',
              value: detail.packageName,
            ),
            _AdminDetailRow(label: 'iOS bundle', value: detail.bundleId),
            _AdminDetailRow(label: 'Workspace', value: detail.workspaceName),
            _AdminDetailRow(label: 'Template', value: detail.templateVersion),
            _AdminDetailRow(
              label: 'Τελευταίο build',
              value: detail.lastBuildAt,
            ),
            _AdminDetailRow(
              label: 'Τελευταίο release',
              value: detail.lastReleaseAt,
            ),
          ],
        ),
        _AdminDetailSection(
          title: 'Μετρήσεις',
          values: [
            _AdminDetailRow(label: 'Barbers', value: '${detail.barberCount}'),
            _AdminDetailRow(label: 'Πελάτες', value: '${detail.customerCount}'),
            _AdminDetailRow(
              label: 'Υπηρεσίες',
              value: '${detail.serviceCount}',
            ),
            _AdminDetailRow(
              label: 'Ραντεβού',
              value: '${detail.appointmentCount}',
            ),
            _AdminDetailRow(
              label: 'Tokens ειδοποιήσεων',
              value: '${detail.notificationTokenCount}',
            ),
          ],
        ),
        _AdminEntitySection(
          title: 'Barbers',
          items: detail.barbers,
          primaryKeys: const ['fullName', 'name', 'displayName'],
          secondaryKeys: const ['email', 'phone', 'status'],
        ),
        _AdminEntitySection(
          title: 'Πελάτες',
          items: detail.customers,
          primaryKeys: const ['fullName', 'name', 'displayName'],
          secondaryKeys: const ['email', 'phone'],
        ),
        _AdminEntitySection(
          title: 'Υπηρεσίες',
          items: detail.services,
          primaryKeys: const ['label', 'name', 'title', 'key'],
          secondaryKeys: const ['price', 'duration', 'minutes'],
        ),
        _AdminEntitySection(
          title: 'Ραντεβού',
          items: detail.appointments,
          primaryKeys: const [
            'name',
            'customerName',
            'serviceLabel',
            'serviceName',
          ],
          secondaryKeys: const ['date', 'startTime', 'status'],
        ),
      ],
    );
  }
}

class _AdminDetailError extends StatelessWidget {
  const _AdminDetailError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Δεν ήταν δυνατή η φόρτωση των στοιχείων του shop.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.barberinTextSecondary),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Δοκιμή ξανά')),
        ],
      ),
    );
  }
}

class _AdminEntitySection extends StatelessWidget {
  const _AdminEntitySection({
    required this.title,
    required this.items,
    required this.primaryKeys,
    required this.secondaryKeys,
  });

  final String title;
  final List<Map<String, dynamic>> items;
  final List<String> primaryKeys;
  final List<String> secondaryKeys;

  String _value(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = '${item[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _AdminDetailSection(
        title: '$title (0)',
        values: const [
          _AdminDetailRow(label: 'Κατάσταση', value: 'Δεν υπάρχουν στοιχεία'),
        ],
      );
    }
    final visibleItems = items.take(50).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title (${items.length})',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: .4,
              color: context.barberinTextSecondary,
            ),
          ),
          const SizedBox(height: 6),
          for (final item in visibleItems)
            _AdminDetailRow(
              label: _value(item, primaryKeys).isEmpty
                  ? 'Χωρίς όνομα'
                  : _value(item, primaryKeys),
              value: _value(item, secondaryKeys),
            ),
          if (items.length > visibleItems.length)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Εμφανίζονται τα πρώτα ${visibleItems.length} στοιχεία.',
                style: TextStyle(
                  fontSize: 11,
                  color: context.barberinTextSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AdminMeta extends StatelessWidget {
  const _AdminMeta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label  $value',
      style: TextStyle(fontSize: 11, color: context.barberinTextSecondary),
    );
  }
}

class _AdminFilterDropdown extends StatelessWidget {
  const _AdminFilterDropdown({
    required this.width,
    required this.label,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
  });

  final double width;
  final String label;
  final String value;
  final List<String> items;
  final String Function(String value) labelBuilder;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          for (final item in items)
            DropdownMenuItem<String>(
              value: item,
              child: Text(labelBuilder(item), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    );
  }
}

class _AdminMetric extends StatelessWidget {
  const _AdminMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: context.barberinTextSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: context.barberinTextPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminDashboardSections extends StatelessWidget {
  const _AdminDashboardSections({
    required this.dashboard,
    required this.onOpenProvisioning,
  });

  final PlatformAdminDashboard dashboard;
  final ValueChanged<PlatformAdminProvisioningItem> onOpenProvisioning;

  @override
  Widget build(BuildContext context) {
    final alertShops = dashboard.shops
        .where((shop) => shop.alertCount > 0)
        .take(3)
        .toList();
    final activity = dashboard.activity.take(3).toList();
    final queue = dashboard.provisioningQueue.take(3).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AdminSectionLine(
            title: 'Κατάσταση καταστημάτων',
            values: [
              _AdminStatusValue(
                label: 'Ενεργά',
                value: dashboard.totalLabel('activeShops'),
              ),
              _AdminStatusValue(
                label: 'Σε trial',
                value: dashboard.totalLabel('trialingShops'),
              ),
              _AdminStatusValue(
                label: 'Ληγμένα',
                value: dashboard.totalLabel('expiredShops'),
              ),
            ],
          ),
          _AdminSectionLine(
            title: 'Κατάσταση εφαρμογών',
            values: [
              _AdminStatusValue(
                label: 'Έτοιμες',
                value: dashboard.totalLabel('appsBuilt'),
              ),
              _AdminStatusValue(
                label: 'Σε αναμονή',
                value: dashboard.totalLabel('appsPending'),
              ),
            ],
          ),
          if (alertShops.isNotEmpty) ...[
            _AdminSectionTitle(title: 'Ειδοποιήσεις'),
            for (final shop in alertShops)
              _AdminFeedRow(
                leading: shop.shopName,
                detail: '${shop.alertCount} ενεργές ειδοποιήσεις',
                emphasis: true,
              ),
          ],
          if (queue.isNotEmpty) ...[
            _AdminSectionTitle(title: 'Ουρά δημιουργίας εφαρμογών'),
            for (final item in queue)
              _AdminFeedRow(
                leading: item.displayName.isEmpty
                    ? item.shopId
                    : item.displayName,
                detail: '${item.phase} · ${item.progressPercent}%',
                onTap: () => onOpenProvisioning(item),
              ),
          ],
          if (activity.isNotEmpty) ...[
            _AdminSectionTitle(title: 'Πρόσφατη δραστηριότητα'),
            for (final item in activity)
              _AdminFeedRow(
                leading: _feedShopName(item),
                detail: _feedActivity(item),
              ),
          ],
        ],
      ),
    );
  }

  String _feedShopName(Map<String, dynamic> item) {
    final name = '${item['shopName'] ?? item['displayName'] ?? ''}'.trim();
    final shopId = '${item['shopId'] ?? ''}'.trim();
    return name.isNotEmpty ? name : shopId;
  }

  String _feedActivity(Map<String, dynamic> item) {
    final action = '${item['action'] ?? 'Ενημέρωση'}'.trim();
    final status = '${item['status'] ?? ''}'.trim();
    return status.isEmpty ? action : '$action · $status';
  }
}

class _AdminSectionLine extends StatelessWidget {
  const _AdminSectionLine({required this.title, required this.values});

  final String title;
  final List<_AdminStatusValue> values;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.barberinBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 148,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 11,
                color: context.barberinTextSecondary,
              ),
            ),
          ),
          Expanded(child: Wrap(spacing: 18, runSpacing: 6, children: values)),
        ],
      ),
    );
  }
}

class _AdminStatusValue extends StatelessWidget {
  const _AdminStatusValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 12, color: context.barberinTextPrimary),
        children: [
          TextSpan(
            text: '$value ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: label,
            style: TextStyle(color: context.barberinTextSecondary),
          ),
        ],
      ),
    );
  }
}

class _AdminSectionTitle extends StatelessWidget {
  const _AdminSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: .4,
          color: context.barberinTextSecondary,
        ),
      ),
    );
  }
}

class _AdminFeedRow extends StatelessWidget {
  const _AdminFeedRow({
    required this.leading,
    required this.detail,
    this.emphasis = false,
    this.onTap,
  });

  final String leading;
  final String detail;
  final bool emphasis;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.barberinBorder)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                leading.isEmpty ? 'Άγνωστο shop' : leading,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: emphasis ? FontWeight.w700 : FontWeight.w500,
                  color: context.barberinTextPrimary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              detail,
              style: TextStyle(
                fontSize: 11,
                color: emphasis
                    ? context.barberinAccent
                    : context.barberinTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminDetailSection extends StatelessWidget {
  const _AdminDetailSection({required this.title, required this.values});

  final String title;
  final List<Widget> values;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: .4,
              color: context.barberinTextSecondary,
            ),
          ),
          const SizedBox(height: 6),
          ...values,
        ],
      ),
    );
  }
}

class _AdminDetailRow extends StatelessWidget {
  const _AdminDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.barberinBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: context.barberinTextSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                color: context.barberinTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
