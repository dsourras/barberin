part of 'main.dart';

class BarberShell extends StatefulWidget {
  const BarberShell({super.key});

  @override
  State<BarberShell> createState() => _BarberShellState();
}

class _BarberShellState extends State<BarberShell>
    with WidgetsBindingObserver {
  int tabIndex = 0;
  late DateTime currentAthensTime;
  late DateTime selectedDate;
  String ownerFirstName = 'Owner';
  List<ScheduleDay> weeklySchedule = buildDefaultWeeklySchedule();
  int slotMinutes = 30;
  List<ServiceDurationSetting> serviceDurations = buildDefaultServiceDurations();
  List<ServicePriceSetting> servicePrices = buildDefaultServicePrices();
  List<Appointment> liveAppointments = const <Appointment>[];
  List<CustomerProfile> liveCustomers = const <CustomerProfile>[];
  List<CrewMember> liveBarbers = const <CrewMember>[];
  Timer? _clockTimer;
  StreamSubscription<DatabaseEvent>? _shopSubscription;
  final WeeklyScheduleRepository _scheduleRepository =
      WeeklyScheduleRepository();
  final CustomerAdminRepository _customerAdminRepository =
      CustomerAdminRepository();

  BarberoSession get _session => requireCurrentBarberoSession();
  BarberoPermissions get _permissions => _session.permissions;

  void _syncCurrentDayIfNeeded() {
    final now = athensNow();
    final today = athensDateOnly(now);
    if (!mounted) {
      currentAthensTime = now;
      selectedDate = today;
      return;
    }
    final shouldUpdateTime =
        currentAthensTime.year != now.year ||
        currentAthensTime.month != now.month ||
        currentAthensTime.day != now.day ||
        currentAthensTime.hour != now.hour ||
        currentAthensTime.minute != now.minute;
    final shouldUpdateDate = selectedDate != today;
    if (!shouldUpdateTime && !shouldUpdateDate) {
      return;
    }
    setState(() {
      currentAthensTime = now;
      if (shouldUpdateDate) {
        selectedDate = today;
      }
    });
  }

  bool _canManageAppointment(Appointment appointment) {
    if (_permissions.manageAllAppointments) {
      return true;
    }
    if (!_permissions.manageOwnAppointments) {
      return false;
    }
    if (_session.crewId.trim().isNotEmpty &&
        appointment.barberId.trim() == _session.crewId.trim()) {
      return true;
    }
    return appointment.barberName.trim().toLowerCase() ==
        _session.displayName.trim().toLowerCase();
  }

  Future<void> _updateAppointmentStatus({
    required String appointmentId,
    required String status,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('missing-shop-user');
    }
    final session = _session;
    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse(
        'https://europe-west1-barbero-88d00.cloudfunctions.net/barberoUpdateAppointmentStatus',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
        'shopId': session.shopId,
        'appointmentId': appointmentId,
        'status': status,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('appointment-status-update-failed');
    }
  }

  Future<void> _rescheduleAppointment({
    required String appointmentId,
    required String barberId,
    required String barberName,
    required DateTime date,
    required String startTime,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('missing-shop-user');
    }
    final session = _session;
    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse(
        'https://europe-west1-barbero-88d00.cloudfunctions.net/barberoRescheduleAppointment',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
        'shopId': session.shopId,
        'appointmentId': appointmentId,
        'barberId': barberId,
        'barberName': barberName,
        'date':
            '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'startTime': startTime,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('appointment-reschedule-failed');
    }
  }

  Future<List<String>> _fetchAvailabilitySlotsForOwner({
    required String barberId,
    required DateTime date,
    required int requiredMinutes,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const <String>[];
    }
    final session = _session;
    final response = await http.post(
      Uri.parse(
        'https://europe-west1-barbero-88d00.cloudfunctions.net/atelier22GetAvailability',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'shopId': session.shopId,
        'barberId': barberId,
        'date':
            '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'requiredMinutes': requiredMinutes <= 0 ? slotMinutes : requiredMinutes,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const <String>[];
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return const <String>[];
    }
    final slots =
        (decoded['slots'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
    return slots
        .map((slot) => '${slot['startTime'] ?? ''}'.trim())
        .where((slot) => slot.isNotEmpty)
        .toList();
  }

  List<CrewMember> get _manageableBarbers {
    if (_permissions.manageAllAppointments) {
      return List<CrewMember>.from(liveBarbers);
    }
    final ownCrewId = _session.crewId.trim();
    if (ownCrewId.isNotEmpty) {
      final filtered =
          liveBarbers
              .where((barber) => barber.id.trim() == ownCrewId)
              .toList();
      if (filtered.isNotEmpty) {
        return filtered;
      }
    }
    final byName =
        liveBarbers
            .where(
              (barber) =>
                  barber.fullName.trim().toLowerCase() ==
                  _session.displayName.trim().toLowerCase(),
            )
            .toList();
    return byName;
  }

  Future<void> _createManualAppointment({
    required String barberId,
    required String customerName,
    required String customerPhone,
    required String customerEmail,
    required DateTime date,
    required String startTime,
    required int totalMinutes,
    required int totalPrice,
    required bool blocked,
    String serviceKey = '',
    String serviceLabel = '',
    String blockReason = '',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('missing-shop-user');
    }
    final session = _session;
    final barber =
        liveBarbers.cast<CrewMember?>().firstWhere(
              (item) => item?.id.trim() == barberId.trim(),
              orElse: () => null,
            );
    if (barber == null) {
      throw Exception('missing-barber');
    }
    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse(
        'https://europe-west1-barbero-88d00.cloudfunctions.net/barberoCreateManualAppointment',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
        'shopId': session.shopId,
        'appointment': {
          'barberId': barber.id,
          'barberName': barber.fullName,
          'customerName': customerName,
          'customerPhone': customerPhone,
          'customerEmail': customerEmail,
          'date':
              '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
          'startTime': startTime,
          'totalMinutes': totalMinutes,
          'totalPrice': totalPrice,
          'blocked': blocked,
          'serviceKey': serviceKey,
          'serviceLabel': serviceLabel,
          'blockReason': blockReason,
        },
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('manual-appointment-create-failed');
    }
  }

  Future<void> _openQuickAddSheet(
    BuildContext context, {
    DateTime? initialDate,
    String? initialBarberId,
    String? initialStartTime,
  }) async {
    final manageableBarbers = _manageableBarbers;
    if (manageableBarbers.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No accessible barbers found.')),
      );
      return;
    }

    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return _QuickAddAppointmentSheet(
          selectedDate: initialDate ?? selectedDate,
          barbers: manageableBarbers,
          serviceDurations: serviceDurations,
          servicePrices: servicePrices,
          slotMinutes: slotMinutes,
          initialBarberId: initialBarberId,
          initialStartTime: initialStartTime,
          onLoadSlots: ({
            required String barberId,
            required DateTime date,
            required int requiredMinutes,
          }) {
            return _fetchAvailabilitySlotsForOwner(
              barberId: barberId,
              date: date,
              requiredMinutes: requiredMinutes,
            );
          },
          onSave: ({
            required String barberId,
            required String customerName,
            required String customerPhone,
            required String customerEmail,
            required DateTime date,
            required String startTime,
            required int totalMinutes,
            required int totalPrice,
            required bool blocked,
            required String serviceKey,
            required String serviceLabel,
            required String blockReason,
          }) {
            return _createManualAppointment(
              barberId: barberId,
              customerName: customerName,
              customerPhone: customerPhone,
              customerEmail: customerEmail,
              date: date,
              startTime: startTime,
              totalMinutes: totalMinutes,
              totalPrice: totalPrice,
              blocked: blocked,
              serviceKey: serviceKey,
              serviceLabel: serviceLabel,
              blockReason: blockReason,
            );
          },
        );
      },
    );

    if (changed == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Schedule updated.')),
      );
    }
  }

  List<CrewMember> _parseCrewMembersFromShopData(Map<String, dynamic> shopData) {
    final rawBarbers =
        _mapFromRawValue(shopData['barbers']) ?? <String, dynamic>{};
    final members = <CrewMember>[];
    for (final entry in rawBarbers.entries) {
      final value = _mapFromRawValue(entry.value);
      if (value == null) {
        continue;
      }
      final member = CrewMember.fromJson(entry.key, value);
      if (member.fullName.trim().isEmpty) {
        continue;
      }
      members.add(member);
    }
    members.sort(
      (left, right) =>
          left.fullName.toLowerCase().compareTo(right.fullName.toLowerCase()),
    );
    return members;
  }

  // ignore: unused_element
  Future<void> _manageAppointmentStatus({
    required BuildContext context,
    required String appointmentId,
    required String customerName,
    required String currentStatus,
  }) async {
    if (appointmentId.trim().isEmpty) {
      return;
    }
    final nextStatus = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF111111),
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
                  customerName,
                  style: const TextStyle(
                    color: Color(0xFFF0E5D1),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Current status: ${Appointment('', '', '', '', status: currentStatus).statusLabel}',
                  style: const TextStyle(
                    color: Color(0xFFBFB7AA),
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.check_circle_outline_rounded,
                    color: Color(0xFF7DB37D),
                  ),
                  title: const Text(
                    'Confirm appointment',
                    style: TextStyle(color: Color(0xFFF0E5D1)),
                  ),
                  onTap: () => Navigator.of(context).pop('confirmed'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.cancel_outlined,
                    color: Color(0xFFE08A7A),
                  ),
                  title: const Text(
                    'Cancel appointment',
                    style: TextStyle(color: Color(0xFFF0E5D1)),
                  ),
                  onTap: () => Navigator.of(context).pop('cancelled'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (nextStatus == null || !context.mounted) {
      return;
    }

    try {
      await _updateAppointmentStatus(
        appointmentId: appointmentId,
        status: nextStatus,
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextStatus == 'confirmed'
                ? 'Το ραντεβού επιβεβαιώθηκε.'
                : 'Το ραντεβού ακυρώθηκε.',
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Δεν ήταν δυνατή η ενημέρωση του ραντεβού.'),
        ),
      );
    }
  }

  Future<void> _openOwnerAppointmentActions({
    required BuildContext context,
    required Appointment appointment,
  }) async {
    if (appointment.id.trim().isEmpty || !_canManageAppointment(appointment)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You do not have access to this appointment.')),
        );
      }
      return;
    }

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF111111),
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
                  appointment.isBlocked ? 'Blocked slot' : appointment.name,
                  style: const TextStyle(
                    color: Color(0xFFF0E5D1),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Current status: ${appointment.statusLabel}',
                  style: const TextStyle(
                    color: Color(0xFFBFB7AA),
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 16),
                if (!appointment.isBlocked)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.edit_calendar_outlined,
                      color: Color(0xFFD1A45C),
                    ),
                    title: const Text(
                      'Reschedule appointment',
                      style: TextStyle(color: Color(0xFFF0E5D1)),
                    ),
                    onTap: () => Navigator.of(context).pop('reschedule'),
                  ),
                if (!appointment.isBlocked)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.check_circle_outline_rounded,
                      color: Color(0xFF7DB37D),
                    ),
                    title: const Text(
                      'Confirm appointment',
                      style: TextStyle(color: Color(0xFFF0E5D1)),
                    ),
                    onTap: () => Navigator.of(context).pop('confirmed'),
                  ),
                if (!appointment.isBlocked)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.task_alt_rounded,
                      color: Color(0xFF7AA6D1),
                    ),
                    title: const Text(
                      'Mark as completed',
                      style: TextStyle(color: Color(0xFFF0E5D1)),
                    ),
                    onTap: () => Navigator.of(context).pop('completed'),
                  ),
                if (!appointment.isBlocked)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.person_off_outlined,
                      color: Color(0xFFB08AE0),
                    ),
                    title: const Text(
                      'Mark as no-show',
                      style: TextStyle(color: Color(0xFFF0E5D1)),
                    ),
                    onTap: () => Navigator.of(context).pop('no_show'),
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.cancel_outlined,
                    color: Color(0xFFE08A7A),
                  ),
                  title: Text(
                    appointment.isBlocked ? 'Release blocked slot' : 'Cancel appointment',
                    style: const TextStyle(color: Color(0xFFF0E5D1)),
                  ),
                  onTap: () => Navigator.of(context).pop('cancelled'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (action == null || !context.mounted) {
      return;
    }

    if (action == 'reschedule') {
      await _openOwnerRescheduleSheet(context: context, appointment: appointment);
      return;
    }

    try {
      await _updateAppointmentStatus(
        appointmentId: appointment.id,
        status: action,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            switch (action) {
              'confirmed' => 'Appointment confirmed.',
              'completed' => 'Appointment marked as completed.',
              'no_show' => 'Appointment marked as no-show.',
              _ => appointment.isBlocked
                  ? 'Blocked slot released.'
                  : 'Appointment cancelled.',
            },
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update appointment.'),
        ),
      );
    }
  }

  Future<void> _openOwnerRescheduleSheet({
    required BuildContext context,
    required Appointment appointment,
  }) async {
    if (liveBarbers.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No barbers available for reschedule.')),
      );
      return;
    }

    final initialBarber =
        liveBarbers.cast<CrewMember?>().firstWhere(
              (barber) => barber?.fullName.trim() == appointment.barberName.trim(),
              orElse: () => liveBarbers.first,
            ) ??
        liveBarbers.first;

    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return _OwnerRescheduleSheet(
          appointment: appointment,
          barbers: liveBarbers,
          initialBarber: initialBarber,
          onLoadSlots: ({
            required String barberId,
            required DateTime date,
            required int requiredMinutes,
          }) {
            return _fetchAvailabilitySlotsForOwner(
              barberId: barberId,
              date: date,
              requiredMinutes: requiredMinutes,
            );
          },
          onSave: ({
            required String barberId,
            required String barberName,
            required DateTime date,
            required String startTime,
          }) {
            return _rescheduleAppointment(
              appointmentId: appointment.id,
              barberId: barberId,
              barberName: barberName,
              date: date,
              startTime: startTime,
            );
          },
        );
      },
    );

    if (changed == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Appointment rescheduled.')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    currentAthensTime = athensNow();
    selectedDate = athensDateOnly(currentAthensTime);
    WidgetsBinding.instance.addObserver(this);
    _initializeRealtimeShopSync();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _syncCurrentDayIfNeeded();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _shopSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncCurrentDayIfNeeded();
    }
  }

  Future<void> _initializeRealtimeShopSync() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final session = _session;
      await _scheduleRepository.loadOrCreateDefault();
      final ref = FirebaseDatabase.instance.ref('shops/${session.shopId}');
      await _shopSubscription?.cancel();
      _shopSubscription = ref.onValue.listen((event) {
        final shopData = _mapFromRawValue(event.snapshot.value);
        if (shopData == null || !mounted) return;
        final scheduleData = _parseWeeklyScheduleFromShop(shopData);
        final appointments = _parseAppointmentsFromShop(shopData);
        final customers = _parseCustomersFromShop(shopData, appointments);
        final barbers = _parseCrewMembersFromShopData(shopData);
        final ownerName = '${shopData['ownerName'] ?? ''}'.trim();
        setState(() {
          slotMinutes = scheduleData.slotMinutes;
          weeklySchedule = List<ScheduleDay>.from(scheduleData.days);
          serviceDurations = List<ServiceDurationSetting>.from(
            scheduleData.serviceDurations,
          );
          servicePrices = List<ServicePriceSetting>.from(
            scheduleData.servicePrices,
          );
          liveAppointments = appointments;
          liveCustomers = customers;
          liveBarbers = barbers;
          final preferredName = session.isOwner ? ownerName : session.displayName;
          if (preferredName.trim().isNotEmpty) {
            ownerFirstName = preferredName.split(RegExp(r'\s+')).first;
          }
        });
      });
    } catch (_) {}
  }

  Future<void> openWeeklySchedule(BuildContext context) async {
    if (!_permissions.editSchedule) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You do not have access to schedule settings.')),
      );
      return;
    }
    await _openBarberoMenuPage(context, const WeeklySchedulePage());
  }

  Future<void> _openCustomerActions({
    required BuildContext context,
    required CustomerProfile customer,
  }) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF111111),
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
                  customer.name,
                  style: const TextStyle(
                    color: Color(0xFFF0E5D1),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.edit_note_rounded,
                    color: Color(0xFFD1A45C),
                  ),
                  title: const Text(
                    'Edit preferences and notes',
                    style: TextStyle(color: Color(0xFFF0E5D1)),
                  ),
                  onTap: () => Navigator.of(context).pop('edit'),
                ),
                if (_permissions.manageCrew)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.merge_type_rounded,
                      color: Color(0xFF7AA6D1),
                    ),
                    title: const Text(
                      'Merge duplicate customer',
                      style: TextStyle(color: Color(0xFFF0E5D1)),
                    ),
                    onTap: () => Navigator.of(context).pop('merge'),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (action == null || !context.mounted) {
      return;
    }
    if (action == 'edit') {
      await _openEditCustomerSheet(context: context, customer: customer);
      return;
    }
    if (action == 'merge') {
      await _openMergeCustomerSheet(context: context, sourceCustomer: customer);
    }
  }

  Future<void> _openEditCustomerSheet({
    required BuildContext context,
    required CustomerProfile customer,
  }) async {
    if (customer.uid.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only saved customers can be edited.'),
        ),
      );
      return;
    }

    final preferencesController = TextEditingController(
      text: customer.preferences.join('\n'),
    );
    final notesController = TextEditingController(text: customer.notes);
    bool saving = false;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF111111),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              Future<void> save() async {
                setModalState(() => saving = true);
                try {
                  await _customerAdminRepository.updateCustomerProfile(
                    customerUid: customer.uid,
                    preferences: preferencesController.text
                        .split('\n')
                        .map((item) => item.trim())
                        .where((item) => item.isNotEmpty)
                        .toList(),
                    notes: notesController.text.trim(),
                  );
                  if (!sheetContext.mounted) return;
                  Navigator.of(sheetContext).pop();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Customer profile updated.')),
                  );
                } catch (_) {
                  if (!sheetContext.mounted) return;
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    const SnackBar(
                      content: Text('Unable to update customer profile.'),
                    ),
                  );
                } finally {
                  if (sheetContext.mounted) {
                    setModalState(() => saving = false);
                  }
                }
              }

              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    18,
                    18,
                    18,
                    18 + MediaQuery.of(sheetContext).viewInsets.bottom,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer.name,
                          style: const TextStyle(
                            color: Color(0xFFF0E5D1),
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: preferencesController,
                          maxLines: 5,
                          style: const TextStyle(color: Color(0xFFF0E5D1)),
                          decoration: _darkFieldDecoration(
                            'Preferences, one line per item',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: notesController,
                          maxLines: 5,
                          style: const TextStyle(color: Color(0xFFF0E5D1)),
                          decoration: _darkFieldDecoration('Notes'),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: saving
                                    ? null
                                    : () => Navigator.of(sheetContext).pop(),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFF0E5D1),
                                  side: const BorderSide(
                                    color: Color(0xFF3A3A3A),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text('CLOSE'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: saving ? null : save,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFD1A45C),
                                  foregroundColor: const Color(0xFF111111),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: saving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF111111),
                                        ),
                                      )
                                    : const Text(
                                        'SAVE',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      preferencesController.dispose();
      notesController.dispose();
    }
  }

  Future<void> _openMergeCustomerSheet({
    required BuildContext context,
    required CustomerProfile sourceCustomer,
  }) async {
    if (sourceCustomer.uid.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only saved customers can be merged.')),
      );
      return;
    }
    final mergeTargets =
        liveCustomers
            .where(
              (customer) =>
                  customer.uid.trim().isNotEmpty &&
                  customer.uid.trim() != sourceCustomer.uid.trim(),
            )
            .toList()
          ..sort(
            (left, right) =>
                left.name.toLowerCase().compareTo(right.name.toLowerCase()),
          );
    if (mergeTargets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No merge target available.')),
      );
      return;
    }

    String selectedTargetUid = mergeTargets.first.uid;
    bool saving = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> merge() async {
              setModalState(() => saving = true);
              try {
                await _customerAdminRepository.mergeCustomers(
                  sourceCustomerUid: sourceCustomer.uid,
                  targetCustomerUid: selectedTargetUid,
                );
                if (!sheetContext.mounted) return;
                Navigator.of(sheetContext).pop();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Customers merged successfully.')),
                );
              } catch (_) {
                if (!sheetContext.mounted) return;
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(content: Text('Unable to merge customers.')),
                );
              } finally {
                if (sheetContext.mounted) {
                  setModalState(() => saving = false);
                }
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  18,
                  18,
                  18 + MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Merge ${sourceCustomer.name}',
                      style: const TextStyle(
                        color: Color(0xFFF0E5D1),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: selectedTargetUid,
                      dropdownColor: const Color(0xFF181818),
                      decoration: _darkFieldDecoration('Keep this customer'),
                      items: mergeTargets
                          .map(
                            (customer) => DropdownMenuItem<String>(
                              value: customer.uid,
                              child: Text(
                                customer.name,
                                style: const TextStyle(
                                  color: Color(0xFFF0E5D1),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() => selectedTargetUid = value);
                      },
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: saving
                                ? null
                                : () => Navigator.of(sheetContext).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFF0E5D1),
                              side: const BorderSide(color: Color(0xFF3A3A3A)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text('CLOSE'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: saving ? null : merge,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD1A45C),
                              foregroundColor: const Color(0xFF111111),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF111111),
                                    ),
                                  )
                                : const Text(
                                    'MERGE',
                                    style: TextStyle(fontWeight: FontWeight.w700),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _handleTabTap(int index) {
    if (index == 2 && !_permissions.viewClients) {
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('You do not have access to clients.')),
      );
      return;
    }
    if (index == 3 && !_permissions.viewStats) {
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('You do not have access to reports.')),
      );
      return;
    }
    setState(() => tabIndex = index);
  }

  void openProgramTab() {
    setState(() => tabIndex = 1);
  }

  void changeSelectedDate(int dayDelta) {
    setState(() {
      selectedDate = athensDateOnly(selectedDate.add(Duration(days: dayDelta)));
    });
  }

  Future<void> pickSelectedDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFD1A45C),
              surface: Color(0xFF151515),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) return;
    setState(() => selectedDate = athensDateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    final bookedAppointments = buildAppointmentsForDate(
      selectedDate,
      liveAppointments,
    );
    final selectedAppointments = buildHomeAppointmentsForDate(
      selectedDate: selectedDate,
      bookedAppointments: bookedAppointments,
      weeklySchedule: weeklySchedule,
      slotMinutes: slotMinutes,
    );
    final pages = [
      BarberHomePage(
        onOpenSchedule: () => openWeeklySchedule(context),
        onOpenProgram: openProgramTab,
        onOpenNotifications: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const BarberoNotificationsPage(),
            ),
          );
        },
        currentAthensTime: currentAthensTime,
        selectedDate: selectedDate,
        ownerFirstName: ownerFirstName,
        appointments: selectedAppointments,
        customerPhotoUrlForAppointment: _customerPhotoUrlForAppointment,
        onOpenCustomer: (appointment) {
          if (appointment.isBlocked || appointment.name.trim().isEmpty) {
            return;
          }
          final customer = _customerProfileForAppointment(appointment);
          openCustomerProfilePage(context, customer);
        },
        onManageAppointment: (appointment) {
          _openOwnerAppointmentActions(
            context: context,
            appointment: appointment,
          );
        },
        onQuickAddForSlot: (appointment) {
          _openQuickAddSheet(
            context,
            initialDate: selectedDate,
            initialBarberId: appointment.barberId.trim().isEmpty
                ? null
                : appointment.barberId.trim(),
            initialStartTime: appointment.time.trim(),
          );
        },
      ),
      ProgramPage(
        selectedDate: selectedDate,
        entries: buildProgramEntriesForDate(
          selectedDate: selectedDate,
          bookedAppointments: bookedAppointments,
          weeklySchedule: weeklySchedule,
        ),
        onPreviousDay: () => changeSelectedDate(-1),
        onNextDay: () => changeSelectedDate(1),
        onPickDate: () => pickSelectedDate(context),
        onQuickAdd: () => _openQuickAddSheet(context),
        customerPhotoUrlForEntry: _customerPhotoUrlForEntry,
        onOpenCustomer: (entry) {
          if (entry.blocked || entry.name.trim().isEmpty) {
            return;
          }
          final customer = _customerProfileForIdentity(
            customerUid: entry.customerUid,
            customerName: entry.name,
          );
          openCustomerProfilePage(context, customer);
        },
        onManageAppointment: (entry) {
          final appointment = liveAppointments.firstWhere(
            (item) => item.id == entry.appointmentId,
            orElse: () => Appointment(
              entry.hour,
              entry.name,
              entry.service,
              entry.duration,
              id: entry.appointmentId,
              customerUid: entry.customerUid,
              barberId: '',
              barberName: entry.barberName,
              status: entry.status,
              blocked: entry.blocked,
              blockReason: entry.blockReason,
              date:
                  '${selectedDate.year.toString().padLeft(4, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
            ),
          );
          _openOwnerAppointmentActions(
            context: context,
            appointment: appointment,
          );
        },
      ),
      CustomersListPage(
        customers: liveCustomers,
        onOpenCustomer: (customer) {
          openCustomerProfilePage(context, customer);
        },
        onManageCustomer: (customer) {
          _openCustomerActions(context: context, customer: customer);
        },
      ),
      _permissions.viewStats
          ? RevenueReportsPage(
              selectedDate: selectedDate,
              appointments: bookedAppointments,
            )
          : const PlaceholderScaffold(title: 'Access restricted'),
    ];
    final safeTabIndex = tabIndex >= pages.length ? pages.length - 1 : tabIndex;

    return Scaffold(
      body: pages[safeTabIndex],
      bottomNavigationBar: _BottomBar(
        currentIndex: safeTabIndex,
        onTap: _handleTabTap,
      ),
    );
  }

  CustomerProfile _customerProfileForAppointment(Appointment appointment) {
    return _customerProfileForIdentity(
      customerUid: appointment.customerUid,
      customerName: appointment.name,
    );
  }

  String _customerPhotoUrlForAppointment(Appointment appointment) {
    return _customerProfileForAppointment(appointment).photoUrl.trim();
  }

  String _customerPhotoUrlForEntry(ProgramEntry entry) {
    return _customerProfileForIdentity(
      customerUid: entry.customerUid,
      customerName: entry.name,
    ).photoUrl.trim();
  }

  CustomerProfile _customerProfileForIdentity({
    required String customerUid,
    required String customerName,
  }) {
    if (customerUid.trim().isNotEmpty) {
      for (final customer in liveCustomers) {
        if (customer.uid.trim() == customerUid.trim()) {
          return customer;
        }
      }
    }
    for (final customer in liveCustomers) {
      if (customer.name.trim().toLowerCase() ==
          customerName.trim().toLowerCase()) {
        return customer;
      }
    }
    return CustomerProfile(
      uid: customerUid,
      name: customerName,
      phone: _fallbackAppointmentPhone(customerUid, customerName),
      email: _fallbackAppointmentEmail(customerUid, customerName),
      photoUrl: '',
      preferences: const <String>[],
      notes: '',
      history: _buildVisitHistoryForCustomer(customerName, liveAppointments),
    );
  }

  String _fallbackAppointmentPhone(String customerUid, String customerName) {
    for (final appointment in liveAppointments) {
      if (customerUid.trim().isNotEmpty &&
          appointment.customerUid.trim() == customerUid.trim() &&
          appointment.customerPhone.trim().isNotEmpty) {
        return appointment.customerPhone.trim();
      }
      if (appointment.name.trim().toLowerCase() ==
              customerName.trim().toLowerCase() &&
          appointment.customerPhone.trim().isNotEmpty) {
        return appointment.customerPhone.trim();
      }
    }
    return '';
  }

  String _fallbackAppointmentEmail(String customerUid, String customerName) {
    for (final appointment in liveAppointments) {
      if (customerUid.trim().isNotEmpty &&
          appointment.customerUid.trim() == customerUid.trim() &&
          appointment.customerEmail.trim().isNotEmpty) {
        return appointment.customerEmail.trim();
      }
      if (appointment.name.trim().toLowerCase() ==
              customerName.trim().toLowerCase() &&
          appointment.customerEmail.trim().isNotEmpty) {
        return appointment.customerEmail.trim();
      }
    }
    return '';
  }
}

