part of 'main.dart';

class Appointment {
  const Appointment(
    this.time,
    this.name,
    this.service,
    this.duration, {
    this.id = '',
    this.isBooked = true,
    this.customerUid = '',
    this.customerPhone = '',
    this.customerEmail = '',
    this.date = '',
    this.barberId = '',
    this.barberName = '',
    this.status = 'confirmed',
    this.blocked = false,
    this.blockReason = '',
    this.priceOverride,
    this.minutesOverride,
  });

  final String id;
  final String time;
  final String name;
  final String service;
  final String duration;
  final bool isBooked;
  final String customerUid;
  final String customerPhone;
  final String customerEmail;
  final String date;
  final String barberId;
  final String barberName;
  final String status;
  final bool blocked;
  final String blockReason;
  final int? priceOverride;
  final int? minutesOverride;

  bool get isPending => status == 'pending';
  bool get isConfirmed => status == 'confirmed';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';
  bool get isNoShow => status == 'no_show';
  bool get isBlocked => blocked;

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'confirmed':
        return 'Confirmed';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      case 'no_show':
        return 'No-show';
      default:
        return 'Confirmed';
    }
  }

  int get minutes {
    return minutesOverride ?? int.tryParse(duration.replaceAll("'", '')) ?? 0;
  }

  int get price {
    if (priceOverride != null) {
      return priceOverride!;
    }
    switch (service) {
      case 'Classic Haircut':
        return 30;
      case 'Fade & Beard':
        return 45;
      case 'Haircut & Beard':
        return 50;
      case 'Kids Haircut':
        return 20;
      default:
        return 25;
    }
  }
}

class CustomerProfile {
  const CustomerProfile({
    this.uid = '',
    required this.name,
    required this.phone,
    this.email = '',
    this.photoUrl = '',
    required this.preferences,
    required this.notes,
    required this.history,
  });

  final String uid;
  final String name;
  final String phone;
  final String email;
  final String photoUrl;
  final List<String> preferences;
  final String notes;
  final List<VisitRecord> history;
}

class VisitRecord {
  const VisitRecord({
    required this.date,
    required this.service,
    required this.price,
  });

  final String date;
  final String service;
  final int price;
}

class ProgramEntry {
  const ProgramEntry({
    this.appointmentId = '',
    required this.hour,
    this.customerUid = '',
    this.name = '',
    this.service = '',
    this.duration = '',
    this.barberName = '',
    this.status = 'confirmed',
    this.blocked = false,
    this.blockReason = '',
    this.highlighted = false,
    this.isBreak = false,
  });

  const ProgramEntry.breakLine({required this.hour})
    : appointmentId = '',
      customerUid = '',
      name = '',
      service = '',
      duration = '',
      barberName = '',
      status = 'confirmed',
      blocked = false,
      blockReason = '',
      highlighted = false,
      isBreak = true;

  final String appointmentId;
  final String hour;
  final String customerUid;
  final String name;
  final String service;
  final String duration;
  final String barberName;
  final String status;
  final bool blocked;
  final String blockReason;
  final bool highlighted;
  final bool isBreak;
}

class ScheduleDay {
  const ScheduleDay({
    required this.name,
    required this.enabled,
    required this.start,
    required this.end,
    required this.breakStart,
    required this.breakEnd,
  });

  final String name;
  final bool enabled;
  final String start;
  final String end;
  final String breakStart;
  final String breakEnd;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'enabled': enabled,
      'start': start,
      'end': end,
      'breakStart': breakStart,
      'breakEnd': breakEnd,
    };
  }

  factory ScheduleDay.fromJson(Map<String, dynamic> json) {
    final enabled = json['enabled'] as bool? ?? false;
    final start = json['start'] as String? ?? '--:--';
    final end = json['end'] as String? ?? '--:--';
    final breakStart = json['breakStart'] as String? ?? '--:--';
    final breakEnd = json['breakEnd'] as String? ?? '--:--';

    return ScheduleDay(
      name: json['name'] as String,
      enabled: enabled,
      start: start,
      end: end,
      breakStart: breakStart,
      breakEnd: breakEnd,
    );
  }

  ScheduleDay copyWith({
    String? name,
    bool? enabled,
    String? start,
    String? end,
    String? breakStart,
    String? breakEnd,
  }) {
    return ScheduleDay(
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      start: start ?? this.start,
      end: end ?? this.end,
      breakStart: breakStart ?? this.breakStart,
      breakEnd: breakEnd ?? this.breakEnd,
    );
  }
}

