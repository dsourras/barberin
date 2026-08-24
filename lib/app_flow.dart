part of 'main.dart';

bool _isResolvingBarberoWorkspace = false;

class BarberoSessionResolutionException implements Exception {
  const BarberoSessionResolutionException({
    required this.statusCode,
    required this.reason,
  });

  final int statusCode;
  final String reason;

  @override
  String toString() =>
      'BarberoSessionResolutionException($statusCode, $reason)';
}

// Keep the workspace available while developing locally. Production builds
// enable the subscription gate explicitly with --dart-define.
const bool _subscriptionGateEnabled = bool.fromEnvironment(
  'BARBERIN_ENABLE_SUBSCRIPTION_GATE',
  defaultValue: !kDebugMode,
);

class BarberinApp extends StatelessWidget {
  const BarberinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BarberinLanguage>(
      valueListenable: barberinLanguage,
      builder: (context, language, child) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: barberinThemeMode,
          builder: (context, mode, child) {
            return MaterialApp(
              key: ValueKey<BarberinLanguage>(language),
              debugShowCheckedModeBanner: false,
              title: 'Barberin',
              locale: language == BarberinLanguage.english
                  ? const Locale('en')
                  : const Locale('el'),
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('el'), Locale('en')],
              scaffoldMessengerKey: rootScaffoldMessengerKey,
              theme: _barberinLightTheme(),
              darkTheme: _barberinDarkTheme(),
              themeMode: mode,
              home: const AppFlowPage(),
            );
          },
        );
      },
    );
  }
}

ThemeData _barberinDarkTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF090909),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFFD1A45C),
      secondary: Color(0xFFE7C98F),
      surface: Color(0xFF151515),
      surfaceContainerHighest: Color(0xFF202020),
      outline: Color(0xFF3A3127),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF090909),
      foregroundColor: Color(0xFFF5ECDD),
      elevation: 0,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: false,
      border: UnderlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF2A2A2A)),
      ),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF2A2A2A)),
      ),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: Color(0xFFD1A45C), width: 1.4),
      ),
    ),
    dividerTheme: DividerThemeData(color: Color(0xFF2A2A2A)),
    useMaterial3: true,
  );
}

ThemeData _barberinLightTheme() {
  const primary = Color(0xFF1F2937);
  const background = Color(0xFFF6F8FA);
  const surface = Color(0xFFFFFFFF);
  const outline = Color(0xFFD9E0E8);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: primary,
        onPrimary: Colors.white,
        secondary: const Color(0xFF475569),
        onSecondary: Colors.white,
        surface: surface,
        surfaceContainerHighest: const Color(0xFFEEF2F6),
        outline: outline,
        onSurface: const Color(0xFF1F2937),
        onSurfaceVariant: const Color(0xFF64748B),
      );
  return ThemeData(
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    canvasColor: background,
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      foregroundColor: primary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: const CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: false,
      border: UnderlineInputBorder(borderSide: BorderSide(color: outline)),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: primary, width: 1.4),
      ),
    ),
    dividerTheme: const DividerThemeData(color: outline),
    useMaterial3: true,
  );
}

extension BarberinThemeContext on BuildContext {
  bool get barberinIsLight => Theme.of(this).brightness == Brightness.light;

  Color get barberinBackground =>
      barberinIsLight ? const Color(0xFFF6F5EF) : const Color(0xFF0F242A);

  Color get barberinSurface =>
      barberinIsLight ? const Color(0xFFFFFDF8) : const Color(0xFF102B35);

  Color get barberinSurfaceAlt =>
      barberinIsLight ? const Color(0xFFEAF4F5) : const Color(0xFF0F3440);

  Color get barberinBorder =>
      barberinIsLight ? const Color(0xFFD8E2DF) : const Color(0xFF2C4A52);

  Color get barberinTextPrimary =>
      barberinIsLight ? const Color(0xFF102B35) : const Color(0xFFFFFDF8);

  Color get barberinTextSecondary =>
      barberinIsLight ? const Color(0xFF6D8184) : const Color(0xFFB8CAC9);

  Color get barberinAccentSoft =>
      barberinIsLight ? const Color(0xFFDCEEF2) : const Color(0xFF183F49);

