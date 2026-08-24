part of 'main.dart';

class CrewMember {
  const CrewMember({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.email,
    required this.role,
    required this.notes,
    required this.specialties,
    required this.photoUrl,
    this.isOwnerBarber = false,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String phone;
  final String email;
  final String role;
  final String notes;
  final List<String> specialties;
  final String photoUrl;
  final bool isOwnerBarber;

  String get fullName => '$firstName $lastName'.trim();

  factory CrewMember.fromJson(String id, Map<String, dynamic> json) {
    final firstName = '${json['firstName'] ?? ''}'.trim();
    final lastName = '${json['lastName'] ?? ''}'.trim();
    final fullName = '${json['fullName'] ?? json['name'] ?? ''}'.trim();
    final nameParts = fullName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    return CrewMember(
      id: id,
      firstName: firstName.isNotEmpty
          ? firstName
          : (nameParts.isNotEmpty ? nameParts.first : ''),
      lastName: lastName.isNotEmpty
          ? lastName
          : (nameParts.length > 1 ? nameParts.sublist(1).join(' ') : ''),
      phone: '${json['phone'] ?? ''}'.trim(),
      email: '${json['email'] ?? ''}'.trim(),
      role: '${json['role'] ?? 'Barber'}'.trim(),
      notes: '${json['notes'] ?? ''}'.trim(),
      specialties: _crewSpecialtiesFromRaw(json['specialties']),
      photoUrl: '${json['photoUrl'] ?? ''}'.trim(),
      isOwnerBarber: json['isOwnerBarber'] == true,
    );
  }
}

class CrewMemberRegistrationData {
  const CrewMemberRegistrationData({
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.email,
    required this.role,
    required this.notes,
    required this.specialties,
  });

  final String firstName;
  final String lastName;
  final String phone;
  final String email;
  final String role;
  final String notes;
  final List<String> specialties;
}

const List<_CrewSpecialtyOption> _crewSpecialtyOptions = <_CrewSpecialtyOption>[
  _CrewSpecialtyOption(key: 'skin_fade', label: 'Skin fade'),
  _CrewSpecialtyOption(key: 'buzz_cut', label: 'Buzz cut'),
  _CrewSpecialtyOption(key: 'scissor_cut', label: 'Scissor cut'),
  _CrewSpecialtyOption(key: 'head_shave', label: 'Head shave'),
  _CrewSpecialtyOption(key: 'hot_towel_shave', label: 'Hot towel shave'),
  _CrewSpecialtyOption(key: 'beard_shape', label: 'Beard shape'),
  _CrewSpecialtyOption(key: 'hair_styling', label: 'Styling'),
  _CrewSpecialtyOption(key: 'eyebrow_trim', label: 'Eyebrow trim'),
  _CrewSpecialtyOption(key: 'classic_haircut', label: 'Classic haircut'),
  _CrewSpecialtyOption(key: 'beard_trim', label: 'Beard trim'),
  _CrewSpecialtyOption(key: 'haircut_and_beard', label: 'Haircut & beard'),
  _CrewSpecialtyOption(key: 'fade_and_beard', label: 'Fade & beard'),
  _CrewSpecialtyOption(key: 'kids_haircut', label: 'Kids haircut'),
];

List<String> _crewSpecialtiesFromRaw(dynamic raw) {
  if (raw is List) {
    return raw
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  final singleValue = '$raw'.trim();
  if (singleValue.isEmpty || singleValue == 'null') {
    return const <String>[];
  }
  return <String>[singleValue];
}

String _crewSpecialtyLabel(String key) {
  for (final option in _crewSpecialtyOptions) {
    if (option.key == key) {
      return option.label;
    }
  }
  return key.replaceAll('_', ' ').trim();
}

String _crewRoleLabel(String role) {
  switch (role.trim()) {
    case 'Senior Barber':
      return 'Ανώτερος barber';
    case 'Barber':
      return 'barber';
    case 'Beard Specialist':
      return 'Ειδικός γενειάδας';
    case 'Color Specialist':
      return 'Ειδικός χρώματος';
    default:
      return role;
  }
}

class _CrewSpecialtyOption {
  const _CrewSpecialtyOption({required this.key, required this.label});

  final String key;
  final String label;
}

class CrewRepository {
  static const _baseUrl = 'https://barbero-88d00-default-rtdb.firebaseio.com';
  static const _functionsBaseUrl =
      'https://europe-west1-barbero-88d00.cloudfunctions.net';

  String get _currentShopId {
    return requireCurrentBarberoSession().shopId;
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

  Future<List<CrewMember>> loadCrewMembers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('No authenticated shop user');
    }
    final idToken = await user.getIdToken();
    final functionResponse = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoGetCrewMembers'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'idToken': idToken, 'shopId': _currentShopId}),
    );
    if (functionResponse.statusCode >= 200 &&
        functionResponse.statusCode < 300) {
      final decoded = jsonDecode(functionResponse.body);
      final rawCrew = decoded is Map ? decoded['crew'] : null;
      if (rawCrew is List) {
        return rawCrew
            .whereType<Map>()
            .map(
              (raw) => CrewMember.fromJson(
                '${raw['id'] ?? ''}',
                Map<String, dynamic>.from(raw),
              ),
            )
            .where((member) => member.id.trim().isNotEmpty)
            .toList()
          ..sort(
            (left, right) => left.fullName.toLowerCase().compareTo(
              right.fullName.toLowerCase(),
            ),
          );
      }
    }

    final response = await http.get(
      Uri.parse('$_baseUrl/shops/$_currentShopId/barbers.json'),
      headers: await _authHeaders(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load crew');
    }
    if (response.body == 'null') {
      return const <CrewMember>[];
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return const <CrewMember>[];
    }

    final members =
        decoded.entries
            .map((entry) {
              final raw = entry.value;
              if (raw is! Map) {
                return null;
              }
              return CrewMember.fromJson(
                entry.key,
                Map<String, dynamic>.from(raw),
              );
            })
            .whereType<CrewMember>()
            .toList()
          ..sort(
            (left, right) => left.fullName.toLowerCase().compareTo(
              right.fullName.toLowerCase(),
            ),
          );

    return members;
  }

  Future<CrewMember> createCrewMember(CrewMemberRegistrationData data) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('No authenticated shop user');
    }
    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoSaveCrewMember'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
        'crew': {
          'shopId': _currentShopId,
          'firstName': data.firstName,
          'lastName': data.lastName,
          'phone': data.phone,
          'email': data.email,
          'role': data.role,
          'notes': data.notes,
          'specialties': data.specialties,
        },
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to save crew member');
    }