Map<String, dynamic>? _mapFromRawValue(Object? raw) {
  if (raw is Map) {
    return raw.map((key, value) => MapEntry('$key', value));
  }
  return null;
}

String _normalizeAppointmentServiceText(String raw) {
  final source = raw.trim();
  if (source.isEmpty) {
    return 'Service';
  }

  final decoded = _decodeLikelyMojibake(source).trim();
  final lower = decoded.toLowerCase();

  if (lower.contains('kids') || decoded.contains('\u03A0\u03B1\u03B9\u03B4')) {
    return 'Kids Haircut';
  }
  if (lower.contains('fade') &&
      (lower.contains('beard') ||
          decoded.contains('\u0393\u03B5\u03BD\u03B5\u03B9'))) {
    return 'Fade & Beard';
  }
  if ((lower.contains('haircut') ||
          decoded.contains('\u039A\u03BF\u03CD\u03C1\u03B5\u03BC')) &&
      (lower.contains('beard') ||
          decoded.contains('\u0393\u03B5\u03BD\u03B5\u03B9'))) {
    return 'Haircut & Beard';
  }
  if (lower.contains('beard') ||
      decoded.contains('\u0393\u03B5\u03BD\u03B5\u03B9')) {
    return 'Beard Trim';
  }
  if (lower.contains('hair styling')) {
    return 'Hair Styling';
  }
  if (lower.contains('haircut') ||
      decoded.contains('\u039A\u03BF\u03CD\u03C1\u03B5\u03BC')) {
    return 'Classic Haircut';
  }
  if (lower == 'service' ||
      decoded == '\u03A5\u03C0\u03B7\u03C1\u03B5\u03C3\u03AF\u03B1') {
    return 'Service';
  }
  if (_looksCorruptedServiceText(source) || _looksCorruptedServiceText(decoded)) {
    return 'Service';
  }
  return decoded;
}

