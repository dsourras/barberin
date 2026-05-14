part of 'main.dart';

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
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.26,
              child: Image.asset(
                'assets/images/welcome_background.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              children: [
                const SizedBox(height: 28),
                Container(
                  width: 320,
                  height: 320,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(42),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 28,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(42),
                    child: Image.asset(
                      'assets/images/welcome_emblem.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ],
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
                  child: const Text('Join existing shop'),
                ),
              ],
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
            '\u03a3\u03c5\u03bc\u03c0\u03bb\u03ae\u03c1\u03c9\u03c3\u03b5 email \u03ba\u03b1\u03b9 \u03ba\u03c9\u03b4\u03b9\u03ba\u03cc.',
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
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u03a4\u03bf Firebase Auth \u03b4\u03b5\u03bd \u03b5\u03af\u03bd\u03b1\u03b9 \u03ad\u03c4\u03bf\u03b9\u03bc\u03bf \u03b1\u03ba\u03cc\u03bc\u03b1. \u0392\u03ac\u03bb\u03b5 \u03c4\u03b1 config files.',
          ),
        ),
      );
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
          backgroundColor: const Color(0xFF171717),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            '\u0391\u03bd\u03ac\u03ba\u03c4\u03b7\u03c3\u03b7 \u03ba\u03c9\u03b4\u03b9\u03ba\u03bf\u03cd',
            style: TextStyle(color: Color(0xFFF4E7CE)),
          ),
          content: TextField(
            controller: dialogController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Color(0xFFF4E7CE)),
            decoration: InputDecoration(
              labelText: 'Email',
              labelStyle: const TextStyle(color: Color(0xFFBFA37A)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0x33D1A45C)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFD1A45C)),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                '\u0386\u03ba\u03c5\u03c1\u03bf',
                style: TextStyle(color: Color(0xFFBFA37A)),
              ),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(dialogController.text.trim()),
              child: const Text(
                '\u0391\u03c0\u03bf\u03c3\u03c4\u03bf\u03bb\u03ae',
                style: TextStyle(color: Color(0xFFD1A45C)),
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
            '\u03a3\u03c5\u03bc\u03c0\u03bb\u03ae\u03c1\u03c9\u03c3\u03b5 \u03c4\u03bf email \u03b3\u03b9\u03b1 \u03b1\u03bd\u03ac\u03ba\u03c4\u03b7\u03c3\u03b7 \u03ba\u03c9\u03b4\u03b9\u03ba\u03bf\u03cd.',
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
            '\u03a3\u03c4\u03ac\u03bb\u03b8\u03b7\u03ba\u03b5 email \u03b1\u03bd\u03ac\u03ba\u03c4\u03b7\u03c3\u03b7\u03c2 \u03ba\u03c9\u03b4\u03b9\u03ba\u03bf\u03cd.',
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
            '\u0394\u03b5\u03bd \u03ae\u03c4\u03b1\u03bd \u03b4\u03c5\u03bd\u03b1\u03c4\u03ae \u03b7 \u03b1\u03c0\u03bf\u03c3\u03c4\u03bf\u03bb\u03ae email \u03b1\u03bd\u03ac\u03ba\u03c4\u03b7\u03c3\u03b7\u03c2.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AuthTopBar(onBack: widget.onBack),
        const SizedBox(height: 30),
        const Text(
          '\u03a3\u03cd\u03bd\u03b4\u03b5\u03c3\u03b7',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 18),
        Panel(
          child: Column(
            children: [
              AppTextField(
                label: 'Email',
                controller: _emailController,
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: '\u039a\u03c9\u03b4\u03b9\u03ba\u03cc\u03c2',
                controller: _passwordController,
                icon: Icons.lock_outline_rounded,
                obscureText: true,
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isSubmitting ? null : _sendPasswordReset,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFD1A45C),
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
        ),
        const SizedBox(height: 24),
        if (_isSubmitting)
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFFD1A45C)),
            ),
          ),
        PrimaryButton(
          label: '\u0395\u03af\u03c3\u03bf\u03b4\u03bf\u03c2',
          onPressed: _isSubmitting ? () {} : _submit,
        ),
        const SizedBox(height: 12),
        SecondaryButton(
          label: '\u0395\u03b3\u03b3\u03c1\u03b1\u03c6\u03ae',
          onPressed: widget.onRegisterTap,
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: widget.onJoinTap,
          child: const Text('Join existing shop'),
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

  Future<void> _submit() async {
    final email = normalizeEmail(_emailController.text);
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill in email and password.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final invite = await _invitationRepository.lookupInvite(email);
      try {
        await _authRepository.register(email: email, password: password);
      } on FirebaseAuthException catch (error) {
        if (error.code == 'email-already-in-use') {
          await _authRepository.signIn(email: email, password: password);
        } else {
          rethrow;
        }
      }
      await _invitationRepository.activateInvite(invite.shopId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Joined ${invite.shopName}.')),
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
          content: Text('No matching crew invitation was found for this email.'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AuthTopBar(onBack: widget.onBack),
        const SizedBox(height: 30),
        const Text(
          'Join Existing Shop',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        const Text(
          'Use the same email the owner added in Barbers.',
          style: TextStyle(color: Color(0xFFBFA37A), fontSize: 13),
        ),
        const SizedBox(height: 18),
        Panel(
          child: Column(
            children: [
              AppTextField(
                label: 'Email',
                controller: _emailController,
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: '\u039a\u03c9\u03b4\u03b9\u03ba\u03cc\u03c2',
                controller: _passwordController,
                icon: Icons.lock_outline_rounded,
                obscureText: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (_isSubmitting)
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFFD1A45C)),
            ),
          ),
        PrimaryButton(
          label: 'Join Shop',
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
  final _shopNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _authRepository = AuthRepository();
  final ShopRegistrationRepository _repository = ShopRegistrationRepository();
  bool _isSubmitting = false;
  int _step = 0;

  @override
  void dispose() {
    _ownerNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
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

    if (ownerName.isEmpty ||
        phone.isEmpty ||
        email.isEmpty ||
        password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u03a3\u03c5\u03bc\u03c0\u03bb\u03ae\u03c1\u03c9\u03c3\u03b5 \u03cc\u03bb\u03b1 \u03c4\u03b1 \u03c0\u03b5\u03b4\u03af\u03b1.',
          ),
        ),
      );
      return;
    }

    setState(() => _step = 1);
  }

  Future<void> _submit() async {
    final ownerName = _ownerNameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final shopName = _shopNameController.text.trim();
    final address = _addressController.text.trim();
    final city = _cityController.text.trim();

    if (ownerName.isEmpty ||
        phone.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
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

    setState(() => _isSubmitting = true);
    try {
      final credential = await _authRepository.register(
        email: email,
        password: password,
      );
      await _repository.registerShop(
        ShopRegistrationData(
          shopId: credential.user!.uid,
          ownerName: ownerName,
          ownerPhone: phone,
          ownerEmail: email,
          shopName: shopName,
          address: '$address, $city',
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u0397 \u03b5\u03b3\u03b3\u03c1\u03b1\u03c6\u03ae \u03bf\u03bb\u03bf\u03ba\u03bb\u03b7\u03c1\u03ce\u03b8\u03b7\u03ba\u03b5 \u03b5\u03c0\u03b9\u03c4\u03c5\u03c7\u03ce\u03c2.',
          ),
        ),
      );
      widget.onComplete(credential.user!.uid, ownerName);
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
            '\u0391\u03c0\u03bf\u03c4\u03c5\u03c7\u03af\u03b1 \u03b5\u03b3\u03b3\u03c1\u03b1\u03c6\u03ae\u03c2. \u0394\u03bf\u03ba\u03af\u03bc\u03b1\u03c3\u03b5 \u03be\u03b1\u03bd\u03ac.',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AuthTopBar(onBack: widget.onBack),
        const SizedBox(height: 30),
        const Text(
          '\u0395\u03b3\u03b3\u03c1\u03b1\u03c6\u03ae',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 18),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_step == 0) ...[
                const SectionLabel(
                  '\u0399\u03b4\u03b9\u03bf\u03ba\u03c4\u03ae\u03c4\u03b7\u03c2',
                ),
                const SizedBox(height: 14),
                AppTextField(
                  label:
                      '\u039f\u03bd\u03bf\u03bc\u03b1\u03c4\u03b5\u03c0\u03ce\u03bd\u03c5\u03bc\u03bf',
                  controller: _ownerNameController,
                  icon: Icons.person_outline_rounded,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: '\u03a4\u03b7\u03bb\u03ad\u03c6\u03c9\u03bd\u03bf',
                  controller: _phoneController,
                  icon: Icons.call_outlined,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'Email',
                  controller: _emailController,
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: '\u039a\u03c9\u03b4\u03b9\u03ba\u03cc\u03c2',
                  controller: _passwordController,
                  icon: Icons.lock_outline_rounded,
                  obscureText: true,
                ),
              ] else ...[
                const SectionLabel(
                  '\u0395\u03c0\u03b9\u03c7\u03b5\u03af\u03c1\u03b7\u03c3\u03b7',
                ),
                const SizedBox(height: 14),
                AppTextField(
                  label:
                      '\u0395\u03c0\u03c9\u03bd\u03c5\u03bc\u03af\u03b1 \u03b5\u03c0\u03b9\u03c7\u03b5\u03af\u03c1\u03b7\u03c3\u03b7\u03c2',
                  controller: _shopNameController,
                  icon: Icons.storefront_outlined,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label:
                      '\u0394\u03b9\u03b5\u03cd\u03b8\u03c5\u03bd\u03c3\u03b7',
                  controller: _addressController,
                  icon: Icons.location_on_outlined,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: '\u03a0\u03cc\u03bb\u03b7',
                  controller: _cityController,
                  icon: Icons.location_city_outlined,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (_isSubmitting)
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFFD1A45C)),
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
          content: Text(
            '\u03a0\u03c1\u03bf\u03ad\u03ba\u03c5\u03c8\u03b5 \u03c3\u03c6\u03ac\u03bb\u03bc\u03b1 \u03ba\u03b1\u03c4\u03ac \u03c4\u03bf upload \u03c4\u03b7\u03c2 \u03c6\u03c9\u03c4\u03bf\u03b3\u03c1\u03b1\u03c6\u03af\u03b1\u03c2.',
          ),
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
              const Text(
                '\u03a0\u03c1\u03cc\u03c3\u03b8\u03b5\u03c3\u03b5 selfie \u03ae \u03c6\u03c9\u03c4\u03bf\u03b3\u03c1\u03b1\u03c6\u03af\u03b1 \u03c0\u03c1\u03bf\u03c6\u03af\u03bb.',
                style: TextStyle(
                  color: Color(0xFFF0E5D1),
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.ownerName,
                style: const TextStyle(color: Color(0xFFB8AE9E), fontSize: 14),
              ),
              const SizedBox(height: 24),
              Center(
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF3A3127),
                      width: 1.5,
                    ),
                    image: _previewBytes == null
                        ? null
                        : DecorationImage(
                            image: MemoryImage(_previewBytes!),
                            fit: BoxFit.cover,
                          ),
                  ),
                  child: _previewBytes == null
                      ? const Icon(
                          Icons.person_rounded,
                          size: 72,
                          color: Color(0xFFD1A45C),
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        if (_uploading)
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFFD1A45C)),
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
            child: const Text(
              '\u03a0\u0391\u03a1\u0391\u039b\u0395\u0399\u03a8\u0397',
              style: TextStyle(
                color: Color(0xFFB8AE9E),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
