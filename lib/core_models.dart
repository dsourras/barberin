part of 'main.dart';

List<Map<String, dynamic>> _mapListFromRaw(Object? raw) {
  if (raw is List) {
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }
  if (raw is Map) {
    final entries = raw.entries.toList()
      ..sort((left, right) {
        final leftIndex = int.tryParse('${left.key}');
        final rightIndex = int.tryParse('${right.key}');
        if (leftIndex != null && rightIndex != null) {
          return leftIndex.compareTo(rightIndex);
        }
        return '${left.key}'.compareTo('${right.key}');
      });
    return entries
        .map((entry) => entry.value)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }
  return const <Map<String, dynamic>>[];
}

bool _hasRawCollection(Object? raw) => raw is List || raw is Map;

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
        return 'Σε αναμονή';
      case 'confirmed':
        return 'Επιβεβαιωμένο';
      case 'completed':
        return 'Ολοκληρωμένο';
      case 'cancelled':
        return 'Ακυρωμένο';
      case 'no_show':
        return 'Χωρίς εμφάνιση';
      default:
        return 'Επιβεβαιωμένο';
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
    this.isAvailable = false,
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
      isBreak = true,
      isAvailable = false;

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
  final bool isAvailable;
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
  if (barberinUsesEnglish) {
    const englishNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    if (index < 0 || index >= englishNames.length) return 'Day';
    return englishNames[index];
  }
  const names = [
    'Δευτέρα',
    'Τρίτη',
    'Τετάρτη',
    'Πέμπτη',
    'Παρασκευή',
    'Σάββατο',
    'Κυριακή',
  ];
  if (index < 0 || index >= names.length) return 'Ημέρα';
  return names[index];
}

class ServiceDurationSetting {
  const ServiceDurationSetting({
    required this.key,
    required this.label,
    required this.minutes,
    this.enabled = true,
    this.barberIds = const <String>[],
  });

  final String key;
  final String label;
  final int minutes;
  final bool enabled;
  final List<String> barberIds;

