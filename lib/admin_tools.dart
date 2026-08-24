part of 'main.dart';

class CustomerAdminRepository {
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

  Future<List<CustomerProfile>> loadCustomers() async {
    final dynamic decoded;
    if (isBarberinWindows) {
      decoded = await WindowsBackendAdapter.instance.loadClients(
        _currentShopId,
      );
    } else {
      final response = await http.get(
        Uri.parse('$_baseUrl/shops/$_currentShopId/customers.json'),
        headers: await _authHeaders(),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Failed to load customers');
      }
      if (response.body == 'null') {
        return const <CustomerProfile>[];
      }
      decoded = jsonDecode(response.body);
    }
    if (decoded is! Map<String, dynamic>) {
      return const <CustomerProfile>[];
    }

    final customers =
        decoded.entries
            .map((entry) {
              final raw = entry.value;
              if (raw is! Map) {
                return null;
              }
              final data = Map<String, dynamic>.from(raw);
              final fullName = '${data['fullName'] ?? data['name'] ?? ''}'
                  .trim();
              if (fullName.isEmpty) {
                return null;
              }
              return CustomerProfile(
                uid: entry.key,
                name: fullName,
                phone: '${data['phone'] ?? ''}'.trim(),
                email: '${data['email'] ?? ''}'.trim(),
                photoUrl: '${data['photoUrl'] ?? ''}'.trim(),
                preferences: _customerPreferencesFromRaw(data['preferences']),
                notes: '${data['notes'] ?? ''}'.trim(),
                history: const <VisitRecord>[],
              );
            })
            .whereType<CustomerProfile>()
            .toList()
          ..sort(
            (left, right) =>
                left.name.toLowerCase().compareTo(right.name.toLowerCase()),
          );
    return customers;
  }

  Future<void> updateCustomerProfile({
    required String customerUid,
    required List<String> preferences,
    required String notes,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('No authenticated shop user');
    }
    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoUpdateCustomerProfile'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
        'customer': {
          'shopId': _currentShopId,
          'customerUid': customerUid,
          'preferences': preferences,
          'notes': notes,
        },
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to update customer profile');
    }
  }

  Future<void> mergeCustomers({
    required String sourceCustomerUid,
    required String targetCustomerUid,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('No authenticated shop user');
    }
    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoMergeCustomers'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
        'shopId': _currentShopId,
        'sourceCustomerUid': sourceCustomerUid,
        'targetCustomerUid': targetCustomerUid,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to merge customers');
    }
  }

  Future<RepairSummary> repairCorruptedRecords() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('No authenticated shop user');
    }
    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/barberoRepairCorruptedRecords'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'idToken': idToken, 'shopId': _currentShopId}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to repair corrupted records');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid repair response');
    }
    return RepairSummary(
      repairedAppointments:
          (decoded['repairedAppointments'] as num?)?.toInt() ?? 0,
      repairedCustomers: (decoded['repairedCustomers'] as num?)?.toInt() ?? 0,
      repairedBarbers: (decoded['repairedBarbers'] as num?)?.toInt() ?? 0,
      changedPaths: (decoded['changedPaths'] as num?)?.toInt() ?? 0,
    );
  }
}

class RepairSummary {
  const RepairSummary({
    required this.repairedAppointments,
    required this.repairedCustomers,
    required this.repairedBarbers,
    required this.changedPaths,
  });

  final int repairedAppointments;
  final int repairedCustomers;
  final int repairedBarbers;
  final int changedPaths;
}

class _DuplicateCustomerCandidate {
  const _DuplicateCustomerCandidate({
    required this.primary,
    required this.secondary,
    required this.reason,
  });

  final CustomerProfile primary;
  final CustomerProfile secondary;
  final String reason;
}

List<_DuplicateCustomerCandidate> _buildDuplicateCustomerCandidates(
  List<CustomerProfile> customers,
) {
  final duplicates = <_DuplicateCustomerCandidate>[];
  final seen = <String>{};

  String normalizeName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  for (var i = 0; i < customers.length; i += 1) {
    final left = customers[i];
    if (left.uid.trim().isEmpty) continue;
    for (var j = i + 1; j < customers.length; j += 1) {
      final right = customers[j];
      if (right.uid.trim().isEmpty) continue;

      String? reason;
      if (normalizeName(left.name) == normalizeName(right.name)) {
        reason = 'Ίδιο όνομα';
      } else if (left.phone.trim().isNotEmpty &&
          left.phone.trim() == right.phone.trim()) {
        reason = 'Ίδιο τηλέφωνο';
      } else if (left.email.trim().isNotEmpty &&
          left.email.trim().toLowerCase() == right.email.trim().toLowerCase()) {
        reason = 'Ίδιο email';
      }

      if (reason == null) continue;
      final pairKey = [left.uid.trim(), right.uid.trim()]..sort();
      final key = pairKey.join('|');
      if (seen.contains(key)) continue;
      seen.add(key);
      duplicates.add(
        _DuplicateCustomerCandidate(
          primary: left,
          secondary: right,
          reason: reason,
        ),
      );
    }
  }

  duplicates.sort(
    (left, right) => left.primary.name.toLowerCase().compareTo(
      right.primary.name.toLowerCase(),
    ),
  );
  return duplicates;
}