String _serviceLabelForKey(String key) {
  switch (key.trim()) {
    case 'classic_haircut':
      return 'Classic Haircut';
    case 'beard_trim':
      return 'Beard Trim';
    case 'haircut_and_beard':
      return 'Haircut & Beard';
    case 'fade_and_beard':
      return 'Fade & Beard';
    case 'kids_haircut':
      return 'Kids Haircut';
    default:
      final normalized = key.trim().replaceAll('_', ' ');
      if (normalized.isEmpty) {
        return 'Appointment';
      }
      return normalized
          .split(' ')
          .where((part) => part.isNotEmpty)
          .map(
            (part) =>
                '${part[0].toUpperCase()}${part.length > 1 ? part.substring(1) : ''}',
          )
          .join(' ');
    }
}

String _appointmentServiceLabelFromRaw(Map<String, dynamic> value) {
  final serviceKeys =
      (value['serviceKeys'] as List?)?.map((item) => '$item'.trim()).toList() ??
      const <String>[];
  final filteredServiceKeys =
      serviceKeys.where((item) => item.isNotEmpty).toList();
  if (filteredServiceKeys.isNotEmpty) {
    return filteredServiceKeys.map(_serviceLabelForKey).join(' + ');
  }

  final services =
      (value['services'] as List?)?.map((item) => '$item'.trim()).toList() ??
      const <String>[];
  final filteredServices = services.where((item) => item.isNotEmpty).toList();
  if (filteredServices.isNotEmpty) {
    return _normalizeAppointmentServiceText(filteredServices.join(' + '));
  }

  final singleService = '${value['service'] ?? ''}'.trim();
  if (singleService.isNotEmpty) {
    return _normalizeAppointmentServiceText(singleService);
  }

  return 'Appointment';
}