  Color get barberinAccent =>
      barberinIsLight ? const Color(0xFF1B5B70) : const Color(0xFF9AC7B7);
}

Color barberinAppointmentTone(String status, {bool isAvailable = false}) {
  if (isAvailable) {
    return const Color(0xFFC8DDE1);
  }
  return switch (status) {
    'pending' => const Color(0xFFF7E9DF),
    'confirmed' => const Color(0xFF9AC7B7),
    'completed' => const Color(0xFFC8DDE1),
    'cancelled' => const Color(0xFFF7E2E0),
    'no_show' => const Color(0xFFEAF4F5),
    _ => const Color(0xFFC8DDE1),
  };
}

Color barberinAppointmentForeground(String status, {bool isAvailable = false}) {
  if (isAvailable) {
    return const Color(0xFF1B5B70);
  }
  return switch (status) {
    'pending' => const Color(0xFF0F3440),
    'confirmed' => const Color(0xFF0F3440),
    'completed' => const Color(0xFF1B5B70),
    'cancelled' => const Color(0xFF8A3030),
    'no_show' => const Color(0xFF6D8184),
    _ => const Color(0xFF1B5B70),
  };
}

class AppFlowPage extends StatefulWidget {
  const AppFlowPage({super.key});

  @override
  State<AppFlowPage> createState() => _AppFlowPageState();
}