    final decoded = jsonDecode(response.body);
    final crew = decoded is Map<String, dynamic> ? decoded['crew'] : null;
    final crewId = decoded is Map<String, dynamic>
        ? '${decoded['crewId'] ?? ''}'.trim()
        : '';

    if (crew is! Map || crewId.isEmpty) {
      throw Exception('Invalid crew response');
    }

    return CrewMember.fromJson(crewId, Map<String, dynamic>.from(crew));
  }

  Future<CrewMember> updateCrewMember({
    required String crewId,
    required CrewMemberRegistrationData data,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('No authenticated shop user');
    }
    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoUpdateCrewMember'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
        'crew': {
          'shopId': _currentShopId,
          'crewId': crewId,
          'firstName': data.firstName,
          'lastName': data.lastName,
          'phone': data.phone,
          'email': data.email,
          'role': data.role,
          'notes': data.notes,
          'specialties': data.specialties,
        },
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to update crew member');
    }

    final decoded = jsonDecode(response.body);
    final crew = decoded is Map<String, dynamic> ? decoded['crew'] : null;
    if (crew is! Map) {
      throw Exception('Invalid crew response');
    }
    return CrewMember.fromJson(crewId, Map<String, dynamic>.from(crew));
  }

  Future<String> uploadCrewMemberPhoto({
    required String crewId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('No authenticated shop user');
    }
    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoUploadCrewMemberPhoto'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
        'shopId': _currentShopId,
        'crewId': crewId,
        'contentType': contentType,
        'imageBase64': base64Encode(bytes),
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to upload crew photo');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      final photoUrl = '${decoded['photoUrl'] ?? ''}'.trim();
      if (photoUrl.isNotEmpty) {
        return photoUrl;
      }
    }
    throw Exception('Missing crew photo URL');
  }

  Future<bool> setOwnerBarberStatus(bool enabled) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('No authenticated shop user');
    }
    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoSetOwnerBarberStatus'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
        'shopId': _currentShopId,
        'enabled': enabled,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to update owner barber status');
    }

    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic>
        ? decoded['enabled'] == true
        : enabled;
  }

  Future<void> deleteCrewMember(String crewId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('No authenticated shop user');
    }
    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoDeleteCrewMember'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
        'shopId': _currentShopId,
        'crewId': crewId,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to delete crew member');
    }
  }
}