String _decodeLikelyMojibake(String value) {
  if (!value.contains('\u039E') &&
      !value.contains('\u00CE') &&
      !value.contains('\u00C3')) {
    return value;
  }
  try {
    return utf8.decode(latin1.encode(value));
  } catch (_) {
    return value;
  }
}

bool _looksCorruptedServiceText(String value) {
  for (final rune in value.runes) {
    if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0x3400 && rune <= 0x4DBF)) {
      return true;
    }
  }
  return value.contains('\u039E') || value.contains('\uFFFD');
}

WeeklyScheduleData _parseWeeklyScheduleFromShop(Map<String, dynamic> shopData) {
  final schedule =
      _mapFromRawValue(shopData['weekly_schedule']) ?? <String, dynamic>{};
  final rawDays =
      (schedule['days'] as List?)
          ?.whereType<Map>()
          .map((item) => ScheduleDay.fromJson(Map<String, dynamic>.from(item)))
          .toList() ??
      buildDefaultWeeklySchedule();
  final normalizedDays = rawDays.asMap().entries.map((entry) {
    return entry.value.copyWith(name: scheduleDayNameForIndex(entry.key));
  }).toList();

  return WeeklyScheduleData(
    slotMinutes: (schedule['slotMinutes'] as num?)?.toInt() ?? 30,
    appointmentsPerSlot:
        (schedule['appointmentsPerSlot'] as num?)?.toInt() ?? 1,
    showPrices: schedule['showPrices'] == true,
    serviceDurations: buildDefaultServiceDurations(),
    servicePrices: buildDefaultServicePrices(),
    days: normalizedDays,
  );
}

List<Appointment> _parseAppointmentsFromShop(Map<String, dynamic> shopData) {
  final rawAppointments =
      _mapFromRawValue(shopData['appointments']) ?? <String, dynamic>{};
  final appointments = <Appointment>[];

  for (final entry in rawAppointments.entries) {
    final value = _mapFromRawValue(entry.value);
    if (value == null) continue;
    final totalMinutes = (value['totalMinutes'] as num?)?.toInt() ?? 0;
    final totalPrice = (value['totalPrice'] as num?)?.toInt() ?? 0;
    appointments.add(
      Appointment(
        '${value['time'] ?? ''}',
        '${value['customerName'] ?? ''}',
        _appointmentServiceLabelFromRaw(value),
        "${totalMinutes > 0 ? totalMinutes : 0}'",
        id: entry.key,
        customerUid: '${value['customerUid'] ?? ''}',
        customerPhone: '${value['customerPhone'] ?? ''}',
        customerEmail: '${value['customerEmail'] ?? ''}',
        date: '${value['date'] ?? ''}',
        barberId: '${value['barberId'] ?? ''}',
        barberName: '${value['barberName'] ?? ''}',
        status: '${value['status'] ?? 'confirmed'}'.trim(),
        blocked: value['blocked'] == true,
        blockReason: '${value['blockReason'] ?? ''}'.trim(),
        priceOverride: totalPrice,
        minutesOverride: totalMinutes,
      ),
    );
  }

  appointments.sort((left, right) {
    final dateCompare = left.date.compareTo(right.date);
    if (dateCompare != 0) return dateCompare;
    return _parseClockValue(left.time).compareTo(_parseClockValue(right.time));
  });
  return appointments;
}

List<CustomerProfile> _parseCustomersFromShop(
  Map<String, dynamic> shopData,
  List<Appointment> appointments,
) {
  final rawCustomers =
      _mapFromRawValue(shopData['customers']) ?? <String, dynamic>{};
  final profilesByName = <String, CustomerProfile>{};

  for (final entry in rawCustomers.entries) {
    final value = _mapFromRawValue(entry.value);
    if (value == null) continue;
    final fullName = '${value['fullName'] ?? value['name'] ?? ''}'.trim();
    if (fullName.isEmpty) continue;
    final key = fullName.toLowerCase();
    profilesByName[key] = CustomerProfile(
      uid: entry.key,
      name: fullName,
      phone: '${value['phone'] ?? ''}'.trim(),
      email: '${value['email'] ?? ''}'.trim(),
      photoUrl: '${value['photoUrl'] ?? ''}'.trim(),
      preferences: _customerPreferencesFromRaw(value['preferences']),
      notes: '${value['notes'] ?? ''}'.trim(),
      history: _buildVisitHistoryForCustomer(fullName, appointments),
    );
  }

  for (final appointment in appointments) {
    if (appointment.isBlocked) {
      continue;
    }
    final fullName = appointment.name.trim();
    if (fullName.isEmpty) continue;
    final key = fullName.toLowerCase();
    profilesByName.putIfAbsent(
      key,
      () => CustomerProfile(
        uid: appointment.customerUid,
        name: fullName,
        phone: appointment.customerPhone.trim(),
        email: appointment.customerEmail.trim(),
        photoUrl: '',
        preferences: const <String>[],
        notes: '',
        history: _buildVisitHistoryForCustomer(fullName, appointments),
      ),
    );
  }

  final customers = profilesByName.values.toList()
    ..sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
  return customers;
}

List<String> _customerPreferencesFromRaw(dynamic raw) {
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

List<VisitRecord> _buildVisitHistoryForCustomer(
  String customerName,
  List<Appointment> appointments,
) {
  final customerAppointments =
      appointments
          .where(
            (appointment) =>
                !appointment.isBlocked &&
                appointment.name.trim().toLowerCase() ==
                customerName.trim().toLowerCase(),
          )
          .toList()
        ..sort((left, right) {
          final dateCompare = right.date.compareTo(left.date);
          if (dateCompare != 0) return dateCompare;
          return _parseClockValue(
            right.time,
          ).compareTo(_parseClockValue(left.time));
        });

  return customerAppointments
      .map(
        (appointment) => VisitRecord(
          date: appointment.date,
          service: appointment.service,
          price: appointment.price,
        ),
      )
      .toList();
}

class PlaceholderScaffold extends StatelessWidget {
  const PlaceholderScaffold({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF121212), Color(0xFF090909)],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  const AppHamburgerMenu(),
                  const Spacer(),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF2E3C8),
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 22),
                ],
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );
  }
}

class RevenueReportsPage extends StatefulWidget {
  const RevenueReportsPage({
    super.key,
    required this.selectedDate,
    required this.appointments,
  });

  final DateTime selectedDate;
  final List<Appointment> appointments;

  @override
  State<RevenueReportsPage> createState() => _RevenueReportsPageState();
}

enum _RevenuePeriod { day, month, year }

class _RevenueReportsPageState extends State<RevenueReportsPage> {
  _RevenuePeriod _period = _RevenuePeriod.day;