String scheduleDayNameForIndex(int index) {
  const names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  if (index < 0 || index >= names.length) return 'Day';
  return names[index];
}

class ServiceDurationSetting {
  const ServiceDurationSetting({
    required this.key,
    required this.label,
    required this.minutes,
  });

  final String key;
  final String label;
  final int minutes;

  Map<String, dynamic> toJson() {
    return {'key': key, 'label': label, 'minutes': minutes};
  }

  factory ServiceDurationSetting.fromJson(Map<String, dynamic> json) {
    return ServiceDurationSetting(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      minutes: json['minutes'] as int? ?? 30,
    );
  }

  ServiceDurationSetting copyWith({String? key, String? label, int? minutes}) {
    return ServiceDurationSetting(
      key: key ?? this.key,
      label: label ?? this.label,
      minutes: minutes ?? this.minutes,
    );
  }
}

class ServicePriceSetting {
  const ServicePriceSetting({
    required this.key,
    required this.label,
    required this.price,
  });

  final String key;
  final String label;
  final int price;

  Map<String, dynamic> toJson() {
    return {'key': key, 'label': label, 'price': price};
  }

  factory ServicePriceSetting.fromJson(Map<String, dynamic> json) {
    return ServicePriceSetting(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      price: json['price'] as int? ?? 0,
    );
  }

  ServicePriceSetting copyWith({String? key, String? label, int? price}) {
    return ServicePriceSetting(
      key: key ?? this.key,
      label: label ?? this.label,
      price: price ?? this.price,
    );
  }
}

List<ServiceDurationSetting> buildDefaultServiceDurations() {
  return const [
    ServiceDurationSetting(
      key: 'classic_haircut',
      label: '\u039a\u03bf\u03cd\u03c1\u03b5\u03bc\u03b1',
      minutes: 30,
    ),
    ServiceDurationSetting(
      key: 'beard_trim',
      label: '\u0393\u03b5\u03bd\u03b5\u03b9\u03ac\u03b4\u03b1',
      minutes: 20,
    ),
    ServiceDurationSetting(
      key: 'haircut_and_beard',
      label:
          '\u039a\u03bf\u03cd\u03c1\u03b5\u03bc\u03b1 + \u0393\u03b5\u03bd\u03b5\u03b9\u03ac\u03b4\u03b1',
      minutes: 45,
    ),
    ServiceDurationSetting(
      key: 'fade_and_beard',
      label: 'Fade + \u0393\u03b5\u03bd\u03b5\u03b9\u03ac\u03b4\u03b1',
      minutes: 50,
    ),
    ServiceDurationSetting(
      key: 'kids_haircut',
      label:
          '\u03a0\u03b1\u03b9\u03b4\u03b9\u03ba\u03cc \u03ba\u03bf\u03cd\u03c1\u03b5\u03bc\u03b1',
      minutes: 25,
    ),
  ];
}

List<ServicePriceSetting> buildDefaultServicePrices() {
  return const [
    ServicePriceSetting(
      key: 'classic_haircut',
      label: '\u039a\u03bf\u03cd\u03c1\u03b5\u03bc\u03b1',
      price: 15,
    ),
    ServicePriceSetting(
      key: 'beard_trim',
      label: '\u0393\u03b5\u03bd\u03b5\u03b9\u03ac\u03b4\u03b1',
      price: 10,
    ),
    ServicePriceSetting(
      key: 'haircut_and_beard',
      label:
          '\u039a\u03bf\u03cd\u03c1\u03b5\u03bc\u03b1 + \u0393\u03b5\u03bd\u03b5\u03b9\u03ac\u03b4\u03b1',
      price: 22,
    ),
    ServicePriceSetting(
      key: 'fade_and_beard',
      label: 'Fade + \u0393\u03b5\u03bd\u03b5\u03b9\u03ac\u03b4\u03b1',
      price: 25,
    ),
    ServicePriceSetting(
      key: 'kids_haircut',
      label:
          '\u03a0\u03b1\u03b9\u03b4\u03b9\u03ba\u03cc \u03ba\u03bf\u03cd\u03c1\u03b5\u03bc\u03b1',
      price: 12,
    ),
  ];
}