  bool isAvailableForBarber(String barberId) {
    final normalizedBarberId = barberId.trim();
    return enabled &&
        (barberIds.isEmpty || barberIds.contains(normalizedBarberId));
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'label': label,
      'minutes': minutes,
      'enabled': enabled,
      'barberIds': barberIds,
    };
  }

  factory ServiceDurationSetting.fromJson(Map<String, dynamic> json) {
    return ServiceDurationSetting(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      minutes: json['minutes'] as int? ?? 30,
      enabled: json['enabled'] != false,
      barberIds:
          (json['barberIds'] as List?)
              ?.map((item) => '$item'.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false) ??
          const <String>[],
    );
  }

  ServiceDurationSetting copyWith({
    String? key,
    String? label,
    int? minutes,
    bool? enabled,
    List<String>? barberIds,
  }) {
    return ServiceDurationSetting(
      key: key ?? this.key,
      label: label ?? this.label,
      minutes: minutes ?? this.minutes,
      enabled: enabled ?? this.enabled,
      barberIds: barberIds ?? this.barberIds,
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

class ServiceAddOnSetting {
  const ServiceAddOnSetting({
    required this.key,
    required this.label,
    required this.price,
    required this.minutes,
    this.enabled = false,
    this.compatibleServiceKeys = const <String>[],
  });

  final String key;
  final String label;
  final int price;
  final int minutes;
  final bool enabled;
  final List<String> compatibleServiceKeys;

  bool appliesToService(String serviceKey) {
    return enabled && compatibleServiceKeys.contains(serviceKey.trim());
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'label': label,
      'price': price,
      'minutes': minutes,
      'enabled': enabled,
      'compatibleServiceKeys': compatibleServiceKeys,
    };
  }

  factory ServiceAddOnSetting.fromJson(Map<String, dynamic> json) {
    return ServiceAddOnSetting(
      key: json['key'] as String? ?? '',
      label:
          json['label'] as String? ??
          '\u039b\u03bf\u03cd\u03c3\u03b9\u03bc\u03bf',
      price: (json['price'] as num?)?.toInt() ?? 0,
      minutes: (json['minutes'] as num?)?.toInt() ?? 5,
      enabled: json['enabled'] == true,
      compatibleServiceKeys:
          (json['compatibleServiceKeys'] as List?)
              ?.map((item) => '$item'.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false) ??
          const <String>[],
    );
  }

  ServiceAddOnSetting copyWith({
    String? key,
    String? label,
    int? price,
    int? minutes,
    bool? enabled,
    List<String>? compatibleServiceKeys,
  }) {
    return ServiceAddOnSetting(
      key: key ?? this.key,
      label: label ?? this.label,
      price: price ?? this.price,
      minutes: minutes ?? this.minutes,
      enabled: enabled ?? this.enabled,
      compatibleServiceKeys:
          compatibleServiceKeys ?? this.compatibleServiceKeys,
    );
  }
}

List<ServiceDurationSetting> buildDefaultServiceDurations() {
  return const [
    ServiceDurationSetting(
      key: 'classic_haircut',
      label: 'Classic haircut',
      minutes: 30,
    ),
    ServiceDurationSetting(key: 'skin_fade', label: 'Skin fade', minutes: 35),
    ServiceDurationSetting(key: 'beard_trim', label: 'Beard trim', minutes: 20),
    ServiceDurationSetting(
      key: 'haircut_and_beard',
      label: 'Haircut & beard',
      minutes: 45,
    ),
    ServiceDurationSetting(
      key: 'fade_and_beard',
      label: 'Fade & beard',
      minutes: 50,
    ),
    ServiceDurationSetting(
      key: 'kids_haircut',
      label: 'Kids haircut',
      minutes: 25,
    ),
    ServiceDurationSetting(key: 'buzz_cut', label: 'Buzz cut', minutes: 20),
    ServiceDurationSetting(
      key: 'scissor_cut',
      label: 'Scissor cut',
      minutes: 40,
    ),
    ServiceDurationSetting(key: 'head_shave', label: 'Head shave', minutes: 25),
    ServiceDurationSetting(
      key: 'hot_towel_shave',
      label: 'Hot towel shave',
      minutes: 30,
    ),
    ServiceDurationSetting(
      key: 'beard_shape',
      label: 'Beard shape',
      minutes: 25,
    ),
    ServiceDurationSetting(key: 'hair_styling', label: 'Styling', minutes: 15),
    ServiceDurationSetting(
      key: 'eyebrow_trim',
      label: 'Eyebrow trim',
      minutes: 10,
    ),
  ];
}

List<ServicePriceSetting> buildDefaultServicePrices() {
  return const [
    ServicePriceSetting(
      key: 'classic_haircut',
      label: 'Classic haircut',
      price: 15,
    ),
    ServicePriceSetting(key: 'skin_fade', label: 'Skin fade', price: 18),
    ServicePriceSetting(key: 'beard_trim', label: 'Beard trim', price: 10),
    ServicePriceSetting(
      key: 'haircut_and_beard',
      label: 'Haircut & beard',
      price: 22,
    ),
    ServicePriceSetting(
      key: 'fade_and_beard',
      label: 'Fade & beard',
      price: 25,
    ),
    ServicePriceSetting(key: 'kids_haircut', label: 'Kids haircut', price: 12),
    ServicePriceSetting(key: 'buzz_cut', label: 'Buzz cut', price: 10),
    ServicePriceSetting(key: 'scissor_cut', label: 'Scissor cut', price: 18),
    ServicePriceSetting(key: 'head_shave', label: 'Head shave', price: 12),
    ServicePriceSetting(
      key: 'hot_towel_shave',
      label: 'Hot towel shave',
      price: 15,
    ),
    ServicePriceSetting(key: 'beard_shape', label: 'Beard shape', price: 12),
    ServicePriceSetting(key: 'hair_styling', label: 'Styling', price: 8),
    ServicePriceSetting(key: 'eyebrow_trim', label: 'Eyebrow trim', price: 5),
  ];
}

List<ServiceAddOnSetting> buildDefaultServiceAddOns() {
  return const [
    ServiceAddOnSetting(
      key: 'hair_wash',
      label: 'Hair wash',
      price: 0,
      minutes: 5,
      compatibleServiceKeys: [
        'classic_haircut',
        'skin_fade',
        'haircut_and_beard',
        'fade_and_beard',
        'kids_haircut',
        'buzz_cut',
        'scissor_cut',
      ],
    ),
  ];
}

class SlotCapacityOverride {
  const SlotCapacityOverride({
    required this.dayIndex,
    required this.start,
    required this.end,
    required this.appointmentsPerSlot,
  });

  final int dayIndex;
  final String start;
  final String end;
  final int appointmentsPerSlot;

  Map<String, dynamic> toJson() {
    return {
      'dayIndex': dayIndex,
      'start': start,
      'end': end,
      'appointmentsPerSlot': appointmentsPerSlot,
    };
  }

  factory SlotCapacityOverride.fromJson(Map<String, dynamic> json) {
    return SlotCapacityOverride(
      dayIndex: (json['dayIndex'] as num?)?.toInt() ?? 0,
      start: json['start'] as String? ?? '--:--',
      end: json['end'] as String? ?? '--:--',
      appointmentsPerSlot: (json['appointmentsPerSlot'] as num?)?.toInt() ?? 1,
    );
  }

  SlotCapacityOverride copyWith({
    int? dayIndex,
    String? start,
    String? end,
    int? appointmentsPerSlot,
  }) {
    return SlotCapacityOverride(
      dayIndex: dayIndex ?? this.dayIndex,
      start: start ?? this.start,
      end: end ?? this.end,
      appointmentsPerSlot: appointmentsPerSlot ?? this.appointmentsPerSlot,
    );
  }
}

class ClosedDateOverride {
  const ClosedDateOverride({
    required this.dateKey,
    required this.label,
    required this.isClosed,
  });

  final String dateKey;
  final String label;
  final bool isClosed;

  Map<String, dynamic> toJson() {
    return {'date': dateKey, 'label': label, 'isClosed': isClosed};
  }

  factory ClosedDateOverride.fromJson(Map<String, dynamic> json) {
    return ClosedDateOverride(
      dateKey: '${json['date'] ?? json['dateKey'] ?? ''}'.trim(),
      label: '${json['label'] ?? ''}'.trim(),
      isClosed: json['isClosed'] == true,
    );
  }

  ClosedDateOverride copyWith({
    String? dateKey,
    String? label,
    bool? isClosed,
  }) {
    return ClosedDateOverride(
      dateKey: dateKey ?? this.dateKey,
      label: label ?? this.label,
      isClosed: isClosed ?? this.isClosed,
    );
  }
}

class BarberWeeklySchedule {
  const BarberWeeklySchedule({required this.barberId, required this.days});

  final String barberId;
  final List<ScheduleDay> days;

  Map<String, dynamic> toJson() {
    return {
      'barberId': barberId,
      'days': days.map((day) => day.toJson()).toList(),
    };
  }

  factory BarberWeeklySchedule.fromJson(Map<String, dynamic> json) {
    final rawDays = (json['days'] as List<dynamic>? ?? const [])
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
    return BarberWeeklySchedule(
      barberId: '${json['barberId'] ?? ''}'.trim(),
      days: rawDays.isEmpty ? buildDefaultWeeklySchedule() : rawDays,
    );
  }

  BarberWeeklySchedule copyWith({String? barberId, List<ScheduleDay>? days}) {
    return BarberWeeklySchedule(
      barberId: barberId ?? this.barberId,
      days: days ?? this.days,
    );
  }
}

class WeeklyScheduleData {
  const WeeklyScheduleData({
    required this.slotMinutes,
    required this.appointmentsPerSlot,
    required this.slotCapacityOverrides,
    required this.closedDateOverrides,
    required this.barberSchedules,
    required this.showPrices,
    required this.serviceDurations,
    required this.servicePrices,
    this.serviceAddOns = const <ServiceAddOnSetting>[],
    required this.days,
  });

  final int slotMinutes;
  final int appointmentsPerSlot;
  final List<SlotCapacityOverride> slotCapacityOverrides;
  final List<ClosedDateOverride> closedDateOverrides;
  final List<BarberWeeklySchedule> barberSchedules;
  final bool showPrices;
  final List<ServiceDurationSetting> serviceDurations;
  final List<ServicePriceSetting> servicePrices;
  final List<ServiceAddOnSetting> serviceAddOns;
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

  Future<Map<String, String>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('No authenticated shop user');
    }
    final idToken = await user.getIdToken();
    if (idToken == null || idToken.trim().isEmpty) {
      throw Exception('Missing authenticated shop token');
    }
    return <String, String>{'Authorization': 'Bearer $idToken'};
  }

  WeeklyScheduleData buildDefaultData() {
    return WeeklyScheduleData(
      slotMinutes: 30,
      appointmentsPerSlot: 1,
      slotCapacityOverrides: const <SlotCapacityOverride>[],
      closedDateOverrides: const <ClosedDateOverride>[],
      barberSchedules: const <BarberWeeklySchedule>[],
      showPrices: false,
      serviceDurations: buildDefaultServiceDurations(),
      servicePrices: buildDefaultServicePrices(),
      serviceAddOns: buildDefaultServiceAddOns(),
      days: buildDefaultWeeklySchedule(),
    );
  }

  Future<WeeklyScheduleData?> load() async {
    final Map<String, dynamic> data;
    if (isBarberinWindows) {
      final remote = await WindowsBackendAdapter.instance.loadSchedule(
        _currentShopId,
      );
      if (remote.isEmpty) {
        return null;
      }
      data = remote;
    } else {
      final response = await http.get(
        _uriForShop(_currentShopId),
        headers: await _authHeaders(),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Failed to load weekly schedule');
      }
      if (response.body == 'null') {
        return null;
      }
      data = jsonDecode(response.body) as Map<String, dynamic>;
    }
    final slotMinutes = data['slotMinutes'] as int? ?? 30;
    final appointmentsPerSlot = data['appointmentsPerSlot'] as int? ?? 1;
    final rawSlotCapacityOverrides = _mapListFromRaw(
      data['slotCapacityOverrides'],
    ).map((item) => SlotCapacityOverride.fromJson(item)).toList();
    final rawClosedDateOverrides = _mapListFromRaw(data['closedDateOverrides'])
        .map((item) => ClosedDateOverride.fromJson(item))
        .where((item) => item.dateKey.isNotEmpty)
        .toList();
    final rawBarberSchedules = _mapListFromRaw(data['barberSchedules'])
        .map((item) => BarberWeeklySchedule.fromJson(item))
        .where((item) => item.barberId.isNotEmpty)
        .toList();
    final showPrices = data['showPrices'] == true;
    final rawServiceDurations = _mapListFromRaw(
      data['serviceDurations'],
    ).map((item) => ServiceDurationSetting.fromJson(item)).toList();
    final rawServicePrices = _mapListFromRaw(
      data['servicePrices'],
    ).map((item) => ServicePriceSetting.fromJson(item)).toList();
    final rawServiceAddOns = _mapListFromRaw(data['serviceAddOns'])
        .map((item) => ServiceAddOnSetting.fromJson(item))
        .where((item) => item.key.isNotEmpty)
        .toList();
    final rawDays = _mapListFromRaw(data['days']).asMap().entries.map((entry) {
      final day = ScheduleDay.fromJson(entry.value);
      return day.copyWith(name: scheduleDayNameForIndex(entry.key));
    }).toList();

    return WeeklyScheduleData(
      slotMinutes: slotMinutes,
      appointmentsPerSlot: appointmentsPerSlot,
      slotCapacityOverrides: rawSlotCapacityOverrides,
      closedDateOverrides: rawClosedDateOverrides,
      barberSchedules: rawBarberSchedules,
      showPrices: showPrices,
      serviceDurations: _hasRawCollection(data['serviceDurations'])
          ? rawServiceDurations
          : buildDefaultServiceDurations(),
      servicePrices: _hasRawCollection(data['servicePrices'])
          ? rawServicePrices
          : buildDefaultServicePrices(),
      serviceAddOns: _hasRawCollection(data['serviceAddOns'])
          ? rawServiceAddOns
          : buildDefaultServiceAddOns(),
      days: rawDays,
    );
  }

  Future<WeeklyScheduleData> loadOrCreateDefault() async {
    if (isBarberinWindows) {
      final existing = await load();
      if (existing != null) {
        return existing;
      }
      final defaults = buildDefaultData();
      await save(
        slotMinutes: defaults.slotMinutes,
        appointmentsPerSlot: defaults.appointmentsPerSlot,
        slotCapacityOverrides: defaults.slotCapacityOverrides,
        closedDateOverrides: defaults.closedDateOverrides,
        barberSchedules: defaults.barberSchedules,
        showPrices: defaults.showPrices,
        serviceDurations: defaults.serviceDurations,
        servicePrices: defaults.servicePrices,
        serviceAddOns: defaults.serviceAddOns,
        days: defaults.days,
      );
      return defaults;
    }
    final response = await http.get(
      _uriForShop(_currentShopId),
      headers: await _authHeaders(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load weekly schedule');
    }

    if (response.body == 'null') {
      final defaults = buildDefaultData();
      await save(
        slotMinutes: defaults.slotMinutes,
        appointmentsPerSlot: defaults.appointmentsPerSlot,
        slotCapacityOverrides: defaults.slotCapacityOverrides,
        closedDateOverrides: defaults.closedDateOverrides,
        barberSchedules: defaults.barberSchedules,
        showPrices: defaults.showPrices,
        serviceDurations: defaults.serviceDurations,
        servicePrices: defaults.servicePrices,
        serviceAddOns: defaults.serviceAddOns,
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
        slotCapacityOverrides: defaults.slotCapacityOverrides,
        closedDateOverrides: defaults.closedDateOverrides,
        barberSchedules: defaults.barberSchedules,
        showPrices: defaults.showPrices,
        serviceDurations: defaults.serviceDurations,
        servicePrices: defaults.servicePrices,
        serviceAddOns: defaults.serviceAddOns,
        days: defaults.days,
      );
      return defaults;
    }

    final hasServiceDurations = _hasRawCollection(raw['serviceDurations']);
    final hasServicePrices = _hasRawCollection(raw['servicePrices']);
    final hasSlotCapacityOverrides = _hasRawCollection(
      raw['slotCapacityOverrides'],
    );
    final hasClosedDateOverrides = _hasRawCollection(
      raw['closedDateOverrides'],
    );
    final hasBarberSchedules = _hasRawCollection(raw['barberSchedules']);
    final hasShowPrices = raw['showPrices'] is bool;
    final hasServiceAddOns = _hasRawCollection(raw['serviceAddOns']);
    if (!hasServiceDurations ||
        !hasServicePrices ||
        !hasSlotCapacityOverrides ||
        !hasClosedDateOverrides ||
        !hasBarberSchedules ||
        !hasShowPrices ||
        !hasServiceAddOns) {
      final defaults = buildDefaultData();
      final merged = WeeklyScheduleData(
        slotMinutes: existing.slotMinutes,
        appointmentsPerSlot: existing.appointmentsPerSlot,
        slotCapacityOverrides: hasSlotCapacityOverrides
            ? existing.slotCapacityOverrides
            : defaults.slotCapacityOverrides,
        closedDateOverrides: hasClosedDateOverrides
            ? existing.closedDateOverrides
            : defaults.closedDateOverrides,
        barberSchedules: hasBarberSchedules
            ? existing.barberSchedules
            : defaults.barberSchedules,
        showPrices: hasShowPrices ? existing.showPrices : defaults.showPrices,
        serviceDurations: hasServiceDurations
            ? existing.serviceDurations
            : defaults.serviceDurations,
        servicePrices: hasServicePrices
            ? existing.servicePrices
            : defaults.servicePrices,
        serviceAddOns: hasServiceAddOns
            ? existing.serviceAddOns
            : defaults.serviceAddOns,
        days: existing.days,
      );
      await save(
        slotMinutes: merged.slotMinutes,
        appointmentsPerSlot: merged.appointmentsPerSlot,
        slotCapacityOverrides: merged.slotCapacityOverrides,
        closedDateOverrides: merged.closedDateOverrides,
        barberSchedules: merged.barberSchedules,
        showPrices: merged.showPrices,
        serviceDurations: merged.serviceDurations,
        servicePrices: merged.servicePrices,
        serviceAddOns: merged.serviceAddOns,
        days: merged.days,
      );
      return merged;
    }

    return existing;
  }

  Future<void> save({
    required int slotMinutes,
    required int appointmentsPerSlot,
    required List<SlotCapacityOverride> slotCapacityOverrides,
    required List<ClosedDateOverride> closedDateOverrides,
    required List<BarberWeeklySchedule> barberSchedules,
    required bool showPrices,
    required List<ServiceDurationSetting> serviceDurations,
    required List<ServicePriceSetting> servicePrices,
    List<ServiceAddOnSetting>? serviceAddOns,
    required List<ScheduleDay> days,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final session = requireCurrentBarberoSession();
    if (user == null) throw Exception('No authenticated shop user');
    final idToken = await user.getIdToken();
    final schedulePayload = <String, dynamic>{
      'slotMinutes': slotMinutes,
      'appointmentsPerSlot': appointmentsPerSlot,
      'slotCapacityOverrides': slotCapacityOverrides
          .map((item) => item.toJson())
          .toList(),
      'closedDateOverrides': closedDateOverrides
          .map((item) => item.toJson())
          .toList(),
      'barberSchedules': barberSchedules.map((item) => item.toJson()).toList(),
      'showPrices': showPrices,
      'serviceDurations': serviceDurations
          .map((service) => service.toJson())
          .toList(),
      'servicePrices': servicePrices
          .map((service) => service.toJson())
          .toList(),
      'days': days.map((day) => day.toJson()).toList(),
    };
    if (serviceAddOns != null) {
      schedulePayload['serviceAddOns'] = serviceAddOns
          .map((addOn) => addOn.toJson())
          .toList();
    }

    if (isBarberinWindows) {
      await WindowsBackendAdapter.instance.saveSchedule(
        shopId: session.shopId,
        schedule: schedulePayload,
      );
      return;
    }

    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoSaveWeeklySchedule'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
        'shopId': session.shopId,
        'schedule': schedulePayload,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to save weekly schedule');
    }
  }
}