  @override
  Widget build(BuildContext context) {
    final periodAppointments = _appointmentsForPeriod(
      period: _period,
      selectedDate: widget.selectedDate,
      appointments: widget.appointments,
    );
    final summary = _buildRevenueSummary(periodAppointments);
    final rows = _buildRevenueRows(periodAppointments);
    final serviceRows = _buildServiceRows(periodAppointments);
    final barberCategoryRows = _buildBarberCategoryRows(periodAppointments);
    final periodLabel = _periodLabel(_period, widget.selectedDate);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF121212), Color(0xFF090909)],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const AppHamburgerMenu(),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reports',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.4,
                            color: Color(0xFFF5F5F2),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Owner analytics overview',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D0E),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF171719)),
                ),
                child: Row(
                  children: [
                    _ReportsPeriodButton(
                      label: 'Day',
                      selected: _period == _RevenuePeriod.day,
                      onTap: () => setState(() => _period = _RevenuePeriod.day),
                    ),
                    _ReportsPeriodButton(
                      label: 'Month',
                      selected: _period == _RevenuePeriod.month,
                      onTap: () =>
                          setState(() => _period = _RevenuePeriod.month),
                    ),
                    _ReportsPeriodButton(
                      label: 'Year',
                      selected: _period == _RevenuePeriod.year,
                      onTap: () => setState(() => _period = _RevenuePeriod.year),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _RevenueHeroCard(
                      periodLabel: periodLabel,
                      summary: summary,
                    ),
                    const SizedBox(height: 18),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.5,
                      children: [
                        _ReportsMetricCard(
                          label: 'Appointments',
                          value: '${summary.totalAppointments}',
                        ),
                        _ReportsMetricCard(
                          label: 'Completed',
                          value: '${summary.completedAppointments}',
                        ),
                        _ReportsMetricCard(
                          label: 'Estimated',
                          value: 'EUR ${summary.estimatedRevenue}',
                        ),
                        _ReportsMetricCard(
                          label: 'Actual',
                          value: 'EUR ${summary.actualRevenue}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _RevenueStatusCard(summary: summary),
                    const SizedBox(height: 18),
                    _RevenueSection(
                      title: 'Barber performance',
                      subtitle: periodLabel,
                      rows: rows,
                    ),
                    const SizedBox(height: 18),
                    _ServiceMixSection(
                      subtitle: periodLabel,
                      rows: serviceRows,
                    ),
                    const SizedBox(height: 18),
                    _BarberCategorySection(
                      subtitle: periodLabel,
                      rows: barberCategoryRows,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RevenueSection extends StatelessWidget {
  const _RevenueSection({
    required this.title,
    required this.subtitle,
    required this.rows,
  });

  final String title;
  final String subtitle;
  final List<_BarberRevenueRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF111214),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1A1B1E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFF5F5F2),
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF8E8E93),
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            const Text(
              'No report data for this period.',
              style: TextStyle(color: Color(0xFFBFB7AA), fontSize: 12.5),
            )
          else
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RevenueRowCard(row: row),
              ),
            ),
        ],
      ),
    );
  }
}

class _RevenueRowCard extends StatelessWidget {
  const _RevenueRowCard({required this.row});

  final _BarberRevenueRow row;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF17181A),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.barberName,
                  style: const TextStyle(
                    color: Color(0xFFF5F5F2),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Text(
                'EUR ${row.actualRevenue}',
                style: const TextStyle(
                  color: Color(0xFFF5F5F2),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _InlineMetricRow(
            label: 'Booked appointments',
            value: '${row.bookedAppointments}',
          ),
          _InlineMetricRow(
            label: 'Completed appointments',
            value: '${row.completedAppointments}',
          ),
          _InlineMetricRow(
            label: 'Estimated revenue',
            value: 'EUR ${row.estimatedRevenue}',
          ),
          _InlineMetricRow(
            label: 'Actual revenue',
            value: 'EUR ${row.actualRevenue}',
          ),
          if (row.cancelledAppointments > 0)
            _InlineMetricRow(
              label: 'Cancelled appointments',
              value: '${row.cancelledAppointments}',
            ),
          if (row.noShowAppointments > 0)
            _InlineMetricRow(
              label: 'No-show appointments',
              value: '${row.noShowAppointments}',
            ),
        ],
      ),
    );
  }
}

class _RevenueHeroCard extends StatelessWidget {
  const _RevenueHeroCard({
    required this.periodLabel,
    required this.summary,
  });

  final String periodLabel;
  final _RevenueSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF141517),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF1B1C1F)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            periodLabel,
            style: const TextStyle(
              color: Color(0xFF8E8E93),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Store overview',
            style: TextStyle(
              color: Color(0xFFF5F5F2),
              fontSize: 26,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            summary.totalAppointments > 0
                ? '${summary.totalAppointments} appointments tracked for this period. Completed revenue is EUR ${summary.actualRevenue} out of an estimated EUR ${summary.estimatedRevenue}.'
                : 'No appointments have been tracked for this period yet.',
            style: const TextStyle(
              color: Color(0xFFB3B3B8),
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportsMetricCard extends StatelessWidget {
  const _ReportsMetricCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF141517),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF1B1C1F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8E8E93),
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFF5F5F2),
              fontSize: 24,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _RevenueStatusCard extends StatelessWidget {
  const _RevenueStatusCard({required this.summary});

  final _RevenueSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF111214),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1A1B1E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Appointment flow',
            style: TextStyle(
              color: Color(0xFFF5F5F2),
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 14),
          _InlineMetricRow(
            label: 'Pending appointments',
            value: '${summary.pendingAppointments}',
          ),
          _InlineMetricRow(
            label: 'Confirmed appointments',
            value: '${summary.confirmedAppointments}',
          ),
          _InlineMetricRow(
            label: 'Completed appointments',
            value: '${summary.completedAppointments}',
          ),
          _InlineMetricRow(
            label: 'Cancelled appointments',
            value: '${summary.cancelledAppointments}',
          ),
          _InlineMetricRow(
            label: 'No-show appointments',
            value: '${summary.noShowAppointments}',
          ),
        ],
      ),
    );
  }
}

class _InlineMetricRow extends StatelessWidget {
  const _InlineMetricRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFF5F5F2),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportsPeriodButton extends StatelessWidget {
  const _ReportsPeriodButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFFF4F4F0)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF111111)
                    : const Color(0xFF8E8E93),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarberRevenueRow {
  const _BarberRevenueRow({
    required this.barberName,
    required this.estimatedRevenue,
    required this.actualRevenue,
    required this.bookedAppointments,
    required this.completedAppointments,
    required this.cancelledAppointments,
    required this.noShowAppointments,
  });

  final String barberName;
  final int estimatedRevenue;
  final int actualRevenue;
  final int bookedAppointments;
  final int completedAppointments;
  final int cancelledAppointments;
  final int noShowAppointments;
}

List<_BarberRevenueRow> _buildRevenueRows(Iterable<Appointment> appointments) {
  final map = <String, _BarberRevenueRow>{};
  for (final appointment in appointments) {
    final barberName = appointment.barberName.trim().isEmpty
        ? 'Unassigned Barber'
        : appointment.barberName.trim();
    final current = map[barberName];
    final isEstimated =
        !appointment.isBlocked &&
        !appointment.isCancelled &&
        !appointment.isNoShow;
    map[barberName] = _BarberRevenueRow(
      barberName: barberName,
      estimatedRevenue:
          (current?.estimatedRevenue ?? 0) + (isEstimated ? appointment.price : 0),
      actualRevenue:
          (current?.actualRevenue ?? 0) + (appointment.isCompleted ? appointment.price : 0),
      bookedAppointments:
          (current?.bookedAppointments ?? 0) + (isEstimated ? 1 : 0),
      completedAppointments:
          (current?.completedAppointments ?? 0) + (appointment.isCompleted ? 1 : 0),
      cancelledAppointments:
          (current?.cancelledAppointments ?? 0) + (appointment.isCancelled ? 1 : 0),
      noShowAppointments:
          (current?.noShowAppointments ?? 0) + (appointment.isNoShow ? 1 : 0),
    );
  }
  final rows = map.values.toList()
    ..sort((left, right) {
      final actualCompare = right.actualRevenue.compareTo(left.actualRevenue);
      if (actualCompare != 0) {
        return actualCompare;
      }
      return right.estimatedRevenue.compareTo(left.estimatedRevenue);
    });
  return rows;
}

class _RevenueSummary {
  const _RevenueSummary({
    required this.totalAppointments,
    required this.estimatedRevenue,
    required this.actualRevenue,
    required this.pendingAppointments,
    required this.confirmedAppointments,
    required this.completedAppointments,
    required this.cancelledAppointments,
    required this.noShowAppointments,
  });

  final int totalAppointments;
  final int estimatedRevenue;
  final int actualRevenue;
  final int pendingAppointments;
  final int confirmedAppointments;
  final int completedAppointments;
  final int cancelledAppointments;
  final int noShowAppointments;
}