class _AppFlowPageState extends State<AppFlowPage> with WidgetsBindingObserver {
  int step = 0;
  Timer? _billingExpiryTimer;
  Timer? _fallbackNotificationPollTimer;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;
  String? _platformAdminRoleUid;
  Future<void>? _platformAdminRoleFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (FirebaseAuth.instance.currentUser != null) {
      step = 4;
    }
    unawaited(BarberoStoreBillingService.instance.initialize());
    _initializeOwnerNotifications();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _billingExpiryTimer?.cancel();
    _fallbackNotificationPollTimer?.cancel();
    unawaited(BarberoStoreBillingService.instance.dispose());
    _tokenRefreshSubscription?.cancel();
    _foregroundMessageSubscription?.cancel();
    _messageOpenedSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _fallbackNotificationPollTimer?.cancel();
      _fallbackNotificationPollTimer = null;
      return;
    }
    if (barberinRegistrationInProgress.value) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && currentBarberoSession.value != null) {
      unawaited(_refreshBillingOnResume());
      if (isBarberinDesktopNotificationFallback) {
        _startFallbackNotificationPolling();
        unawaited(_pollFallbackNotifications());
      }
    }
  }

  Future<void> _refreshBillingOnResume() async {
    try {
      final billing = await BillingRepository().loadCurrentBilling();
      currentBarberoBilling.value = billing;
      _scheduleBillingExpiry(billing);
      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      // A temporary network failure must not sign the user out. Server-side
      // checks still protect every protected action while the app retries.
    }
  }

  Future<void> _refreshPlatformAdminRole(User user) async {
    try {
      await refreshBarberinPlatformAdminRole(forceRefresh: true);
      if (mounted && FirebaseAuth.instance.currentUser?.uid == user.uid) {
        setState(() {});
      }
    } catch (_) {
      if (mounted && FirebaseAuth.instance.currentUser?.uid == user.uid) {
        currentBarberinPlatformAdmin.value = false;
        setState(() {});
      }
    }
  }

  String _notificationTokenKey(String token) {
    return base64Url.encode(utf8.encode(token));
  }

  String _notificationPlatform() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      default:
        return 'unknown';
    }
  }

  Future<void> _saveOwnerNotificationToken(String token) async {
    if (isBarberinDesktopNotificationFallback) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    final session = currentBarberoSession.value;
    if (user == null ||
        token.trim().isEmpty ||
        session == null ||
        !session.isOwner) {
      return;
    }
    final ownerShops = currentBarberoAccessibleShops.value
        .where((shop) => shop.isOwner)
        .toList();
    final targetShopIds = ownerShops.isNotEmpty
        ? ownerShops
              .map((shop) => shop.shopId.trim())
              .where((id) => id.isNotEmpty)
        : <String>[session.shopId.trim()];
    for (final shopId in targetShopIds) {
      await FirebaseDatabase.instance
          .ref(
            'shops/$shopId/notificationTokens/${_notificationTokenKey(token)}',
          )
          .set({
            'token': token,
            'platform': _notificationPlatform(),
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          });
    }
  }

  Future<void> _resolveSessionForUser(User user) async {
    try {
      // Keep Firebase authentication separate from workspace resolution. A
      // backend outage or a missing shop must not be reported as a Firebase
      // Auth failure.
      await resolveBarberoSessionForCurrentUser(user, signOutOnFailure: false);
      final billing = currentBarberoBilling.value;
      if (billing != null) {
        _scheduleBillingExpiry(billing);
      }
      // APNs/FCM registration is best-effort and must never invalidate a
      // successful authentication, especially during the first iPad launch.
      try {
        if (isBarberinFirebaseMessagingSupported) {
          final token = await FirebaseMessaging.instance.getToken();
          if (token != null) {
            await _saveOwnerNotificationToken(token);
          }
        }
      } catch (_) {}
      if (isBarberinDesktopNotificationFallback) {
        _startFallbackNotificationPolling();
      }
      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      if (isBarberinPlatformAdmin) {
        currentBarberoSession.value = null;
        currentBarberoBilling.value = null;
        if (mounted) setState(() {});
        return;
      }
      currentBarberoSession.value = null;
      currentBarberoBilling.value = null;
      _billingExpiryTimer?.cancel();
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(_barberoSessionErrorMessage(error))),
      );
    }
  }

  String _barberoSessionErrorMessage(Object error) {
    if (error is BarberoSessionResolutionException &&
        error.reason == 'barbero-session-not-found') {
      return 'Η σύνδεση ολοκληρώθηκε, αλλά δεν βρέθηκε ενεργό κατάστημα για τον λογαριασμό αυτό.';
    }
    if (error is BarberoSessionResolutionException) {
      return 'Η σύνδεση ολοκληρώθηκε, αλλά δεν φορτώθηκε το κατάστημα. Δοκίμασε ξανά σε λίγο.';
    }
    return 'Η σύνδεση ολοκληρώθηκε, αλλά δεν φορτώθηκε το κατάστημα.';
  }

  void _scheduleBillingExpiry(BarberoBillingSnapshot billing) {
    _billingExpiryTimer?.cancel();
    if (!billing.allowsAccess || billing.accessUntilMillis <= 0) {
      return;
    }
    final remainingMillis =
        billing.accessUntilMillis - DateTime.now().millisecondsSinceEpoch;
    if (remainingMillis <= 0) {
      currentBarberoBilling.value = billing.copyWith(
        status: BarberoBillingStatus.expired,
        allowsAccess: false,
        requiresOwnerAction: true,
      );
      if (mounted) setState(() {});
      return;
    }
    _billingExpiryTimer = Timer(Duration(milliseconds: remainingMillis), () {
      final current = currentBarberoBilling.value;
      if (current == null ||
          current.accessUntilMillis != billing.accessUntilMillis) {
        return;
      }
      currentBarberoBilling.value = current.copyWith(
        status: BarberoBillingStatus.expired,
        allowsAccess: false,
        requiresOwnerAction: true,
      );
      if (mounted) setState(() {});
    });
  }

  Future<void> _initializeOwnerNotifications() async {
    if (isBarberinDesktopNotificationFallback) {
      _startFallbackNotificationPolling();
      return;
    }
    if (!isBarberinFirebaseMessagingSupported) {
      return;
    }
    final messaging = FirebaseMessaging.instance;
    try {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final initialToken = await messaging.getToken();
      if (initialToken != null) {
        await _saveOwnerNotificationToken(initialToken);
      }
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        await _storeBarberoNotificationFromRemoteMessage(initialMessage);
      }
    } catch (_) {
      // APNs can be unavailable briefly on a fresh iPad install. Authentication
      // and workspace access must continue while notification setup retries.
    }
    try {
      _tokenRefreshSubscription = messaging.onTokenRefresh.listen((token) {
        unawaited(_saveOwnerNotificationToken(token));
      });
      _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen((
        message,
      ) async {
        final notification = await _storeBarberoNotificationFromRemoteMessage(
          message,
        );
        final title = message.notification?.title?.trim() ?? '';
        final body = message.notification?.body?.trim() ?? '';
        final text = [title, body].where((item) => item.isNotEmpty).join('\n');
        if (text.isEmpty) {
          return;
        }
        rootScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(text),
            action: notification?.appointmentId.isNotEmpty == true
                ? SnackBarAction(
                    label: barberinLabel(
                      '\u03a0\u03a1\u039f\u0392\u039f\u039b\u0397',
                      'VIEW',
                    ),
                    onPressed: () {
                      barberoPendingAppointmentNotification.value =
                          notification;
                    },
                  )
                : null,
          ),
        );
      });
      _messageOpenedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((
        message,
      ) async {
        await _storeBarberoNotificationFromRemoteMessage(message);
      });
    } catch (_) {}
  }

  void _startFallbackNotificationPolling() {
    if (!isBarberinDesktopNotificationFallback ||
        _fallbackNotificationPollTimer != null) {
      return;
    }
    unawaited(_pollFallbackNotifications());
    _fallbackNotificationPollTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(_pollFallbackNotifications()),
    );
  }

  Future<void> _pollFallbackNotifications() async {
    if (!isBarberinDesktopNotificationFallback) {
      return;
    }
    final session = currentBarberoSession.value;
    if (session == null || !session.isOwner) {
      return;
    }
    try {
      final items = await WindowsBackendAdapter.instance.loadNotifications(
        session.shopId,
      );
      for (final item in items) {
        final notification = _barberoNotificationFromFallback(item);
        if (notification != null) {
          await _storeBarberoNotificationItemIfMissing(notification);
        }
      }
    } catch (_) {
      // Polling is best-effort. Existing local notifications remain available.
    }
  }

  BarberoNotificationItem? _barberoNotificationFromFallback(
    Map<String, dynamic> raw,
  ) {
    final id = '${raw['id'] ?? ''}'.trim();
    final notification = raw['notification'];
    final data = raw['data'];
    final notificationMap = notification is Map
        ? notification.cast<String, dynamic>()
        : const <String, dynamic>{};
    final dataMap = data is Map
        ? data.cast<String, dynamic>()
        : const <String, dynamic>{};
    final title = '${notificationMap['title'] ?? ''}'.trim();
    final body = '${notificationMap['body'] ?? ''}'.trim();
    if (id.isEmpty || (title.isEmpty && body.isEmpty)) {
      return null;
    }
    return BarberoNotificationItem(
      id: id,
      title: title.isEmpty ? 'Ειδοποίηση' : title,
      body: body,
      receivedAtIso:
          '${raw['createdAt'] ?? DateTime.now().toUtc().toIso8601String()}',
      type: '${dataMap['type'] ?? raw['eventType'] ?? 'general'}'.trim(),
      appointmentId: '${dataMap['appointmentId'] ?? ''}'.trim(),
      appointmentDate: '${dataMap['date'] ?? ''}'.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: barberinRegistrationInProgress,
      builder: (context, registrationInProgress, _) {
        return StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Scaffold(
                body: Center(
                  child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              );
            }

            final user = snapshot.data;
            if (user != null && !registrationInProgress) {
              if (_platformAdminRoleUid != user.uid) {
                _platformAdminRoleUid = user.uid;
                _platformAdminRoleFuture = _refreshPlatformAdminRole(user);
                unawaited(_platformAdminRoleFuture!);
              }
              final platformAdminRoleFuture = _platformAdminRoleFuture;
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                await platformAdminRoleFuture;
                if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
                  return;
                }
                if (currentBarberoSession.value?.userUid != user.uid ||
                    currentBarberoBilling.value == null ||
                    currentBarberoAccessibleShops.value.isEmpty) {
                  await _resolveSessionForUser(user);
                }
              });
            } else {
              _platformAdminRoleUid = null;
              _platformAdminRoleFuture = null;
              if (currentBarberinPlatformAdmin.value) {
                currentBarberinPlatformAdmin.value = false;
              }
              if (currentBarberoSession.value != null ||
                  currentBarberoBilling.value != null ||
                  currentBarberoAccessibleShops.value.isNotEmpty) {
                currentBarberoAccessibleShops.value =
                    const <BarberoAccessibleShop>[];
                currentBarberoSession.value = null;
                currentBarberoBilling.value = null;
                unawaited(_clearPreferredBarberoShopId());
              }
            }
            return ValueListenableBuilder<BarberoSession?>(
              valueListenable: currentBarberoSession,
              builder: (context, session, _) {
                return ValueListenableBuilder<BarberoBillingSnapshot?>(
                  valueListenable: currentBarberoBilling,
                  builder: (context, billing, child) {
                    late final Widget page;
                    late final Object pageKey;

                    if (registrationInProgress) {
                      pageKey = 'registration';
                      page = AuthShell(
                        child: RegistrationScreen(
                          onBack: () {
                            barberinRegistrationInProgress.value = false;
                            setState(() => step = 1);
                          },
                          onComplete: (shopId, ownerName) =>
                              setState(() => step = 4),
                        ),
                      );
                    } else if (user != null &&
                        isBarberinPlatformAdmin &&
                        (session == null || billing == null)) {
                      pageKey = 'platform-admin';
                      page = const PlatformAdminPage();
                    } else if (user != null &&
                        session != null &&
                        billing != null) {
                      if (!_subscriptionGateEnabled ||
                          billing.canOpenWorkspace) {
                        pageKey = 'workspace-${session.shopId}';
                        page = BarberShell(key: ValueKey(session.shopId));
                      } else {
                        pageKey = 'billing-${session.shopId}';
                        page = BarberoSubscriptionGatePage(
                          key: ValueKey('billing-${session.shopId}'),
                          session: session,
                          billing: billing,
                        );
                      }
                    } else if (user != null) {
                      pageKey = 5;
                      page = Scaffold(
                        body: Center(
                          child: CircularProgressIndicator(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      );
                    } else {
                      final authStep = step > 3 ? 0 : step;

                      final pages = [
                        AuthShell(
                          child: WelcomeScreen(
                            onLoginTap: () => setState(() => step = 1),
                            onRegisterTap: () => setState(() => step = 2),
                            onJoinTap: () => setState(() => step = 3),
                          ),
                        ),
                        AuthShell(
                          child: LoginScreen(
                            onBack: () => setState(() => step = 0),
                            onLogin: () => setState(() => step = 4),
                            onRegisterTap: () => setState(() => step = 2),
                            onJoinTap: () => setState(() => step = 3),
                          ),
                        ),
                        AuthShell(
                          child: RegistrationScreen(
                            onBack: () => setState(() => step = 1),
                            onComplete: (shopId, ownerName) =>
                                setState(() => step = 4),
                          ),
                        ),
                        AuthShell(
                          child: JoinCrewScreen(
                            onBack: () => setState(() => step = 1),
                            onComplete: () => setState(() => step = 4),
                          ),
                        ),
                      ];

                      pageKey = authStep;
                      page = pages[authStep];
                    }

                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      child: KeyedSubtree(key: ValueKey(pageKey), child: page),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

Future<String?> _loadPreferredBarberoShopId() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_barberoActiveShopStorageKey)?.trim() ?? '';
  return raw.isEmpty ? null : raw;
}

Future<void> _savePreferredBarberoShopId(String shopId) async {
  final normalized = shopId.trim();
  final prefs = await SharedPreferences.getInstance();
  if (normalized.isEmpty) {
    await prefs.remove(_barberoActiveShopStorageKey);
    return;
  }
  await prefs.setString(_barberoActiveShopStorageKey, normalized);
}

Future<void> _clearPreferredBarberoShopId() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_barberoActiveShopStorageKey);
}

List<BarberoAccessibleShop> _parseAccessibleBarberoShops(
  dynamic shopsData,
  BarberoSession fallbackSession,
) {
  if (shopsData is List) {
    final parsed = shopsData
        .whereType<Map>()
        .map(
          (item) =>
              BarberoAccessibleShop.fromJson(item.cast<String, dynamic>()),
        )
        .where((shop) => shop.shopId.isNotEmpty)
        .toList(growable: false);
    if (parsed.isNotEmpty) {
      return parsed;
    }
  }
  return <BarberoAccessibleShop>[
    BarberoAccessibleShop(
      shopId: fallbackSession.shopId,
      shopName: fallbackSession.shopName,
      ownerName: fallbackSession.displayName,
      role: fallbackSession.role,
      crewId: fallbackSession.crewId,
      displayName: fallbackSession.displayName,
    ),
  ];
}

Future<void> resolveBarberoSessionForCurrentUser(
  User user, {
  String? preferredShopId,
  bool signOutOnFailure = true,
}) async {
  if (_isResolvingBarberoWorkspace) {
    return;
  }
  _isResolvingBarberoWorkspace = true;
  try {
    final idToken = await user.getIdToken();
    final requestedShopId =
        (preferredShopId ?? await _loadPreferredBarberoShopId())?.trim() ?? '';
    final response = await http.post(
      Uri.parse(
        'https://europe-west1-barbero-88d00.cloudfunctions.net/barberoResolveSession',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
        if (requestedShopId.isNotEmpty) 'activeShopId': requestedShopId,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var reason = 'session-resolve-failed';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && '${body['message'] ?? ''}'.trim().isNotEmpty) {
          reason = '${body['message']}'.trim();
        }
      } catch (_) {
        // Keep the stable fallback reason when the server response is not JSON.
      }
      throw BarberoSessionResolutionException(
        statusCode: response.statusCode,
        reason: reason,
      );
    }
    // The backend refreshes shop membership custom claims for database rules.
    await user.getIdToken(true);
    final decoded = jsonDecode(response.body);
    final sessionData = decoded is Map<String, dynamic>
        ? decoded['session']
        : null;
    if (sessionData is! Map) {
      throw Exception('invalid-session-response');
    }
    final nextSession = BarberoSession(
      shopId: '${sessionData['shopId'] ?? ''}'.trim(),
      shopName: '${sessionData['shopName'] ?? ''}'.trim(),
      userUid: user.uid,
      userEmail: user.email ?? '',
      role: barberoRoleFromRaw('${sessionData['role'] ?? ''}'),
      crewId: '${sessionData['crewId'] ?? ''}'.trim(),
      displayName: '${sessionData['displayName'] ?? ''}'.trim(),
    );
    if (nextSession.shopId.isEmpty) {
      throw Exception('invalid-session-shop');
    }
    final billingData = decoded is Map<String, dynamic>
        ? decoded['billing']
        : null;
    final nextBilling = billingData is Map
        ? BarberoBillingSnapshot.fromJson(billingData.cast<String, dynamic>())
        : null;
    final nextAccessibleShops = _parseAccessibleBarberoShops(
      decoded is Map<String, dynamic> ? decoded['shops'] : null,
      nextSession,
    );
    currentBarberoAccessibleShops.value = nextAccessibleShops;
    currentBarberoSession.value = nextSession;
    currentBarberoBilling.value = nextBilling;
    await _savePreferredBarberoShopId(nextSession.shopId);
  } catch (_) {
    if (signOutOnFailure) {
      currentBarberoAccessibleShops.value = const <BarberoAccessibleShop>[];
      currentBarberoSession.value = null;
      currentBarberoBilling.value = null;
      await _clearPreferredBarberoShopId();
      await FirebaseAuth.instance.signOut();
    } else {
      rethrow;
    }
  } finally {
    _isResolvingBarberoWorkspace = false;
  }
}

Future<void> switchBarberoActiveShop(String shopId) async {
  final normalizedShopId = shopId.trim();
  if (normalizedShopId.isEmpty ||
      currentBarberoSession.value?.shopId == normalizedShopId) {
    return;
  }
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw Exception('missing-barbero-user');
  }
  await resolveBarberoSessionForCurrentUser(
    user,
    preferredShopId: normalizedShopId,
    signOutOnFailure: false,
  );
}

class AuthShell extends StatelessWidget {
  const AuthShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = _barberinLightTheme();
    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFBFCFD), Color(0xFFF0F3F6)],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                  child: Center(
                    child: SizedBox(
                      width: math.min(constraints.maxWidth, 720),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight - 46,
                        ),
                        child: IntrinsicHeight(child: child),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