class AppointmentSettings {
  const AppointmentSettings({
    this.autoConfirmAppointments = false,
    this.remindersEnabled = true,
    this.customerCancellationCutoffMinutes = 0,
    this.customerRescheduleCutoffMinutes = 0,
  });

  final bool autoConfirmAppointments;
  final bool remindersEnabled;
  final int customerCancellationCutoffMinutes;
  final int customerRescheduleCutoffMinutes;

  static int _cutoffMinutes(dynamic value) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    if (parsed == null || parsed <= 0) return 0;
    const options = <int>[0, 30, 60, 120, 180, 360, 720, 1440];
    final bounded = parsed.clamp(0, 1440);
    return options.reduce(
      (closest, option) =>
          (option - bounded).abs() < (closest - bounded).abs()
              ? option
              : closest,
    );
  }

  factory AppointmentSettings.fromJson(Map<String, dynamic> json) {
    return AppointmentSettings(
      autoConfirmAppointments: json['autoConfirmAppointments'] == true,
      remindersEnabled: json['remindersEnabled'] != false,
      customerCancellationCutoffMinutes:
          _cutoffMinutes(json['customerCancellationCutoffMinutes']),
      customerRescheduleCutoffMinutes:
          _cutoffMinutes(json['customerRescheduleCutoffMinutes']),
    );
  }

  AppointmentSettings copyWith({
    bool? autoConfirmAppointments,
    bool? remindersEnabled,
    int? customerCancellationCutoffMinutes,
    int? customerRescheduleCutoffMinutes,
  }) {
    return AppointmentSettings(
      autoConfirmAppointments:
          autoConfirmAppointments ?? this.autoConfirmAppointments,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      customerCancellationCutoffMinutes:
          customerCancellationCutoffMinutes ??
          this.customerCancellationCutoffMinutes,
      customerRescheduleCutoffMinutes:
          customerRescheduleCutoffMinutes ??
          this.customerRescheduleCutoffMinutes,
    );
  }
}

