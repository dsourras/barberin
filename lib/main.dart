import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_selector/file_selector.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
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
part 'platform_admin_page.dart';
part 'legal_pages.dart';
part 'help_center.dart';
part 'notifications_page.dart';
part 'billing_page.dart';
part 'billing_store.dart';
part 'unified_dashboard_page.dart';
part 'sustainability_page.dart';
part 'services_management_page.dart';
part 'settings_page.dart';
part 'windows_backend_adapter.dart';
part 'platform_notifications.dart';
part 'localization_translations.dart';
part 'localization.dart';

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final ValueNotifier<BarberoSession?> currentBarberoSession =
    ValueNotifier<BarberoSession?>(null);
final ValueNotifier<List<BarberoAccessibleShop>> currentBarberoAccessibleShops =
    ValueNotifier<List<BarberoAccessibleShop>>(const <BarberoAccessibleShop>[]);
final ValueNotifier<BarberoBillingSnapshot?> currentBarberoBilling =
    ValueNotifier<BarberoBillingSnapshot?>(null);
final ValueNotifier<bool> barberinRegistrationInProgress = ValueNotifier<bool>(
  false,
);
final ValueNotifier<List<BarberoNotificationItem>> barberoNotifications =
    ValueNotifier<List<BarberoNotificationItem>>(
      const <BarberoNotificationItem>[],
    );
final ValueNotifier<BarberoNotificationItem?>
barberoPendingAppointmentNotification = ValueNotifier<BarberoNotificationItem?>(
  null,
);
final ValueNotifier<int> barberoReturnHomeTrigger = ValueNotifier<int>(0);
final ValueNotifier<ThemeMode> barberinThemeMode = ValueNotifier<ThemeMode>(
  ThemeMode.light,
);

const String _barberoNotificationsStorageKey = 'barbero_notifications_v1';
const String _barberoActiveShopStorageKey = 'barberin_active_shop_v1';
const String _barberinThemeStorageKey = 'barberin_theme_mode_v1';

Future<void> loadBarberinThemeMode() async {
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getString(_barberinThemeStorageKey);
  barberinThemeMode.value = stored == 'dark' ? ThemeMode.dark : ThemeMode.light;
}

Future<void> setBarberinThemeMode(ThemeMode mode) async {
  barberinThemeMode.value = mode;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    _barberinThemeStorageKey,
    mode == ThemeMode.light ? 'light' : 'dark',
  );
}