class AdminToolsPage extends StatefulWidget {
  const AdminToolsPage({super.key});

  @override
  State<AdminToolsPage> createState() => _AdminToolsPageState();
}

class _AdminToolsPageState extends State<AdminToolsPage> {
  final CustomerAdminRepository _repository = CustomerAdminRepository();
  List<CustomerProfile> _customers = const <CustomerProfile>[];
  bool _loadingCustomers = true;
  bool _repairing = false;
  RepairSummary? _lastRepairSummary;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    setState(() => _loadingCustomers = true);
    try {
      final customers = await _repository.loadCustomers();
      if (!mounted) return;
      setState(() => _customers = customers);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Δεν ήταν δυνατή η φόρτωση των πελατών.')),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingCustomers = false);
      }
    }
  }

  Future<void> _repairCorruptedRecords() async {
    setState(() => _repairing = true);
    try {
      final summary = await _repository.repairCorruptedRecords();
      if (!mounted) return;
      setState(() => _lastRepairSummary = summary);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Η επιδιόρθωση ολοκληρώθηκε.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Δεν ήταν δυνατή η επιδιόρθωση των παλιών εγγραφών.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _repairing = false);
      }
    }
  }

  Future<void> _mergeDuplicate(
    _DuplicateCustomerCandidate candidate,
    bool keepPrimary,
  ) async {
    final keep = keepPrimary ? candidate.primary : candidate.secondary;
    final merge = keepPrimary ? candidate.secondary : candidate.primary;
    try {
      await _repository.mergeCustomers(
        sourceCustomerUid: merge.uid,
        targetCustomerUid: keep.uid,
      );
      if (!mounted) return;
      setState(() {
        _customers = _customers
            .where((customer) => customer.uid.trim() != merge.uid.trim())
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Συγχωνεύτηκε με τον πελάτη ${keep.name}.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Δεν ήταν δυνατή η συγχώνευση διπλών πελατών.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final duplicates = _buildDuplicateCustomerCandidates(_customers);
    return Scaffold(
      backgroundColor: context.barberinBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AuthTopBar(onBack: () => Navigator.of(context).pop()),
              const SizedBox(height: 24),
              Text(
                'Εργαλεία διαχειριστή',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: context.barberinTextPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Επιδιόρθωση παλιών εγγραφών και καθαρισμός διπλών δεδομένων πελατών.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: context.barberinTextSecondary,
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionLabel('Επιδιόρθωση παλιών εγγραφών'),
                            const SizedBox(height: 10),
                            Text(
                              'Επιδιορθώνει παλιά κατεστραμμένα πεδία κειμένου και ανανεώνει τις λανθασμένες ονομασίες υπηρεσιών.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: context.barberinTextSecondary,
                              ),
                            ),
                            const SizedBox(height: 14),
                            PrimaryButton(
                              label: _repairing
                                  ? 'Επιδιόρθωση...'
                                  : 'Επιδιόρθωση κατεστραμμένων εγγραφών',
                              onPressed: _repairing
                                  ? () {}
                                  : _repairCorruptedRecords,
                            ),
                            if (_lastRepairSummary != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Ραντεβού: ${_lastRepairSummary!.repairedAppointments}  Πελάτες: ${_lastRepairSummary!.repairedCustomers}  barber: ${_lastRepairSummary!.repairedBarbers}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.barberinTextPrimary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionLabel('Διπλοί πελάτες'),
                            const SizedBox(height: 10),
                            if (_loadingCustomers)
                              Center(
                                child: CircularProgressIndicator(
                                  color: context.barberinAccent,
                                ),
                              )
                            else if (duplicates.isEmpty)
                              Text(
                                'Δεν εντοπίστηκαν διπλοί πελάτες αυτή τη στιγμή.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: context.barberinTextSecondary,
                                ),
                              )
                            else
                              ...duplicates.map(
                                (candidate) => Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: context.barberinBorder,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        candidate.reason,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: context.barberinAccent,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        '${candidate.primary.name}  |  ${candidate.primary.phone}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: context.barberinTextPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${candidate.secondary.name}  |  ${candidate.secondary.phone}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: context.barberinTextPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () => _mergeDuplicate(
                                                candidate,
                                                true,
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: const Color(
                                                  0xFFF0E5D1,
                                                ),
                                                side: const BorderSide(
                                                  color: Color(0xFF3A3A3A),
                                                ),
                                              ),
                                              child: Text('Διατήρηση πρώτου'),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () => _mergeDuplicate(
                                                candidate,
                                                false,
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: const Color(
                                                  0xFFF0E5D1,
                                                ),
                                                side: const BorderSide(
                                                  color: Color(0xFF3A3A3A),
                                                ),
                                              ),
                                              child: Text('Διατήρηση δεύτερου'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
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
