part of 'main.dart';

final GoogleSignIn _barberinGoogleSignIn = GoogleSignIn.instance;
Future<void>? _barberinGoogleInitialization;
const _barberinGoogleServerClientId = String.fromEnvironment(
  'BARBERIN_GOOGLE_SERVER_CLIENT_ID',
);

class _BarberinGoogleCredentialConflict implements Exception {
  const _BarberinGoogleCredentialConflict({
    required this.email,
    required this.credential,
  });

  final String email;
  final AuthCredential credential;
}

class _BarberinGoogleRecoveryCanceled implements Exception {
  const _BarberinGoogleRecoveryCanceled();
}

class _BarberinAppleCredentialConflict implements Exception {
  const _BarberinAppleCredentialConflict({
    required this.email,
    required this.credential,
  });

  final String email;
  final AuthCredential credential;
}

class _BarberinAppleRecoveryCanceled implements Exception {
  const _BarberinAppleRecoveryCanceled();
}

bool get _barberinAppleSignInAvailable =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

class _BarberinGoogleLogo extends StatelessWidget {
  const _BarberinGoogleLogo();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/google_logo.png',
      width: 22,
      height: 22,
      fit: BoxFit.contain,
      semanticLabel: 'Google',
    );
  }
}

Future<UserCredential> _barberinSignInWithGoogle() async {
  // google_sign_in has no Windows implementation. Desktop uses a loopback
  // browser flow and feeds the returned Google credential to Firebase Auth.
  if (defaultTargetPlatform == TargetPlatform.windows) {
    return _barberinSignInWithGoogleOnWindows();
  }

  _barberinGoogleInitialization ??= _barberinGoogleSignIn.initialize(
    serverClientId: _barberinGoogleServerClientId.trim().isEmpty
        ? null
        : _barberinGoogleServerClientId,
  );
  await _barberinGoogleInitialization;
  await _barberinGoogleSignIn.signOut();

  final account = await _barberinGoogleSignIn.authenticate();
  final idToken = account.authentication.idToken;
  if (idToken == null || idToken.isEmpty) {
    throw FirebaseAuthException(
      code: 'google-id-token-missing',
      message: 'Google did not return an ID token.',
    );
  }
  final credential = GoogleAuthProvider.credential(idToken: idToken);
  try {
    return await FirebaseAuth.instance.signInWithCredential(credential);
  } on FirebaseAuthException catch (error) {
    if (error.code == 'account-exists-with-different-credential') {
      throw _BarberinGoogleCredentialConflict(
        email: account.email,
        credential: credential,
      );
    }
    rethrow;
  }
}

Future<UserCredential> _barberinSignInWithGoogleOnWindows() async {
  final state = base64Url
      .encode(List<int>.generate(32, (_) => math.Random.secure().nextInt(256)))
      .replaceAll('=', '');
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final result = Completer<Map<String, String>>();
  final firebaseConfig = jsonEncode({
    'apiKey': const String.fromEnvironment('BARBERIN_FIREBASE_API_KEY'),
    'authDomain':
        '${const String.fromEnvironment('BARBERIN_FIREBASE_PROJECT_ID')}.firebaseapp.com',
    'projectId': const String.fromEnvironment('BARBERIN_FIREBASE_PROJECT_ID'),
    'appId': const String.fromEnvironment('BARBERIN_FIREBASE_APP_ID'),
    'messagingSenderId': const String.fromEnvironment(
      'BARBERIN_FIREBASE_MESSAGING_SENDER_ID',
    ),
  });
  final page = _barberinGoogleDesktopAuthPage(
    state: state,
    firebaseConfig: firebaseConfig,
  );

  Future<void> respond(
    HttpRequest request, {
    required int statusCode,
    required String body,
    ContentType? contentType,
  }) async {
    request.response.statusCode = statusCode;
    if (contentType != null) {
      request.response.headers.contentType = contentType;
    }
    request.response.write(body);
    await request.response.close();
  }

  final subscription = server.listen((request) async {
    if (request.method == 'GET' && request.uri.path == '/') {
      if (request.uri.queryParameters['state'] != state) {
        await respond(request, statusCode: 403, body: 'Invalid state.');
      } else {
        await respond(
          request,
          statusCode: 200,
          body: page,
          contentType: ContentType.html,
        );
      }
      return;
    }

    if (request.method == 'POST' && request.uri.path == '/complete') {
      try {
        final rawBody = await utf8.decoder.bind(request).join();
        final body = jsonDecode(rawBody);
        if (body is! Map || '${body['state'] ?? ''}' != state) {
          throw const FormatException('Invalid OAuth state.');
        }
        final idToken = '${body['idToken'] ?? ''}'.trim();
        final accessToken = '${body['accessToken'] ?? ''}'.trim();
        final error = '${body['error'] ?? ''}'.trim();
        if (error.isNotEmpty) {
          throw FirebaseAuthException(
            code: 'google-browser-error',
            message: error,
          );
        }
        if (idToken.isEmpty && accessToken.isEmpty) {
          throw const FormatException('Google returned no credential.');
        }
        if (!result.isCompleted) {
          result.complete({'idToken': idToken, 'accessToken': accessToken});
        }
        await respond(
          request,
          statusCode: 200,
          body: 'You can close this window.',
        );
      } catch (error) {
        if (!result.isCompleted) {
          result.completeError(error);
        }
        await respond(
          request,
          statusCode: 400,
          body: 'Google sign-in did not complete.',
        );
      }
      return;
    }

    await respond(request, statusCode: 404, body: 'Not found.');
  });

  try {
    final opened = await launchUrl(
      // Firebase Auth includes localhost in the default authorized domains;
      // using the hostname avoids rejecting the loopback OAuth redirect.
      Uri.parse('http://localhost:${server.port}/?state=$state'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      throw FirebaseAuthException(
        code: 'google-browser-unavailable',
        message: 'The system browser could not be opened.',
      );
    }
    final credentialData = await result.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () => throw FirebaseAuthException(
        code: 'google-sign-in-timeout',
        message: 'Google sign-in timed out.',
      ),
    );
    final credential = GoogleAuthProvider.credential(
      idToken: credentialData['idToken'],
      accessToken: credentialData['accessToken'],
    );
    return FirebaseAuth.instance.signInWithCredential(credential);
  } finally {
    await subscription.cancel();
    await server.close(force: true);
  }
}