class BarberoNotificationItem {
  const BarberoNotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.receivedAtIso,
    this.type = 'general',
    this.read = false,
    this.appointmentId = '',
    this.appointmentDate = '',
  });

  final String id;
  final String title;
  final String body;
  final String receivedAtIso;
  final String type;
  final bool read;
  final String appointmentId;
  final String appointmentDate;

  DateTime get receivedAt =>
      DateTime.tryParse(receivedAtIso)?.toLocal() ?? DateTime.now();

  BarberoNotificationItem copyWith({
    String? id,
    String? title,
    String? body,
    String? receivedAtIso,
    String? type,
    bool? read,
    String? appointmentId,
    String? appointmentDate,
  }) {
    return BarberoNotificationItem(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      receivedAtIso: receivedAtIso ?? this.receivedAtIso,
      type: type ?? this.type,
      read: read ?? this.read,
      appointmentId: appointmentId ?? this.appointmentId,
      appointmentDate: appointmentDate ?? this.appointmentDate,
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
      'appointmentId': appointmentId,
      'appointmentDate': appointmentDate,
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
      appointmentId: '${json['appointmentId'] ?? ''}'.trim(),
      appointmentDate: '${json['appointmentDate'] ?? ''}'.trim(),
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
    final items = (decoded as List)
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

Future<void> _storeBarberoNotificationItem(BarberoNotificationItem item) async {
  final current = List<BarberoNotificationItem>.from(
    barberoNotifications.value,
  );
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

Future<void> _storeBarberoNotificationItemIfMissing(
  BarberoNotificationItem item,
) async {
  if (barberoNotifications.value.any((entry) => entry.id == item.id)) {
    return;
  }
  await _storeBarberoNotificationItem(item);
}

Future<BarberoNotificationItem?> _storeBarberoNotificationFromRemoteMessage(
  RemoteMessage message,
) async {
  final title = message.notification?.title?.trim() ?? '';
  final body = message.notification?.body?.trim() ?? '';
  if (title.isEmpty && body.isEmpty) {
    return null;
  }
  await _storeBarberoNotificationItem(
    BarberoNotificationItem(
      id: _barberoNotificationIdFromMessage(message),
      title: title.isEmpty ? 'Ειδοποίηση' : title,
      body: body,
      receivedAtIso: (message.sentTime ?? DateTime.now())
          .toUtc()
          .toIso8601String(),
      type: '${message.data['type'] ?? 'general'}'.trim(),
      appointmentId: '${message.data['appointmentId'] ?? ''}'.trim(),
      appointmentDate: '${message.data['date'] ?? ''}'.trim(),
    ),
  );
  return barberoNotifications.value.firstWhere(
    (item) => item.id == _barberoNotificationIdFromMessage(message),
  );
}

Future<void> _markAllBarberoNotificationsRead() async {
  final current = barberoNotifications.value;
  if (current.isEmpty || current.every((item) => item.read)) {
    return;
  }
  barberoNotifications.value = current
      .map((item) => item.read ? item : item.copyWith(read: true))
      .toList(growable: false);
  await _persistBarberoNotifications();
}

FirebaseOptions? _barberinFirebaseOptionsFromEnvironment() {
  const apiKey = String.fromEnvironment('BARBERIN_FIREBASE_API_KEY');
  const appId = String.fromEnvironment('BARBERIN_FIREBASE_APP_ID');
  const messagingSenderId = String.fromEnvironment(
    'BARBERIN_FIREBASE_MESSAGING_SENDER_ID',
  );
  const projectId = String.fromEnvironment('BARBERIN_FIREBASE_PROJECT_ID');
  const storageBucket = String.fromEnvironment(
    'BARBERIN_FIREBASE_STORAGE_BUCKET',
  );
  if ([
    apiKey,
    appId,
    messagingSenderId,
    projectId,
    storageBucket,
  ].any((value) => value.trim().isEmpty)) {
    return null;
  }
  const databaseUrl = String.fromEnvironment('BARBERIN_FIREBASE_DATABASE_URL');
  return FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    storageBucket: storageBucket,
    databaseURL: databaseUrl.trim().isEmpty ? null : databaseUrl,
  );
}

Future<void> _initializeBarberinFirebase() async {
  final options = _barberinFirebaseOptionsFromEnvironment();
  if (options == null) {
    await Firebase.initializeApp();
    return;
  }
  await Firebase.initializeApp(options: options);
}

@pragma('vm:entry-point')
Future<void> _barberoMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await _initializeBarberinFirebase();
  } catch (_) {}
  await _loadStoredBarberoNotifications();
  await loadBarberinThemeMode();
  await _storeBarberoNotificationFromRemoteMessage(message);
}

enum BarberoRole { owner, seniorBarber, barber, assistant }

enum BarberoBillingStatus {
  setupRequired,
  trialing,
  active,
  gracePeriod,
  expired,
  canceled,
  pendingVerification,
}

