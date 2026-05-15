import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

part 'app_flow.dart';
part 'auth_screens.dart';
part 'barber_shell.dart';
part 'program_pages.dart';
part 'home_page.dart';
part 'weekly_schedule_page.dart';
part 'shared_ui.dart';
part 'core_models.dart';
part 'crew_management.dart';
part 'admin_tools.dart';
part 'legal_pages.dart';
part 'help_center.dart';
part 'notifications_page.dart';
part 'billing_page.dart';
part 'billing_store.dart';

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final ValueNotifier<BarberoSession?> currentBarberoSession =
    ValueNotifier<BarberoSession?>(null);
final ValueNotifier<BarberoBillingSnapshot?> currentBarberoBilling =
    ValueNotifier<BarberoBillingSnapshot?>(null);
final ValueNotifier<List<BarberoNotificationItem>> barberoNotifications =
    ValueNotifier<List<BarberoNotificationItem>>(
      const <BarberoNotificationItem>[],
    );

const String _barberoNotificationsStorageKey = 'barbero_notifications_v1';

class BarberoNotificationItem {
  const BarberoNotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.receivedAtIso,
    this.type = 'general',
    this.read = false,
  });

  final String id;
  final String title;
  final String body;
  final String receivedAtIso;
  final String type;
  final bool read;

  DateTime get receivedAt =>
      DateTime.tryParse(receivedAtIso)?.toLocal() ?? DateTime.now();

  BarberoNotificationItem copyWith({
    String? id,
    String? title,
    String? body,
    String? receivedAtIso,
    String? type,
    bool? read,
  }) {
    return BarberoNotificationItem(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      receivedAtIso: receivedAtIso ?? this.receivedAtIso,
      type: type ?? this.type,
      read: read ?? this.read,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'body': body,
      'receivedAtIso': receivedAtIso,
      'type': type,
      'read': read,
    };
  }

  factory BarberoNotificationItem.fromJson(Map<String, dynamic> json) {
    return BarberoNotificationItem(
      id: '${json['id'] ?? ''}'.trim(),
      title: '${json['title'] ?? ''}'.trim(),
      body: '${json['body'] ?? ''}'.trim(),
      receivedAtIso:
          '${json['receivedAtIso'] ?? DateTime.now().toIso8601String()}'.trim(),
      type: '${json['type'] ?? 'general'}'.trim(),
      read: json['read'] == true,
    );
  }
}

String _barberoNotificationIdFromMessage(RemoteMessage message) {
  final messageId = (message.messageId ?? '').trim();
  if (messageId.isNotEmpty) {
    return messageId;
  }
  final title = message.notification?.title?.trim() ?? '';
  final body = message.notification?.body?.trim() ?? '';
  final sentAt =
      message.sentTime?.toUtc().toIso8601String() ??
      DateTime.now().toUtc().toIso8601String();
  return base64Url.encode(utf8.encode('$sentAt|$title|$body'));
}

Future<void> _persistBarberoNotifications() async {
  final prefs = await SharedPreferences.getInstance();
  final encoded = jsonEncode(
    barberoNotifications.value
        .map((item) => item.toJson())
        .toList(growable: false),
  );
  await prefs.setString(_barberoNotificationsStorageKey, encoded);
}

Future<void> _loadStoredBarberoNotifications() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_barberoNotificationsStorageKey);
  if (raw == null || raw.trim().isEmpty) {
    barberoNotifications.value = const <BarberoNotificationItem>[];
    return;
  }
  try {
    final decoded = jsonDecode(raw);
    final items =
        (decoded as List)
            .whereType<Map>()
            .map(
              (item) =>
                  BarberoNotificationItem.fromJson(item.cast<String, dynamic>()),
            )
            .toList(growable: false);
    barberoNotifications.value = items;
  } catch (_) {
    barberoNotifications.value = const <BarberoNotificationItem>[];
  }
}

Future<void> _storeBarberoNotificationItem(
  BarberoNotificationItem item,
) async {
  final current = List<BarberoNotificationItem>.from(barberoNotifications.value);
  final existingIndex = current.indexWhere((entry) => entry.id == item.id);
  if (existingIndex >= 0) {
    current.removeAt(existingIndex);
  }
  current.insert(0, item);
  if (current.length > 50) {
    current.removeRange(50, current.length);
  }
  barberoNotifications.value = current;
  await _persistBarberoNotifications();
}

Future<void> _storeBarberoNotificationFromRemoteMessage(
  RemoteMessage message,
) async {
  final title = message.notification?.title?.trim() ?? '';
  final body = message.notification?.body?.trim() ?? '';
  if (title.isEmpty && body.isEmpty) {
    return;
  }
  await _storeBarberoNotificationItem(
    BarberoNotificationItem(
      id: _barberoNotificationIdFromMessage(message),
      title: title.isEmpty ? 'Notification' : title,
      body: body,
      receivedAtIso:
          (message.sentTime ?? DateTime.now()).toUtc().toIso8601String(),
      type: '${message.data['type'] ?? 'general'}'.trim(),
    ),
  );
}

