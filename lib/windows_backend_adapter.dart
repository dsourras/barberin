part of 'main.dart';

/// Windows does not ship with the FlutterFire Realtime Database and
/// Messaging plugins used by the mobile targets. Keep business data behind
/// authenticated HTTPS requests instead of falling back to public database
/// reads or embedding service credentials in the desktop client.
bool get isBarberinWindows => !kIsWeb && Platform.isWindows;

class WindowsBackendAdapter {
  WindowsBackendAdapter._();

  static final WindowsBackendAdapter instance = WindowsBackendAdapter._();

  static const _endpoint =
      'https://europe-west1-barbero-88d00.cloudfunctions.net/barberoWindowsDataAdapter';

  Future<String> _idToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('missing-shop-user');
    }
    // Reuse the cached token and refresh only when Firebase requires it.
    final token = await user.getIdToken();
    if (token == null || token.trim().isEmpty) {
      throw Exception('missing-shop-token');
    }
    return token;
  }

  Future<Map<String, dynamic>> _request(
    String action, {
    String? shopId,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) async {
    final body = <String, dynamic>{
      'idToken': await _idToken(),
      'action': action,
      if (shopId != null && shopId.trim().isNotEmpty) 'shopId': shopId.trim(),
      ...payload,
    };
    final response = await http.post(
      Uri.parse(_endpoint),
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    Map<String, dynamic> decoded = const <String, dynamic>{};
    try {
      final raw = jsonDecode(response.body);
      if (raw is Map) {
        decoded = raw.cast<String, dynamic>();
      }
    } catch (_) {
      // Convert a non-JSON response into the same stable client error below.
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message =
          '${decoded['message'] ?? 'windows-backend-request-failed'}';
      throw Exception(message);
    }
    if (decoded['ok'] != true) {
      throw Exception(
        '${decoded['message'] ?? 'windows-backend-request-failed'}',
      );
    }
    return decoded;
  }

  Future<Map<String, dynamic>> loadShopSnapshot(String shopId) async {
    final response = await _request('snapshot', shopId: shopId);
    final shop = response['shop'];
    if (shop is! Map) {
      throw Exception('invalid-windows-shop-snapshot');
    }
    return shop.cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> loadSchedule(String shopId) async {
    final response = await _request('schedule', shopId: shopId);
    final schedule = response['schedule'];
    return schedule is Map
        ? schedule.cast<String, dynamic>()
        : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> saveSchedule({
    required String shopId,
    required Map<String, dynamic> schedule,
  }) async {
    final response = await _request(
      'save_schedule',
      shopId: shopId,
      payload: <String, dynamic>{'schedule': schedule},
    );
    final saved = response['schedule'];
    return saved is Map ? saved.cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> loadAppointments(String shopId) async {
    final response = await _request('appointments', shopId: shopId);
    return _mapList(response['appointments']);
  }

  Future<Map<String, dynamic>> loadClients(String shopId) async {
    final response = await _request('clients', shopId: shopId);
    final clients = response['clients'];
    return clients is Map ? clients.cast<String, dynamic>() : {};
  }

  Future<Map<String, dynamic>> loadServices(String shopId) async {
    final response = await _request('services', shopId: shopId);
    final services = response['services'];
    return services is Map ? services.cast<String, dynamic>() : {};
  }

  Future<Map<String, dynamic>> loadReports({
    required String shopId,
    required String startDate,
    required String endDate,
  }) {
    return _request(
      'reports',
      shopId: shopId,
      payload: <String, dynamic>{'startDate': startDate, 'endDate': endDate},
    );
  }

  Future<Map<String, dynamic>> loadBilling(String shopId) async {
    final response = await _request('billing', shopId: shopId);
    final billing = response['billing'];
    return billing is Map ? billing.cast<String, dynamic>() : {};
  }

  Future<List<Map<String, dynamic>>> loadNotifications(String shopId) async {
    final response = await _request('notifications', shopId: shopId);
    return _mapList(response['notifications']);
  }

  List<Map<String, dynamic>> _mapList(Object? raw) {
    if (raw is! List) {
      return <Map<String, dynamic>>[];
    }
    return raw
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList(growable: false);
  }
}