enum BarberoBillingPlan { monthly, yearly }

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
    this.accessUntilMillis = 0,
    this.platform = '',
    this.storeProductId = '',
    this.autoRenewEnabled,
    this.cancellationAtIso = '',
    this.cancellationReason = '',
    this.storeStatus = '',
    this.storeEnvironment = '',
    this.revokedAtIso = '',
    this.refundedAtIso = '',
    this.lastStoreSyncAtIso = '',
    this.lastStoreSyncStatus = '',
  });

  final BarberoBillingStatus status;
  final BarberoBillingPlan selectedPlan;
  final bool planConfirmed;
  final bool allowsAccess;
  final bool requiresOwnerAction;
  final double monthlyPriceEur;
  final double yearlyPriceEur;
  final double yearlySavingsEur;
  final String trialStartedAtIso;
  final String trialEndsAtIso;
  final String currentPeriodEndIso;
  final int accessUntilMillis;
  final String platform;
  final String storeProductId;
  final bool? autoRenewEnabled;
  final String cancellationAtIso;
  final String cancellationReason;
  final String storeStatus;
  final String storeEnvironment;
  final String revokedAtIso;
  final String refundedAtIso;
  final String lastStoreSyncAtIso;
  final String lastStoreSyncStatus;

  bool get requiresPlanSelection =>
      status == BarberoBillingStatus.setupRequired || !planConfirmed;
  bool get isTrialing => status == BarberoBillingStatus.trialing;
  bool get isInTrial {
    if (isTrialing) {
      return true;
    }
    final endsAt = trialEndsAt;
    return endsAt != null &&
        endsAt.isAfter(DateTime.now()) &&
        status != BarberoBillingStatus.expired &&
        status != BarberoBillingStatus.canceled;
  }

  bool get isExpired => status == BarberoBillingStatus.expired;
  bool get isActive =>
      status == BarberoBillingStatus.active ||
      status == BarberoBillingStatus.trialing ||
      status == BarberoBillingStatus.gracePeriod;
  bool get canOpenWorkspace =>
      allowsAccess && accessUntilMillis > DateTime.now().millisecondsSinceEpoch;
  bool get isMonthly => selectedPlan == BarberoBillingPlan.monthly;
  bool get isYearly => selectedPlan == BarberoBillingPlan.yearly;
  String get selectedPlanLabel => isYearly ? 'Ετήσιο' : 'Μηνιαίο';
  BarberoBillingPlan get currentPlan {
    switch (storeProductId) {
      case 'barbero_yearly':
        return BarberoBillingPlan.yearly;
      case 'barbero_monthly':
        return BarberoBillingPlan.monthly;
      default:
        return selectedPlan;
    }
  }

  String get currentPlanLabel => currentPlan == BarberoBillingPlan.yearly
      ? 'Ετήσια συνδρομή'
      : 'Μηνιαία συνδρομή';
  DateTime? get trialEndsAt => DateTime.tryParse(trialEndsAtIso)?.toLocal();
  DateTime? get currentPeriodEnd =>
      DateTime.tryParse(currentPeriodEndIso)?.toLocal();

  String get statusLabel {
    switch (status) {
      case BarberoBillingStatus.setupRequired:
        return 'Απαιτείται ρύθμιση';
      case BarberoBillingStatus.trialing:
        return 'Δωρεάν δοκιμή';
      case BarberoBillingStatus.active:
        return 'Ενεργή';
      case BarberoBillingStatus.gracePeriod:
        return 'Περίοδος χάριτος';
      case BarberoBillingStatus.expired:
        return 'Έχει λήξει';
      case BarberoBillingStatus.canceled:
        return 'Ακυρωμένη';
      case BarberoBillingStatus.pendingVerification:
        return 'Αναμονή επαλήθευσης';
    }
  }

  String get switcherStatusLabel {
    if (isInTrial) {
      return 'Σε δωρεάν δοκιμή';
    }
    if (allowsAccess) {
      return 'Ενεργή';
    }
    if (status == BarberoBillingStatus.expired ||
        status == BarberoBillingStatus.canceled) {
      return 'Έληξε';
    }
    return statusLabel;
  }

  factory BarberoBillingSnapshot.fromJson(Map<String, dynamic> json) {
    return BarberoBillingSnapshot(
      status: barberoBillingStatusFromRaw('${json['status'] ?? ''}'),
      selectedPlan: barberoBillingPlanFromRaw('${json['selectedPlan'] ?? ''}'),
      planConfirmed: json['planConfirmed'] == true,
      allowsAccess: json['allowsAccess'] == true,
      requiresOwnerAction: json['requiresOwnerAction'] == true,
      monthlyPriceEur: (json['monthlyPriceEur'] as num?)?.toDouble() ?? 29.99,
      yearlyPriceEur: (json['yearlyPriceEur'] as num?)?.toDouble() ?? 299.99,
      yearlySavingsEur: (json['yearlySavingsEur'] as num?)?.toDouble() ?? 59.89,
      trialStartedAtIso: '${json['trialStartedAt'] ?? ''}'.trim(),
      trialEndsAtIso: '${json['trialEndsAt'] ?? ''}'.trim(),
      currentPeriodEndIso: '${json['currentPeriodEnd'] ?? ''}'.trim(),
      accessUntilMillis: json['accessUntilMillis'] is num
          ? (json['accessUntilMillis'] as num).toInt()
          : int.tryParse('${json['accessUntilMillis'] ?? ''}') ?? 0,
      platform: '${json['platform'] ?? ''}'.trim(),
      storeProductId: '${json['storeProductId'] ?? ''}'.trim(),
      autoRenewEnabled: json['autoRenewEnabled'] is bool
          ? json['autoRenewEnabled'] as bool
          : null,
      cancellationAtIso: '${json['cancellationAt'] ?? ''}'.trim(),
      cancellationReason: '${json['cancellationReason'] ?? ''}'.trim(),
      storeStatus: '${json['storeStatus'] ?? ''}'.trim(),
      storeEnvironment: '${json['storeEnvironment'] ?? ''}'.trim(),
      revokedAtIso: '${json['revokedAt'] ?? ''}'.trim(),
      refundedAtIso: '${json['refundedAt'] ?? ''}'.trim(),
      lastStoreSyncAtIso: '${json['lastStoreSyncAt'] ?? ''}'.trim(),
      lastStoreSyncStatus: '${json['lastStoreSyncStatus'] ?? ''}'.trim(),
    );
  }

  BarberoBillingSnapshot copyWith({
    BarberoBillingStatus? status,
    BarberoBillingPlan? selectedPlan,
    bool? planConfirmed,
    bool? allowsAccess,
    bool? requiresOwnerAction,
    double? monthlyPriceEur,
    double? yearlyPriceEur,
    double? yearlySavingsEur,
    String? trialStartedAtIso,
    String? trialEndsAtIso,
    String? currentPeriodEndIso,
    int? accessUntilMillis,
    String? platform,
    String? storeProductId,
    bool? autoRenewEnabled,
    String? cancellationAtIso,
    String? cancellationReason,
    String? storeStatus,
    String? storeEnvironment,
    String? revokedAtIso,
    String? refundedAtIso,
    String? lastStoreSyncAtIso,
    String? lastStoreSyncStatus,
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
      accessUntilMillis: accessUntilMillis ?? this.accessUntilMillis,
      platform: platform ?? this.platform,
      storeProductId: storeProductId ?? this.storeProductId,
      autoRenewEnabled: autoRenewEnabled ?? this.autoRenewEnabled,
      cancellationAtIso: cancellationAtIso ?? this.cancellationAtIso,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      storeStatus: storeStatus ?? this.storeStatus,
      storeEnvironment: storeEnvironment ?? this.storeEnvironment,
      revokedAtIso: revokedAtIso ?? this.revokedAtIso,
      refundedAtIso: refundedAtIso ?? this.refundedAtIso,
      lastStoreSyncAtIso: lastStoreSyncAtIso ?? this.lastStoreSyncAtIso,
      lastStoreSyncStatus: lastStoreSyncStatus ?? this.lastStoreSyncStatus,
    );
  }
}