Future<void> _markAllBarberoNotificationsRead() async {
  final current = barberoNotifications.value;
  if (current.isEmpty || current.every((item) => item.read)) {
    return;
  }
  barberoNotifications.value =
      current
          .map((item) => item.read ? item : item.copyWith(read: true))
          .toList(growable: false);
  await _persistBarberoNotifications();
}

@pragma('vm:entry-point')
Future<void> _barberoMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  await _loadStoredBarberoNotifications();
  await _storeBarberoNotificationFromRemoteMessage(message);
}

enum BarberoRole {
  owner,
  seniorBarber,
  barber,
  assistant,
}

enum BarberoBillingStatus {
  setupRequired,
  trialing,
  active,
  gracePeriod,
  expired,
  canceled,
  pendingVerification,
}

enum BarberoBillingPlan {
  monthly,
  yearly,
}

class BarberoPermissions {
  const BarberoPermissions({
    required this.manageCrew,
    required this.editSchedule,
    required this.editPrices,
    required this.viewClients,
    required this.viewStats,
    required this.manageAllAppointments,
    required this.manageOwnAppointments,
  });

  final bool manageCrew;
  final bool editSchedule;
  final bool editPrices;
  final bool viewClients;
  final bool viewStats;
  final bool manageAllAppointments;
  final bool manageOwnAppointments;
}

BarberoBillingPlan barberoBillingPlanFromRaw(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'yearly':
      return BarberoBillingPlan.yearly;
    default:
      return BarberoBillingPlan.monthly;
  }
}

BarberoBillingStatus barberoBillingStatusFromRaw(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'trialing':
      return BarberoBillingStatus.trialing;
    case 'active':
      return BarberoBillingStatus.active;
    case 'grace_period':
      return BarberoBillingStatus.gracePeriod;
    case 'canceled':
      return BarberoBillingStatus.canceled;
    case 'pending_verification':
      return BarberoBillingStatus.pendingVerification;
    case 'expired':
      return BarberoBillingStatus.expired;
    default:
      return BarberoBillingStatus.setupRequired;
  }
}

class BarberoBillingSnapshot {
  const BarberoBillingSnapshot({
    required this.status,
    required this.selectedPlan,
    required this.planConfirmed,
    required this.allowsAccess,
    required this.requiresOwnerAction,
    required this.monthlyPriceEur,
    required this.yearlyPriceEur,
    required this.yearlySavingsEur,
    this.trialStartedAtIso = '',
    this.trialEndsAtIso = '',
    this.currentPeriodEndIso = '',
    this.platform = '',
    this.storeProductId = '',
  });

  final BarberoBillingStatus status;
  final BarberoBillingPlan selectedPlan;
  final bool planConfirmed;
  final bool allowsAccess;
  final bool requiresOwnerAction;
  final int monthlyPriceEur;
  final int yearlyPriceEur;
  final int yearlySavingsEur;
  final String trialStartedAtIso;
  final String trialEndsAtIso;
  final String currentPeriodEndIso;
  final String platform;
  final String storeProductId;

  bool get requiresPlanSelection =>
      status == BarberoBillingStatus.setupRequired || !planConfirmed;
  bool get isTrialing => status == BarberoBillingStatus.trialing;
  bool get isExpired => status == BarberoBillingStatus.expired;
  bool get isActive =>
      status == BarberoBillingStatus.active ||
      status == BarberoBillingStatus.trialing ||
      status == BarberoBillingStatus.gracePeriod;
  bool get canOpenWorkspace => allowsAccess;
  bool get isMonthly => selectedPlan == BarberoBillingPlan.monthly;
  bool get isYearly => selectedPlan == BarberoBillingPlan.yearly;
  String get selectedPlanLabel => isYearly ? 'Yearly' : 'Monthly';
  DateTime? get trialEndsAt => DateTime.tryParse(trialEndsAtIso)?.toLocal();
  DateTime? get currentPeriodEnd =>
      DateTime.tryParse(currentPeriodEndIso)?.toLocal();

  String get statusLabel {
    switch (status) {
      case BarberoBillingStatus.setupRequired:
        return 'Setup required';
      case BarberoBillingStatus.trialing:
        return 'Free trial';
      case BarberoBillingStatus.active:
        return 'Active';
      case BarberoBillingStatus.gracePeriod:
        return 'Grace period';
      case BarberoBillingStatus.expired:
        return 'Expired';
      case BarberoBillingStatus.canceled:
        return 'Canceled';
      case BarberoBillingStatus.pendingVerification:
        return 'Pending verification';
    }
  }

  factory BarberoBillingSnapshot.fromJson(Map<String, dynamic> json) {
    return BarberoBillingSnapshot(
      status: barberoBillingStatusFromRaw('${json['status'] ?? ''}'),
      selectedPlan: barberoBillingPlanFromRaw('${json['selectedPlan'] ?? ''}'),
      planConfirmed: json['planConfirmed'] == true,
      allowsAccess: json['allowsAccess'] == true,
      requiresOwnerAction: json['requiresOwnerAction'] == true,
      monthlyPriceEur: (json['monthlyPriceEur'] as num?)?.toInt() ?? 29,
      yearlyPriceEur: (json['yearlyPriceEur'] as num?)?.toInt() ?? 290,
      yearlySavingsEur: (json['yearlySavingsEur'] as num?)?.toInt() ?? 58,
      trialStartedAtIso: '${json['trialStartedAt'] ?? ''}'.trim(),
      trialEndsAtIso: '${json['trialEndsAt'] ?? ''}'.trim(),
      currentPeriodEndIso: '${json['currentPeriodEnd'] ?? ''}'.trim(),
      platform: '${json['platform'] ?? ''}'.trim(),
      storeProductId: '${json['storeProductId'] ?? ''}'.trim(),
    );
  }