class WeeklyScheduleData {
  const WeeklyScheduleData({
    required this.slotMinutes,
    required this.appointmentsPerSlot,
    required this.showPrices,
    required this.serviceDurations,
    required this.servicePrices,
    required this.days,
  });

  final int slotMinutes;
  final int appointmentsPerSlot;
  final bool showPrices;
  final List<ServiceDurationSetting> serviceDurations;
  final List<ServicePriceSetting> servicePrices;
  final List<ScheduleDay> days;
}

class WeeklyScheduleRepository {
  static const _baseUrl = 'https://barbero-88d00-default-rtdb.firebaseio.com';
  static const _functionsBaseUrl =
      'https://europe-west1-barbero-88d00.cloudfunctions.net';

  String get _currentShopId {
    return requireCurrentBarberoSession().shopId;
  }

  Uri _uriForShop(String shopId) {
    return Uri.parse('$_baseUrl/shops/$shopId/weekly_schedule.json');
  }

  WeeklyScheduleData buildDefaultData() {
    return WeeklyScheduleData(
      slotMinutes: 30,
      appointmentsPerSlot: 1,
      showPrices: false,
      serviceDurations: buildDefaultServiceDurations(),
      servicePrices: buildDefaultServicePrices(),
      days: buildDefaultWeeklySchedule(),
    );
  }

  Future<WeeklyScheduleData?> load() async {
    final response = await http.get(_uriForShop(_currentShopId));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load weekly schedule');
    }

    if (response.body == 'null') {
      return null;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final slotMinutes = data['slotMinutes'] as int? ?? 30;
    final appointmentsPerSlot = data['appointmentsPerSlot'] as int? ?? 1;
    final showPrices = data['showPrices'] == true;
    final rawServiceDurations =
        (data['serviceDurations'] as List<dynamic>? ?? const [])
            .cast<Map>()
            .map(
              (item) => ServiceDurationSetting.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList();
    final rawServicePrices =
        (data['servicePrices'] as List<dynamic>? ?? const [])
            .cast<Map>()
            .map(
              (item) =>
                  ServicePriceSetting.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList();
    final rawDays = (data['days'] as List<dynamic>? ?? const [])
        .cast<Map>()
        .toList()
        .asMap()
        .entries
        .map((entry) {
          final day = ScheduleDay.fromJson(
            Map<String, dynamic>.from(entry.value),
          );
          return day.copyWith(name: scheduleDayNameForIndex(entry.key));
        })
        .toList();

    return WeeklyScheduleData(
      slotMinutes: slotMinutes,
      appointmentsPerSlot: appointmentsPerSlot,
      showPrices: showPrices,
      serviceDurations: rawServiceDurations.isEmpty
          ? buildDefaultServiceDurations()
          : rawServiceDurations,
      servicePrices: rawServicePrices.isEmpty
          ? buildDefaultServicePrices()
          : rawServicePrices,
      days: rawDays,
    );
  }

  Future<WeeklyScheduleData> loadOrCreateDefault() async {
    final response = await http.get(_uriForShop(_currentShopId));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load weekly schedule');
    }

    if (response.body == 'null') {
      final defaults = buildDefaultData();
      await save(
        slotMinutes: defaults.slotMinutes,
        appointmentsPerSlot: defaults.appointmentsPerSlot,
        showPrices: defaults.showPrices,
        serviceDurations: defaults.serviceDurations,
        servicePrices: defaults.servicePrices,
        days: defaults.days,
      );
      return defaults;
    }

    final raw = jsonDecode(response.body) as Map<String, dynamic>;
    final existing = await load();
    if (existing == null) {
      final defaults = buildDefaultData();
      await save(
        slotMinutes: defaults.slotMinutes,
        appointmentsPerSlot: defaults.appointmentsPerSlot,
        showPrices: defaults.showPrices,
        serviceDurations: defaults.serviceDurations,
        servicePrices: defaults.servicePrices,
        days: defaults.days,
      );
      return defaults;
    }

    final hasServiceDurations = raw['serviceDurations'] is List;
    final hasServicePrices = raw['servicePrices'] is List;
    final hasShowPrices = raw['showPrices'] is bool;
    if (!hasServiceDurations || !hasServicePrices || !hasShowPrices) {
      final defaults = buildDefaultData();
      final merged = WeeklyScheduleData(
        slotMinutes: existing.slotMinutes,
        appointmentsPerSlot: existing.appointmentsPerSlot,
        showPrices: hasShowPrices ? existing.showPrices : defaults.showPrices,
        serviceDurations: hasServiceDurations
            ? existing.serviceDurations
            : defaults.serviceDurations,
        servicePrices: hasServicePrices
            ? existing.servicePrices
            : defaults.servicePrices,
        days: existing.days,
      );
      await save(
        slotMinutes: merged.slotMinutes,
        appointmentsPerSlot: merged.appointmentsPerSlot,
        showPrices: merged.showPrices,
        serviceDurations: merged.serviceDurations,
        servicePrices: merged.servicePrices,
        days: merged.days,
      );
      return merged;
    }

    return existing;
  }

  Future<void> save({
    required int slotMinutes,
    required int appointmentsPerSlot,
    required bool showPrices,
    required List<ServiceDurationSetting> serviceDurations,
    required List<ServicePriceSetting> servicePrices,
    required List<ScheduleDay> days,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final session = requireCurrentBarberoSession();
    if (user == null) throw Exception('No authenticated shop user');
    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoSaveWeeklySchedule'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
        'shopId': session.shopId,
        'schedule': {
          'slotMinutes': slotMinutes,
          'appointmentsPerSlot': appointmentsPerSlot,
          'showPrices': showPrices,
          'serviceDurations': serviceDurations
              .map((service) => service.toJson())
              .toList(),
          'servicePrices': servicePrices
              .map((service) => service.toJson())
              .toList(),
          'days': days.map((day) => day.toJson()).toList(),
        },
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to save weekly schedule');
    }
  }
}

class ShopRegistrationData {
  const ShopRegistrationData({
    required this.shopId,
    required this.ownerName,
    required this.ownerPhone,
    required this.ownerEmail,
    required this.shopName,
    required this.address,
  });