String _barberinGoogleDesktopAuthPage({
  required String state,
  required String firebaseConfig,
}) {
  final encodedState = jsonEncode(state);
  return '''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Barberin Google sign-in</title>
  <style>body{font-family:system-ui,sans-serif;max-width:520px;margin:16vh auto;padding:24px;color:#182333}#status{padding:20px;border:1px solid #d6dce5;border-radius:16px}</style>
</head>
<body><div id="status">Continuing with Google...</div>
<script src="https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js"></script>
<script src="https://www.gstatic.com/firebasejs/10.14.1/firebase-auth-compat.js"></script>
<script>
const firebaseConfig = $firebaseConfig;
const state = $encodedState;
const status = document.getElementById('status');
const complete = async (payload) => {
  try {
    await fetch('/complete', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({...payload, state})});
    status.textContent = payload.error ? 'Google sign-in did not complete. You can close this window.' : 'Signed in. You can close this window.';
  } catch (error) {
    status.textContent = 'The app could not receive the Google sign-in result.';
  }
};
try {
  firebase.initializeApp(firebaseConfig);
  const auth = firebase.auth();
  auth.useDeviceLanguage();
  const provider = new firebase.auth.GoogleAuthProvider();
  auth.getRedirectResult().then((result) => {
    if (result && result.credential) {
      const credential = result.credential;
      return complete({idToken: credential.idToken || '', accessToken: credential.accessToken || ''});
    }
    return auth.signInWithRedirect(provider);
  }).catch((error) => complete({error: error && (error.code || error.message) || 'google-redirect-failed'}));
} catch (error) {
  complete({error: error && (error.code || error.message) || 'google-page-failed'});
}
</script></body></html>''';
}

Future<UserCredential> _barberinSignInWithApple() async {
  if (!_barberinAppleSignInAvailable || !await SignInWithApple.isAvailable()) {
    throw FirebaseAuthException(
      code: 'apple-sign-in-unavailable',
      message: 'Sign in with Apple is not available on this device.',
    );
  }

  final rawNonce = generateNonce();
  final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
  final appleCredential = await SignInWithApple.getAppleIDCredential(
    scopes: const [
      AppleIDAuthorizationScopes.email,
      AppleIDAuthorizationScopes.fullName,
    ],
    nonce: hashedNonce,
  );
  final identityToken = appleCredential.identityToken;
  if (identityToken == null || identityToken.isEmpty) {
    throw FirebaseAuthException(
      code: 'apple-identity-token-missing',
      message: 'Apple did not return an identity token.',
    );
  }

  final credential = OAuthProvider(
    'apple.com',
  ).credential(idToken: identityToken, rawNonce: rawNonce);
  try {
    return await FirebaseAuth.instance.signInWithCredential(credential);
  } on FirebaseAuthException catch (error) {
    if (error.code == 'account-exists-with-different-credential') {
      throw _BarberinAppleCredentialConflict(
        email: appleCredential.email?.trim() ?? '',
        credential: credential,
      );
    }
    rethrow;
  }
}

Future<String?> _barberinAskForExistingPassword(
  BuildContext context,
  String email,
  String provider,
) async {
  final controller = TextEditingController();
  final password = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        backgroundColor: scheme.surface,
        title: Text(
          barberinLabel(
            '\u03a3\u03cd\u03bd\u03b4\u03b5\u03c3\u03b7 \u03bb\u03bf\u03b3\u03b1\u03c1\u03b9\u03b1\u03c3\u03bc\u03bf\u03cd',
            'Connect your account',
          ),
          style: TextStyle(color: scheme.onSurface),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              barberinLabel(
                '\u03a4\u03bf $email \u03c7\u03c1\u03b7\u03c3\u03b9\u03bc\u03bf\u03c0\u03bf\u03b9\u03b5\u03af \u03ae\u03b4\u03b7 email \u03ba\u03b1\u03b9 \u03ba\u03c9\u03b4\u03b9\u03ba\u03cc. \u03a0\u03bb\u03b7\u03ba\u03c4\u03c1\u03bf\u03bb\u03cc\u03b3\u03b7\u03c3\u03b5 \u03c4\u03bf\u03bd \u03c5\u03c0\u03ac\u03c1\u03c7\u03bf\u03bd\u03c4\u03b1 \u03ba\u03c9\u03b4\u03b9\u03ba\u03cc \u03b3\u03b9\u03b1 \u03bd\u03b1 \u03c3\u03c5\u03bd\u03b4\u03b5\u03b8\u03b5\u03af \u03c2\u03c4\u03bf Google.',
                'This email already uses email and password. Enter the existing password once to connect $provider.',
              ),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                  Navigator.of(dialogContext).pop(value);
                }
              },
              style: TextStyle(color: scheme.onSurface),
              decoration: InputDecoration(
                labelText: barberinLabel(
                  '\u039a\u03c9\u03b4\u03b9\u03ba\u03cc\u03c2',
                  'Password',
                ),
                labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: scheme.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: scheme.primary),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              barberinLabel('\u0386\u03ba\u03c5\u03c1\u03bf', 'Cancel'),
            ),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                Navigator.of(dialogContext).pop(controller.text);
              }
            },
            child: Text(
              barberinLabel(
                '\u03a3\u03c5\u03bd\u03ad\u03c7\u03b5\u03b9\u03b1',
                'Continue',
              ),
            ),
          ),
        ],
      );
    },
  );
  controller.dispose();
  return password;
}