class CrewManagementPage extends StatefulWidget {
  const CrewManagementPage({
    super.key,
    this.initialMembers = const <CrewMember>[],
  });

  final List<CrewMember> initialMembers;

  @override
  State<CrewManagementPage> createState() => _CrewManagementPageState();
}

class _CrewManagementPageState extends State<CrewManagementPage> {
  static const List<String> _roles = <String>[
    'Senior Barber',
    'Barber',
    'Beard Specialist',
    'Color Specialist',
    'Apprentice',
  ];

  final CrewRepository _repository = CrewRepository();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _editorKey = GlobalKey();

  List<CrewMember> _crewMembers = const <CrewMember>[];
  Uint8List? _selectedPhotoBytes;
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _ownerWorksAsBarber = false;
  bool _isUpdatingOwnerBarber = false;
  String? _editingCrewId;
  String _selectedRole = _roles.first;
  List<String> _selectedSpecialties = const <String>[];

  @override
  void initState() {
    super.initState();
    _crewMembers = List<CrewMember>.from(widget.initialMembers);
    _ownerWorksAsBarber = _crewMembers.any((member) => member.isOwnerBarber);
    _loadCrewMembers();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCrewMembers() async {
    setState(() => _isLoading = true);
    try {
      final crewMembers = await _repository.loadCrewMembers();
      if (!mounted) return;
      setState(() {
        _crewMembers = crewMembers;
        _ownerWorksAsBarber = crewMembers.any((member) => member.isOwnerBarber);
      });
      currentBarberoLiveBarbers.value = List<CrewMember>.from(crewMembers);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u0394\u03b5\u03bd \u03ae\u03c4\u03b1\u03bd \u03b4\u03c5\u03bd\u03b1\u03c4\u03ae \u03b7 \u03c6\u03cc\u03c1\u03c4\u03c9\u03c3\u03b7 \u03c4\u03c9\u03bd \u03c3\u03c5\u03bd\u03b5\u03c1\u03b3\u03b1\u03c4\u03ce\u03bd.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1400,
    );
    if (file == null) return;

    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() => _selectedPhotoBytes = bytes);
  }