_RevenueSummary _buildRevenueSummary(Iterable<Appointment> appointments) {
  var totalAppointments = 0;
  var estimatedRevenue = 0;
  var actualRevenue = 0;
  var pendingAppointments = 0;
  var confirmedAppointments = 0;
  var completedAppointments = 0;
  var cancelledAppointments = 0;
  var noShowAppointments = 0;

  for (final appointment in appointments) {
    if (!appointment.isBlocked) {
      totalAppointments += 1;
    }
    if (!appointment.isBlocked &&
        !appointment.isCancelled &&
        !appointment.isNoShow) {
      estimatedRevenue += appointment.price;
    }
    if (appointment.isCompleted) {
      actualRevenue += appointment.price;
      completedAppointments += 1;
    } else if (appointment.isPending) {
      pendingAppointments += 1;
    } else if (appointment.isConfirmed) {
      confirmedAppointments += 1;
    } else if (appointment.isCancelled) {
      cancelledAppointments += 1;
    } else if (appointment.isNoShow) {
      noShowAppointments += 1;
    }
  }

  return _RevenueSummary(
    totalAppointments: totalAppointments,
    estimatedRevenue: estimatedRevenue,
    actualRevenue: actualRevenue,
    pendingAppointments: pendingAppointments,
    confirmedAppointments: confirmedAppointments,
    completedAppointments: completedAppointments,
    cancelledAppointments: cancelledAppointments,
    noShowAppointments: noShowAppointments,
  );
}

List<Appointment> _appointmentsForPeriod({
  required _RevenuePeriod period,
  required DateTime selectedDate,
  required List<Appointment> appointments,
}) {
  return appointments.where((appointment) {
    switch (period) {
      case _RevenuePeriod.day:
        return appointment.date == _dateKey(selectedDate);
      case _RevenuePeriod.month:
        return appointment.date.startsWith(_monthKey(selectedDate));
      case _RevenuePeriod.year:
        return appointment.date.startsWith('${selectedDate.year}-');
    }
  }).toList(growable: false);
}

String _periodLabel(_RevenuePeriod period, DateTime selectedDate) {
  switch (period) {
    case _RevenuePeriod.day:
      return greekDateLabel(selectedDate);
    case _RevenuePeriod.month:
      return _greekMonthYearLabel(selectedDate);
    case _RevenuePeriod.year:
      return '${selectedDate.year}';
  }
}

class _ServiceReportRow {
  const _ServiceReportRow({
    required this.label,
    required this.count,
    required this.completedCount,
    required this.estimatedRevenue,
    required this.actualRevenue,
  });

  final String label;
  final int count;
  final int completedCount;
  final int estimatedRevenue;
  final int actualRevenue;
}

class _BarberCategoryRow {
  const _BarberCategoryRow({
    required this.barberName,
    required this.services,
  });

  final String barberName;
  final List<_ServiceReportRow> services;
}

List<_ServiceReportRow> _buildServiceRows(Iterable<Appointment> appointments) {
  final map = <String, _ServiceReportRow>{};
  for (final appointment in appointments) {
    if (appointment.isBlocked) {
      continue;
    }
    final label = _reportServiceLabel(appointment.service);
    final current = map[label];
    final isEstimated = !appointment.isCancelled && !appointment.isNoShow;
    map[label] = _ServiceReportRow(
      label: label,
      count: (current?.count ?? 0) + (isEstimated ? 1 : 0),
      completedCount:
          (current?.completedCount ?? 0) + (appointment.isCompleted ? 1 : 0),
      estimatedRevenue:
          (current?.estimatedRevenue ?? 0) + (isEstimated ? appointment.price : 0),
      actualRevenue:
          (current?.actualRevenue ?? 0) + (appointment.isCompleted ? appointment.price : 0),
    );
  }
  final rows = map.values.toList()
    ..sort((left, right) => right.count.compareTo(left.count));
  return rows;
}

List<_BarberCategoryRow> _buildBarberCategoryRows(
  Iterable<Appointment> appointments,
) {
  final grouped = <String, List<Appointment>>{};
  for (final appointment in appointments) {
    if (appointment.isBlocked) {
      continue;
    }
    final barberName = appointment.barberName.trim().isEmpty
        ? 'Unassigned Barber'
        : appointment.barberName.trim();
    grouped.putIfAbsent(barberName, () => <Appointment>[]).add(appointment);
  }
  final rows =
      grouped.entries
          .map(
            (entry) => _BarberCategoryRow(
              barberName: entry.key,
              services: _buildServiceRows(entry.value),
            ),
          )
          .toList()
        ..sort((left, right) => left.barberName.compareTo(right.barberName));
  return rows;
}

String _reportServiceLabel(String raw) {
  final value = raw.trim();
  switch (value) {
    case 'Classic Haircut':
      return 'Haircut';
    case 'Beard Trim':
      return 'Beard';
    case 'Kids Haircut':
      return 'Kids haircut';
    case 'Haircut & Beard':
      return 'Haircut and beard';
    case 'Fade & Beard':
      return 'Fade and beard';
    default:
      return value.isEmpty ? 'Other service' : value;
  }
}

class _ServiceMixSection extends StatelessWidget {
  const _ServiceMixSection({
    required this.subtitle,
    required this.rows,
  });

  final String subtitle;
  final List<_ServiceReportRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF111214),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1A1B1E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Service mix',
            style: TextStyle(
              color: Color(0xFFF5F5F2),
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF8E8E93),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            const Text(
              'No service activity yet.',
              style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12.5),
            )
          else
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ServiceMixRow(row: row),
              ),
            ),
        ],
      ),
    );
  }
}

class _ServiceMixRow extends StatelessWidget {
  const _ServiceMixRow({required this.row});

  final _ServiceReportRow row;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF17181A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.label,
                  style: const TextStyle(
                    color: Color(0xFFF5F5F2),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Text(
                '${row.count} appointments',
                style: const TextStyle(
                  color: Color(0xFF8E8E93),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InlineMetricRow(
            label: 'Completed appointments',
            value: '${row.completedCount}',
          ),
          _InlineMetricRow(
            label: 'Estimated revenue',
            value: 'EUR ${row.estimatedRevenue}',
          ),
          _InlineMetricRow(
            label: 'Actual revenue',
            value: 'EUR ${row.actualRevenue}',
          ),
        ],
      ),
    );
  }
}

class _BarberCategorySection extends StatelessWidget {
  const _BarberCategorySection({
    required this.subtitle,
    required this.rows,
  });

  final String subtitle;
  final List<_BarberCategoryRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF111214),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1A1B1E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Barber by category',
            style: TextStyle(
              color: Color(0xFFF5F5F2),
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF8E8E93),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            const Text(
              'No barber category activity yet.',
              style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12.5),
            )
          else
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _BarberCategoryCard(row: row),
              ),
            ),
        ],
      ),
    );
  }
}

class _BarberCategoryCard extends StatelessWidget {
  const _BarberCategoryCard({required this.row});

  final _BarberCategoryRow row;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF17181A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.barberName,
            style: const TextStyle(
              color: Color(0xFFF5F5F2),
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 14),
          if (row.services.isEmpty)
            const Text(
              'No category data for this barber.',
              style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
            )
          else
            ...row.services.take(4).map(
              (service) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _InlineMetricRow(
                  label: '${service.label} (${service.count})',
                  value: 'EUR ${service.actualRevenue}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _dateKey(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

String _monthKey(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}';
}

String _greekMonthYearLabel(DateTime value) {
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
  return '${months[value.month - 1]} ${value.year}';
}

class AppHamburgerMenu extends StatelessWidget {
  const AppHamburgerMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showAppSideMenu(context),
        child: const SizedBox(
          width: 46,
          height: 46,
          child: Center(
            child: Icon(
              Icons.menu_rounded,
              color: Color(0xFFD1A45C),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _openBarberoMenuPage(BuildContext context, Widget page) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _ReturnToHomeOnBack(child: page),
    ),
  );
}

class _ReturnToHomeOnBack extends StatelessWidget {
  const _ReturnToHomeOnBack({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        Navigator.of(context).popUntil((route) => route.isFirst);
      },
      child: child,
    );
  }
}

Future<void> showAppSideMenu(BuildContext context) async {
  await showGeneralDialog<void>(
    context: context,
    barrierLabel: 'Menu',
    barrierDismissible: true,
    barrierColor: const Color(0x88000000),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (context, animation, secondaryAnimation) {
      return const _AppSideMenuSheet();
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final offsetAnimation = Tween<Offset>(
        begin: const Offset(-1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

      return SlideTransition(
        position: offsetAnimation,
        child: FadeTransition(opacity: animation, child: child),
      );
    },
  );
}

Future<void> _openBarberoDeleteAccountFlow(BuildContext context) async {
  final session = currentBarberoSession.value;
  final user = FirebaseAuth.instance.currentUser;
  if (session == null || user == null) {
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      const SnackBar(content: Text('No active Barbero account found.')),
    );
    return;
  }

  final isOwner = session.isOwner;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: const Color(0xFF171717),
        title: const Text(
          'Delete account',
          style: TextStyle(color: Color(0xFFF2E3C8)),
        ),
        content: Text(
          isOwner
              ? 'This will permanently remove your Barbero owner account from active use and delete the entire live shop workspace, including barbers, customers, appointments, schedules, reports, and settings. A restricted deleted archive may be kept for security, recovery review, legal compliance, or audit purposes. Do you want to continue?'
              : 'This will permanently delete your Barbero login access for this shop. Your live access will be removed immediately. Limited historical operational records may remain in the shop for appointment history, reporting integrity, security, or legal reasons. Do you want to continue?',
          style: const TextStyle(
            color: Color(0xFFE8DCC9),
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8A1F1F),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete account'),
          ),
        ],
      );
    },
  );

  if (confirmed != true) {
    return;
  }

  try {
    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse(
        'https://europe-west1-barbero-88d00.cloudfunctions.net/barberoDeleteAccount',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
        'shopId': session.shopId,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('barbero-delete-account-failed');
    }
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          isOwner
              ? 'The live shop account has been deleted.'
              : 'Your Barbero account has been deleted.',
        ),
      ),
    );
    await FirebaseAuth.instance.signOut();
  } catch (_) {
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      const SnackBar(content: Text('Unable to delete this account.')),
    );
  }
}

class _AppSideMenuSheet extends StatelessWidget {
  const _AppSideMenuSheet();