Future<UserCredential> _barberinSignInWithGoogleAndRecovery(
  BuildContext context,
) async {
  try {
    return await _barberinSignInWithGoogle();
  } on _BarberinGoogleCredentialConflict catch (conflict) {
    if (!context.mounted) {
      throw const _BarberinGoogleRecoveryCanceled();
    }
    final password = await _barberinAskForExistingPassword(
      context,
      conflict.email,
      'Google',
    );
    if (password == null || password.isEmpty) {
      throw const _BarberinGoogleRecoveryCanceled();
    }

    final existingCredential = await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: conflict.email, password: password);
    final user = existingCredential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'google-link-user-missing',
        message: 'The existing Firebase user was not found.',
      );
    }
    try {
      return await user.linkWithCredential(conflict.credential);
    } on FirebaseAuthException catch (error) {
      if (error.code == 'provider-already-linked') {
        return existingCredential;
      }
      rethrow;
    }
  }
}

Future<UserCredential> _barberinSignInWithAppleAndRecovery(
  BuildContext context,
) async {
  try {
    return await _barberinSignInWithApple();
  } on _BarberinAppleCredentialConflict catch (conflict) {
    if (!context.mounted) {
      throw const _BarberinAppleRecoveryCanceled();
    }
    if (conflict.email.isEmpty) {
      throw FirebaseAuthException(
        code: 'apple-existing-account',
        message:
            'Sign in with Apple returned a private identity without an email. Sign in with the existing account first.',
      );
    }
    final password = await _barberinAskForExistingPassword(
      context,
      conflict.email,
      'Apple',
    );
    if (password == null || password.isEmpty) {
      throw const _BarberinAppleRecoveryCanceled();
    }

    final existingCredential = await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: conflict.email, password: password);
    final user = existingCredential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'apple-link-user-missing',
        message: 'The existing Firebase user was not found.',
      );
    }
    try {
      return await user.linkWithCredential(conflict.credential);
    } on FirebaseAuthException catch (error) {
      if (error.code == 'provider-already-linked') {
        return existingCredential;
      }
      rethrow;
    }
  }
}

String _barberinGoogleErrorMessage(Object error) {
  if (error is GoogleSignInException &&
      error.code == GoogleSignInExceptionCode.canceled) {
    return '';
  }
  if (error is FirebaseAuthException &&
      error.code == 'account-exists-with-different-credential') {
    return barberinLabel(
      'Αυτό το email χρησιμοποιεί ήδη email και κωδικό. Συνδέσου με αυτόν τον τρόπο.',
      'This email already uses email and password. Sign in with that method.',
    );
  }
  if (error is FirebaseAuthException && error.code == 'operation-not-allowed') {
    return barberinLabel(
      'Η σύνδεση με Google δεν είναι ενεργοποιημένη στο Firebase.',
      'Google sign-in is not enabled in Firebase.',
    );
  }
  if (error is FirebaseAuthException &&
      error.code == 'network-request-failed') {
    return barberinLabel(
      'Πρόβλημα σύνδεσης με το δίκτυο.',
      'Network connection failed.',
    );
  }
  return barberinLabel(
    'Δεν ήταν δυνατή η σύνδεση με Google.',
    'Google sign-in was not completed.',
  );
}