  final String shopId;
  final String ownerName;
  final String ownerPhone;
  final String ownerEmail;
  final String shopName;
  final String address;
}

class ShopRegistrationRepository {
  static const _baseUrl = 'https://barbero-88d00-default-rtdb.firebaseio.com';
  static const _functionsBaseUrl =
      'https://europe-west1-barbero-88d00.cloudfunctions.net';

  Future<void> registerShop(ShopRegistrationData data) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('No authenticated shop user');
    }
    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoRegisterShop'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
        'shop': {
          'shopId': data.shopId,
          'ownerName': data.ownerName,
          'ownerPhone': data.ownerPhone,
          'ownerEmail': data.ownerEmail,
          'shopName': data.shopName,
          'address': data.address,
        },
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to register shop');
    }
  }

  Future<String?> loadOwnerName(String shopId) async {
    final uri = Uri.parse('$_baseUrl/shops/$shopId/ownerName.json');
    final response = await http.get(uri);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load owner name');
    }

    if (response.body == 'null') {
      return null;
    }

    final decoded = jsonDecode(response.body);
    if (decoded is String && decoded.trim().isNotEmpty) {
      return decoded.trim();
    }
    return null;
  }

  Future<void> saveOwnerPhotoUrl(String shopId, String photoUrl) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('No authenticated shop user');
    }
    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoSaveOwnerPhotoUrl'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
        'shopId': shopId,
        'ownerPhotoUrl': photoUrl,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to save owner photo');
    }
  }
}

class BillingRepository {
  static const _functionsBaseUrl =
      'https://europe-west1-barbero-88d00.cloudfunctions.net';