class BarberoSession {
  const BarberoSession({
    required this.shopId,
    required this.shopName,
    required this.userUid,
    required this.userEmail,
    required this.role,
    this.crewId = '',
    this.displayName = '',
  });

  final String shopId;
  final String shopName;
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

class BarberoAccessibleShop {
  const BarberoAccessibleShop({
    required this.shopId,
    required this.shopName,
    required this.ownerName,
    required this.role,
    this.crewId = '',
    this.displayName = '',
    this.billing,
    this.customerApp,
  });

  final String shopId;
  final String shopName;
  final String ownerName;
  final BarberoRole role;
  final String crewId;
  final String displayName;
  final BarberoBillingSnapshot? billing;
  final BarberoCustomerAppConfiguration? customerApp;

  bool get isOwner => role == BarberoRole.owner;

  String get roleLabel {
    switch (role) {
      case BarberoRole.owner:
        return 'Ιδιοκτήτης';
      case BarberoRole.seniorBarber:
        return 'Ανώτερος barber';
      case BarberoRole.assistant:
        return 'Βοηθός';
      case BarberoRole.barber:
        return 'barber';
    }
  }

  factory BarberoAccessibleShop.fromJson(Map<String, dynamic> json) {
    return BarberoAccessibleShop(
      shopId: '${json['shopId'] ?? ''}'.trim(),
      shopName: '${json['shopName'] ?? ''}'.trim(),
      ownerName: '${json['ownerName'] ?? ''}'.trim(),
      role: barberoRoleFromRaw('${json['role'] ?? ''}'),
      crewId: '${json['crewId'] ?? ''}'.trim(),
      displayName: '${json['displayName'] ?? ''}'.trim(),
      billing: json['billing'] is Map
          ? BarberoBillingSnapshot.fromJson(
              (json['billing'] as Map).cast<String, dynamic>(),
            )
          : null,
      customerApp: json['customerApp'] is Map
          ? BarberoCustomerAppConfiguration.fromJson(
              (json['customerApp'] as Map).cast<String, dynamic>(),
            )
          : null,
    );
  }
}

class BarberoCustomerAppConfiguration {
  const BarberoCustomerAppConfiguration({
    required this.status,
    required this.displayName,
    required this.packageName,
    required this.bundleId,
    required this.firebaseAndroidAppId,
    required this.firebaseIosAppId,
  });