class AppointmentSettingsRepository {
  static const _baseUrl = 'https://barbero-88d00-default-rtdb.firebaseio.com';
  static const _functionsBaseUrl =
      'https://europe-west1-barbero-88d00.cloudfunctions.net';

  String get _currentShopId => requireCurrentBarberoSession().shopId;

  Future<String> _idToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('No authenticated shop user');
    }
    final token = await user.getIdToken();
    if (token == null || token.trim().isEmpty) {
      throw Exception('Missing authenticated shop token');
    }
    return token;
  }

  Future<AppointmentSettings> load() async {
    final token = await _idToken();
    final response = await http.get(
      Uri.parse('$_baseUrl/shops/$_currentShopId/appointmentSettings.json'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load appointment settings');
    }
    if (response.body == 'null' || response.body.trim().isEmpty) {
      return const AppointmentSettings();
    }
    final decoded = jsonDecode(response.body);
    return decoded is Map
        ? AppointmentSettings.fromJson(Map<String, dynamic>.from(decoded))
        : const AppointmentSettings();
  }

  Future<AppointmentSettings> save({
    required AppointmentSettings settings,
  }) async {
    final token = await _idToken();
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoSaveAppointmentSettings'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': token,
        'shopId': _currentShopId,
        'appointmentSettings': {
          'autoConfirmAppointments': settings.autoConfirmAppointments,
          'remindersEnabled': settings.remindersEnabled,
          'customerCancellationCutoffMinutes':
              settings.customerCancellationCutoffMinutes,
          'customerRescheduleCutoffMinutes':
              settings.customerRescheduleCutoffMinutes,
        },
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to save appointment settings');
    }
    final decoded = jsonDecode(response.body);
    final payload = decoded is Map && decoded['appointmentSettings'] is Map
        ? Map<String, dynamic>.from(decoded['appointmentSettings'] as Map)
        : <String, dynamic>{};
    return payload.isEmpty ? settings : AppointmentSettings.fromJson(payload);
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
    this.city = '',
    this.logoBase64 = '',
    this.logoContentType = '',
  });

  final String shopId;
  final String ownerName;
  final String ownerPhone;
  final String ownerEmail;
  final String shopName;
  final String address;
  final String city;
  final String logoBase64;
  final String logoContentType;
}