  BarberoBillingSnapshot copyWith({
    BarberoBillingStatus? status,
    BarberoBillingPlan? selectedPlan,
    bool? planConfirmed,
    bool? allowsAccess,
    bool? requiresOwnerAction,
    int? monthlyPriceEur,
    int? yearlyPriceEur,
    int? yearlySavingsEur,
    String? trialStartedAtIso,
    String? trialEndsAtIso,
    String? currentPeriodEndIso,
    String? platform,
    String? storeProductId,
  }) {
    return BarberoBillingSnapshot(
      status: status ?? this.status,
      selectedPlan: selectedPlan ?? this.selectedPlan,
      planConfirmed: planConfirmed ?? this.planConfirmed,
      allowsAccess: allowsAccess ?? this.allowsAccess,
      requiresOwnerAction: requiresOwnerAction ?? this.requiresOwnerAction,
      monthlyPriceEur: monthlyPriceEur ?? this.monthlyPriceEur,
      yearlyPriceEur: yearlyPriceEur ?? this.yearlyPriceEur,
      yearlySavingsEur: yearlySavingsEur ?? this.yearlySavingsEur,
      trialStartedAtIso: trialStartedAtIso ?? this.trialStartedAtIso,
      trialEndsAtIso: trialEndsAtIso ?? this.trialEndsAtIso,
      currentPeriodEndIso: currentPeriodEndIso ?? this.currentPeriodEndIso,
      platform: platform ?? this.platform,
      storeProductId: storeProductId ?? this.storeProductId,
    );
  }
}

class BarberoSession {
  const BarberoSession({
    required this.shopId,
    required this.userUid,
    required this.userEmail,
    required this.role,
    this.crewId = '',
    this.displayName = '',
  });

  final String shopId;
  final String userUid;
  final String userEmail;
  final BarberoRole role;
  final String crewId;
  final String displayName;

  bool get isOwner => role == BarberoRole.owner;

  BarberoPermissions get permissions {
    switch (role) {
      case BarberoRole.owner:
        return const BarberoPermissions(
          manageCrew: true,
          editSchedule: true,
          editPrices: true,
          viewClients: true,
          viewStats: true,
          manageAllAppointments: true,
          manageOwnAppointments: true,
        );
      case BarberoRole.seniorBarber:
        return const BarberoPermissions(
          manageCrew: false,
          editSchedule: true,
          editPrices: false,
          viewClients: true,
          viewStats: true,
          manageAllAppointments: true,
          manageOwnAppointments: true,
        );
      case BarberoRole.barber:
        return const BarberoPermissions(
          manageCrew: false,
          editSchedule: false,
          editPrices: false,
          viewClients: true,
          viewStats: false,
          manageAllAppointments: false,
          manageOwnAppointments: true,
        );
      case BarberoRole.assistant:
        return const BarberoPermissions(
          manageCrew: false,
          editSchedule: true,
          editPrices: false,
          viewClients: true,
          viewStats: false,
          manageAllAppointments: true,
          manageOwnAppointments: false,
        );
    }
  }
}

BarberoRole barberoRoleFromRaw(String raw) {
  final normalized = raw.trim().toLowerCase();
  if (normalized.contains('senior')) {
    return BarberoRole.seniorBarber;
  }
  if (normalized.contains('assistant')) {
    return BarberoRole.assistant;
  }
  if (normalized.contains('owner')) {
    return BarberoRole.owner;
  }
  return BarberoRole.barber;
}

String normalizeEmail(String raw) => raw.trim().toLowerCase();

BarberoSession requireCurrentBarberoSession() {
  final session = currentBarberoSession.value;
  if (session == null) {
    throw Exception('missing-barbero-session');
  }
  return session;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  await _loadStoredBarberoNotifications();
  FirebaseMessaging.onBackgroundMessage(_barberoMessagingBackgroundHandler);
  runApp(const BarberoApp());
}

DateTime athensNow() {
  final utc = DateTime.now().toUtc();
  return utc.add(Duration(hours: _athensOffsetHours(utc)));
}

int _athensOffsetHours(DateTime utc) {
  final dstStart = _lastSundayUtc(utc.year, 3).add(const Duration(hours: 1));
  final dstEnd = _lastSundayUtc(utc.year, 10).add(const Duration(hours: 1));
  final isDst = !utc.isBefore(dstStart) && utc.isBefore(dstEnd);
  return isDst ? 3 : 2;
}

DateTime _lastSundayUtc(int year, int month) {
  final lastDay = DateTime.utc(year, month + 1, 0);
  return lastDay.subtract(Duration(days: lastDay.weekday % 7));
}

