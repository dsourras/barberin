part of 'main.dart';

class BarberoApp extends StatelessWidget {
  const BarberoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Barbero',
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090909),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFD1A45C),
          secondary: Color(0xFFE7C98F),
          surface: Color(0xFF151515),
        ),
        useMaterial3: true,
      ),
      home: const AppFlowPage(),
    );
  }
}

class AppFlowPage extends StatefulWidget {
  const AppFlowPage({super.key});

  @override
  State<AppFlowPage> createState() => _AppFlowPageState();
}

class _AppFlowPageState extends State<AppFlowPage> {
  int step = 0;
  bool _isResolvingSession = false;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;

  @override
  void initState() {
    super.initState();
    if (FirebaseAuth.instance.currentUser != null) {
      step = 4;
    }
    unawaited(BarberoStoreBillingService.instance.initialize());
    _initializeOwnerNotifications();
  }

  @override
  void dispose() {
    unawaited(BarberoStoreBillingService.instance.dispose());
    _tokenRefreshSubscription?.cancel();
    _foregroundMessageSubscription?.cancel();
    _messageOpenedSubscription?.cancel();
    super.dispose();
  }

  String _notificationTokenKey(String token) {
    return base64Url.encode(utf8.encode(token));
  }

  Future<void> _saveOwnerNotificationToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    final session = currentBarberoSession.value;
    if (user == null || token.trim().isEmpty || session == null || !session.isOwner) {
      return;
    }
    await FirebaseDatabase.instance
        .ref('shops/${session.shopId}/notificationTokens/${_notificationTokenKey(token)}')
        .set({
          'token': token,
          'platform': 'android',
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        });
  }

  Future<void> _resolveSessionForUser(User user) async {
    if (_isResolvingSession) {
      return;
    }
    _isResolvingSession = true;
    try {
      final idToken = await user.getIdToken();
      final response = await http.post(
        Uri.parse(
          'https://europe-west1-barbero-88d00.cloudfunctions.net/barberoResolveSession',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'idToken': idToken}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('session-resolve-failed');
      }
      final decoded = jsonDecode(response.body);
      final sessionData =
          decoded is Map<String, dynamic> ? decoded['session'] : null;
      if (sessionData is! Map) {
        throw Exception('invalid-session-response');
      }
      final session = BarberoSession(
        shopId: '${sessionData['shopId'] ?? ''}'.trim(),
        userUid: user.uid,
        userEmail: user.email ?? '',
        role: barberoRoleFromRaw('${sessionData['role'] ?? ''}'),
        crewId: '${sessionData['crewId'] ?? ''}'.trim(),
        displayName: '${sessionData['displayName'] ?? ''}'.trim(),
      );
      final billingData =
          decoded is Map<String, dynamic> ? decoded['billing'] : null;
      currentBarberoSession.value = session;
      currentBarberoBilling.value =
          billingData is Map
              ? BarberoBillingSnapshot.fromJson(
                billingData.cast<String, dynamic>(),
              )
              : null;
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _saveOwnerNotificationToken(token);
      }
      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      currentBarberoSession.value = null;
      currentBarberoBilling.value = null;
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Unable to access this shop account.')),
      );
    } finally {
      _isResolvingSession = false;
    }
  }

  Future<void> _initializeOwnerNotifications() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    final initialToken = await messaging.getToken();
    if (initialToken != null) {
      await _saveOwnerNotificationToken(initialToken);
    }
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      await _storeBarberoNotificationFromRemoteMessage(initialMessage);
    }
    _tokenRefreshSubscription = messaging.onTokenRefresh.listen((token) {
      _saveOwnerNotificationToken(token);
    });
    _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen((
      message,
    ) async {
      await _storeBarberoNotificationFromRemoteMessage(message);
      final title = message.notification?.title?.trim() ?? '';
      final body = message.notification?.body?.trim() ?? '';
      final text = [title, body].where((item) => item.isNotEmpty).join('\n');
      if (text.isEmpty) {
        return;
      }
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(text)),
      );
    });
    _messageOpenedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((
      message,
    ) async {
      await _storeBarberoNotificationFromRemoteMessage(message);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFFD1A45C)),
            ),
          );
        }

        final user = snapshot.data;
        if (user != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (currentBarberoSession.value?.userUid != user.uid ||
                currentBarberoBilling.value == null) {
              await _resolveSessionForUser(user);
            } else {
              final token = await FirebaseMessaging.instance.getToken();
              if (token != null) {
                await _saveOwnerNotificationToken(token);
              }
            }
          });
        } else if (currentBarberoSession.value != null ||
            currentBarberoBilling.value != null) {
          currentBarberoSession.value = null;
          currentBarberoBilling.value = null;
        }
        return ValueListenableBuilder<BarberoSession?>(
          valueListenable: currentBarberoSession,
          builder: (context, session, _) {
            return ValueListenableBuilder<BarberoBillingSnapshot?>(
              valueListenable: currentBarberoBilling,
              builder: (context, billing, child) {
                late final Widget page;
                late final int pageKey;

                if (user != null && session != null && billing != null) {
                  if (billing.canOpenWorkspace) {
                    pageKey = 4;
                    page = const BarberShell();
                  } else {
                    pageKey = 6;
                    page = BarberoSubscriptionGatePage(
                      session: session,
                      billing: billing,
                    );
                  }
                } else if (user != null) {
                  pageKey = 5;
                  page = const Scaffold(
                    body: Center(
                      child: CircularProgressIndicator(color: Color(0xFFD1A45C)),
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
  }
}

class AuthShell extends StatelessWidget {
  const AuthShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: const Color(0xFF000000),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 46,
                  ),
                  child: IntrinsicHeight(child: child),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