  Future<BarberoBillingSnapshot> loadCurrentBilling() async {
    final user = FirebaseAuth.instance.currentUser;
    final session = currentBarberoSession.value;
    if (user == null || session == null) {
      throw Exception('missing-billing-context');
    }
    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoGetBillingStatus'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'idToken': idToken, 'shopId': session.shopId}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('billing-load-failed');
    }
    final decoded = jsonDecode(response.body);
    final billing = decoded is Map<String, dynamic> ? decoded['billing'] : null;
    if (billing is! Map) {
      throw Exception('invalid-billing-response');
    }
    return BarberoBillingSnapshot.fromJson(billing.cast<String, dynamic>());
  }

  Future<BarberoBillingSnapshot> savePlan(BarberoBillingPlan plan) async {
    final user = FirebaseAuth.instance.currentUser;
    final session = currentBarberoSession.value;
    if (user == null || session == null) {
      throw Exception('missing-billing-context');
    }
    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoSaveBillingPlan'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
        'shopId': session.shopId,
        'selectedPlan': plan == BarberoBillingPlan.yearly ? 'yearly' : 'monthly',
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('billing-plan-save-failed');
    }
    final decoded = jsonDecode(response.body);
    final billing = decoded is Map<String, dynamic> ? decoded['billing'] : null;
    if (billing is! Map) {
      throw Exception('invalid-billing-response');
    }
    return BarberoBillingSnapshot.fromJson(billing.cast<String, dynamic>());
  }

  Future<BarberoBillingSnapshot> startTrial(BarberoBillingPlan plan) async {
    final user = FirebaseAuth.instance.currentUser;
    final session = currentBarberoSession.value;
    if (user == null || session == null) {
      throw Exception('missing-billing-context');
    }
    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoStartSubscriptionTrial'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
        'shopId': session.shopId,
        'selectedPlan': plan == BarberoBillingPlan.yearly ? 'yearly' : 'monthly',
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('billing-trial-start-failed');
    }
    final decoded = jsonDecode(response.body);
    final billing = decoded is Map<String, dynamic> ? decoded['billing'] : null;
    if (billing is! Map) {
      throw Exception('invalid-billing-response');
    }
    return BarberoBillingSnapshot.fromJson(billing.cast<String, dynamic>());
  }
}

class AppointmentRepository {
  static const _baseUrl = 'https://barbero-88d00-default-rtdb.firebaseio.com';

  String get _currentShopId {
    return requireCurrentBarberoSession().shopId;
  }

  Future<List<Appointment>> loadAppointments() async {
    final uri = Uri.parse('$_baseUrl/shops/$_currentShopId/appointments.json');
    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load appointments');
    }
    if (response.body == 'null') {
      return const <Appointment>[];
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return const <Appointment>[];
    }

    final appointments = <Appointment>[];
    for (final entry in decoded.entries) {
      final value = entry.value;
      if (value is! Map) continue;
      final data = Map<String, dynamic>.from(value);
      final totalMinutes = (data['totalMinutes'] as num?)?.toInt() ?? 0;
      final totalPrice = (data['totalPrice'] as num?)?.toInt() ?? 0;
      appointments.add(
        Appointment(
          '${data['time'] ?? ''}',
          '${data['customerName'] ?? ''}',
          _appointmentServiceLabelFromRaw(data),
          "${totalMinutes > 0 ? totalMinutes : 0}'",
          id: entry.key,
          customerUid: '${data['customerUid'] ?? ''}',
          customerPhone: '${data['customerPhone'] ?? ''}',
          customerEmail: '${data['customerEmail'] ?? ''}',
          date: '${data['date'] ?? ''}',
          barberId: '${data['barberId'] ?? ''}',
          barberName: '${data['barberName'] ?? ''}',
          status: '${data['status'] ?? 'confirmed'}',
          blocked: data['blocked'] == true,
          blockReason: '${data['blockReason'] ?? ''}'.trim(),
          priceOverride: totalPrice,
          minutesOverride: totalMinutes,
        ),
      );
    }

    appointments.sort((left, right) {
      final dateCompare = left.date.compareTo(right.date);
      if (dateCompare != 0) return dateCompare;
      return _parseClockValue(
        left.time,
      ).compareTo(_parseClockValue(right.time));
    });
    return appointments;
  }
}

class AuthRepository {
  FirebaseAuth get _auth => FirebaseAuth.instance;