class ShopRegistrationRepository {
  static const _baseUrl = 'https://barbero-88d00-default-rtdb.firebaseio.com';
  static const _functionsBaseUrl =
      'https://europe-west1-barbero-88d00.cloudfunctions.net';

  Future<String> registerShop(ShopRegistrationData data) async {
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
          'city': data.city,
          'logoBase64': data.logoBase64,
          'logoContentType': data.logoContentType,
        },
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      var details = '';
      try {
        final decodedError = jsonDecode(response.body);
        if (decodedError is Map) {
          details = '${decodedError['message'] ?? ''}'.trim();
          final serverDetails = '${decodedError['details'] ?? ''}'.trim();
          if (serverDetails.isNotEmpty) {
            details = details.isEmpty
                ? serverDetails
                : '$details: $serverDetails';
          }
        }
      } catch (_) {
        details = response.body.trim();
      }
      throw Exception(
        details.isEmpty ? 'Failed to register shop' : 'register-shop-$details',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      final shopId = '${decoded['shopId'] ?? ''}'.trim();
      if (shopId.isNotEmpty) {
        return shopId;
      }
    }
    throw Exception('Invalid shop registration response');
  }

  Future<String?> loadOwnerName(String shopId) async {
    final uri = Uri.parse('$_baseUrl/shops/$shopId/ownerName.json');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return null;
    }
    final idToken = await user.getIdToken();
    if (idToken == null || idToken.trim().isEmpty) {
      return null;
    }
    final response = await http.get(
      uri,
      headers: <String, String>{'Authorization': 'Bearer $idToken'},
    );

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
    final session = currentBarberoSession.value;
    if (session == null) {
      throw Exception('missing-billing-context');
    }
    if (isBarberinWindows) {
      final billing = await WindowsBackendAdapter.instance.loadBilling(
        session.shopId,
      );
      return BarberoBillingSnapshot.fromJson(billing);
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
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
    if (isBarberinWindows) {
      // Windows is intentionally status-only. Plan changes must be started
      // from the native store that owns the subscription entitlement.
      throw Exception('native-store-required');
    }
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
        'selectedPlan': plan == BarberoBillingPlan.yearly
            ? 'yearly'
            : 'monthly',
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
}