  Future<void> _submit() async {
    _dismissKeyboard();
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final notes = _notesController.text.trim();

    if (firstName.isEmpty || lastName.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u03a3\u03c5\u03bc\u03c0\u03bb\u03ae\u03c1\u03c9\u03c3\u03b5 \u03cc\u03bd\u03bf\u03bc\u03b1, \u03b5\u03c0\u03ce\u03bd\u03c5\u03bc\u03bf \u03ba\u03b1\u03b9 \u03c4\u03b7\u03bb\u03ad\u03c6\u03c9\u03bd\u03bf.',
          ),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final registrationData = CrewMemberRegistrationData(
        firstName: firstName,
        lastName: lastName,
        phone: phone,
        email: email,
        role: _selectedRole,
        notes: notes,
        specialties: _selectedSpecialties,
      );
      final isEditing = _editingCrewId != null;
      var member = isEditing
          ? await _repository.updateCrewMember(
              crewId: _editingCrewId!,
              data: registrationData,
            )
          : await _repository.createCrewMember(registrationData);

      if (_selectedPhotoBytes != null) {
        final photoUrl = await _repository.uploadCrewMemberPhoto(
          crewId: member.id,
          bytes: _selectedPhotoBytes!,
        );
        member = CrewMember(
          id: member.id,
          firstName: member.firstName,
          lastName: member.lastName,
          phone: member.phone,
          email: member.email,
          role: member.role,
          notes: member.notes,
          specialties: member.specialties,
          photoUrl: photoUrl,
          isOwnerBarber: member.isOwnerBarber,
        );
      }

      if (!mounted) return;
      setState(() {
        _crewMembers =
            <CrewMember>[
              member,
              ..._crewMembers.where((item) => item.id != member.id),
            ]..sort(
              (left, right) => left.fullName.toLowerCase().compareTo(
                right.fullName.toLowerCase(),
              ),
            );
      });
      currentBarberoLiveBarbers.value = List<CrewMember>.from(_crewMembers);
      _resetForm();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEditing
                ? 'Ο barber ενημερώθηκε επιτυχώς.'
                : '\u039f \u03c3\u03c5\u03bd\u03b5\u03c1\u03b3\u03ac\u03c4\u03b7\u03c2 \u03b1\u03c0\u03bf\u03b8\u03b7\u03ba\u03b5\u03cd\u03c4\u03b7\u03ba\u03b5 \u03b5\u03c0\u03b9\u03c4\u03c5\u03c7\u03ce\u03c2.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u0394\u03b5\u03bd \u03ae\u03c4\u03b1\u03bd \u03b4\u03c5\u03bd\u03b1\u03c4\u03ae \u03b7 \u03b1\u03c0\u03bf\u03b8\u03ae\u03ba\u03b5\u03c5\u03c3\u03b7 \u03c4\u03bf\u03c5 \u03c3\u03c5\u03bd\u03b5\u03c1\u03b3\u03ac\u03c4\u03b7.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _toggleOwnerBarber(bool enabled) async {
    if (_isUpdatingOwnerBarber) return;
    setState(() => _isUpdatingOwnerBarber = true);
    try {
      await _repository.setOwnerBarberStatus(enabled);
      final crewMembers = await _repository.loadCrewMembers();
      if (!mounted) return;
      setState(() {
        _crewMembers = crewMembers;
        _ownerWorksAsBarber = crewMembers.any((member) => member.isOwnerBarber);
      });
      currentBarberoLiveBarbers.value = List<CrewMember>.from(crewMembers);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            barberinLabel(
              enabled
                  ? 'Ο owner ενεργοποιήθηκε ως barber.'
                  : 'Ο owner αφαιρέθηκε από τους barbers.',
              enabled
                  ? 'The owner is now an active barber.'
                  : 'The owner was removed from the barbers.',
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            barberinLabel(
              'Δεν ήταν δυνατή η ενημέρωση του owner ως barber.',
              'The owner barber setting could not be updated.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingOwnerBarber = false);
      }
    }
  }

  void _editOwnerBarberProfile() {
    _dismissKeyboard();
    CrewMember? ownerBarber;
    for (final member in _crewMembers) {
      if (member.isOwnerBarber) {
        ownerBarber = member;
        break;
      }
    }
    if (ownerBarber == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            barberinLabel(
              'Δεν βρέθηκε το προφίλ owner-barber.',
              'The owner-barber profile could not be found.',
            ),
          ),
        ),
      );
      return;
    }
    _startEditingCrewMember(ownerBarber);
  }

  void _startEditingCrewMember(CrewMember member) {
    setState(() {
      _editingCrewId = member.id;
      _firstNameController.text = member.firstName;
      _lastNameController.text = member.lastName;
      _phoneController.text = member.phone;
      _emailController.text = member.email;
      _notesController.text = member.notes;
      _selectedRole = _roles.contains(member.role) ? member.role : _roles.first;
      _selectedSpecialties = List<String>.from(member.specialties);
      _selectedPhotoBytes = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final editorContext = _editorKey.currentContext;
      if (!mounted || editorContext == null) return;
      Scrollable.ensureVisible(
        editorContext,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    });
  }

  void _resetForm() {
    _dismissKeyboard();
    setState(() {
      _editingCrewId = null;
      _selectedPhotoBytes = null;
      _selectedRole = _roles.first;
      _selectedSpecialties = const <String>[];
    });
    _firstNameController.clear();
    _lastNameController.clear();
    _phoneController.clear();
    _emailController.clear();
    _notesController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _dismissKeyboard());
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
  }

  Future<void> _openCrewMemberActions(CrewMember member) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.fullName,
                  style: TextStyle(
                    color: context.barberinTextPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.edit_outlined,
                    color: context.barberinAccent,
                  ),
                  title: Text(
                    'Επεξεργασία barber',
                    style: TextStyle(color: context.barberinTextPrimary),
                  ),
                  onTap: () => Navigator.of(context).pop('edit'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFE07A5F),
                  ),
                  title: Text(
                    'Διαγραφή barber',
                    style: TextStyle(color: context.barberinTextPrimary),
                  ),
                  onTap: () => Navigator.of(context).pop('delete'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    if (action == 'edit') {
      _startEditingCrewMember(member);
      return;
    }
    if (action == 'delete') {
      await _confirmDeleteCrewMember(member);
    }
  }

  Future<void> _confirmDeleteCrewMember(CrewMember member) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Text(
            '\u0394\u03b9\u03b1\u03b3\u03c1\u03b1\u03c6\u03ae \u03c3\u03c5\u03bd\u03b5\u03c1\u03b3\u03ac\u03c4\u03b7',
            style: TextStyle(color: context.barberinTextPrimary),
          ),
          content: Text(
            '\u0398\u03ad\u03bb\u03b5\u03b9\u03c2 \u03bd\u03b1 \u03b4\u03b9\u03b1\u03b3\u03c1\u03ac\u03c8\u03b5\u03b9\u03c2 \u03c4\u03bf\u03bd ${member.fullName};',
            style: TextStyle(
              color: context.barberinTextSecondary,
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                '\u0386\u03ba\u03c5\u03c1\u03bf',
                style: TextStyle(color: context.barberinAccent),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                '\u0394\u03b9\u03b1\u03b3\u03c1\u03b1\u03c6\u03ae',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !mounted) return;

    try {
      await _repository.deleteCrewMember(member.id);
      if (!mounted) return;
      setState(() {
        _crewMembers = _crewMembers
            .where((crewMember) => crewMember.id != member.id)
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u039f \u03c3\u03c5\u03bd\u03b5\u03c1\u03b3\u03ac\u03c4\u03b7\u03c2 \u03b4\u03b9\u03b1\u03b3\u03c1\u03ac\u03c6\u03b7\u03ba\u03b5.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u0394\u03b5\u03bd \u03ae\u03c4\u03b1\u03bd \u03b4\u03c5\u03bd\u03b1\u03c4\u03ae \u03b7 \u03b4\u03b9\u03b1\u03b3\u03c1\u03b1\u03c6\u03ae \u03c4\u03bf\u03c5 \u03c3\u03c5\u03bd\u03b5\u03c1\u03b3\u03ac\u03c4\u03b7.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.barberinBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AuthTopBar(onBack: () => Navigator.of(context).pop()),
              const SizedBox(height: 18),
              Text(
                'Barbers',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: context.barberinTextPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '\u03a0\u03c1\u03cc\u03c3\u03b8\u03b5\u03c3\u03b5 \u03c4\u03b1 \u03bc\u03ad\u03bb\u03b7 \u03c4\u03bf\u03c5 crew.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: context.barberinTextSecondary,
                ),
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            barberinLabel(
                              'Ο owner εργάζεται ως barber',
                              'Owner works as a barber',
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: context.barberinTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            barberinLabel(
                              'Εμφανίζεται και στις κρατήσεις πελατών.',
                              'The owner also appears in customer bookings.',
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: context.barberinTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isUpdatingOwnerBarber)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.barberinAccent,
                        ),
                      )
                    else
                      Switch.adaptive(
                        value: _ownerWorksAsBarber,
                        onChanged: _toggleOwnerBarber,
                      ),
                  ],
                ),
              ),
              if (_ownerWorksAsBarber) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _isUpdatingOwnerBarber
                        ? null
                        : _editOwnerBarberProfile,
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: Text(
                      barberinLabel(
                        'Επεξεργασία προφίλ owner-barber',
                        'Edit owner-barber profile',
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: context.barberinAccent,
                    ),
                  ),
                ),
              ],
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        key: _editorKey,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _editingCrewId == null
                                      ? '\u039d\u03ad\u03bf\u03c2 \u03c3\u03c5\u03bd\u03b5\u03c1\u03b3\u03ac\u03c4\u03b7\u03c2'
                                      : _crewMembers.any(
                                          (member) =>
                                              member.id == _editingCrewId &&
                                              member.isOwnerBarber,
                                        )
                                      ? barberinLabel(
                                          '\u0395\u03c0\u03b5\u03be\u03b5\u03c1\u03b3\u03b1\u03c3\u03af\u03b1 \u03c0\u03c1\u03bf\u03c6\u03af\u03bb owner-barber',
                                          'Edit owner-barber profile',
                                        )
                                      : '\u0395\u03c0\u03b5\u03be\u03b5\u03c1\u03b3\u03b1\u03c3\u03af\u03b1 barber',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: context.barberinTextPrimary,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.person_add_alt_1_rounded,
                                size: 19,
                                color: context.barberinTextSecondary,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _CrewPhotoPicker(
                            previewBytes: _selectedPhotoBytes,
                            onCameraTap: _isSubmitting
                                ? null
                                : () => _pickPhoto(ImageSource.camera),
                            onGalleryTap: _isSubmitting
                                ? null
                                : () => _pickPhoto(ImageSource.gallery),
                          ),
                          const SizedBox(height: 14),
                          AppTextField(
                            label: '\u038c\u03bd\u03bf\u03bc\u03b1',
                            controller: _firstNameController,
                            icon: Icons.badge_outlined,
                            large: true,
                          ),
                          const SizedBox(height: 12),
                          AppTextField(
                            label: '\u0395\u03c0\u03ce\u03bd\u03c5\u03bc\u03bf',
                            controller: _lastNameController,
                            icon: Icons.person_outline_rounded,
                            large: true,
                          ),
                          const SizedBox(height: 12),
                          AppTextField(
                            label:
                                '\u03a4\u03b7\u03bb\u03ad\u03c6\u03c9\u03bd\u03bf',
                            controller: _phoneController,
                            icon: Icons.call_outlined,
                            keyboardType: TextInputType.phone,
                            large: true,
                          ),
                          const SizedBox(height: 12),
                          AppTextField(
                            label: 'Ηλεκτρονικό ταχυδρομείο',
                            controller: _emailController,
                            icon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            large: true,
                          ),
                          const SizedBox(height: 12),
                          _CrewRoleDropdown(
                            value: _selectedRole,
                            onChanged: _isSubmitting
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    setState(() => _selectedRole = value);
                                  },
                          ),
                          const SizedBox(height: 12),
                          _CrewSpecialtiesPicker(
                            selectedKeys: _selectedSpecialties,
                            enabled: !_isSubmitting,
                            onToggle: (key) {
                              setState(() {
                                if (_selectedSpecialties.contains(key)) {
                                  _selectedSpecialties = _selectedSpecialties
                                      .where((item) => item != key)
                                      .toList();
                                } else {
                                  _selectedSpecialties = <String>[
                                    ..._selectedSpecialties,
                                    key,
                                  ];
                                }
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          _CrewNotesField(controller: _notesController),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_isSubmitting)
                        Padding(
                          padding: EdgeInsets.only(bottom: 14),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: context.barberinAccent,
                            ),
                          ),
                        ),
                      PrimaryButton(
                        label: _editingCrewId == null
                            ? '\u0391\u03c0\u03bf\u03b8\u03ae\u03ba\u03b5\u03c5\u03c3\u03b7 \u03c3\u03c5\u03bd\u03b5\u03c1\u03b3\u03ac\u03c4\u03b7'
                            : 'Ενημέρωση barber',
                        onPressed: _isSubmitting ? () {} : _submit,
                      ),
                      if (_editingCrewId != null) ...[
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: _isSubmitting ? null : _resetForm,
                          child: Text(
                            'Ακύρωση επεξεργασίας',
                            style: TextStyle(color: context.barberinAccent),
                          ),
                        ),
                      ],
                      const SizedBox(height: 26),
                      Row(
                        children: [
                          Text(
                            '\u03a5\u03c0\u03ac\u03c1\u03c7\u03bf\u03bd crew',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: context.barberinTextPrimary,
                            ),
                          ),
                          const Spacer(),
                          if (_isLoading)
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.barberinAccent,
                              ),
                            )
                          else
                            TextButton(
                              onPressed: _loadCrewMembers,
                              child: Text(
                                '\u0391\u03bd\u03b1\u03bd\u03ad\u03c9\u03c3\u03b7',
                                style: TextStyle(color: context.barberinAccent),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (!_isLoading && _crewMembers.isEmpty)
                        Panel(
                          child: Text(
                            '\u0394\u03b5\u03bd \u03c5\u03c0\u03ac\u03c1\u03c7\u03bf\u03c5\u03bd \u03b1\u03ba\u03cc\u03bc\u03b1 \u03ba\u03b1\u03c4\u03b1\u03c7\u03c9\u03c1\u03b7\u03bc\u03ad\u03bd\u03bf\u03b9 \u03c3\u03c5\u03bd\u03b5\u03c1\u03b3\u03ac\u03c4\u03b5\u03c2.',
                            style: TextStyle(
                              fontSize: 13,
                              color: context.barberinTextSecondary,
                            ),
                          ),
                        )
                      else
                        ..._crewMembers.map(
                          (member) => _CrewMemberCard(
                            member: member,
                            onLongPress: () => _openCrewMemberActions(member),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CrewPhotoPicker extends StatelessWidget {
  const _CrewPhotoPicker({
    required this.previewBytes,
    required this.onCameraTap,
    required this.onGalleryTap,
  });

  final Uint8List? previewBytes;
  final VoidCallback? onCameraTap;
  final VoidCallback? onGalleryTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: context.barberinSurfaceAlt,
            shape: BoxShape.circle,
            border: Border.all(color: context.barberinBorder, width: 1.5),
            image: previewBytes == null
                ? null
                : DecorationImage(
                    image: MemoryImage(previewBytes!),
                    fit: BoxFit.cover,
                  ),
          ),
          child: previewBytes == null
              ? Icon(
                  Icons.person_rounded,
                  size: 30,
                  color: context.barberinAccent,
                )
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '\u03a6\u03c9\u03c4\u03bf\u03b3\u03c1\u03b1\u03c6\u03af\u03b1 \u03c3\u03c5\u03bd\u03b5\u03c1\u03b3\u03ac\u03c4\u03b7',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.barberinTextPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '\u03a0\u03c1\u03bf\u03b1\u03b9\u03c1\u03b5\u03c4\u03b9\u03ba\u03ae \u03c6\u03c9\u03c4\u03bf\u03b3\u03c1\u03b1\u03c6\u03af\u03b1',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: context.barberinTextSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MiniActionButton(
                    icon: Icons.photo_camera_outlined,
                    label: '\u039a\u03ac\u03bc\u03b5\u03c1\u03b1',
                    onTap: onCameraTap,
                  ),
                  _MiniActionButton(
                    icon: Icons.photo_library_outlined,
                    label: '\u03a3\u03c5\u03bb\u03bb\u03bf\u03b3\u03ae',
                    onTap: onGalleryTap,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniActionButton extends StatelessWidget {
  const _MiniActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: context.barberinSurfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.barberinBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: context.barberinAccent),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.barberinTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CrewRoleDropdown extends StatelessWidget {
  const _CrewRoleDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '\u03a1\u03cc\u03bb\u03bf\u03c2',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 0.8,
            color: context.barberinAccent,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
          decoration: BoxDecoration(
            color: context.barberinSurfaceAlt,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.barberinBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              dropdownColor: Theme.of(context).colorScheme.surface,
              iconEnabledColor: context.barberinAccent,
              style: TextStyle(
                fontSize: 13,
                color: context.barberinTextPrimary,
                fontWeight: FontWeight.w500,
              ),
              isExpanded: true,
              onChanged: onChanged,
              items: _CrewManagementPageState._roles
                  .map(
                    (role) => DropdownMenuItem<String>(
                      value: role,
                      child: Text(_crewRoleLabel(role)),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class _CrewNotesField extends StatelessWidget {
  const _CrewNotesField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '\u03a3\u03b7\u03bc\u03b5\u03b9\u03ce\u03c3\u03b5\u03b9\u03c2',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 0.8,
            color: context.barberinAccent,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: 3,
          minLines: 3,
          style: TextStyle(
            fontSize: 14,
            color: context.barberinTextPrimary,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: UnderlineInputBorder(
              borderSide: BorderSide(color: context.barberinBorder),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: context.barberinBorder),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: context.barberinAccent, width: 1.4),
            ),
            hintText: barberinTranslate(
              '\u03a0.\u03c7. \u03b4\u03b9\u03b1\u03b8\u03ad\u03c3\u03b9\u03bc\u03bf\u03c2 \u03b3\u03b9\u03b1 fades, \u03c0\u03b5\u03c1\u03b9\u03c0\u03bf\u03af\u03b7\u03c3\u03b7 \u03b3\u03b5\u03bd\u03b5\u03b9\u03ac\u03b4\u03b1\u03c2 \u03ae \u03b1\u03c0\u03bf\u03b3\u03b5\u03c5\u03bc\u03b1\u03c4\u03b9\u03bd\u03ad\u03c2 \u03b2\u03ac\u03c1\u03b4\u03b9\u03b5\u03c2.',
            ),
            hintStyle: TextStyle(color: context.barberinTextSecondary),
          ),
          cursorColor: context.barberinAccent,
        ),
      ],
    );
  }
}

class _CrewMemberCard extends StatelessWidget {
  const _CrewMemberCard({required this.member, required this.onLongPress});

  final CrewMember member;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.barberinBorder)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: context.barberinSurfaceAlt,
                shape: BoxShape.circle,
                border: Border.all(color: context.barberinBorder),
                image: member.photoUrl.isEmpty
                    ? null
                    : DecorationImage(
                        image: NetworkImage(member.photoUrl),
                        fit: BoxFit.cover,
                      ),
              ),
              child: member.photoUrl.isEmpty
                  ? Icon(
                      Icons.content_cut_rounded,
                      color: context.barberinAccent,
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.fullName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.barberinTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _crewRoleLabel(member.role),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.barberinAccent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (member.phone.isNotEmpty)
                    Text(
                      member.phone,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.barberinTextSecondary,
                      ),
                    ),
                  if (member.email.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        member.email,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.barberinTextSecondary,
                        ),
                      ),
                    ),
                  if (member.notes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        member.notes,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: context.barberinTextSecondary,
                        ),
                      ),
                    ),
                  if (member.specialties.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: member.specialties
                            .map(
                              (item) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: context.barberinSurfaceAlt,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: context.barberinBorder,
                                  ),
                                ),
                                child: Text(
                                  _crewSpecialtyLabel(item),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.barberinTextPrimary,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CrewSpecialtiesPicker extends StatelessWidget {
  const _CrewSpecialtiesPicker({
    required this.selectedKeys,
    required this.enabled,
    required this.onToggle,
  });

  final List<String> selectedKeys;
  final bool enabled;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ειδικότητες',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 0.8,
            color: context.barberinAccent,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _crewSpecialtyOptions.map((option) {
            final selected = selectedKeys.contains(option.key);
            return GestureDetector(
              onTap: enabled ? () => onToggle(option.key) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? context.barberinAccentSoft
                      : context.barberinSurfaceAlt,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected
                        ? context.barberinAccent
                        : context.barberinBorder,
                  ),
                ),
                child: Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? context.barberinTextPrimary
                        : context.barberinTextSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