DateTime athensDateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

String greekGreeting(DateTime value) {
  if (value.hour < 12) {
    return '\u039a\u03b1\u03bb\u03b7\u03bc\u03ad\u03c1\u03b1';
  }
  if (value.hour < 18) {
    return '\u039a\u03b1\u03bb\u03cc \u03b1\u03c0\u03cc\u03b3\u03b5\u03c5\u03bc\u03b1';
  }
  return '\u039a\u03b1\u03bb\u03b7\u03c3\u03c0\u03ad\u03c1\u03b1';
}

String greekDateLabel(DateTime value) {
  const weekdays = [
    '\u0394\u03b5\u03c5\u03c4\u03ad\u03c1\u03b1',
    '\u03a4\u03c1\u03af\u03c4\u03b7',
    '\u03a4\u03b5\u03c4\u03ac\u03c1\u03c4\u03b7',
    '\u03a0\u03ad\u03bc\u03c0\u03c4\u03b7',
    '\u03a0\u03b1\u03c1\u03b1\u03c3\u03ba\u03b5\u03c5\u03ae',
    '\u03a3\u03ac\u03b2\u03b2\u03b1\u03c4\u03bf',
    '\u039a\u03c5\u03c1\u03b9\u03b1\u03ba\u03ae',
  ];
  const months = [
    '\u0399\u03b1\u03bd\u03bf\u03c5\u03ac\u03c1\u03b9\u03bf\u03c2',
    '\u03a6\u03b5\u03b2\u03c1\u03bf\u03c5\u03ac\u03c1\u03b9\u03bf\u03c2',
    '\u039c\u03ac\u03c1\u03c4\u03b9\u03bf\u03c2',
    '\u0391\u03c0\u03c1\u03af\u03bb\u03b9\u03bf\u03c2',
    '\u039c\u03ac\u03b9\u03bf\u03c2',
    '\u0399\u03bf\u03cd\u03bd\u03b9\u03bf\u03c2',
    '\u0399\u03bf\u03cd\u03bb\u03b9\u03bf\u03c2',
    '\u0391\u03cd\u03b3\u03bf\u03c5\u03c3\u03c4\u03bf\u03c2',
    '\u03a3\u03b5\u03c0\u03c4\u03ad\u03bc\u03b2\u03c1\u03b9\u03bf\u03c2',
    '\u039f\u03ba\u03c4\u03ce\u03b2\u03c1\u03b9\u03bf\u03c2',
    '\u039d\u03bf\u03ad\u03bc\u03b2\u03c1\u03b9\u03bf\u03c2',
    '\u0394\u03b5\u03ba\u03ad\u03bc\u03b2\u03c1\u03b9\u03bf\u03c2',
  ];
  return '${weekdays[value.weekday - 1]}, ${value.day} ${months[value.month - 1]}';
}

List<Appointment> buildAppointmentsForDate(
  DateTime selectedDate,
  List<Appointment> source,
) {
  final dateKey =
      '${selectedDate.year.toString().padLeft(4, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
  final filtered =
      source.where((appointment) => appointment.date == dateKey).toList()..sort(
        (left, right) =>
            _parseClockValue(left.time).compareTo(_parseClockValue(right.time)),
      );
  return filtered;
}

List<ProgramEntry> buildProgramEntriesForDate({
  required DateTime selectedDate,
  required List<Appointment> bookedAppointments,
  required List<ScheduleDay> weeklySchedule,
}) {
  final entries = <ProgramEntry>[];
  for (final appointment in bookedAppointments) {
    entries.add(
      ProgramEntry(
        appointmentId: appointment.id,
        hour: appointment.time,
        customerUid: appointment.customerUid,
        name: appointment.name,
        service: appointment.service,
        duration: appointment.duration,
        barberName: appointment.barberName,
        status: appointment.status,
        blocked: appointment.blocked,
        blockReason: appointment.blockReason,
        highlighted:
            appointment.service.contains('&') ||
            appointment.service.contains('+'),
      ),
    );
  }

  if (weeklySchedule.length >= 7) {
    final daySchedule = weeklySchedule[selectedDate.weekday - 1];
    final breakStart = _parseClockValue(daySchedule.breakStart);
    final breakEnd = _parseClockValue(daySchedule.breakEnd);
    if (daySchedule.enabled &&
        breakStart >= 0 &&
        breakEnd > breakStart &&
        entries.every((entry) => entry.hour != daySchedule.breakStart)) {
      entries.add(ProgramEntry.breakLine(hour: daySchedule.breakStart));
      entries.sort(
        (left, right) =>
            _parseClockValue(left.hour).compareTo(_parseClockValue(right.hour)),
      );
    }
  }

  return entries;
}