class ShopSustainabilityProfile {
  const ShopSustainabilityProfile({
    this.monthlyRevenue = 0,
    this.otherRevenue = 0,
    this.fixedCosts = 0,
    this.rentCost = 0,
    this.payrollCost = 0,
    this.utilitiesCost = 0,
    this.suppliesCost = 0,
    this.taxesCost = 0,
    this.marketingCost = 0,
    this.equipmentCost = 0,
    this.cashReserve = 0,
    this.workingHoursMonth = 160,
    this.updatedAtIso = '',
  });

  final double monthlyRevenue;
  final double otherRevenue;
  final double fixedCosts;
  final double rentCost;
  final double payrollCost;
  final double utilitiesCost;
  final double suppliesCost;
  final double taxesCost;
  final double marketingCost;
  final double equipmentCost;
  final double cashReserve;
  final double workingHoursMonth;
  final String updatedAtIso;

  double get totalIncome => monthlyRevenue + otherRevenue;

  double get totalExpenses =>
      fixedCosts +
      rentCost +
      payrollCost +
      utilitiesCost +
      suppliesCost +
      taxesCost +
      marketingCost +
      equipmentCost;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'monthlyRevenue': monthlyRevenue,
      'otherRevenue': otherRevenue,
      'fixedCosts': fixedCosts,
      'rentCost': rentCost,
      'payrollCost': payrollCost,
      'utilitiesCost': utilitiesCost,
      'suppliesCost': suppliesCost,
      'taxesCost': taxesCost,
      'marketingCost': marketingCost,
      'equipmentCost': equipmentCost,
      'cashReserve': cashReserve,
      'workingHoursMonth': workingHoursMonth,
      'updatedAt': updatedAtIso,
    };
  }

  factory ShopSustainabilityProfile.fromJson(Map<String, dynamic> json) {
    double toValue(Object? value) {
      if (value is double) return value;
      if (value is num) return value.toDouble();
      return double.tryParse('${value ?? ''}') ?? 0;
    }

    return ShopSustainabilityProfile(
      monthlyRevenue: toValue(json['monthlyRevenue']),
      otherRevenue: toValue(json['otherRevenue']),
      fixedCosts: toValue(json['fixedCosts']),
      rentCost: toValue(json['rentCost']),
      payrollCost: toValue(json['payrollCost']),
      utilitiesCost: toValue(json['utilitiesCost']),
      suppliesCost: toValue(json['suppliesCost']),
      taxesCost: toValue(json['taxesCost']),
      marketingCost: toValue(json['marketingCost']),
      equipmentCost: toValue(json['equipmentCost']),
      cashReserve: toValue(json['cashReserve']),
      workingHoursMonth: toValue(json['workingHoursMonth']) <= 0
          ? 160
          : toValue(json['workingHoursMonth']),
      updatedAtIso: '${json['updatedAt'] ?? ''}'.trim(),
    );
  }

  ShopSustainabilityProfile copyWith({
    double? monthlyRevenue,
    double? otherRevenue,
    double? fixedCosts,
    double? rentCost,
    double? payrollCost,
    double? utilitiesCost,
    double? suppliesCost,
    double? taxesCost,
    double? marketingCost,
    double? equipmentCost,
    double? cashReserve,
    double? workingHoursMonth,
    String? updatedAtIso,
  }) {
    return ShopSustainabilityProfile(
      monthlyRevenue: monthlyRevenue ?? this.monthlyRevenue,
      otherRevenue: otherRevenue ?? this.otherRevenue,
      fixedCosts: fixedCosts ?? this.fixedCosts,
      rentCost: rentCost ?? this.rentCost,
      payrollCost: payrollCost ?? this.payrollCost,
      utilitiesCost: utilitiesCost ?? this.utilitiesCost,
      suppliesCost: suppliesCost ?? this.suppliesCost,
      taxesCost: taxesCost ?? this.taxesCost,
      marketingCost: marketingCost ?? this.marketingCost,
      equipmentCost: equipmentCost ?? this.equipmentCost,
      cashReserve: cashReserve ?? this.cashReserve,
      workingHoursMonth: workingHoursMonth ?? this.workingHoursMonth,
      updatedAtIso: updatedAtIso ?? this.updatedAtIso,
    );
  }
}