  Future<UserCredential> register({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> sendPasswordResetEmail({required String email}) {
    return _auth.sendPasswordResetEmail(email: email);
  }
}

class CrewInvitePreview {
  const CrewInvitePreview({
    required this.shopId,
    required this.shopName,
    required this.ownerName,
    required this.crewId,
    required this.role,
    required this.displayName,
    required this.status,
  });

  final String shopId;
  final String shopName;
  final String ownerName;
  final String crewId;
  final String role;
  final String displayName;
  final String status;
}

class CrewInvitationRepository {
  static const _functionsBaseUrl =
      'https://europe-west1-barbero-88d00.cloudfunctions.net';

  Future<CrewInvitePreview> lookupInvite(String email) async {
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoLookupCrewInvite'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim().toLowerCase()}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('crew-invite-not-found');
    }
    final decoded = jsonDecode(response.body);
    final invite = decoded is Map<String, dynamic> ? decoded['invite'] : null;
    if (invite is! Map) {
      throw Exception('invalid-crew-invite');
    }
    return CrewInvitePreview(
      shopId: '${invite['shopId'] ?? ''}'.trim(),
      shopName: '${invite['shopName'] ?? ''}'.trim(),
      ownerName: '${invite['ownerName'] ?? ''}'.trim(),
      crewId: '${invite['crewId'] ?? ''}'.trim(),
      role: '${invite['role'] ?? ''}'.trim(),
      displayName: '${invite['displayName'] ?? ''}'.trim(),
      status: '${invite['status'] ?? ''}'.trim(),
    );
  }

  Future<void> activateInvite(String shopId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('missing-crew-user');
    }
    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoActivateCrewInvite'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
        'shopId': shopId,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('crew-invite-activation-failed');
    }
  }
}

String _firebaseAuthMessage(FirebaseAuthException error) {
  switch (error.code) {
    case 'email-already-in-use':
      return '\u03a4\u03bf email \u03c7\u03c1\u03b7\u03c3\u03b9\u03bc\u03bf\u03c0\u03bf\u03b9\u03b5\u03af\u03c4\u03b1\u03b9 \u03ae\u03b4\u03b7.';
    case 'invalid-email':
      return '\u03a4\u03bf email \u03b4\u03b5\u03bd \u03b5\u03af\u03bd\u03b1\u03b9 \u03ad\u03b3\u03ba\u03c5\u03c1\u03bf.';
    case 'weak-password':
      return '\u039f \u03ba\u03c9\u03b4\u03b9\u03ba\u03cc\u03c2 \u03b5\u03af\u03bd\u03b1\u03b9 \u03c0\u03bf\u03bb\u03cd \u03b1\u03b4\u03cd\u03bd\u03b1\u03bc\u03bf\u03c2.';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return '\u039b\u03ac\u03b8\u03bf\u03c2 email \u03ae \u03ba\u03c9\u03b4\u03b9\u03ba\u03cc\u03c2.';
    case 'network-request-failed':
      return '\u03a0\u03c1\u03cc\u03b2\u03bb\u03b7\u03bc\u03b1 \u03c3\u03cd\u03bd\u03b4\u03b5\u03c3\u03b7\u03c2 \u03bc\u03b5 \u03c4\u03bf \u03b4\u03af\u03ba\u03c4\u03c5\u03bf.';
    case 'too-many-requests':
      return '\u03a0\u03ac\u03c1\u03b1 \u03c0\u03bf\u03bb\u03bb\u03ad\u03c2 \u03c0\u03c1\u03bf\u03c3\u03c0\u03ac\u03b8\u03b5\u03b9\u03b5\u03c2. \u0394\u03bf\u03ba\u03af\u03bc\u03b1\u03c3\u03b5 \u03be\u03b1\u03bd\u03ac \u03c3\u03b5 \u03bb\u03af\u03b3\u03bf.';
    default:
      return '\u0391\u03c0\u03bf\u03c4\u03c5\u03c7\u03af\u03b1 \u03c3\u03cd\u03bd\u03b4\u03b5\u03c3\u03b7\u03c2 \u03bc\u03b5 \u03c4\u03bf Firebase Auth.';
  }
}