List<ScheduleDay> buildDefaultWeeklySchedule() {
  return const [
    ScheduleDay(
      name: 'Monday',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
    ScheduleDay(
      name: 'Tuesday',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
    ScheduleDay(
      name: 'Wednesday',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
    ScheduleDay(
      name: 'Thursday',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
    ScheduleDay(
      name: 'Friday',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
    ScheduleDay(
      name: 'Saturday',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
    ScheduleDay(
      name: 'Sunday',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
  ];
}

List<Appointment> buildHomeAppointmentsForDate({
  required DateTime selectedDate,
  required List<Appointment> bookedAppointments,
  required List<ScheduleDay> weeklySchedule,
  required int slotMinutes,
  required int appointmentsPerSlot,
  required List<SlotCapacityOverride> slotCapacityOverrides,
}) {
  if (weeklySchedule.length < 7 || slotMinutes <= 0) {
    return bookedAppointments;
  }
  final daySchedule = weeklySchedule[selectedDate.weekday - 1];
  if (!daySchedule.enabled ||
      daySchedule.start == '--:--' ||
      daySchedule.end == '--:--') {
    return const [];
  }
  final startMinutes = _parseClockValue(daySchedule.start);
  final endMinutes = _parseClockValue(daySchedule.end);
  if (startMinutes < 0 || endMinutes <= startMinutes) {
    return const [];
  }
  final breakStart = _parseClockValue(daySchedule.breakStart);
  final breakEnd = _parseClockValue(daySchedule.breakEnd);
  final slots = <Appointment>[];
  final sortedAppointments = List<Appointment>.from(bookedAppointments)
    ..sort(
      (left, right) =>
          _parseClockValue(left.time).compareTo(_parseClockValue(right.time)),
    );

  bool slotHasCapacity(int startMinute) {
    final capacity = resolveAppointmentsPerSlotForMinute(
      dayIndex: selectedDate.weekday - 1,
      minuteOfDay: startMinute,
      defaultAppointmentsPerSlot: appointmentsPerSlot,
      overrides: slotCapacityOverrides,
    );
    if (capacity <= 1) {
      return !sortedAppointments.any((appointment) {
        final appointmentStart = _parseClockValue(appointment.time);
        final appointmentEnd = appointmentStart + appointment.minutes;
        return appointmentStart < startMinute + slotMinutes &&
            appointmentEnd > startMinute;
      });
    }
    var overlapCount = 0;
    for (final appointment in sortedAppointments) {
      final appointmentStart = _parseClockValue(appointment.time);
      final appointmentEnd = appointmentStart + appointment.minutes;
      if (appointmentStart < startMinute + slotMinutes &&
          appointmentEnd > startMinute) {
        overlapCount += 1;
        if (overlapCount >= capacity) {
          return false;
        }
      }
    }
    return true;
  }

  void fillGap(int gapStart, int gapEnd) {
    for (
      var minute = gapStart;
      minute + slotMinutes <= gapEnd;
      minute += slotMinutes
    ) {
      if (!slotHasCapacity(minute)) {
        continue;
      }
      slots.add(
        Appointment(
          _formatClockMinutes(minute),
          '\u0394\u03b9\u03b1\u03b8\u03ad\u03c3\u03b9\u03bc\u03bf slot',
          '\u03a7\u03c9\u03c1\u03af\u03c2 \u03c1\u03b1\u03bd\u03c4\u03b5\u03b2\u03bf\u03cd',
          "$slotMinutes'",
          isBooked: false,
        ),
      );
    }
  }

  final segments = <({int start, int end})>[
    if (breakStart >= 0 && breakEnd > breakStart) ...[
      (start: startMinutes, end: breakStart),
      (start: breakEnd, end: endMinutes),
    ] else
      (start: startMinutes, end: endMinutes),
  ];

  for (final segment in segments) {
    var cursor = segment.start;
    final segmentAppointments =
        sortedAppointments.where((appointment) {
          final appointmentStart = _parseClockValue(appointment.time);
          final appointmentEnd = appointmentStart + appointment.minutes;
          return appointmentStart >= segment.start &&
              appointmentStart < segment.end &&
              appointmentEnd > segment.start;
        }).toList()..sort(
          (left, right) => _parseClockValue(
            left.time,
          ).compareTo(_parseClockValue(right.time)),
        );

    for (final appointment in segmentAppointments) {
      final appointmentStart = _parseClockValue(appointment.time);
      if (appointmentStart > cursor) {
        fillGap(cursor, appointmentStart);
      }
      slots.add(appointment);
      final appointmentEnd = appointmentStart + appointment.minutes;
      if (appointmentEnd > cursor) {
        cursor = appointmentEnd;
      }
    }

    if (cursor < segment.end) {
      fillGap(cursor, segment.end);
    }
  }

  return slots;
}

int resolveAppointmentsPerSlotForMinute({
  required int dayIndex,
  required int minuteOfDay,
  required int defaultAppointmentsPerSlot,
  required List<SlotCapacityOverride> overrides,
}) {
  var resolved = defaultAppointmentsPerSlot;
  for (final override in overrides) {
    if (override.dayIndex != dayIndex) {
      continue;
    }
    final start = _parseClockValue(override.start);
    final end = _parseClockValue(override.end);
    if (start < 0 || end <= start) {
      continue;
    }
    if (minuteOfDay >= start && minuteOfDay < end) {
      resolved = override.appointmentsPerSlot;
    }
  }
  return resolved < 1 ? 1 : resolved;
}

int _parseClockValue(String value) {
  if (value == '--:--') {
    return -1;
  }
  final parts = value.split(':');
  if (parts.length != 2) {
    return -1;
  }
  final hours = int.tryParse(parts[0]);
  final minutes = int.tryParse(parts[1]);
  if (hours == null || minutes == null) {
    return -1;
  }
  return hours * 60 + minutes;
}

String _formatClockMinutes(int totalMinutes) {
  final hours = (totalMinutes ~/ 60).toString().padLeft(2, '0');
  final minutes = (totalMinutes % 60).toString().padLeft(2, '0');
  return '$hours:$minutes';
}

void openCustomerProfile(BuildContext context, String customerName) {
  openCustomerProfilePage(context, buildCustomerProfileByName(customerName));
}

void openCustomerProfilePage(BuildContext context, CustomerProfile customer) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CustomerProfilePage(customer: customer, showBack: true),
    ),
  );
}

Future<void> launchPhoneCall(String phoneNumber) async {
  final sanitized = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
  if (sanitized.isEmpty) {
    return;
  }
  final uri = Uri(scheme: 'tel', path: sanitized);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

CustomerProfile buildCustomerProfileByName(String name) {
  switch (name) {
    case 'ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β½ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β°ΞΒΞ’ΒΞβ€™Ξ’Β½ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦':
      return const CustomerProfile(
        name:
            'ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β½ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β°ΞΒΞ’ΒΞβ€™Ξ’Β½ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦',
        phone: '694 123 4567',
        preferences: [
          'ΞΒΞ’ΒΞβ€™Ξ’Β§ΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β·ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞβ€™Ξ’Β Fade',
          'Beard Trim',
          'Matte Look',
        ],
        notes:
            'ΞΒΞ’ΒΞβ€™Ξ’Β ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β¬ ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξβ€¦ΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β·ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞβ€™Ξ’Β fade ΞΒΞ’ΒΞβ€“Ξ²β‚¬β„ΆΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β± ΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞβ€™Ξ’Β¬ΞΒΞ’ΒΞβ€™Ξ’Β³ΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞβ€™Ξ’Β±.\nΞΒΞ’ΒΞβ€™Ξ’Β¦ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ΞΒΞ’ΒΞβ€“Ξ²β‚¬β„ΆΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β³ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β ΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞβ€™Ξ’Β¬ΞΒΞ’ΒΞβ€™Ξ’Β½ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β°.\nΞΒΞ’ΒΞβ€™Ξ’Β§ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β·ΞΒΞ’ΒΞβ€“Ξ²β‚¬β„ΆΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞβ€™Ξ’ΒµΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ† matte ΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β½ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±.',
        history: [
          VisitRecord(
            date:
                '15 ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ 2025',
            service: 'Fade & Beard',
            price: 28,
          ),
          VisitRecord(
            date:
                '1 ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ 2025',
            service: 'Classic Haircut',
            price: 18,
          ),
          VisitRecord(
            date:
                '17 ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ 2025',
            service: 'Haircut & Beard',
            price: 30,
          ),
        ],
      );
    case 'ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€“Ξ²β‚¬β„ΆΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β ΞΒΞ’ΒΞβ€™Ξ’Β .':
      return const CustomerProfile(
        name:
            'ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€“Ξ²β‚¬β„ΆΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β ΞΒΞ’ΒΞβ€™Ξ’Β .',
        phone: '697 210 8841',
        preferences: ['Classic Cut', 'Side Part', 'Natural Finish'],
        notes:
            'ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β¬ ΞΒΞ’ΒΞβ€“Ξ²β‚¬β„ΆΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’ΒµΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞβ€“Ξ²β‚¬β„ΆΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β ΞΒΞ’ΒΞβ€“Ξ²β‚¬β„ΆΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξβ€¦ΞΒΞ’ΒΞβ€™Ξ’Β®ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±.\nΞΒΞ’ΒΞβ€™Ξ’Β ΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞΒΞ’Β ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β½ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β¬ ΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β½ΞΒΞ’ΒΞβ€™Ξ’Β¬ ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β¬ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Βµ ΞΒΞ’ΒΞΒΞ²β‚¬ΒΞΒΞ’ΒΞβ€™Ξ’ΒµΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’ΒµΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β· ΞΒΞ’ΒΞβ€™Ξ’ΒµΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞβ€“Ξ²β‚¬β„ΆΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’ΒµΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β·.',
        history: [
          VisitRecord(
            date:
                '6 ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ 2025',
            service: 'Classic Haircut',
            price: 18,
          ),
          VisitRecord(
            date:
                '22 ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ 2025',
            service: 'Classic Haircut',
            price: 18,
          ),
          VisitRecord(
            date:
                '8 ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ 2025',
            service: 'Classic Haircut',
            price: 18,
          ),
        ],
      );
    case 'ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξβ€¦ΞΒΞ’ΒΞβ€™Ξ’Β¬ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞβ€™Ξ’Β·ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β ΞΒΞ’ΒΞβ€™Ξ’Β.':
      return const CustomerProfile(
        name:
            'ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξβ€¦ΞΒΞ’ΒΞβ€™Ξ’Β¬ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞβ€™Ξ’Β·ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β ΞΒΞ’ΒΞβ€™Ξ’Β.',
        phone: '698 550 2201',
        preferences: ['Haircut & Beard', 'Mid Fade', 'Beard Shape'],
        notes:
            'ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β­ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞβ€™Ξ’ΒµΞΒΞ’ΒΞΒΞ²β‚¬Β° ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β ΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞβ€™Ξ’ΒµΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞβ€™Ξ’Β³ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β± ΞΒΞ’ΒΞβ€“Ξ²β‚¬β„ΆΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β± ΞΒΞ’ΒΞβ€™Ξ’Β³ΞΒΞ’ΒΞβ€™Ξ’Β­ΞΒΞ’ΒΞβ€™Ξ’Β½ΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞβ€™Ξ’Β±.\nΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξβ€¦ΞΒΞ’ΒΞΒΞ²β‚¬Β° ΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞβ€™Ξ’Β ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξβ€¦ΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β·ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞβ€™Ξ’Β¬ ΞΒΞ’ΒΞβ€“Ξ²β‚¬β„ΆΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β ΞΒΞ’ΒΞβ€™Ξ’Β³ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β°ΞΒΞ’ΒΞβ€™Ξ’Β½ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞβ€™Ξ’ΒµΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β.',
        history: [
          VisitRecord(
            date:
                '8 ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ 2025',
            service: 'Haircut & Beard',
            price: 30,
          ),
          VisitRecord(
            date:
                '24 ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ 2025',
            service: 'Haircut & Beard',
            price: 30,
          ),
          VisitRecord(
            date:
                '10 ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ 2025',
            service: 'Beard Trim',
            price: 12,
          ),
        ],
      );
    case 'ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞβ€™Ξ’Β¬ΞΒΞ’ΒΞβ€™Ξ’Β½ΞΒΞ’ΒΞβ€™Ξ’Β½ΞΒΞ’ΒΞβ€™Ξ’Β·ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞβ€™Ξ’Β®ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β':
      return const CustomerProfile(
        name:
            'ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞβ€™Ξ’Β¬ΞΒΞ’ΒΞβ€™Ξ’Β½ΞΒΞ’ΒΞβ€™Ξ’Β½ΞΒΞ’ΒΞβ€™Ξ’Β·ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞβ€™Ξ’Β®ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β',
        phone: '699 112 3374',
        preferences: ['Kids Haircut', 'Soft Fade', 'No Razor'],
        notes:
            'ΞΒΞ’ΒΞβ€™Ξ’Β ΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞΒΞ²β‚¬ΒΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’ΒµΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β± ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Βµ ΞΒΞ’ΒΞβ€™Ξ’Β®ΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞβ€™Ξ’Β± ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’ΒµΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β¬ΞΒΞ’ΒΞβ€™Ξ’Β²ΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞβ€“Ξ²β‚¬β„ΆΞΒΞ’ΒΞβ€™Ξ’Β·.\nΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β ΞΒΞ’ΒΞβ€™Ξ’ΒµΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β³ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Βµ ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β ΞΒΞ’ΒΞβ€™Ξ’Β¬ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ²β‚¬Β° ΞΒΞ’ΒΞβ€“Ξ²β‚¬β„ΆΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β½ ΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξβ€¦ΞΒΞ’ΒΞβ€™Ξ’Β­ΞΒΞ’ΒΞβ€™Ξ’Β½ΞΒΞ’ΒΞβ€™Ξ’Β±.',
        history: [
          VisitRecord(
            date:
                '3 ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ 2025',
            service: 'Kids Haircut',
            price: 14,
          ),
          VisitRecord(
            date:
                '5 ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ 2025',
            service: 'Kids Haircut',
            price: 14,
          ),
          VisitRecord(
            date:
                '9 ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ 2025',
            service: 'Kids Haircut',
            price: 14,
          ),
        ],
      );
    case 'ΞΒΞ’ΒΞβ€™Ξ’Β§ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β®ΞΒΞ’ΒΞβ€“Ξ²β‚¬β„ΆΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β ΞΒΞ’ΒΞβ€™Ξ’Β£.':
      return const CustomerProfile(
        name:
            'ΞΒΞ’ΒΞβ€™Ξ’Β§ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β®ΞΒΞ’ΒΞβ€“Ξ²β‚¬β„ΆΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β ΞΒΞ’ΒΞβ€™Ξ’Β£.',
        phone: '695 770 4411',
        preferences: ['Fade & Beard', 'Sharp Line', 'Gloss Finish'],
        notes:
            'ΞΒΞ’ΒΞβ€™Ξ’Β ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β¬ ΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞΒΞ’Β ΞΒΞ’ΒΞβ€™Ξ’Β­ΞΒΞ’ΒΞβ€™Ξ’Β½ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β½ΞΒΞ’ΒΞβ€™Ξ’Β· ΞΒΞ’ΒΞβ€™Ξ’Β³ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β® ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€“Ξ²β‚¬β„ΆΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β¬.\nΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬ΒΞΒΞ’ΒΞβ€™Ξ’Β·ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β¬ ΞΒΞ’ΒΞβ€“Ξ²β‚¬β„ΆΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’ΒµΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞβ€™Ξ’Β± ΞΒΞ’ΒΞβ€“Ξ²β‚¬β„ΆΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β± ΞΒΞ’ΒΞβ€™Ξ’Β³ΞΒΞ’ΒΞβ€™Ξ’Β­ΞΒΞ’ΒΞβ€™Ξ’Β½ΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞβ€™Ξ’Β±.',
        history: [
          VisitRecord(
            date:
                '2 ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ 2025',
            service: 'Fade & Beard',
            price: 28,
          ),
          VisitRecord(
            date:
                '18 ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ 2025',
            service: 'Fade & Beard',
            price: 28,
          ),
          VisitRecord(
            date:
                '4 ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ 2025',
            service: 'Beard Trim',
            price: 12,
          ),
        ],
      );
    case 'ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞβ€™Ξ’Β­ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞβ€™Ξ’Β½ΞΒΞ’ΒΞΒΞ²β‚¬ΒΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β ΞΒΞ’ΒΞβ€™Ξ’Β.':
      return const CustomerProfile(
        name:
            'ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞβ€™Ξ’Β­ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞβ€™Ξ’Β½ΞΒΞ’ΒΞΒΞ²β‚¬ΒΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β ΞΒΞ’ΒΞβ€™Ξ’Β.',
        phone: '693 321 7740',
        preferences: ['Classic Haircut', 'Scissor Cut', 'Texture'],
        notes:
            'ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β­ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞβ€™Ξ’ΒµΞΒΞ’ΒΞΒΞ²β‚¬Β° ΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞΒΞ’Β ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞΒΞ²β‚¬ΒΞΒΞ’ΒΞβ€™Ξ’Β¬ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒΞ’Β ΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞβ€™Ξ’Β¬ΞΒΞ’ΒΞβ€™Ξ’Β½ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β°.\nΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β·ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Βµ ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β³ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’Β ΞΒΞ’ΒΞβ€“Ξ²β‚¬β„ΆΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β ΞΒΞ’ΒΞβ€™Ξ’Β­ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β.',
        history: [
          VisitRecord(
            date:
                '7 ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ 2025',
            service: 'Classic Haircut',
            price: 18,
          ),
          VisitRecord(
            date:
                '23 ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ 2025',
            service: 'Classic Haircut',
            price: 18,
          ),
          VisitRecord(
            date:
                '11 ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ 2025',
            service: 'Hair Styling',
            price: 10,
          ),
        ],
      );
    case 'ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β ΞΒΞ’ΒΞβ€™Ξ’Β¤.':
      return const CustomerProfile(
        name:
            'ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β ΞΒΞ’ΒΞβ€™Ξ’Β¤.',
        phone: '694 880 1152',
        preferences: ['Haircut & Beard', 'Low Fade', 'Natural Beard'],
        notes:
            'ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β­ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞβ€™Ξ’ΒµΞΒΞ’ΒΞΒΞ²β‚¬Β° ΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞΒΞ’Β ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ΞΒΞ’ΒΞβ€“Ξ²β‚¬β„ΆΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’ΒµΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞβ€™Ξ’ΒµΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β°ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β± ΞΒΞ’ΒΞβ€“Ξ²β‚¬β„ΆΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β± ΞΒΞ’ΒΞβ€™Ξ’Β³ΞΒΞ’ΒΞβ€™Ξ’Β­ΞΒΞ’ΒΞβ€™Ξ’Β½ΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞβ€™Ξ’Β±.\nΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξβ€¦ΞΒΞ’ΒΞΒΞ²β‚¬Β° ΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞβ€™Ξ’Β ΞΒΞ’ΒΞβ€™Ξ’Β­ΞΒΞ’ΒΞβ€™Ξ’Β½ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞβ€™Ξ’Β½ΞΒΞ’ΒΞΒΞ’Β contrast.',
        history: [
          VisitRecord(
            date:
                '9 ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ 2025',
            service: 'Haircut & Beard',
            price: 30,
          ),
          VisitRecord(
            date:
                '25 ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ 2025',
            service: 'Haircut & Beard',
            price: 30,
          ),
          VisitRecord(
            date:
                '12 ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ 2025',
            service: 'Classic Haircut',
            price: 18,
          ),
        ],
      );
    default:
      return CustomerProfile(
        name: name,
        phone: '690 000 0000',
        preferences: const ['Classic Haircut'],
        notes:
            'ΞΒΞ’ΒΞβ€™Ξ’Β ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞβ€™Ξ’Β» ΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞβ€™Ξ’ΒµΞΒΞ’ΒΞβ€™Ξ’Β»ΞΒΞ’ΒΞβ€™Ξ’Β¬ΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β· ΞΒΞ’ΒΞβ€™Ξ’Β³ΞΒΞ’ΒΞΒΞ²β‚¬Β°ΞΒΞ’ΒΞβ€™Ξ’Β± demo ΞΒΞ’ΒΞΒ²Ξ²β‚¬ΒΞ’Β¬ΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ΞΒΞ’ΒΞβ€“Ξ²β‚¬β„ΆΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ²β‚¬Ξ†ΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞβ€“Ξ²β‚¬β„ΆΞΒΞ’ΒΞβ€™Ξ’Β·.',
        history: const [
          VisitRecord(
            date:
                '1 ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞβ€™Ξ’Β±ΞΒΞ’ΒΞβ€™Ξ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒΞ’ΒΞΒ²Ξ²β€Β¬Ξ’Β¦ 2025',
            service: 'Classic Haircut',
            price: 18,
          ),
        ],
      );
  }
}