  @override
  Widget build(BuildContext context) {
    final session = currentBarberoSession.value;
    final permissions = session?.permissions;
    return Material(
      color: Colors.transparent,
      child: Row(
        children: [
          Dismissible(
            key: const ValueKey('app-side-menu'),
            direction: DismissDirection.endToStart,
            resizeDuration: null,
            onDismissed: (_) => Navigator.of(context).pop(),
            child: Container(
              width: 280,
              height: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF151515), Color(0xFF0D0D0D)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 30,
                    offset: Offset(6, 0),
                  ),
                ],
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.menu_rounded,
                            color: Color(0xFFD1A45C),
                            size: 22,
                          ),
                          SizedBox(width: 10),
                          Text(
                            '\u039c\u0395\u039d\u039f\u03a5',
                            style: TextStyle(
                              fontSize: 12,
                              letterSpacing: 1.3,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFD1A45C),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      if (permissions?.manageCrew == true) ...[
                        _SideMenuItem(
                          icon: Icons.groups_rounded,
                          label: 'Barbers',
                          onTap: () {
                            Navigator.of(context).pop();
                            _openBarberoMenuPage(
                              context,
                              const CrewManagementPage(),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        _SideMenuItem(
                          icon: Icons.admin_panel_settings_outlined,
                          label: 'Admin tools',
                          onTap: () {
                            Navigator.of(context).pop();
                            _openBarberoMenuPage(
                              context,
                              const AdminToolsPage(),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (permissions?.editSchedule == true) ...[
                        _SideMenuItem(
                          icon: Icons.schedule_rounded,
                          label:
                              '\u0395\u03b2\u03b4\u03bf\u03bc\u03b1\u03b4\u03b9\u03b1\u03af\u03bf \u03c0\u03c1\u03cc\u03b3\u03c1\u03b1\u03bc\u03bc\u03b1',
                          onTap: () {
                            Navigator.of(context).pop();
                            _openBarberoMenuPage(
                              context,
                              const WeeklySchedulePage(),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        _SideMenuItem(
                          icon: Icons.tune_rounded,
                          label:
                              '\u0394\u03b9\u03b1\u03c1\u03ba\u03b5\u03af\u03b5\u03c2 \u03c5\u03c0\u03b7\u03c1\u03b5\u03c3\u03b9\u03ce\u03bd',
                          onTap: () {
                            Navigator.of(context).pop();
                            _openBarberoMenuPage(
                              context,
                              const ServiceDurationsPage(),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        _SideMenuItem(
                          icon: Icons.groups_rounded,
                          label:
                              '\u03a1\u03b1\u03bd\u03c4\u03b5\u03b2\u03bf\u03cd \u03b1\u03bd\u03ac slot',
                          onTap: () {
                            Navigator.of(context).pop();
                            _openBarberoMenuPage(
                              context,
                              const AppointmentsPerSlotPage(),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (permissions?.editPrices == true) ...[
                        _SideMenuItem(
                          icon: Icons.euro_rounded,
                          label:
                              '\u03a4\u03b9\u03bc\u03ad\u03c2 \u03c5\u03c0\u03b7\u03c1\u03b5\u03c3\u03b9\u03ce\u03bd',
                          onTap: () {
                            Navigator.of(context).pop();
                            _openBarberoMenuPage(
                              context,
                              const ServicePricesPage(),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (session?.isOwner == true) ...[
                        _SideMenuItem(
                          icon: Icons.workspace_premium_outlined,
                          label: 'Subscription',
                          onTap: () {
                            Navigator.of(context).pop();
                            _openBarberoMenuPage(
                              context,
                              const BarberoBillingPage(),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                      _SideMenuItem(
                        icon: Icons.privacy_tip_outlined,
                        label: 'Privacy Policy',
                        onTap: () {
                          Navigator.of(context).pop();
                          _openBarberoMenuPage(
                            context,
                            const BarberoPrivacyPolicyPage(),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      _SideMenuItem(
                        icon: Icons.gavel_rounded,
                        label: 'Terms & Conditions',
                        onTap: () {
                          Navigator.of(context).pop();
                          _openBarberoMenuPage(
                            context,
                            const BarberoTermsPage(),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      _SideMenuItem(
                        icon: Icons.logout_rounded,
                        label: 'Logout',
                        onTap: () async {
                          Navigator.of(context).pop();
                          await FirebaseAuth.instance.signOut();
                        },
                      ),
                      const Spacer(),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () async {
                            final dialogContext =
                                rootScaffoldMessengerKey.currentContext ??
                                context;
                            Navigator.of(context).pop();
                            await _openBarberoDeleteAccountFlow(dialogContext);
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A1212),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFF6B2A2A)),
                            ),
                            child: const Text(
                              'Delete account',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFFFD6D6),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SideMenuItem extends StatelessWidget {
  const _SideMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2A2A2A)),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFFD1A45C), size: 18),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFF2E3C8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OwnerRescheduleSheet extends StatefulWidget {
  const _OwnerRescheduleSheet({
    required this.appointment,
    required this.barbers,
    required this.initialBarber,
    required this.onLoadSlots,
    required this.onSave,
  });

  final Appointment appointment;
  final List<CrewMember> barbers;
  final CrewMember initialBarber;
  final Future<List<String>> Function({
    required String barberId,
    required DateTime date,
    required int requiredMinutes,
  }) onLoadSlots;
  final Future<void> Function({
    required String barberId,
    required String barberName,
    required DateTime date,
    required String startTime,
  }) onSave;

  @override
  State<_OwnerRescheduleSheet> createState() => _OwnerRescheduleSheetState();
}

class _OwnerRescheduleSheetState extends State<_OwnerRescheduleSheet> {
  late CrewMember _selectedBarber;
  late DateTime _selectedDate;
  String? _selectedTime;
  List<String> _slots = const <String>[];
  bool _loadingSlots = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedBarber = widget.initialBarber;
    _selectedDate = DateTime.parse(widget.appointment.date);
    _selectedTime = widget.appointment.time;
    _loadSlots();
  }

  Future<void> _loadSlots() async {
    setState(() => _loadingSlots = true);
    final slots = await widget.onLoadSlots(
      barberId: _selectedBarber.id,
      date: _selectedDate,
      requiredMinutes: widget.appointment.minutes,
    );
    if (!mounted) return;
    setState(() {
      _slots = slots;
      if (!_slots.contains(_selectedTime)) {
        _selectedTime = _slots.isNotEmpty ? _slots.first : null;
      }
      _loadingSlots = false;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFD1A45C),
              surface: Color(0xFF151515),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) return;
    setState(() {
      _selectedDate = athensDateOnly(picked);
      _selectedTime = null;
    });
    await _loadSlots();
  }

  Future<void> _save() async {
    final time = _selectedTime;
    if (time == null) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        barberId: _selectedBarber.id,
        barberName: _selectedBarber.fullName,
        date: _selectedDate,
        startTime: time,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to reschedule appointment.')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          18,
          18,
          18 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Reschedule appointment',
                style: TextStyle(
                  color: Color(0xFFF0E5D1),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.appointment.name,
                style: const TextStyle(
                  color: Color(0xFFBFB7AA),
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Barber',
                style: TextStyle(
                  color: Color(0xFFF0E5D1),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.barbers.map((barber) {
                  final selected = barber.id == _selectedBarber.id;
                  return ChoiceChip(
                    label: Text(barber.fullName),
                    selected: selected,
                    onSelected: _saving
                        ? null
                        : (_) async {
                            setState(() {
                              _selectedBarber = barber;
                              _selectedTime = null;
                            });
                            await _loadSlots();
                          },
                    selectedColor: const Color(0xFFD1A45C),
                    backgroundColor: const Color(0xFF171717),
                    labelStyle: TextStyle(
                      color: selected
                          ? const Color(0xFF111111)
                          : const Color(0xFFF0E5D1),
                      fontWeight: FontWeight.w600,
                    ),
                    side: const BorderSide(color: Color(0xFF3A3127)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              const Text(
                'Date',
                style: TextStyle(
                  color: Color(0xFFF0E5D1),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _saving ? null : _pickDate,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF171717),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2D251C)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        color: Color(0xFFD1A45C),
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        greekDateLabel(_selectedDate),
                        style: const TextStyle(
                          color: Color(0xFFF0E5D1),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Available times',
                style: TextStyle(
                  color: Color(0xFFF0E5D1),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              if (_loadingSlots)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: CircularProgressIndicator(color: Color(0xFFD1A45C)),
                  ),
                )
              else if (_slots.isEmpty)
                const Text(
                  'No available slots for this date.',
                  style: TextStyle(color: Color(0xFFBFB7AA)),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _slots.map((slot) {
                    final selected = slot == _selectedTime;
                    return ChoiceChip(
                      label: Text(slot),
                      selected: selected,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _selectedTime = slot),
                      selectedColor: const Color(0xFFD1A45C),
                      backgroundColor: const Color(0xFF171717),
                      labelStyle: TextStyle(
                        color: selected
                            ? const Color(0xFF111111)
                            : const Color(0xFFF0E5D1),
                        fontWeight: FontWeight.w700,
                      ),
                      side: const BorderSide(color: Color(0xFF3A3127)),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF3A3127)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        foregroundColor: const Color(0xFFF0E5D1),
                      ),
                      child: const Text('CLOSE'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saving || _selectedTime == null ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD1A45C),
                        foregroundColor: const Color(0xFF111111),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF111111),
                              ),
                            )
                          : const Text(
                              'SAVE',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAddAppointmentSheet extends StatefulWidget {
  const _QuickAddAppointmentSheet({
    required this.selectedDate,
    required this.barbers,
    required this.serviceDurations,
    required this.servicePrices,
    required this.slotMinutes,
    this.initialBarberId,
    this.initialStartTime,
    required this.onLoadSlots,
    required this.onSave,
  });

  final DateTime selectedDate;
  final List<CrewMember> barbers;
  final List<ServiceDurationSetting> serviceDurations;
  final List<ServicePriceSetting> servicePrices;
  final int slotMinutes;
  final String? initialBarberId;
  final String? initialStartTime;
  final Future<List<String>> Function({
    required String barberId,
    required DateTime date,
    required int requiredMinutes,
  })
  onLoadSlots;
  final Future<void> Function({
    required String barberId,
    required String customerName,
    required String customerPhone,
    required String customerEmail,
    required DateTime date,
    required String startTime,
    required int totalMinutes,
    required int totalPrice,
    required bool blocked,
    required String serviceKey,
    required String serviceLabel,
    required String blockReason,
  })
  onSave;

  @override
  State<_QuickAddAppointmentSheet> createState() =>
      _QuickAddAppointmentSheetState();
}

class _QuickAddAppointmentSheetState extends State<_QuickAddAppointmentSheet> {
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerPhoneController = TextEditingController();
  final TextEditingController _customerEmailController = TextEditingController();
  final TextEditingController _blockReasonController = TextEditingController();
  bool _blocked = false;
  bool _loadingSlots = false;
  bool _saving = false;
  late CrewMember _selectedBarber;
  late DateTime _selectedDate;
  late List<ServiceDurationSetting> _serviceOptions;
  late Map<String, int> _priceByServiceKey;
  ServiceDurationSetting? _selectedService;
  int _blockedMinutes = 30;
  List<String> _availableSlots = const <String>[];
  String? _selectedTime;
  String? _preferredTime;

  int get _effectiveMinutes {
    if (_blocked) {
      return _blockedMinutes;
    }
    return _selectedService?.minutes ?? widget.slotMinutes;
  }

  int get _effectivePrice {
    if (_blocked) {
      return 0;
    }
    final key = _selectedService?.key ?? '';
    return _priceByServiceKey[key] ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _selectedBarber =
        widget.barbers.cast<CrewMember?>().firstWhere(
              (barber) => barber?.id.trim() == widget.initialBarberId?.trim(),
              orElse: () => widget.barbers.first,
            ) ??
        widget.barbers.first;
    _selectedDate = athensDateOnly(widget.selectedDate);
    _preferredTime = widget.initialStartTime?.trim().isEmpty ?? true
        ? null
        : widget.initialStartTime?.trim();
    _serviceOptions = widget.serviceDurations.isEmpty
        ? buildDefaultServiceDurations()
        : widget.serviceDurations;
    final priceSource = widget.servicePrices.isEmpty
        ? buildDefaultServicePrices()
        : widget.servicePrices;
    _priceByServiceKey = {
      for (final item in priceSource) item.key.trim(): item.price,
    };
    _selectedService = _serviceOptions.isEmpty ? null : _serviceOptions.first;
    _blockedMinutes = widget.slotMinutes > 0 ? widget.slotMinutes : 30;
    _reloadSlots();
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _customerEmailController.dispose();
    _blockReasonController.dispose();
    super.dispose();
  }

  Future<void> _reloadSlots() async {
    setState(() {
      _loadingSlots = true;
      _selectedTime = null;
    });
    final slots = await widget.onLoadSlots(
      barberId: _selectedBarber.id,
      date: _selectedDate,
      requiredMinutes: _effectiveMinutes,
    );
    if (!mounted) return;
    final preferredTime = _selectedTime ?? _preferredTime;
    setState(() {
      _availableSlots = slots;
      _loadingSlots = false;
      if (slots.isNotEmpty) {
        _selectedTime = slots.contains(preferredTime) ? preferredTime : slots.first;
      } else {
        _selectedTime = null;
      }
      _preferredTime = null;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFD1A45C),
              surface: Color(0xFF151515),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) return;
    setState(() => _selectedDate = athensDateOnly(picked));
    await _reloadSlots();
  }

  Future<void> _save() async {
    final selectedTime = _selectedTime;
    if (selectedTime == null) {
      return;
    }
    if (!_blocked && _customerNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer name is required.')),
      );
      return;
    }
    if (!_blocked && _selectedService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a service first.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.onSave(
        barberId: _selectedBarber.id,
        customerName: _customerNameController.text.trim(),
        customerPhone: _customerPhoneController.text.trim(),
        customerEmail: _customerEmailController.text.trim(),
        date: _selectedDate,
        startTime: selectedTime,
        totalMinutes: _effectiveMinutes,
        totalPrice: _effectivePrice,
        blocked: _blocked,
        serviceKey: _blocked ? '' : (_selectedService?.key ?? ''),
        serviceLabel: _blocked ? 'Blocked Slot' : (_selectedService?.label ?? ''),
        blockReason: _blockReasonController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _blocked
                ? 'Unable to block this slot.'
                : 'Unable to create manual appointment.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final blockedDurations = {
      widget.slotMinutes > 0 ? widget.slotMinutes : 30,
      30,
      45,
      60,
      90,
      120,
    }.toList()..sort();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          18,
          18,
          18 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Quick add',
                style: TextStyle(
                  color: Color(0xFFF0E5D1),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Manual appointment'),
                    icon: Icon(Icons.event_available_rounded),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Block slot'),
                    icon: Icon(Icons.block_rounded),
                  ),
                ],
                selected: {_blocked},
                style: ButtonStyle(
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? const Color(0xFF111111)
                        : const Color(0xFFF0E5D1),
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? const Color(0xFFD1A45C)
                        : const Color(0xFF191919),
                  ),
                ),
                onSelectionChanged: (selection) async {
                  final nextValue = selection.first;
                  if (nextValue == _blocked) {
                    return;
                  }
                  setState(() => _blocked = nextValue);
                  await _reloadSlots();
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedBarber.id,
                decoration: _darkFieldDecoration('Barber'),
                dropdownColor: const Color(0xFF181818),
                items: widget.barbers
                    .map(
                      (barber) => DropdownMenuItem<String>(
                        value: barber.id,
                        child: Text(
                          barber.fullName,
                          style: const TextStyle(color: Color(0xFFF0E5D1)),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) async {
                  if (value == null) return;
                  setState(() {
                    _selectedBarber = widget.barbers.firstWhere(
                      (barber) => barber.id == value,
                    );
                  });
                  await _reloadSlots();
                },
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF171717),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2A2A2A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        color: Color(0xFFD1A45C),
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${_selectedDate.year.toString().padLeft(4, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            color: Color(0xFFF0E5D1),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_blocked)
                DropdownButtonFormField<int>(
                  initialValue: _blockedMinutes,
                  decoration: _darkFieldDecoration('Block duration'),
                  dropdownColor: const Color(0xFF181818),
                  items: blockedDurations
                      .map(
                        (minutes) => DropdownMenuItem<int>(
                          value: minutes,
                          child: Text(
                            "$minutes'",
                            style: const TextStyle(color: Color(0xFFF0E5D1)),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) async {
                    if (value == null) return;
                    setState(() => _blockedMinutes = value);
                    await _reloadSlots();
                  },
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _selectedService?.key,
                  decoration: _darkFieldDecoration('Service'),
                  dropdownColor: const Color(0xFF181818),
                  items: _serviceOptions
                      .map(
                        (service) => DropdownMenuItem<String>(
                          value: service.key,
                          child: Text(
                            '${service.label} | ${service.minutes} min | EUR ${_priceByServiceKey[service.key] ?? 0}',
                            style: const TextStyle(color: Color(0xFFF0E5D1)),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) async {
                    if (value == null) return;
                    setState(() {
                      _selectedService = _serviceOptions.firstWhere(
                        (service) => service.key == value,
                      );
                    });
                    await _reloadSlots();
                  },
                ),
              const SizedBox(height: 12),
              if (_loadingSlots)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFFD1A45C)),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _selectedTime,
                  decoration: _darkFieldDecoration('Time'),
                  dropdownColor: const Color(0xFF181818),
                  items: _availableSlots
                      .map(
                        (time) => DropdownMenuItem<String>(
                          value: time,
                          child: Text(
                            time,
                            style: const TextStyle(color: Color(0xFFF0E5D1)),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _availableSlots.isEmpty
                      ? null
                      : (value) => setState(() => _selectedTime = value),
                ),
              if (_availableSlots.isEmpty && !_loadingSlots) ...[
                const SizedBox(height: 10),
                const Text(
                  'No slots available for the current selection.',
                  style: TextStyle(
                    color: Color(0xFFB9B1A5),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (_blocked)
                TextField(
                  controller: _blockReasonController,
                  style: const TextStyle(color: Color(0xFFF0E5D1)),
                  decoration: _darkFieldDecoration('Block reason (optional)'),
                  maxLines: 2,
                )
              else ...[
                TextField(
                  controller: _customerNameController,
                  style: const TextStyle(color: Color(0xFFF0E5D1)),
                  decoration: _darkFieldDecoration('Customer name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _customerPhoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Color(0xFFF0E5D1)),
                  decoration: _darkFieldDecoration('Phone'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _customerEmailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Color(0xFFF0E5D1)),
                  decoration: _darkFieldDecoration('Email (optional)'),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF0E5D1),
                        side: const BorderSide(color: Color(0xFF3A3A3A)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('CLOSE'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          _saving || _loadingSlots || _selectedTime == null
                              ? null
                              : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD1A45C),
                        foregroundColor: const Color(0xFF111111),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF111111),
                              ),
                            )
                          : Text(
                              _blocked ? 'BLOCK SLOT' : 'SAVE',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

InputDecoration _darkFieldDecoration(String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Color(0xFFB9B1A5)),
    filled: true,
    fillColor: const Color(0xFF171717),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFD1A45C)),
    ),
  );
}