  final String status;
  final String displayName;
  final String packageName;
  final String bundleId;
  final String firebaseAndroidAppId;
  final String firebaseIosAppId;

  factory BarberoCustomerAppConfiguration.fromJson(Map<String, dynamic> json) {
    return BarberoCustomerAppConfiguration(
      status: '${json['status'] ?? 'provisioning_required'}'.trim(),
      displayName: '${json['displayName'] ?? ''}'.trim(),
      packageName: '${json['packageName'] ?? ''}'.trim(),
      bundleId: '${json['bundleId'] ?? ''}'.trim(),
      firebaseAndroidAppId: '${json['firebaseAndroidAppId'] ?? ''}'.trim(),
      firebaseIosAppId: '${json['firebaseIosAppId'] ?? ''}'.trim(),
    );
  }

  String get statusLabel {
    switch (status) {
      case 'released':
        return 'Έτοιμο για χρήση';
      case 'built':
        return 'Έτοιμο για release';
      case 'configured':
        return 'Έχει ρυθμιστεί';
      default:
        return 'Χρειάζεται δημιουργία app';
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
    await _initializeBarberinFirebase();
  } catch (_) {}
  await _loadStoredBarberoNotifications();
  await loadBarberinLanguage();
  if (isBarberinFirebaseMessagingSupported) {
    FirebaseMessaging.onBackgroundMessage(_barberoMessagingBackgroundHandler);
  }
  runApp(const BarberinApp());
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
  if (barberinUsesEnglish) {
    if (value.hour < 12) return 'Good morning';
    if (value.hour < 18) return 'Good afternoon';
    return 'Good evening';
  }
  if (value.hour < 12) {
    return '\u039a\u03b1\u03bb\u03b7\u03bc\u03ad\u03c1\u03b1';
  }
  if (value.hour < 18) {
    return '\u039a\u03b1\u03bb\u03cc \u03b1\u03c0\u03cc\u03b3\u03b5\u03c5\u03bc\u03b1';
  }
  return '\u039a\u03b1\u03bb\u03b7\u03c3\u03c0\u03ad\u03c1\u03b1';
}

String greekDateLabel(DateTime value, {bool includeYear = false}) {
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
  final label =
      '${weekdays[value.weekday - 1]}, ${value.day} ${months[value.month - 1]}';
  return includeYear ? '$label ${value.year}' : label;
}

String greekDateLabelFromRaw(String raw, {bool includeYear = false}) {
  final value = DateTime.tryParse(raw.trim());
  if (value == null) {
    return raw.trim();
  }
  return greekDateLabel(value, includeYear: includeYear);
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
        isAvailable: !appointment.isBooked,
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
      name: 'Δευτέρα',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
    ScheduleDay(
      name: 'Τρίτη',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
    ScheduleDay(
      name: 'Τετάρτη',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
    ScheduleDay(
      name: 'Πέμπτη',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
    ScheduleDay(
      name: 'Παρασκευή',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
    ScheduleDay(
      name: 'Σάββατο',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
    ScheduleDay(
      name: 'Κυριακή',
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
  final displayName = name.trim().isEmpty ? 'Δείγμα πελάτη' : name.trim();
  return CustomerProfile(
    name: displayName,
    phone: '690 000 0000',
    preferences: const ['Classic haircut', 'Fade'],
    notes: 'Ενδεικτικό προφίλ πελάτη για την προεπισκόπηση της εφαρμογής.',
    history: const [
      VisitRecord(date: '2026-05-08', service: 'Classic haircut', price: 18),
      VisitRecord(date: '2026-04-22', service: 'Haircut & beard', price: 28),
    ],
  );
}