class ShopSustainabilityRepository {
  static const _functionsBaseUrl =
      'https://europe-west1-barbero-88d00.cloudfunctions.net';

  Future<ShopSustainabilityProfile> load() async {
    final user = FirebaseAuth.instance.currentUser;
    final session = currentBarberoSession.value;
    if (user == null || session == null) {
      throw Exception('missing-sustainability-context');
    }
    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoGetSustainabilityProfile'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'idToken': idToken, 'shopId': session.shopId}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('sustainability-load-failed');
    }
    final decoded = jsonDecode(response.body);
    final profile = decoded is Map<String, dynamic> ? decoded['profile'] : null;
    if (profile is! Map) {
      return const ShopSustainabilityProfile();
    }
    return ShopSustainabilityProfile.fromJson(profile.cast<String, dynamic>());
  }

  Future<ShopSustainabilityProfile> save(
    ShopSustainabilityProfile profile,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    final session = currentBarberoSession.value;
    if (user == null || session == null) {
      throw Exception('missing-sustainability-context');
    }
    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoSaveSustainabilityProfile'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
        'shopId': session.shopId,
        'profile': profile.toJson(),
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('sustainability-save-failed');
    }
    final decoded = jsonDecode(response.body);
    final saved = decoded is Map<String, dynamic> ? decoded['profile'] : null;
    if (saved is! Map) {
      throw Exception('invalid-sustainability-response');
    }
    return ShopSustainabilityProfile.fromJson(saved.cast<String, dynamic>());
  }
}

class AppointmentRepository {
  static const _baseUrl = 'https://barbero-88d00-default-rtdb.firebaseio.com';

  String get _currentShopId {
    return requireCurrentBarberoSession().shopId;
  }

  Future<List<Appointment>> loadAppointments() async {
    final appointments = <Appointment>[];
    if (isBarberinWindows) {
      final remote = await WindowsBackendAdapter.instance.loadAppointments(
        _currentShopId,
      );
      for (final data in remote) {
        _appendAppointment(appointments, data, '${data['id'] ?? ''}');
      }
    } else {
      final uri = Uri.parse(
        '$_baseUrl/shops/$_currentShopId/appointments.json',
      );
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No authenticated shop user');
      }
      final idToken = await user.getIdToken();
      if (idToken == null || idToken.trim().isEmpty) {
        throw Exception('Missing authenticated shop token');
      }
      final response = await http.get(
        uri,
        headers: <String, String>{'Authorization': 'Bearer $idToken'},
      );
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
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        _appendAppointment(
          appointments,
          Map<String, dynamic>.from(value),
          entry.key,
        );
      }
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