String _barberinAppleErrorMessage(Object error) {
  if (error is SignInWithAppleAuthorizationException &&
      error.code == AuthorizationErrorCode.canceled) {
    return '';
  }
  if (error is FirebaseAuthException &&
      error.code == 'account-exists-with-different-credential') {
    return barberinLabel(
      'Αυτό το email χρησιμοποιεί ήδη email και κωδικό. Συνδέσου πρώτα με αυτόν τον τρόπο.',
      'This email already uses email and password. Sign in with that method first.',
    );
  }
  if (error is FirebaseAuthException &&
      error.code == 'apple-existing-account') {
    return barberinLabel(
      'Συνδέσου πρώτα με το υπάρχον email και κωδικό για να συνδέσεις το Apple ID.',
      'Sign in with the existing email and password first to connect Apple.',
    );
  }
  return barberinLabel(
    'Δεν ήταν δυνατή η σύνδεση με Apple.',
    'Apple sign-in was not completed.',
  );
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.onLoginTap,
    required this.onRegisterTap,
    required this.onJoinTap,
  });

  final VoidCallback onLoginTap;
  final VoidCallback onRegisterTap;
  final VoidCallback onJoinTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 42),
          child: const BrandWordmark(width: 292),
        ),
        Column(
          children: [
            PrimaryButton(
              label: '\u03a3\u03cd\u03bd\u03b4\u03b5\u03c3\u03b7',
              onPressed: onLoginTap,
            ),
            const SizedBox(height: 12),
            SecondaryButton(
              label: '\u0395\u03b3\u03b3\u03c1\u03b1\u03c6\u03ae',
              onPressed: onRegisterTap,
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: onJoinTap,
              style: TextButton.styleFrom(foregroundColor: scheme.primary),
              child: Text(
                barberinLabel(
                  '\u0391\u03c0\u03ac\u03bd\u03c4\u03b7\u03c3\u03b7 \u03c3\u03b5 \u03c0\u03c1\u03cc\u03c3\u03ba\u03bb\u03b7\u03c3\u03b7 \u03ba\u03b1\u03c4\u03b1\u03c3\u03c4\u03ae\u03bc\u03b1\u03c4\u03bf\u03c2',
                  'Reply to a shop invitation',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.onBack,
    required this.onLogin,
    required this.onRegisterTap,
    required this.onJoinTap,
  });
  final VoidCallback onBack;
  final VoidCallback onLogin;
  final VoidCallback onRegisterTap;
  final VoidCallback onJoinTap;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authRepository = AuthRepository();
  bool _isSubmitting = false;
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u03a3\u03c5\u03bc\u03c0\u03bb\u03ae\u03c1\u03c9\u03c3\u03b5 \u03c4\u03bf \u03b7\u03bb\u03b5\u03ba\u03c4\u03c1\u03bf\u03bd\u03b9\u03ba\u03cc \u03c4\u03b1\u03c7\u03c5\u03b4\u03c1\u03bf\u03bc\u03b5\u03af\u03bf \u03ba\u03b1\u03b9 \u03c4\u03bf\u03bd \u03ba\u03c9\u03b4\u03b9\u03ba\u03cc.',
          ),
        ),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await _authRepository.signIn(email: email, password: password);
      if (!mounted) return;
      widget.onLogin();
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_firebaseAuthMessage(error))));
    } catch (error) {
      if (!mounted) return;
      debugPrint('Barberin email/password auth error: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u0397 \u03c3\u03cd\u03bd\u03b4\u03b5\u03c3\u03b7 \u03b1\u03c0\u03ad\u03c4\u03c5\u03c7\u03b5. \u0388\u03bb\u03b5\u03b3\u03be\u03b5 \u03c4\u03bf \u03b4\u03af\u03ba\u03c4\u03c5\u03bf \u03ba\u03b1\u03b9 \u03b4\u03bf Firebase configuration.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _submitWithGoogle() async {
    setState(() => _isSubmitting = true);
    try {
      await _barberinSignInWithGoogleAndRecovery(context);
      if (!mounted) return;
      widget.onLogin();
    } on _BarberinGoogleRecoveryCanceled {
      return;
    } on GoogleSignInException catch (error) {
      final message = _barberinGoogleErrorMessage(error);
      if (message.isNotEmpty && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } on FirebaseAuthException catch (error) {
      final message = _barberinGoogleErrorMessage(error);
      if (message.isNotEmpty && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      final message = _barberinGoogleErrorMessage(error);
      if (message.isNotEmpty && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _submitWithApple() async {
    setState(() => _isSubmitting = true);
    try {
      await _barberinSignInWithAppleAndRecovery(context);
      if (!mounted) return;
      widget.onLogin();
    } on _BarberinAppleRecoveryCanceled {
      return;
    } on SignInWithAppleException catch (error) {
      final message = _barberinAppleErrorMessage(error);
      if (message.isNotEmpty && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } on FirebaseAuthException catch (error) {
      final message = _barberinAppleErrorMessage(error);
      if (message.isNotEmpty && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      final message = _barberinAppleErrorMessage(error);
      if (message.isNotEmpty && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _sendPasswordReset() async {
    final dialogController = TextEditingController(
      text: _emailController.text.trim(),
    );
    final email = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Text(
            '\u0391\u03bd\u03ac\u03ba\u03c4\u03b7\u03c3\u03b7 \u03ba\u03c9\u03b4\u03b9\u03ba\u03bf\u03cd',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          content: TextField(
            controller: dialogController,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            decoration: InputDecoration(
              labelText: barberinTranslate('Ηλεκτρονικό ταχυδρομείο'),
              labelStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                '\u0386\u03ba\u03c5\u03c1\u03bf',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(dialogController.text.trim()),
              child: Text(
                '\u0391\u03c0\u03bf\u03c3\u03c4\u03bf\u03bb\u03ae',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          ],
        );
      },
    );
    dialogController.dispose();
    if (!mounted || email == null) return;
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u03a3\u03c5\u03bc\u03c0\u03bb\u03ae\u03c1\u03c9\u03c3\u03b5 \u03c4\u03bf \u03b7\u03bb\u03b5\u03ba\u03c4\u03c1\u03bf\u03bd\u03b9\u03ba\u03cc \u03c4\u03b1\u03c7\u03c5\u03b4\u03c1\u03bf\u03bc\u03b5\u03af\u03bf \u03b3\u03b9\u03b1 \u03b1\u03bd\u03ac\u03ba\u03c4\u03b7\u03c3\u03b7 \u03ba\u03c9\u03b4\u03b9\u03ba\u03bf\u03cd.',
          ),
        ),
      );
      return;
    }
    try {
      await _authRepository.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u03a3\u03c4\u03ac\u03bb\u03b8\u03b7\u03ba\u03b5 \u03bc\u03ae\u03bd\u03c5\u03bc\u03b1 \u03b1\u03bd\u03ac\u03ba\u03c4\u03b7\u03c3\u03b7\u03c2 \u03ba\u03c9\u03b4\u03b9\u03ba\u03bf\u03cd \u03c3\u03c4\u03bf \u03b7\u03bb\u03b5\u03ba\u03c4\u03c1\u03bf\u03bd\u03b9\u03ba\u03cc \u03c4\u03b1\u03c7\u03c5\u03b4\u03c1\u03bf\u03bc\u03b5\u03af\u03bf.',
          ),
        ),
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_firebaseAuthMessage(error))));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u0394\u03b5\u03bd \u03ae\u03c4\u03b1\u03bd \u03b4\u03c5\u03bd\u03b1\u03c4\u03ae \u03b7 \u03b1\u03c0\u03bf\u03c3\u03c4\u03bf\u03bb\u03ae \u03bc\u03b7\u03bd\u03cd\u03bc\u03b1\u03c4\u03bf\u03c2 \u03b1\u03bd\u03ac\u03ba\u03c4\u03b7\u03c3\u03b7\u03c2.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AuthTopBar(onBack: widget.onBack),
        const SizedBox(height: 18),
        const Text(
          '\u03a3\u03cd\u03bd\u03b4\u03b5\u03c3\u03b7',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Column(
          children: [
            AppTextField(
              label: 'Ηλεκτρονικό ταχυδρομείο',
              controller: _emailController,
              icon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
              large: true,
              fieldHeight: 50,
            ),
            const SizedBox(height: 8),
            AppTextField(
              label: '\u039a\u03c9\u03b4\u03b9\u03ba\u03cc\u03c2',
              controller: _passwordController,
              icon: Icons.lock_outline_rounded,
              obscureText: true,
              large: true,
              fieldHeight: 50,
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isSubmitting ? null : _sendPasswordReset,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  '\u039e\u03ad\u03c7\u03b1\u03c3\u03b5\u03c2 \u03c4\u03bf\u03bd \u03ba\u03c9\u03b4\u03b9\u03ba\u03cc \u03c3\u03bf\u03c5;',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_isSubmitting)
          Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Center(
              child: CircularProgressIndicator(color: scheme.primary),
            ),
          ),
        PrimaryButton(
          label: '\u0395\u03af\u03c3\u03bf\u03b4\u03bf\u03c2',
          onPressed: _isSubmitting ? () {} : _submit,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                barberinLabel('ή', 'or'),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _isSubmitting ? null : _submitWithGoogle,
            icon: const _BarberinGoogleLogo(),
            label: Text(
              barberinLabel('Συνέχεια με Google', 'Continue with Google'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.onSurface,
              side: BorderSide(color: scheme.outline),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
        if (_barberinAppleSignInAvailable) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _isSubmitting ? null : _submitWithApple,
              icon: const Icon(Icons.apple, size: 22),
              label: Text(
                barberinLabel('Συνέχεια με Apple', 'Continue with Apple'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.onSurface,
                side: BorderSide(color: scheme.outline),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        SecondaryButton(
          label: '\u0395\u03b3\u03b3\u03c1\u03b1\u03c6\u03ae',
          onPressed: widget.onRegisterTap,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: widget.onJoinTap,
          child: Text(
            barberinLabel(
              '\u0391\u03c0\u03ac\u03bd\u03c4\u03b7\u03c3\u03b7 \u03c3\u03b5 \u03c0\u03c1\u03cc\u03c3\u03ba\u03bb\u03b7\u03c3\u03b7 \u03ba\u03b1\u03c4\u03b1\u03c3\u03c4\u03ae\u03bc\u03b1\u03c4\u03bf\u03c2',
              'Reply to a shop invitation',
            ),
          ),
        ),
      ],
    );
  }
}

class JoinCrewScreen extends StatefulWidget {
  const JoinCrewScreen({
    super.key,
    required this.onBack,
    required this.onComplete,
  });

  final VoidCallback onBack;
  final VoidCallback onComplete;

  @override
  State<JoinCrewScreen> createState() => _JoinCrewScreenState();
}

class _JoinCrewScreenState extends State<JoinCrewScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _invitationRepository = CrewInvitationRepository();
  final _authRepository = AuthRepository();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<CrewInvitePreview?> _chooseInvite(
    List<CrewInvitePreview> invites,
  ) async {
    if (invites.isEmpty) {
      return null;
    }
    if (invites.length == 1) {
      return invites.first;
    }
    if (!mounted) {
      return null;
    }

    return showModalBottomSheet<CrewInvitePreview>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '\u0395\u03c0\u03af\u03bb\u03b5\u03be\u03b5 \u03ba\u03b1\u03c4\u03ac\u03c3\u03c4\u03b7\u03bc\u03b1',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '\u0392\u03c1\u03ad\u03b8\u03b7\u03ba\u03b1\u03bd \u03c0\u03bf\u03bb\u03bb\u03b1\u03c0\u03bb\u03ad\u03c2 \u03c0\u03c1\u03bf\u03c3\u03ba\u03bb\u03ae\u03c3\u03b5\u03b9\u03c2 \u03bc\u03b5 \u03b1\u03c5\u03c4\u03cc \u03c4\u03bf email. \u0394\u03b9\u03ac\u03bb\u03b5\u03be\u03b5 \u03c4\u03bf \u03ba\u03b1\u03c4\u03ac\u03c3\u03c4\u03b7\u03bc\u03b1 \u03c3\u03c4\u03bf \u03bf\u03c0\u03bf\u03af\u03bf \u03b8\u03ad\u03bb\u03b5\u03b9\u03c2 \u03bd\u03b1 \u03c5\u03c0\u03b7\u03c1\u03b5\u03c4\u03ae\u03c3\u03b5\u03b9\u03c2.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: invites.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final invite = invites[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          title: Text(
                            invite.shopName.isEmpty
                                ? '\u039a\u03b1\u03c4\u03ac\u03c3\u03c4\u03b7\u03bc\u03b1'
                                : invite.shopName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            [
                              if (invite.ownerName.isNotEmpty) invite.ownerName,
                              if (invite.role.isNotEmpty) invite.role,
                            ].join(' \u2022 '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: scheme.onSurfaceVariant,
                          ),
                          onTap: () => Navigator.of(sheetContext).pop(invite),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    final email = normalizeEmail(_emailController.text);
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Συμπλήρωσε το ηλεκτρονικό ταχυδρομείο και τον κωδικό.',
          ),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      List<CrewInvitePreview> invites;
      try {
        invites = await _invitationRepository.lookupInvites(email);
      } catch (_) {
        // An invite is no longer returned after it has been activated. In
        // that case, authenticate the existing account and resolve its live
        // crew membership instead of showing a misleading "not found" error.
        await _authRepository.signIn(email: email, password: password);
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          throw Exception('crew-membership-not-found');
        }
        try {
          await resolveBarberoSessionForCurrentUser(
            user,
            signOutOnFailure: false,
          );
        } catch (_) {
          await FirebaseAuth.instance.signOut();
          throw Exception('crew-membership-not-found');
        }
        final session = currentBarberoSession.value;
        if (session == null || session.isOwner) {
          await FirebaseAuth.instance.signOut();
          throw Exception('crew-membership-not-found');
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '\u03a3\u03c5\u03bd\u03b4\u03ad\u03b8\u03b7\u03ba\u03b5\u03c2 \u03ae\u03b4\u03b7 \u03c3\u03c4\u03bf \u03ba\u03b1\u03c4\u03ac\u03c3\u03c4\u03b7\u03bc\u03b1 ${session.shopName}.',
            ),
          ),
        );
        widget.onComplete();
        return;
      }
      final invite = await _chooseInvite(invites);
      if (invite == null) {
        return;
      }
      try {
        await _authRepository.register(email: email, password: password);
      } on FirebaseAuthException catch (error) {
        if (error.code == 'email-already-in-use') {
          await _authRepository.signIn(email: email, password: password);
        } else {
          rethrow;
        }
      }
      await _invitationRepository.activateInvite(
        shopId: invite.shopId,
        crewId: invite.crewId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Συνδέθηκες στο κατάστημα ${invite.shopName}.')),
      );
      widget.onComplete();
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_firebaseAuthMessage(error))));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Δεν βρέθηκε πρόσκληση ομάδας για αυτό το ηλεκτρονικό ταχυδρομείο.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AuthTopBar(onBack: widget.onBack),
        const SizedBox(height: 30),
        Text(
          barberinLabel(
            '\u0391\u03c0\u03ac\u03bd\u03c4\u03b7\u03c3\u03b7 \u03c3\u03b5 \u03c0\u03c1\u03cc\u03c3\u03ba\u03bb\u03b7\u03c3\u03b7 \u03ba\u03b1\u03c4\u03b1\u03c3\u03c4\u03ae\u03bc\u03b1\u03c4\u03bf\u03c2',
            'Reply to a shop invitation',
          ),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          barberinLabel(
            '\u03a7\u03c1\u03b7\u03c3\u03b9\u03bc\u03bf\u03c0\u03bf\u03af\u03b7\u03c3\u03b5 \u03c4\u03bf email \u03c0\u03bf\u03c5 \u03ad\u03bb\u03b1\u03b2\u03b5 \u03c4\u03b7\u03bd \u03c0\u03c1\u03cc\u03c3\u03ba\u03bb\u03b7\u03c3\u03b7 \u03b3\u03b9\u03b1 \u03bd\u03b1 \u03c3\u03c5\u03bd\u03b4\u03b5\u03b8\u03b5\u03af\u03c2 \u03c3\u03c4\u03bf \u03ba\u03b1\u03c4\u03ac\u03c3\u03c4\u03b7\u03bc\u03b1.',
            'Use the email address that received the invitation to join the shop.',
          ),
        ),
        const SizedBox(height: 18),
        Column(
          children: [
            AppTextField(
              label: 'Ηλεκτρονικό ταχυδρομείο',
              controller: _emailController,
              icon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
              large: true,
              fieldHeight: 58,
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: '\u039a\u03c9\u03b4\u03b9\u03ba\u03cc\u03c2',
              controller: _passwordController,
              icon: Icons.lock_outline_rounded,
              obscureText: true,
              large: true,
              fieldHeight: 58,
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (_isSubmitting)
          Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Center(
              child: CircularProgressIndicator(color: scheme.primary),
            ),
          ),
        PrimaryButton(
          label: barberinLabel(
            '\u0391\u03c0\u03bf\u03b4\u03bf\u03c7\u03ae \u03c0\u03c1\u03cc\u03c3\u03ba\u03bb\u03b7\u03c3\u03b7\u03c2',
            'Accept invitation',
          ),
          onPressed: _isSubmitting ? () {} : _submit,
        ),
      ],
    );
  }
}

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({
    super.key,
    required this.onBack,
    required this.onComplete,
  });

  final VoidCallback onBack;
  final void Function(String shopId, String ownerName) onComplete;

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _ownerNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _shopNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _authRepository = AuthRepository();
  final ShopRegistrationRepository _repository = ShopRegistrationRepository();
  bool _isSubmitting = false;
  bool _isSocialRegistration = false;
  int _step = 0;

  @override
  void dispose() {
    _ownerNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _shopNameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  void _goNext() {
    final ownerName = _ownerNameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (ownerName.isEmpty ||
        phone.isEmpty ||
        email.isEmpty ||
        (!_isSocialRegistration && password.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u03a3\u03c5\u03bc\u03c0\u03bb\u03ae\u03c1\u03c9\u03c3\u03b5 \u03cc\u03bb\u03b1 \u03c4\u03b1 \u03c0\u03b5\u03b4\u03af\u03b1.',
          ),
        ),
      );
      return;
    }

    if (!_isSocialRegistration && password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            barberinLabel(
              '\u039f\u03b9 \u03ba\u03c9\u03b4\u03b9\u03ba\u03bf\u03af \u03b4\u03b5\u03bd \u03c4\u03b1\u03b9\u03c1\u03b9\u03ac\u03b6\u03bf\u03c5\u03bd.',
              'Passwords do not match.',
            ),
          ),
        ),
      );
      return;
    }

    setState(() => _step = 1);
  }

  Future<void> _startGoogleRegistration() async {
    setState(() => _isSubmitting = true);
    try {
      final credential = await _barberinSignInWithGoogleAndRecovery(context);
      final user = credential.user ?? FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'google-registration-user-missing',
          message: 'The Google user was not found.',
        );
      }
      if (_emailController.text.trim().isEmpty && user.email != null) {
        _emailController.text = user.email!;
      }
      if (_ownerNameController.text.trim().isEmpty &&
          user.displayName != null) {
        _ownerNameController.text = user.displayName!;
      }
      if (mounted) {
        setState(() => _isSocialRegistration = true);
      }
    } on _BarberinGoogleRecoveryCanceled {
      return;
    } on GoogleSignInException catch (error) {
      final message = _barberinGoogleErrorMessage(error);
      if (message.isNotEmpty && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } on FirebaseAuthException catch (error) {
      final message = _barberinGoogleErrorMessage(error);
      if (message.isNotEmpty && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      final message = _barberinGoogleErrorMessage(error);
      if (message.isNotEmpty && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _startAppleRegistration() async {
    setState(() => _isSubmitting = true);
    try {
      final credential = await _barberinSignInWithAppleAndRecovery(context);
      final user = credential.user ?? FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'apple-registration-user-missing',
          message: 'The Apple user was not found.',
        );
      }
      if (_emailController.text.trim().isEmpty && user.email != null) {
        _emailController.text = user.email!;
      }
      if (_ownerNameController.text.trim().isEmpty &&
          user.displayName != null) {
        _ownerNameController.text = user.displayName!;
      }
      if (mounted) {
        setState(() => _isSocialRegistration = true);
      }
    } on _BarberinAppleRecoveryCanceled {
      return;
    } on SignInWithAppleException catch (error) {
      final message = _barberinAppleErrorMessage(error);
      if (message.isNotEmpty && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } on FirebaseAuthException catch (error) {
      final message = _barberinAppleErrorMessage(error);
      if (message.isNotEmpty && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      final message = _barberinAppleErrorMessage(error);
      if (message.isNotEmpty && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _submit() async {
    final ownerName = _ownerNameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final shopName = _shopNameController.text.trim();
    final address = _addressController.text.trim();
    final city = _cityController.text.trim();

    if (ownerName.isEmpty ||
        phone.isEmpty ||
        email.isEmpty ||
        (!_isSocialRegistration &&
            (password.isEmpty || confirmPassword.isEmpty)) ||
        shopName.isEmpty ||
        address.isEmpty ||
        city.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u03a3\u03c5\u03bc\u03c0\u03bb\u03ae\u03c1\u03c9\u03c3\u03b5 \u03cc\u03bb\u03b1 \u03c4\u03b1 \u03c0\u03b5\u03b4\u03af\u03b1.',
          ),
        ),
      );
      return;
    }

    if (!_isSocialRegistration && password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            barberinLabel(
              '\u039f\u03b9 \u03ba\u03c9\u03b4\u03b9\u03ba\u03bf\u03af \u03b4\u03b5\u03bd \u03c4\u03b1\u03b9\u03c1\u03b9\u03ac\u03b6\u03bf\u03c5\u03bd.',
              'Passwords do not match.',
            ),
          ),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    barberinRegistrationInProgress.value = true;
    try {
      if (!_isSocialRegistration) {
        try {
          await _authRepository.register(email: email, password: password);
        } on FirebaseAuthException catch (error) {
          final currentUser = FirebaseAuth.instance.currentUser;
          final sameAuthenticatedEmail =
              currentUser?.email?.trim().toLowerCase() == email.toLowerCase();
          if (error.code != 'email-already-in-use') {
            rethrow;
          }
          if (!sameAuthenticatedEmail) {
            await _authRepository.signIn(email: email, password: password);
          }
        }
      }
      final shopId = await _repository.registerShop(
        ShopRegistrationData(
          shopId: '',
          ownerName: ownerName,
          ownerPhone: phone,
          ownerEmail: email,
          shopName: shopName,
          address: address,
          city: city,
        ),
      );
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('registration-auth-missing');
      }
      await resolveBarberoSessionForCurrentUser(
        user,
        preferredShopId: shopId,
        signOutOnFailure: false,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u0397 \u03b5\u03b3\u03b3\u03c1\u03b1\u03c6\u03ae \u03bf\u03bb\u03bf\u03ba\u03bb\u03b7\u03c1\u03ce\u03b8\u03b7\u03ba\u03b5 \u03b5\u03c0\u03b9\u03c4\u03c5\u03c7\u03ce\u03c2.',
          ),
        ),
      );
      barberinRegistrationInProgress.value = false;
      widget.onComplete(shopId, ownerName);
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_firebaseAuthMessage(error))));
    } catch (_) {
      await FirebaseAuth.instance.signOut();
      _isSocialRegistration = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u0391\u03c0\u03bf\u03c4\u03c5\u03c7\u03af\u03b1 \u03b5\u03b3\u03b3\u03c1\u03b1\u03c6\u03ae\u03c2. \u0394\u03bf\u03ba\u03af\u03bc\u03b1\u03c3\u03b5 \u03be\u03b1\u03bd\u03ac.',
          ),
        ),
      );
    } finally {
      barberinRegistrationInProgress.value = false;
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AuthTopBar(onBack: widget.onBack),
        const SizedBox(height: 18),
        const Text(
          '\u0395\u03b3\u03b3\u03c1\u03b1\u03c6\u03ae',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_step == 0) ...[
              const SectionLabel(
                '\u0399\u03b4\u03b9\u03bf\u03ba\u03c4\u03ae\u03c4\u03b7\u03c2',
              ),
              const SizedBox(height: 8),
              AppTextField(
                label:
                    '\u039f\u03bd\u03bf\u03bc\u03b1\u03c4\u03b5\u03c0\u03ce\u03bd\u03c5\u03bc\u03bf',
                controller: _ownerNameController,
                icon: Icons.person_outline_rounded,
                large: true,
                fieldHeight: 50,
              ),
              const SizedBox(height: 8),
              AppTextField(
                label: '\u03a4\u03b7\u03bb\u03ad\u03c6\u03c9\u03bd\u03bf',
                controller: _phoneController,
                icon: Icons.call_outlined,
                keyboardType: TextInputType.phone,
                large: true,
                fieldHeight: 50,
              ),
              const SizedBox(height: 8),
              AppTextField(
                label: 'Ηλεκτρονικό ταχυδρομείο',
                controller: _emailController,
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                large: true,
                fieldHeight: 50,
              ),
              if (!_isSocialRegistration) ...[
                const SizedBox(height: 8),
                AppTextField(
                  label: '\u039a\u03c9\u03b4\u03b9\u03ba\u03cc\u03c2',
                  controller: _passwordController,
                  icon: Icons.lock_outline_rounded,
                  obscureText: true,
                  large: true,
                  fieldHeight: 50,
                ),
                const SizedBox(height: 8),
                AppTextField(
                  label: barberinLabel(
                    '\u0395\u03c0\u03b9\u03b2\u03b5\u03b2\u03b1\u03af\u03c9\u03c3\u03b7 \u03ba\u03c9\u03b4\u03b9\u03ba\u03bf\u03cd',
                    'Confirm password',
                  ),
                  controller: _confirmPasswordController,
                  icon: Icons.lock_reset_outlined,
                  obscureText: true,
                  large: true,
                  fieldHeight: 50,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        barberinLabel('\u03ae', 'or'),
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _isSubmitting ? null : _startGoogleRegistration,
                    icon: const _BarberinGoogleLogo(),
                    label: Text(
                      barberinLabel(
                        '\u0395\u03b3\u03b3\u03c1\u03b1\u03c6\u03ae \u03bc\u03b5 Google',
                        'Sign up with Google',
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.onSurface,
                      side: BorderSide(color: scheme.outline),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
                if (_barberinAppleSignInAvailable) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _isSubmitting ? null : _startAppleRegistration,
                      icon: const Icon(Icons.apple, size: 22),
                      label: Text(
                        barberinLabel('Εγγραφή με Apple', 'Sign up with Apple'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: scheme.onSurface,
                        side: BorderSide(color: scheme.outline),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ] else ...[
              const SectionLabel(
                '\u0395\u03c0\u03b9\u03c7\u03b5\u03af\u03c1\u03b7\u03c3\u03b7',
              ),
              const SizedBox(height: 8),
              AppTextField(
                label:
                    '\u0395\u03c0\u03c9\u03bd\u03c5\u03bc\u03af\u03b1 \u03b5\u03c0\u03b9\u03c7\u03b5\u03af\u03c1\u03b7\u03c3\u03b7\u03c2',
                controller: _shopNameController,
                icon: Icons.storefront_outlined,
                large: true,
                fieldHeight: 50,
              ),
              const SizedBox(height: 8),
              AppTextField(
                label: '\u0394\u03b9\u03b5\u03cd\u03b8\u03c5\u03bd\u03c3\u03b7',
                controller: _addressController,
                icon: Icons.location_on_outlined,
                large: true,
                fieldHeight: 50,
              ),
              const SizedBox(height: 8),
              AppTextField(
                label: '\u03a0\u03cc\u03bb\u03b7',
                controller: _cityController,
                icon: Icons.location_city_outlined,
                large: true,
                fieldHeight: 50,
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        if (_isSubmitting)
          Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Center(
              child: CircularProgressIndicator(color: scheme.primary),
            ),
          ),
        if (_step == 0)
          PrimaryButton(
            label: '\u03a3\u03c5\u03bd\u03ad\u03c7\u03b5\u03b9\u03b1',
            onPressed: _isSubmitting ? () {} : _goNext,
          )
        else ...[
          SecondaryButton(
            label: '\u03a0\u03af\u03c3\u03c9',
            onPressed: _isSubmitting ? () {} : () => setState(() => _step = 0),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label:
                '\u0394\u03b7\u03bc\u03b9\u03bf\u03c5\u03c1\u03b3\u03af\u03b1 \u03bb\u03bf\u03b3\u03b1\u03c1\u03b9\u03b1\u03c3\u03bc\u03bf\u03cd',
            onPressed: _isSubmitting ? () {} : _submit,
          ),
        ],
      ],
    );
  }
}

class OwnerPhotoScreen extends StatefulWidget {
  const OwnerPhotoScreen({
    super.key,
    required this.shopId,
    required this.ownerName,
    required this.onSkip,
    required this.onComplete,
  });

  final String shopId;
  final String ownerName;
  final VoidCallback onSkip;
  final VoidCallback onComplete;

  @override
  State<OwnerPhotoScreen> createState() => _OwnerPhotoScreenState();
}

class _OwnerPhotoScreenState extends State<OwnerPhotoScreen> {
  final ImagePicker _picker = ImagePicker();
  Uint8List? _previewBytes;
  bool _uploading = false;

  Future<void> _pickAndUpload(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1400,
    );
    if (file == null) {
      return;
    }

    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      if (mounted) {
        setState(() => _previewBytes = bytes);
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.uid != widget.shopId) {
        throw Exception('owner-auth-missing');
      }
      final idToken = await user.getIdToken();
      final response = await http.post(
        Uri.parse(
          'https://europe-west1-barbero-88d00.cloudfunctions.net/barberoUploadOwnerPhoto',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'idToken': idToken,
          'shopId': widget.shopId,
          'contentType': 'image/jpeg',
          'imageBase64': base64Encode(bytes),
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('owner-photo-upload-failed');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u0397 \u03c6\u03c9\u03c4\u03bf\u03b3\u03c1\u03b1\u03c6\u03af\u03b1 \u03b1\u03c0\u03bf\u03b8\u03b7\u03ba\u03b5\u03cd\u03c4\u03b7\u03ba\u03b5.',
          ),
        ),
      );
      widget.onComplete();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Προέκυψε σφάλμα κατά τη μεταφόρτωση της φωτογραφίας.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AuthTopBar(onBack: widget.onSkip),
        const SizedBox(height: 30),
        const Text(
          '\u03a6\u03c9\u03c4\u03bf\u03b3\u03c1\u03b1\u03c6\u03af\u03b1',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 18),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Πρόσθεσε φωτογραφία προφίλ.',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.ownerName,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
              ),
              const SizedBox(height: 24),
              Center(
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.outline, width: 1.5),
                    image: _previewBytes == null
                        ? null
                        : DecorationImage(
                            image: MemoryImage(_previewBytes!),
                            fit: BoxFit.cover,
                          ),
                  ),
                  child: _previewBytes == null
                      ? Icon(
                          Icons.person_rounded,
                          size: 72,
                          color: scheme.primary,
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        if (_uploading)
          Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Center(
              child: CircularProgressIndicator(color: scheme.primary),
            ),
          ),
        PrimaryButton(
          label: '\u039a\u0391\u039c\u0395\u03a1\u0391',
          onPressed: _uploading
              ? () {}
              : () => _pickAndUpload(ImageSource.camera),
        ),
        const SizedBox(height: 12),
        SecondaryButton(
          label: '\u03a3\u03a5\u039b\u039b\u039f\u0393\u0397',
          onPressed: _uploading
              ? () {}
              : () => _pickAndUpload(ImageSource.gallery),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _uploading ? null : widget.onSkip,
            child: Text(
              '\u03a0\u0391\u03a1\u0391\u039b\u0395\u0399\u03a8\u0397',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