  void _appendAppointment(
    List<Appointment> appointments,
    Map<String, dynamic> data,
    String id,
  ) {
    final totalMinutes = (data['totalMinutes'] as num?)?.toInt() ?? 0;
    final totalPrice = (data['totalPrice'] as num?)?.toInt() ?? 0;
    appointments.add(
      Appointment(
        '${data['time'] ?? ''}',
        '${data['customerName'] ?? ''}',
        _appointmentServiceLabelFromRaw(data),
        "${totalMinutes > 0 ? totalMinutes : 0}'",
        id: id,
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

  Future<List<CrewInvitePreview>> lookupInvites(String email) async {
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoLookupCrewInvite'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim().toLowerCase()}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('crew-invite-not-found');
    }
    final decoded = jsonDecode(response.body);
    final rawInvites = decoded is Map<String, dynamic>
        ? decoded['invites']
        : null;
    final inviteItems = rawInvites is List
        ? rawInvites.whereType<Map>().toList()
        : <Map>[];
    if (inviteItems.isEmpty && decoded is Map<String, dynamic>) {
      final legacyInvite = decoded['invite'];
      if (legacyInvite is Map) {
        inviteItems.add(legacyInvite);
      }
    }
    if (inviteItems.isEmpty) {
      throw Exception('invalid-crew-invite');
    }

    return inviteItems
        .map(
          (invite) => CrewInvitePreview(
            shopId: '${invite['shopId'] ?? ''}'.trim(),
            shopName: '${invite['shopName'] ?? ''}'.trim(),
            ownerName: '${invite['ownerName'] ?? ''}'.trim(),
            crewId: '${invite['crewId'] ?? ''}'.trim(),
            role: '${invite['role'] ?? ''}'.trim(),
            displayName: '${invite['displayName'] ?? ''}'.trim(),
            status: '${invite['status'] ?? ''}'.trim(),
          ),
        )
        .where((invite) => invite.shopId.isNotEmpty && invite.crewId.isNotEmpty)
        .toList(growable: false);
  }

  Future<CrewInvitePreview> lookupInvite(String email) async {
    final invites = await lookupInvites(email);
    if (invites.isEmpty) {
      throw Exception('crew-invite-not-found');
    }
    return invites.first;
  }

  Future<void> activateInvite({
    required String shopId,
    required String crewId,
  }) async {
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
        'crewId': crewId,
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
      return '\u03a4\u03bf \u03b7\u03bb\u03b5\u03ba\u03c4\u03c1\u03bf\u03bd\u03b9\u03ba\u03cc \u03c4\u03b1\u03c7\u03c5\u03b4\u03c1\u03bf\u03bc\u03b5\u03af\u03bf \u03c7\u03c1\u03b7\u03c3\u03b9\u03bc\u03bf\u03c0\u03bf\u03b9\u03b5\u03af\u03c4\u03b1\u03b9 \u03ae\u03b4\u03b7.';
    case 'invalid-email':
      return '\u03a4\u03bf \u03b7\u03bb\u03b5\u03ba\u03c4\u03c1\u03bf\u03bd\u03b9\u03ba\u03cc \u03c4\u03b1\u03c7\u03c5\u03b4\u03c1\u03bf\u03bc\u03b5\u03af\u03bf \u03b4\u03b5\u03bd \u03b5\u03af\u03bd\u03b1\u03b9 \u03ad\u03b3\u03ba\u03c5\u03c1\u03bf.';
    case 'weak-password':
      return '\u039f \u03ba\u03c9\u03b4\u03b9\u03ba\u03cc\u03c2 \u03b5\u03af\u03bd\u03b1\u03b9 \u03c0\u03bf\u03bb\u03cd \u03b1\u03b4\u03cd\u03bd\u03b1\u03bc\u03bf\u03c2.';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return '\u039b\u03ac\u03b8\u03bf\u03c2 \u03b7\u03bb\u03b5\u03ba\u03c4\u03c1\u03bf\u03bd\u03b9\u03ba\u03bf\u03cd \u03c4\u03b1\u03c7\u03c5\u03b4\u03c1\u03bf\u03bc\u03b5\u03af\u03bf\u03c5 \u03ae \u03ba\u03c9\u03b4\u03b9\u03ba\u03bf\u03cd.';
    case 'network-request-failed':
      return '\u03a0\u03c1\u03cc\u03b2\u03bb\u03b7\u03bc\u03b1 \u03c3\u03cd\u03bd\u03b4\u03b5\u03c3\u03b7\u03c2 \u03bc\u03b5 \u03c4\u03bf \u03b4\u03af\u03ba\u03c4\u03c5\u03bf.';
    case 'too-many-requests':
      return '\u03a0\u03ac\u03c1\u03b1 \u03c0\u03bf\u03bb\u03bb\u03ad\u03c2 \u03c0\u03c1\u03bf\u03c3\u03c0\u03ac\u03b8\u03b5\u03b9\u03b5\u03c2. \u0394\u03bf\u03ba\u03af\u03bc\u03b1\u03c3\u03b5 \u03be\u03b1\u03bd\u03ac \u03c3\u03b5 \u03bb\u03af\u03b3\u03bf.';
    case 'operation-not-allowed':
      return '\u0397 \u03bc\u03ad\u03b8\u03bf\u03b4\u03bf\u03c2 \u03c3\u03cd\u03bd\u03b4\u03b5\u03c3\u03b7\u03c2 \u03b4\u03b5\u03bd \u03ad\u03c7\u03b5\u03b9 \u03b5\u03bd\u03b5\u03c1\u03b3\u03bf\u03c0\u03bf\u03b9\u03b7\u03b8\u03b5\u03af \u03c3\u03c4\u03bf Firebase.';
    case 'app-not-authorized':
    case 'invalid-api-key':
      return '\u0397 \u03c1\u03cd\u03b8\u03bc\u03b9\u03c3\u03b7 Firebase \u03c4\u03b7\u03c2 \u03b5\u03c6\u03b1\u03c1\u03bc\u03bf\u03b3\u03ae\u03c2 \u03b4\u03b5\u03bd \u03b5\u03af\u03bd\u03b1\u03b9 \u03ad\u03b3\u03ba\u03c5\u03c1\u03b7.';
    default:
      return '\u0391\u03c0\u03bf\u03c4\u03c5\u03c7\u03af\u03b1 \u03c3\u03cd\u03bd\u03b4\u03b5\u03c3\u03b7\u03c2 Firebase Auth (${error.code}).';
  }
}
