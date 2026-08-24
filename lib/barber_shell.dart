part of 'main.dart';

DateTime _barberinReportsAnchorDate = athensDateOnly(athensNow());
List<Appointment> _barberinReportAppointments = const <Appointment>[];
final ValueNotifier<List<CrewMember>> currentBarberoLiveBarbers =
    ValueNotifier<List<CrewMember>>(const <CrewMember>[]);

class BarberShell extends StatefulWidget {
  const BarberShell({super.key});

  @override
  State<BarberShell> createState() => _BarberShellState();
}

bool _useDesktopBarberShell(BuildContext context) {
  if (kIsWeb || (!Platform.isWindows && !Platform.isMacOS)) {
    return false;
  }
  return MediaQuery.sizeOf(context).width >= 960;
}

class _BarberShellState extends State<BarberShell> with WidgetsBindingObserver {
  int tabIndex = 0;
  late DateTime currentAthensTime;
  late DateTime selectedDate;
  String ownerFirstName = '';
  List<ScheduleDay> weeklySchedule = buildDefaultWeeklySchedule();
  int slotMinutes = 30;
  int appointmentsPerSlot = 1;
  List<ServiceDurationSetting> serviceDurations =
      buildDefaultServiceDurations();
  List<ServicePriceSetting> servicePrices = buildDefaultServicePrices();
  List<ServiceAddOnSetting> serviceAddOns = buildDefaultServiceAddOns();
  List<SlotCapacityOverride> slotCapacityOverrides =
      const <SlotCapacityOverride>[];
  List<BarberWeeklySchedule> barberSchedules = const <BarberWeeklySchedule>[];
  List<Appointment> liveAppointments = const <Appointment>[];
  List<CustomerProfile> liveCustomers = const <CustomerProfile>[];
  List<CrewMember> liveBarbers = const <CrewMember>[];
  Timer? _clockTimer;
  Timer? _windowsShopPollTimer;
  final List<StreamSubscription<DatabaseEvent>> _shopSubscriptions =
      <StreamSubscription<DatabaseEvent>>[];
  final Map<String, dynamic> _liveShopData = <String, dynamic>{};
  final WeeklyScheduleRepository _scheduleRepository =
      WeeklyScheduleRepository();
  final CustomerAdminRepository _customerAdminRepository =
      CustomerAdminRepository();

  BarberoSession get _session => requireCurrentBarberoSession();
  BarberoPermissions get _permissions => _session.permissions;

  void _syncCurrentDayIfNeeded() {
    final now = athensNow();
    final today = athensDateOnly(now);
    final previousCurrentDay = athensDateOnly(currentAthensTime);
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
    final shouldFollowCurrentDay = selectedDate == previousCurrentDay;
    final shouldUpdateDate = shouldFollowCurrentDay && selectedDate != today;
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
        'https://europe-west1-barbero-88d00.cloudfunctions.net/barberoGetAvailability',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': await user.getIdToken(),
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
      final filtered = liveBarbers
          .where((barber) => barber.id.trim() == ownCrewId)
          .toList();
      if (filtered.isNotEmpty) {
        return filtered;
      }
    }
    final byName = liveBarbers
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
    List<String> addOnKeys = const <String>[],
    String blockReason = '',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('missing-shop-user');
    }
    final session = _session;
    final barber = liveBarbers.cast<CrewMember?>().firstWhere(
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
          'addOnKeys': addOnKeys,
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
        const SnackBar(content: Text('Δεν βρέθηκαν διαθέσιμοι barber.')),
      );
      return;
    }

    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return _QuickAddAppointmentSheet(
          selectedDate: initialDate ?? selectedDate,
          barbers: manageableBarbers,
          serviceDurations: serviceDurations,
          servicePrices: servicePrices,
          serviceAddOns: serviceAddOns,
          slotMinutes: slotMinutes,
          initialBarberId: initialBarberId,
          initialStartTime: initialStartTime,
          onLoadSlots:
              ({
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
          onSave:
              ({
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
                required List<String> addOnKeys,
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
                  addOnKeys: addOnKeys,
                  blockReason: blockReason,
                );
              },
        );
      },
    );

    if (changed == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Το πρόγραμμα ενημερώθηκε.')),
      );
    }
  }

  List<CrewMember> _parseCrewMembersFromShopData(
    Map<String, dynamic> shopData,
  ) {
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
                  customerName,
                  style: TextStyle(
                    color: context.barberinTextPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Τρέχουσα κατάσταση: ${Appointment('', '', '', '', status: currentStatus).statusLabel}',
                  style: TextStyle(
                    color: context.barberinTextSecondary,
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
                  title: Text(
                    'Επιβεβαίωση ραντεβού',
                    style: TextStyle(color: context.barberinTextPrimary),
                  ),
                  onTap: () => Navigator.of(context).pop('confirmed'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.cancel_outlined,
                    color: Color(0xFFE08A7A),
                  ),
                  title: Text(
                    'Ακύρωση ραντεβού',
                    style: TextStyle(color: context.barberinTextPrimary),
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
          const SnackBar(
            content: Text('Δεν έχεις πρόσβαση σε αυτό το ραντεβού.'),
          ),
        );
      }
      return;
    }

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
            child: ListTileTheme(
              data: ListTileTheme.of(context).copyWith(
                contentPadding: EdgeInsets.zero,
                dense: true,
                tileColor: Colors.transparent,
                horizontalTitleGap: 12,
                minLeadingWidth: 20,
                minVerticalPadding: 12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appointment.isBlocked ? 'Κλειστό slot' : appointment.name,
                    style: TextStyle(
                      color: context.barberinTextPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Τρέχουσα κατάσταση: ${appointment.statusLabel}',
                    style: TextStyle(
                      color: context.barberinTextSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...ListTile.divideTiles(
                    context: context,
                    color: context.barberinBorder,
                    tiles: [
                      if (!appointment.isBlocked &&
                          appointment.id.trim().isEmpty)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.edit_calendar_outlined,
                            color: Color(0xFFD1A45C),
                          ),
                          title: Text(
                            'Επαναπρογραμματισμός ραντεβού',
                            style: TextStyle(
                              color: context.barberinTextPrimary,
                            ),
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
                          title: Text(
                            'Επιβεβαίωση ραντεβού',
                            style: TextStyle(
                              color: context.barberinTextPrimary,
                            ),
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
                          title: Text(
                            'Σήμανση ως ολοκληρωμένο',
                            style: TextStyle(
                              color: context.barberinTextPrimary,
                            ),
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
                          title: Text(
                            'Σήμανση ως δεν εμφανίστηκε',
                            style: TextStyle(
                              color: context.barberinTextPrimary,
                            ),
                          ),
                          onTap: () => Navigator.of(context).pop('no_show'),
                        ),
                      if (!appointment.isBlocked)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.edit_calendar_outlined,
                            color: Color(0xFFD1A45C),
                          ),
                          title: Text(
                            '\u0395\u03c0\u03b1\u03bd\u03b1\u03c0\u03c1\u03bf\u03b3\u03c1\u03b1\u03bc\u03bc\u03b1\u03c4\u03b9\u03c3\u03bc\u03cc\u03c2 \u03c1\u03b1\u03bd\u03c4\u03b5\u03b2\u03bf\u03cd',
                            style: TextStyle(
                              color: context.barberinTextPrimary,
                            ),
                          ),
                          onTap: () => Navigator.of(context).pop('reschedule'),
                        ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.cancel_outlined,
                          color: Color(0xFFE08A7A),
                        ),
                        title: Text(
                          appointment.isBlocked
                              ? 'Απελευθέρωση κλειστού slot'
                              : 'Ακύρωση ραντεβού',
                          style: TextStyle(color: context.barberinTextPrimary),
                        ),
                        onTap: () => Navigator.of(context).pop('cancelled'),
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

    if (action == null || !context.mounted) {
      return;
    }

    if (action == 'reschedule') {
      await _openOwnerRescheduleSheet(
        context: context,
        appointment: appointment,
      );
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
          content: Text(switch (action) {
            'confirmed' => 'Το ραντεβού επιβεβαιώθηκε.',
            'completed' => 'Το ραντεβού σημειώθηκε ως ολοκληρωμένο.',
            'no_show' => 'Το ραντεβού σημειώθηκε ως δεν εμφανίστηκε.',
            _ =>
              appointment.isBlocked
                  ? 'Το κλειστό slot απελευθερώθηκε.'
                  : 'Το ραντεβού ακυρώθηκε.',
          }),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Δεν ήταν δυνατή η ενημέρωση του ραντεβού.'),
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
        const SnackBar(
          content: Text(
            'Δεν υπάρχουν διαθέσιμοι barber για επαναπρογραμματισμό.',
          ),
        ),
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return _OwnerRescheduleSheet(
          appointment: appointment,
          barbers: liveBarbers,
          initialBarber: initialBarber,
          onLoadSlots:
              ({
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
          onSave:
              ({
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
        const SnackBar(content: Text('Το ραντεβού επαναπρογραμματίστηκε.')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    currentBarberoLiveBarbers.value = const <CrewMember>[];
    currentAthensTime = athensNow();
    selectedDate = athensDateOnly(currentAthensTime);
    final sessionName = _session.displayName.trim();
    if (sessionName.isNotEmpty) {
      ownerFirstName = sessionName.split(RegExp(r'\s+')).first;
    }
    WidgetsBinding.instance.addObserver(this);
    barberoReturnHomeTrigger.addListener(_handleReturnHomeTrigger);
    barberoPendingAppointmentNotification.addListener(
      _handlePendingAppointmentNotification,
    );
    _initializeRealtimeShopSync();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _syncCurrentDayIfNeeded();
    });
  }

  void _handleReturnHomeTrigger() {
    if (!mounted || tabIndex == 0) {
      return;
    }
    setState(() => tabIndex = 0);
  }

  void _handlePendingAppointmentNotification() {
    final notification = barberoPendingAppointmentNotification.value;
    if (!mounted || notification == null) return;
    barberoPendingAppointmentNotification.value = null;
    final date = DateTime.tryParse(notification.appointmentDate);
    setState(() {
      if (date != null) {
        selectedDate = athensDateOnly(date);
      }
      tabIndex = 1;
    });
  }

  @override
  void dispose() {
    barberoReturnHomeTrigger.removeListener(_handleReturnHomeTrigger);
    barberoPendingAppointmentNotification.removeListener(
      _handlePendingAppointmentNotification,
    );
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _windowsShopPollTimer?.cancel();
    for (final subscription in _shopSubscriptions) {
      unawaited(subscription.cancel());
    }
    _shopSubscriptions.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncCurrentDayIfNeeded();
      if (isBarberinWindows) {
        _startWindowsShopPolling();
        unawaited(_refreshWindowsShopSnapshot());
      }
    } else if (isBarberinWindows) {
      _windowsShopPollTimer?.cancel();
      _windowsShopPollTimer = null;
    }
  }

  void _applyShopData(Map<String, dynamic> shopData) {
    if (!mounted) return;
    final scheduleData = _parseWeeklyScheduleFromShop(shopData);
    final appointments = _parseAppointmentsFromShop(shopData);
    final customers = _parseCustomersFromShop(shopData, appointments);
    final barbers = _parseCrewMembersFromShopData(shopData);
    final ownerName = '${shopData['ownerName'] ?? ''}'.trim();
    setState(() {
      slotMinutes = scheduleData.slotMinutes;
      appointmentsPerSlot = scheduleData.appointmentsPerSlot;
      weeklySchedule = List<ScheduleDay>.from(scheduleData.days);
      slotCapacityOverrides = List<SlotCapacityOverride>.from(
        scheduleData.slotCapacityOverrides,
      );
      barberSchedules = List<BarberWeeklySchedule>.from(
        scheduleData.barberSchedules,
      );
      serviceDurations = List<ServiceDurationSetting>.from(
        scheduleData.serviceDurations,
      );
      servicePrices = List<ServicePriceSetting>.from(
        scheduleData.servicePrices,
      );
      serviceAddOns = List<ServiceAddOnSetting>.from(
        scheduleData.serviceAddOns,
      );
      liveAppointments = appointments;
      liveCustomers = customers;
      liveBarbers = barbers;
      currentBarberoLiveBarbers.value = List<CrewMember>.from(barbers);
      final session = _session;
      final preferredName = session.isOwner && ownerName.isNotEmpty
          ? ownerName
          : session.displayName;
      if (preferredName.trim().isNotEmpty) {
        ownerFirstName = preferredName.split(RegExp(r'\s+')).first;
      }
    });
    unawaited(_syncOperationalAlerts());
  }

  Future<void> _refreshWindowsShopSnapshot() async {
    try {
      final shopData = await WindowsBackendAdapter.instance.loadShopSnapshot(
        _session.shopId,
      );
      _applyShopData(shopData);
    } catch (_) {
      // Keep the last successful desktop snapshot visible during short outages.
    }
  }

  void _startWindowsShopPolling() {
    if (_windowsShopPollTimer != null) {
      return;
    }
    _windowsShopPollTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(_refreshWindowsShopSnapshot()),
    );
  }

  Future<void> _initializeRealtimeShopSync() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final session = _session;
      if (isBarberinWindows) {
        await _refreshWindowsShopSnapshot();
        _startWindowsShopPolling();
        return;
      }
      for (final subscription in _shopSubscriptions) {
        await subscription.cancel();
      }
      _shopSubscriptions.clear();
      _liveShopData.clear();
      final ref = FirebaseDatabase.instance.ref('shops/${session.shopId}');
      for (final key in const <String>[
        'appointments',
        'customers',
        'barbers',
        'weekly_schedule',
        'ownerName',
      ]) {
        final subscription = ref.child(key).onValue.listen((event) {
          if (!mounted) return;
          final rawValue = event.snapshot.value;
          _liveShopData[key] = key == 'ownerName'
              ? '${rawValue ?? ''}'
              : (_mapFromRawValue(rawValue) ?? <String, dynamic>{});
          _applyShopData(Map<String, dynamic>.from(_liveShopData));
        });
        _shopSubscriptions.add(subscription);
      }
      try {
        await _scheduleRepository.loadOrCreateDefault();
      } catch (_) {
        // The live shop stream must remain active even if schedule bootstrap
        // is temporarily unavailable or the shop has no schedule yet.
      }
    } catch (_) {}
  }

  Future<void> _syncOperationalAlerts() async {
    final today = athensDateOnly(athensNow());
    final alerts = _buildOperationalAlerts(
      period: _RevenuePeriod.month,
      selectedDate: today,
      periodAppointments: _appointmentsForPeriod(
        period: _RevenuePeriod.month,
        selectedDate: today,
        appointments: liveAppointments,
      ),
      allAppointments: liveAppointments,
      weeklySchedule: weeklySchedule,
    );
    for (final alert in alerts) {
      await _storeBarberoNotificationItemIfMissing(
        BarberoNotificationItem(
          id: 'operational:${alert.id}',
          title: alert.title,
          body: alert.body,
          receivedAtIso: DateTime.now().toUtc().toIso8601String(),
          type: 'operational_alert',
        ),
      );
    }
  }

  Future<void> openWeeklySchedule(BuildContext context) async {
    if (!_permissions.editSchedule) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Δεν έχεις πρόσβαση στις ρυθμίσεις προγράμματος.'),
        ),
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
                  customer.name,
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
                    Icons.edit_note_rounded,
                    color: context.barberinAccent,
                  ),
                  title: Text(
                    'Επεξεργασία προτιμήσεων και σημειώσεων',
                    style: TextStyle(color: context.barberinTextPrimary),
                  ),
                  onTap: () => Navigator.of(context).pop('edit'),
                ),
                if (_permissions.manageCrew)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.merge_type_rounded,
                      color: context.barberinAccent,
                    ),
                    title: Text(
                      'Συγχώνευση διπλού πελάτη',
                      style: TextStyle(color: context.barberinTextPrimary),
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
          content: Text('Μπορούν να επεξεργαστούν μόνο αποθηκευμένοι πελάτες.'),
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
        backgroundColor: Theme.of(context).colorScheme.surface,
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
                    const SnackBar(
                      content: Text('Το προφίλ πελάτη ενημερώθηκε.'),
                    ),
                  );
                } catch (_) {
                  if (!sheetContext.mounted) return;
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Δεν ήταν δυνατή η ενημέρωση του προφίλ πελάτη.',
                      ),
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
                          style: TextStyle(
                            color: context.barberinTextPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: preferencesController,
                          maxLines: 5,
                          style: TextStyle(color: context.barberinTextPrimary),
                          decoration: _darkFieldDecoration(
                            'Προτιμήσεις, μία ανά γραμμή',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: notesController,
                          maxLines: 5,
                          style: TextStyle(color: context.barberinTextPrimary),
                          decoration: _darkFieldDecoration('Σημειώσεις'),
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
                                  foregroundColor: context.barberinTextPrimary,
                                  side: BorderSide(
                                    color: context.barberinBorder,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text('ΚΛΕΙΣΙΜΟ'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: saving ? null : save,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: context.barberinAccent,
                                  foregroundColor: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: saving
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onPrimary,
                                        ),
                                      )
                                    : const Text(
                                        'ΑΠΟΘΗΚΕΥΣΗ',
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
        const SnackBar(
          content: Text('Μπορούν να συγχωνευτούν μόνο αποθηκευμένοι πελάτες.'),
        ),
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
        const SnackBar(
          content: Text('Δεν υπάρχει διαθέσιμος πελάτης για συγχώνευση.'),
        ),
      );
      return;
    }

    String selectedTargetUid = mergeTargets.first.uid;
    bool saving = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
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
                  const SnackBar(
                    content: Text('Οι πελάτες συγχωνεύτηκαν επιτυχώς.'),
                  ),
                );
              } catch (_) {
                if (!sheetContext.mounted) return;
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(
                    content: Text('Δεν ήταν δυνατή η συγχώνευση των πελατών.'),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Συγχώνευση ${sourceCustomer.name}',
                      style: TextStyle(
                        color: context.barberinTextPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: selectedTargetUid,
                      dropdownColor: Theme.of(context).colorScheme.surface,
                      decoration: _darkFieldDecoration(
                        'Διατήρηση αυτού του πελάτη',
                      ),
                      items: mergeTargets
                          .map(
                            (customer) => DropdownMenuItem<String>(
                              value: customer.uid,
                              child: Text(
                                customer.name,
                                style: TextStyle(
                                  color: context.barberinTextPrimary,
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
                              foregroundColor: context.barberinTextPrimary,
                              side: BorderSide(color: context.barberinBorder),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text('ΚΛΕΙΣΙΜΟ'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: saving ? null : merge,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: context.barberinAccent,
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: saving
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimary,
                                    ),
                                  )
                                : const Text(
                                    'ΣΥΓΧΩΝΕΥΣΗ',
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
            );
          },
        );
      },
    );
  }

  void _handleTabTap(int index) {
    if (index == 2 && !_permissions.viewClients) {
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Δεν έχεις πρόσβαση στους πελάτες.')),
      );
      return;
    }
    if (index == 3 && !_permissions.viewStats) {
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Δεν έχεις πρόσβαση στις αναφορές.')),
      );
      return;
    }
    setState(() => tabIndex = index);
  }

  void openProgramTab() {
    setState(() => tabIndex = 1);
  }

  void _openAppointmentFromNotification(
    BuildContext context,
    BarberoNotificationItem notification,
  ) {
    final date = DateTime.tryParse(notification.appointmentDate);
    if (!mounted) return;
    Navigator.of(context).pop();
    setState(() {
      if (date != null) {
        selectedDate = athensDateOnly(date);
      }
      tabIndex = 1;
    });
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
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Theme.of(context).colorScheme.primary,
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
    _barberinReportsAnchorDate = selectedDate;
    _barberinReportAppointments = liveAppointments;
    final scheduleAppointments = buildHomeAppointmentsForDate(
      selectedDate: selectedDate,
      bookedAppointments: bookedAppointments,
      weeklySchedule: weeklySchedule,
      slotMinutes: slotMinutes,
      appointmentsPerSlot: appointmentsPerSlot,
      slotCapacityOverrides: slotCapacityOverrides,
    );
    final pages = [
      BarberHomePage(
        onOpenSchedule: () => openWeeklySchedule(context),
        onOpenProgram: openProgramTab,
        onQuickAdd: () => _openQuickAddSheet(context),
        onOpenNotifications: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => BarberoNotificationsPage(
                onOpenAppointment: (notification) =>
                    _openAppointmentFromNotification(context, notification),
              ),
            ),
          );
        },
        selectedDate: selectedDate,
        ownerFirstName: ownerFirstName,
        shopName: _session.shopName,
        appointments: bookedAppointments,
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
          bookedAppointments: scheduleAppointments,
          weeklySchedule: weeklySchedule,
        ),
        onPreviousDay: () => changeSelectedDate(-1),
        onNextDay: () => changeSelectedDate(1),
        onPickDate: () => pickSelectedDate(context),
        onQuickAdd: () => _openQuickAddSheet(context),
        onQuickAddForSlot: (entry) {
          _openQuickAddSheet(
            context,
            initialDate: selectedDate,
            initialStartTime: entry.hour.trim(),
          );
        },
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
              appointments: liveAppointments,
              weeklySchedule: weeklySchedule,
              onOpenCustomerIntelligence: () {
                _openBarberoMenuPage(
                  context,
                  CustomerIntelligencePage(
                    selectedDate: selectedDate,
                    appointments: liveAppointments,
                  ),
                );
              },
            )
          : const PlaceholderScaffold(title: 'Η πρόσβαση είναι περιορισμένη'),
      MoreHubPage(
        onOpenSustainabilityIndex: _permissions.viewStats
            ? () {
                _openBarberoMenuPage(
                  context,
                  SustainabilityIndexPage(
                    selectedDate: _barberinReportsAnchorDate,
                    appointments: _barberinReportAppointments,
                  ),
                );
              }
            : null,
        onOpenCustomerIntelligence: _permissions.viewStats
            ? () {
                _openBarberoMenuPage(
                  context,
                  CustomerIntelligencePage(
                    selectedDate: _barberinReportsAnchorDate,
                    appointments: _barberinReportAppointments,
                  ),
                );
              }
            : null,
        onOpenFinancialClarity: _permissions.viewStats
            ? () {
                _openBarberoMenuPage(
                  context,
                  FinancialClarityPage(
                    selectedDate: _barberinReportsAnchorDate,
                    appointments: _barberinReportAppointments,
                  ),
                );
              }
            : null,
        onOpenOperationalAlerts: _permissions.viewStats
            ? () {
                _openBarberoMenuPage(
                  context,
                  OperationalAlertsPage(
                    selectedDate: _barberinReportsAnchorDate,
                    appointments: _barberinReportAppointments,
                    weeklySchedule: weeklySchedule,
                  ),
                );
              }
            : null,
        onOpenBarberPerformance: _permissions.viewStats
            ? () {
                _openBarberoMenuPage(
                  context,
                  BarberPerformancePage(
                    selectedDate: _barberinReportsAnchorDate,
                    appointments: _barberinReportAppointments,
                  ),
                );
              }
            : null,
        onOpenServiceInsights: _permissions.viewStats
            ? () {
                _openBarberoMenuPage(
                  context,
                  ServiceInsightsPage(
                    selectedDate: _barberinReportsAnchorDate,
                    appointments: _barberinReportAppointments,
                  ),
                );
              }
            : null,
        onOpenDemandInsights: _permissions.viewStats
            ? () {
                _openBarberoMenuPage(
                  context,
                  DemandInsightsPage(
                    selectedDate: _barberinReportsAnchorDate,
                    appointments: _barberinReportAppointments,
                  ),
                );
              }
            : null,
        onOpenBusinessSnapshot: _permissions.viewStats
            ? () {
                _openBarberoMenuPage(
                  context,
                  BusinessSnapshotPage(
                    selectedDate: _barberinReportsAnchorDate,
                    appointments: _barberinReportAppointments,
                    weeklySchedule: weeklySchedule,
                  ),
                );
              }
            : null,
      ),
    ];
    final safeTabIndex = tabIndex >= pages.length ? pages.length - 1 : tabIndex;
    final useDesktopShell = _useDesktopBarberShell(context);

    return PopScope(
      canPop: safeTabIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && safeTabIndex != 0 && mounted) {
          setState(() => tabIndex = 0);
        }
      },
      child: useDesktopShell
          ? _DesktopBarberWorkspace(
              currentIndex: safeTabIndex,
              session: _session,
              canViewClients: _permissions.viewClients,
              canViewStats: _permissions.viewStats,
              hasMultipleShops: currentBarberoAccessibleShops.value.length > 1,
              onTabTap: _handleTabTap,
              onSwitchShop: () => _openBarberoShopSwitcher(context),
              child: pages[safeTabIndex],
            )
          : Scaffold(
              body: pages[safeTabIndex],
              bottomNavigationBar: _BottomBar(
                currentIndex: safeTabIndex,
                onTap: _handleTabTap,
              ),
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
    return 'Υπηρεσία';
  }

  final decoded = _decodeLikelyMojibake(source).trim();
  final lower = decoded.toLowerCase();

  if (lower.contains('kids') || decoded.contains('\u03A0\u03B1\u03B9\u03B4')) {
    return 'Kids haircut';
  }
  if (lower.contains('fade') &&
      (lower.contains('beard') ||
          decoded.contains('\u0393\u03B5\u03BD\u03B5\u03B9'))) {
    return 'Fade & beard';
  }
  if ((lower.contains('haircut') ||
          decoded.contains('\u039A\u03BF\u03CD\u03C1\u03B5\u03BC')) &&
      (lower.contains('beard') ||
          decoded.contains('\u0393\u03B5\u03BD\u03B5\u03B9'))) {
    return 'Haircut & beard';
  }
  if (lower.contains('beard') ||
      decoded.contains('\u0393\u03B5\u03BD\u03B5\u03B9')) {
    return 'Beard trim';
  }
  if (lower.contains('hair styling')) {
    return 'Styling';
  }
  if (lower.contains('haircut') ||
      decoded.contains('\u039A\u03BF\u03CD\u03C1\u03B5\u03BC')) {
    return 'Classic haircut';
  }
  if (lower == 'service' ||
      decoded == '\u03A5\u03C0\u03B7\u03C1\u03B5\u03C3\u03AF\u03B1') {
    return 'Υπηρεσία';
  }
  if (_looksCorruptedServiceText(source) ||
      _looksCorruptedServiceText(decoded)) {
    return 'Υπηρεσία';
  }
  return decoded;
}

String _serviceLabelForKey(String key) {
  switch (key.trim()) {
    case 'skin_fade':
      return 'Skin fade';
    case 'buzz_cut':
      return 'Buzz cut';
    case 'scissor_cut':
      return 'Scissor cut';
    case 'head_shave':
      return 'Head shave';
    case 'hot_towel_shave':
      return 'Hot towel shave';
    case 'beard_shape':
      return 'Beard shape';
    case 'hair_styling':
      return 'Styling';
    case 'eyebrow_trim':
      return 'Eyebrow trim';
    case 'classic_haircut':
      return 'Classic haircut';
    case 'beard_trim':
      return 'Beard trim';
    case 'haircut_and_beard':
      return 'Haircut & beard';
    case 'fade_and_beard':
      return 'Fade & beard';
    case 'kids_haircut':
      return 'Kids haircut';
    default:
      final normalized = key.trim().replaceAll('_', ' ');
      if (normalized.isEmpty) {
        return 'Ραντεβού';
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
  final filteredServiceKeys = serviceKeys
      .where((item) => item.isNotEmpty)
      .toList();
  final addOnKeys =
      (value['addOnKeys'] as List?)?.map((item) => '$item'.trim()).toList() ??
      const <String>[];
  final filteredAddOnKeys = addOnKeys.where((item) => item.isNotEmpty).toList();
  if (filteredServiceKeys.isNotEmpty || filteredAddOnKeys.isNotEmpty) {
    final labels = <String>[
      ...filteredServiceKeys.map(_serviceLabelForKey),
      ...filteredAddOnKeys.map((key) => key == 'hair_wash' ? 'Hair wash' : key),
    ];
    return labels.join(' + ');
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

  return 'Ραντεβού';
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
  final rawServiceDurations = _mapListFromRaw(
    schedule['serviceDurations'],
  ).map((item) => ServiceDurationSetting.fromJson(item)).toList();
  final rawServicePrices = _mapListFromRaw(
    schedule['servicePrices'],
  ).map((item) => ServicePriceSetting.fromJson(item)).toList();
  final rawServiceAddOns = _mapListFromRaw(schedule['serviceAddOns'])
      .map((item) => ServiceAddOnSetting.fromJson(item))
      .where((item) => item.key.isNotEmpty)
      .toList();
  final rawDays = _mapListFromRaw(
    schedule['days'],
  ).map((item) => ScheduleDay.fromJson(item)).toList();
  final days = rawDays.isEmpty ? buildDefaultWeeklySchedule() : rawDays;
  final normalizedDays = days.asMap().entries.map((entry) {
    return entry.value.copyWith(name: scheduleDayNameForIndex(entry.key));
  }).toList();

  return WeeklyScheduleData(
    slotMinutes: (schedule['slotMinutes'] as num?)?.toInt() ?? 30,
    appointmentsPerSlot:
        (schedule['appointmentsPerSlot'] as num?)?.toInt() ?? 1,
    slotCapacityOverrides:
        (schedule['slotCapacityOverrides'] as List?)
            ?.whereType<Map>()
            .map(
              (item) => SlotCapacityOverride.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList() ??
        const <SlotCapacityOverride>[],
    closedDateOverrides:
        (schedule['closedDateOverrides'] as List?)
            ?.whereType<Map>()
            .map(
              (item) =>
                  ClosedDateOverride.fromJson(Map<String, dynamic>.from(item)),
            )
            .where((item) => item.dateKey.isNotEmpty)
            .toList() ??
        const <ClosedDateOverride>[],
    barberSchedules:
        (schedule['barberSchedules'] as List?)
            ?.whereType<Map>()
            .map(
              (item) => BarberWeeklySchedule.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .where((item) => item.barberId.isNotEmpty)
            .toList() ??
        const <BarberWeeklySchedule>[],
    showPrices: schedule['showPrices'] == true,
    serviceDurations: _hasRawCollection(schedule['serviceDurations'])
        ? rawServiceDurations
        : buildDefaultServiceDurations(),
    servicePrices: _hasRawCollection(schedule['servicePrices'])
        ? rawServicePrices
        : buildDefaultServicePrices(),
    serviceAddOns: _hasRawCollection(schedule['serviceAddOns'])
        ? rawServiceAddOns
        : buildDefaultServiceAddOns(),
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
      color: context.barberinBackground,
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
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: context.barberinTextPrimary,
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
    required this.weeklySchedule,
    required this.onOpenCustomerIntelligence,
  });

  final DateTime selectedDate;
  final List<Appointment> appointments;
  final List<ScheduleDay> weeklySchedule;
  final VoidCallback onOpenCustomerIntelligence;

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
    final periodLabel = _periodLabel(_period, widget.selectedDate);
    final trend = _buildRevenueTrend(
      period: _period,
      selectedDate: widget.selectedDate,
      appointments: periodAppointments,
    );

    return Container(
      color: context.barberinBackground,
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Αναφορές',
                          style: _reportsPageTitleStyle.copyWith(
                            color: context.barberinTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Επισκόπηση αναλύσεων ιδιοκτήτη',
                          style: _reportsPageSubtitleStyle.copyWith(
                            color: context.barberinTextSecondary,
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
                  color: context.barberinSurfaceAlt,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: context.barberinBorder),
                ),
                child: Row(
                  children: [
                    _ReportsPeriodButton(
                      label: '7D',
                      selected: _period == _RevenuePeriod.day,
                      onTap: () => setState(() => _period = _RevenuePeriod.day),
                    ),
                    _ReportsPeriodButton(
                      label: '30D',
                      selected: _period == _RevenuePeriod.month,
                      onTap: () =>
                          setState(() => _period = _RevenuePeriod.month),
                    ),
                    _ReportsPeriodButton(
                      label: '1Y',
                      selected: _period == _RevenuePeriod.year,
                      onTap: () =>
                          setState(() => _period = _RevenuePeriod.year),
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
                      trend: trend,
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
                          label: 'Ραντεβού',
                          value: '${summary.totalAppointments}',
                        ),
                        _ReportsMetricCard(
                          label: 'Ολοκληρωμένα',
                          value: '${summary.completedAppointments}',
                        ),
                        _ReportsMetricCard(
                          label: 'Εκτιμώμενα έσοδα',
                          value: 'EUR ${summary.estimatedRevenue}',
                        ),
                        _ReportsMetricCard(
                          label: 'Πραγματικά έσοδα',
                          value: 'EUR ${summary.actualRevenue}',
                        ),
                        _ReportsMetricCard(
                          label: 'Μέση αξία ραντεβού',
                          value: 'EUR ${summary.averageCompletedTicket}',
                        ),
                        _ReportsMetricCard(
                          label: 'Ποσοστό ολοκλήρωσης',
                          value: '${summary.completionRate.round()}%',
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _RevenueStatusCard(summary: summary),
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
    required this.totalBookedMinutes,
  });

  final String title;
  final String subtitle;
  final List<_BarberRevenueRow> rows;
  final int totalBookedMinutes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: context.barberinSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.barberinBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: context.barberinTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: context.barberinTextSecondary,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            Text(
              'Δεν υπάρχουν δεδομένα αναφοράς για αυτή την περίοδο.',
              style: TextStyle(
                color: context.barberinTextSecondary,
                fontSize: 12.5,
              ),
            )
          else
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RevenueRowCard(
                  row: row,
                  totalBookedMinutes: totalBookedMinutes,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

const TextStyle _reportsPageTitleStyle = TextStyle(
  fontSize: 24,
  fontWeight: FontWeight.w600,
  letterSpacing: -0.4,
  decoration: TextDecoration.none,
);

const TextStyle _reportsPageSubtitleStyle = TextStyle(
  fontSize: 12.5,
  decoration: TextDecoration.none,
);

const TextStyle _reportsHeroEyebrowStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w600,
  decoration: TextDecoration.none,
);

const TextStyle _reportsHeroTitleStyle = TextStyle(
  fontSize: 26,
  fontWeight: FontWeight.w600,
  letterSpacing: -0.6,
  decoration: TextDecoration.none,
);

const TextStyle _reportsHeroBodyStyle = TextStyle(
  fontSize: 13,
  height: 1.45,
  decoration: TextDecoration.none,
);

const TextStyle _reportsSectionTitleStyle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w600,
  letterSpacing: -0.2,
  decoration: TextDecoration.none,
);

const TextStyle _reportsSectionSubtitleStyle = TextStyle(
  fontSize: 12.5,
  decoration: TextDecoration.none,
);

TextStyle _customerIntelligenceStyle(TextStyle base) {
  return base.copyWith(
    fontFamily: 'Roboto',
    decoration: TextDecoration.none,
    decorationColor: Colors.transparent,
  );
}

Color _moreCardTextColor(BuildContext context) {
  return context.barberinIsLight ? Colors.black : Colors.white;
}

class _RevenueRowCard extends StatelessWidget {
  const _RevenueRowCard({required this.row, required this.totalBookedMinutes});

  final _BarberRevenueRow row;
  final int totalBookedMinutes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
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
                  style: TextStyle(
                    color: _moreCardTextColor(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Text(
                'EUR ${row.actualRevenue}',
                style: TextStyle(
                  color: _moreCardTextColor(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _InlineMetricRow(
            label: 'Κλεισμένα ραντεβού',
            value: '${row.bookedAppointments}',
          ),
          _InlineMetricRow(
            label: 'Ολοκληρωμένα ραντεβού',
            value: '${row.completedAppointments}',
          ),
          _InlineMetricRow(
            label: 'Ποσοστό ολοκλήρωσης',
            value: '${row.completionRate.round()}%',
          ),
          _InlineMetricRow(
            label: 'Εκτιμώμενα έσοδα',
            value: 'EUR ${row.estimatedRevenue}',
          ),
          _InlineMetricRow(
            label: 'Πραγματικά έσοδα',
            value: 'EUR ${row.actualRevenue}',
          ),
          _InlineMetricRow(
            label: 'Μέση αξία ραντεβού',
            value: 'EUR ${row.averageTicket}',
          ),
          _InlineMetricRow(
            label: 'Πληρότητα',
            value: row.utilizationLabel(totalBookedMinutes),
          ),
          if (row.cancelledAppointments > 0)
            _InlineMetricRow(
              label: 'Ακυρωμένα ραντεβού',
              value: '${row.cancelledAppointments}',
            ),
          if (row.noShowAppointments > 0)
            _InlineMetricRow(
              label: 'Ραντεβού χωρίς εμφάνιση',
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
    required this.trend,
  });

  final String periodLabel;
  final _RevenueSummary summary;
  final _RevenueTrendData trend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: context.barberinSurface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: context.barberinBorder),
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
            style: _reportsHeroEyebrowStyle.copyWith(
              color: context.barberinTextSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Έσοδα',
            style: _reportsHeroTitleStyle.copyWith(
              color: context.barberinTextPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            summary.totalAppointments > 0
                ? 'Τα πραγματικά έσοδα είναι ${summary.actualRevenue} EUR από ${summary.completedAppointments} ολοκληρωμένα ραντεβού.'
                : 'Δεν έχουν καταγραφεί ακόμη ραντεβού για αυτή την περίοδο.',
            style: _reportsHeroBodyStyle.copyWith(
              color: context.barberinTextSecondary,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _RevenueTrendLegend(
                color: Theme.of(context).colorScheme.primary,
                label: 'Πραγματικά',
              ),
              const SizedBox(width: 14),
              _RevenueTrendLegend(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                label: 'Κλεισμένα',
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 112,
            width: double.infinity,
            child: CustomPaint(
              painter: _RevenueTrendPainter(
                actualValues: trend.actualValues,
                bookedValues: trend.bookedValues,
                lineColor: Theme.of(context).colorScheme.primary,
                bookedLineColor: Theme.of(context).colorScheme.onSurfaceVariant,
                gridColor: context.barberinBorder,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RevenueTrendLegend extends StatelessWidget {
  const _RevenueTrendLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: _moreCardTextColor(context),
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ReportsMetricCard extends StatelessWidget {
  const _ReportsMetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _moreCardTextColor(context),
              fontSize: 11.5,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: _moreCardTextColor(context),
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RevenueTrendData {
  const _RevenueTrendData({
    required this.actualValues,
    required this.bookedValues,
  });

  final List<double> actualValues;
  final List<double> bookedValues;
}

_RevenueTrendData _buildRevenueTrend({
  required _RevenuePeriod period,
  required DateTime selectedDate,
  required List<Appointment> appointments,
}) {
  final bucketCount = switch (period) {
    _RevenuePeriod.day => 8,
    _RevenuePeriod.month => 6,
    _RevenuePeriod.year => 12,
  };
  final actualValues = List<double>.filled(bucketCount, 0);
  final bookedValues = List<double>.filled(bucketCount, 0);

  for (final appointment in appointments) {
    if (appointment.isBlocked) {
      continue;
    }
    final bucket = _revenueTrendBucket(
      period: period,
      selectedDate: selectedDate,
      appointment: appointment,
      bucketCount: bucketCount,
    );
    if (bucket == null) {
      continue;
    }
    if (!appointment.isCancelled && !appointment.isNoShow) {
      bookedValues[bucket] += appointment.price;
    }
    if (appointment.isCompleted) {
      actualValues[bucket] += appointment.price;
    }
  }

  return _RevenueTrendData(
    actualValues: actualValues,
    bookedValues: bookedValues,
  );
}

int? _revenueTrendBucket({
  required _RevenuePeriod period,
  required DateTime selectedDate,
  required Appointment appointment,
  required int bucketCount,
}) {
  final date = DateTime.tryParse(appointment.date.trim());
  if (date == null) {
    return null;
  }

  switch (period) {
    case _RevenuePeriod.day:
      final timeParts = appointment.time.trim().split(':');
      if (timeParts.length < 2) {
        return null;
      }
      final hour = int.tryParse(timeParts[0]);
      final minute = int.tryParse(timeParts[1]);
      if (hour == null || minute == null) {
        return null;
      }
      return ((hour * 60 + minute) / (24 * 60 / bucketCount)).floor().clamp(
        0,
        bucketCount - 1,
      );
    case _RevenuePeriod.month:
      if (date.year != selectedDate.year || date.month != selectedDate.month) {
        return null;
      }
      final daysInMonth = DateTime(date.year, date.month + 1, 0).day;
      return (((date.day - 1) * bucketCount) / daysInMonth).floor().clamp(
        0,
        bucketCount - 1,
      );
    case _RevenuePeriod.year:
      if (date.year != selectedDate.year) {
        return null;
      }
      return (date.month - 1).clamp(0, bucketCount - 1);
  }
}

class _RevenueTrendPainter extends CustomPainter {
  const _RevenueTrendPainter({
    required this.actualValues,
    required this.bookedValues,
    required this.lineColor,
    required this.bookedLineColor,
    required this.gridColor,
  });

  final List<double> actualValues;
  final List<double> bookedValues;
  final Color lineColor;
  final Color bookedLineColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.55)
      ..strokeWidth = 0.7;
    for (var index = 1; index < 4; index++) {
      final y = size.height * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final maxValue = <double>[
      ...actualValues,
      ...bookedValues,
    ].fold<double>(0, math.max);
    if (maxValue <= 0 || actualValues.isEmpty || bookedValues.isEmpty) {
      return;
    }

    void drawSeries(List<double> values, Color color, double strokeWidth) {
      final linePaint = Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      for (var index = 0; index < values.length; index++) {
        final x = values.length == 1
            ? size.width / 2
            : size.width * index / (values.length - 1);
        final y = size.height - (values[index] / maxValue * size.height * .86);
        if (index == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, linePaint);
    }

    drawSeries(bookedValues, bookedLineColor.withValues(alpha: 0.7), 1.6);
    drawSeries(actualValues, lineColor, 2.4);

    final lastIndex = actualValues.length - 1;
    final lastX = actualValues.length == 1
        ? size.width / 2
        : size.width * lastIndex / (actualValues.length - 1);
    final lastY =
        size.height - (actualValues.last / maxValue * size.height * .86);
    canvas.drawCircle(Offset(lastX, lastY), 3.5, Paint()..color = lineColor);
  }

  @override
  bool shouldRepaint(covariant _RevenueTrendPainter oldDelegate) {
    return !listEquals(oldDelegate.actualValues, actualValues) ||
        !listEquals(oldDelegate.bookedValues, bookedValues) ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.bookedLineColor != bookedLineColor ||
        oldDelegate.gridColor != gridColor;
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
        color: context.barberinSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.barberinBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ροή ραντεβού',
            style: TextStyle(
              color: context.barberinTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 14),
          _InlineMetricRow(
            label: 'Ραντεβού σε αναμονή',
            value: '${summary.pendingAppointments}',
          ),
          _InlineMetricRow(
            label: 'Επιβεβαιωμένα ραντεβού',
            value: '${summary.confirmedAppointments}',
          ),
          _InlineMetricRow(
            label: 'Ολοκληρωμένα ραντεβού',
            value: '${summary.completedAppointments}',
          ),
          _InlineMetricRow(
            label: 'Ακυρωμένα ραντεβού',
            value: '${summary.cancelledAppointments}',
          ),
          _InlineMetricRow(
            label: 'Ραντεβού χωρίς εμφάνιση',
            value: '${summary.noShowAppointments}',
          ),
          _InlineMetricRow(
            label: 'Ποσοστό ολοκλήρωσης',
            value: '${summary.completionRate.round()}%',
          ),
          _InlineMetricRow(
            label: 'Ποσοστό ακυρώσεων',
            value: '${summary.cancellationRate.round()}%',
          ),
          _InlineMetricRow(
            label: 'Ποσοστό μη εμφάνισης',
            value: '${summary.noShowRate.round()}%',
          ),
          _InlineMetricRow(
            label: 'Εκτίμηση χαμένων εσόδων',
            value: 'EUR ${summary.lostRevenueEstimate}',
          ),
        ],
      ),
    );
  }
}

class _OperationalAlertsSection extends StatelessWidget {
  const _OperationalAlertsSection({required this.alerts});

  final List<_OperationalAlert> alerts;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: context.barberinSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.barberinBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Επιχειρησιακές ειδοποιήσεις',
            style: TextStyle(
              color: context.barberinTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Σήματα που χρειάζονται την προσοχή του ιδιοκτήτη',
            style: TextStyle(
              color: _moreCardTextColor(context),
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 14),
          if (alerts.isEmpty)
            Text(
              'Δεν υπάρχουν επιχειρησιακές ειδοποιήσεις αυτή τη στιγμή.',
              style: TextStyle(
                color: context.barberinTextSecondary,
                fontSize: 12.5,
              ),
            )
          else
            ...alerts.map(
              (alert) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _OperationalAlertCard(alert: alert),
              ),
            ),
        ],
      ),
    );
  }
}

class _FinancialClaritySection extends StatelessWidget {
  const _FinancialClaritySection({required this.insights});

  final _FinancialClarityInsights insights;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: context.barberinSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.barberinBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Οικονομική εικόνα',
            style: _customerIntelligenceStyle(_reportsSectionTitleStyle),
          ),
          const SizedBox(height: 4),
          Text(
            'Εκτιμώμενα και πραγματικά έσοδα, μηνιαία τάση και ετήσια σύγκριση',
            style: _customerIntelligenceStyle(_reportsSectionSubtitleStyle),
          ),
          const SizedBox(height: 14),
          _InlineMetricRow(
            label: 'Εκτιμώμενα έσοδα',
            value: 'EUR ${insights.periodEstimatedRevenue}',
          ),
          _InlineMetricRow(
            label: 'Πραγματικά έσοδα',
            value: 'EUR ${insights.periodActualRevenue}',
          ),
          _InlineMetricRow(
            label: 'Διαφορά',
            value: 'EUR ${insights.periodGap}',
          ),
          const SizedBox(height: 12),
          Text(
            'Μηνιαία τάση',
            style: _customerIntelligenceStyle(
              TextStyle(
                color: context.barberinTextPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (insights.monthlyTrend.isEmpty)
            Text(
              'Δεν υπάρχουν ακόμη δεδομένα μηνιαίας τάσης.',
              style: _customerIntelligenceStyle(
                TextStyle(color: context.barberinTextSecondary, fontSize: 12.5),
              ),
            )
          else
            ...insights.monthlyTrend.map(
              (row) => _InlineMetricRow(
                label: row.label,
                value: 'EUR ${row.actualRevenue} / EUR ${row.estimatedRevenue}',
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Ετήσια σύγκριση',
            style: _customerIntelligenceStyle(
              TextStyle(
                color: context.barberinTextPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (insights.yearlyComparison.isEmpty)
            Text(
              'Δεν υπάρχουν ακόμη δεδομένα ετήσιας σύγκρισης.',
              style: _customerIntelligenceStyle(
                TextStyle(color: context.barberinTextSecondary, fontSize: 12.5),
              ),
            )
          else
            ...insights.yearlyComparison.map(
              (row) => _InlineMetricRow(
                label: row.label,
                value: 'EUR ${row.actualRevenue} / EUR ${row.estimatedRevenue}',
              ),
            ),
        ],
      ),
    );
  }
}

class _OperationalAlertCard extends StatelessWidget {
  const _OperationalAlertCard({required this.alert});

  final _OperationalAlert alert;

  @override
  Widget build(BuildContext context) {
    final accent = switch (alert.severity) {
      _AlertSeverity.high => const Color(0xFFD67676),
      _AlertSeverity.medium => const Color(0xFFD1A45C),
      _AlertSeverity.low => const Color(0xFF7AA6D1),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      decoration: BoxDecoration(
        color: context.barberinSurfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  alert.title,
                  style: TextStyle(
                    color: _moreCardTextColor(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            alert.body,
            style: TextStyle(
              color: _moreCardTextColor(context),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineMetricRow extends StatelessWidget {
  const _InlineMetricRow({required this.label, required this.value});

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
              style: TextStyle(
                color: _moreCardTextColor(context),
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: _moreCardTextColor(context),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemandInsightsSection extends StatelessWidget {
  const _DemandInsightsSection({
    required this.subtitle,
    required this.insights,
  });

  final String subtitle;
  final _DemandInsights insights;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: context.barberinSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.barberinBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Πληροφορίες ζήτησης',
            style: TextStyle(
              color: context.barberinTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: context.barberinTextSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          _InlineMetricRow(
            label: 'Κλεισμένα ραντεβού',
            value: '${insights.bookedAppointmentCount}',
          ),
          _InlineMetricRow(
            label: 'Ενεργές ημέρες',
            value: '${insights.activeDays}',
          ),
          _InlineMetricRow(
            label: 'Πιο πολυσύχναστη ημέρα',
            value: '${insights.busiestDayLabel} (${insights.busiestDayCount})',
          ),
          _InlineMetricRow(
            label: 'Ημέρα με χαμηλότερη κίνηση',
            value: '${insights.weakestDayLabel} (${insights.weakestDayCount})',
          ),
          _InlineMetricRow(
            label: 'Πιο πολυσύχναστη ώρα',
            value:
                '${insights.busiestHourLabel} (${insights.busiestHourCount})',
          ),
          if (insights.peakWindows.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Ώρες αιχμής κρατήσεων',
              style: TextStyle(
                color: context.barberinTextPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...insights.peakWindows.map(
              (entry) => _InlineMetricRow(
                label: entry.key,
                value: '${entry.value} κρατήσεις',
              ),
            ),
          ],
          if (insights.weakWindows.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Αδύναμα slot',
              style: TextStyle(
                color: context.barberinTextPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...insights.weakWindows.map(
              (entry) => _InlineMetricRow(
                label: entry.key,
                value: '${entry.value} κρατήσεις',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class CustomerIntelligencePage extends StatefulWidget {
  const CustomerIntelligencePage({
    super.key,
    required this.selectedDate,
    required this.appointments,
  });

  final DateTime selectedDate;
  final List<Appointment> appointments;

  @override
  State<CustomerIntelligencePage> createState() =>
      _CustomerIntelligencePageState();
}

class FinancialClarityPage extends StatefulWidget {
  const FinancialClarityPage({
    super.key,
    required this.selectedDate,
    required this.appointments,
  });

  final DateTime selectedDate;
  final List<Appointment> appointments;

  @override
  State<FinancialClarityPage> createState() => _FinancialClarityPageState();
}

class OperationalAlertsPage extends StatefulWidget {
  const OperationalAlertsPage({
    super.key,
    required this.selectedDate,
    required this.appointments,
    required this.weeklySchedule,
  });

  final DateTime selectedDate;
  final List<Appointment> appointments;
  final List<ScheduleDay> weeklySchedule;

  @override
  State<OperationalAlertsPage> createState() => _OperationalAlertsPageState();
}

class BarberPerformancePage extends StatefulWidget {
  const BarberPerformancePage({
    super.key,
    required this.selectedDate,
    required this.appointments,
  });

  final DateTime selectedDate;
  final List<Appointment> appointments;

  @override
  State<BarberPerformancePage> createState() => _BarberPerformancePageState();
}

class ServiceInsightsPage extends StatefulWidget {
  const ServiceInsightsPage({
    super.key,
    required this.selectedDate,
    required this.appointments,
  });

  final DateTime selectedDate;
  final List<Appointment> appointments;

  @override
  State<ServiceInsightsPage> createState() => _ServiceInsightsPageState();
}

class DemandInsightsPage extends StatefulWidget {
  const DemandInsightsPage({
    super.key,
    required this.selectedDate,
    required this.appointments,
  });

  final DateTime selectedDate;
  final List<Appointment> appointments;

  @override
  State<DemandInsightsPage> createState() => _DemandInsightsPageState();
}

class BusinessSnapshotPage extends StatefulWidget {
  const BusinessSnapshotPage({
    super.key,
    required this.selectedDate,
    required this.appointments,
    required this.weeklySchedule,
  });

  final DateTime selectedDate;
  final List<Appointment> appointments;
  final List<ScheduleDay> weeklySchedule;

  @override
  State<BusinessSnapshotPage> createState() => _BusinessSnapshotPageState();
}

class MoreHubPage extends StatelessWidget {
  const MoreHubPage({
    super.key,
    required this.onOpenSustainabilityIndex,
    required this.onOpenCustomerIntelligence,
    required this.onOpenFinancialClarity,
    required this.onOpenOperationalAlerts,
    required this.onOpenBarberPerformance,
    required this.onOpenServiceInsights,
    required this.onOpenDemandInsights,
    required this.onOpenBusinessSnapshot,
  });

  final VoidCallback? onOpenSustainabilityIndex;
  final VoidCallback? onOpenCustomerIntelligence;
  final VoidCallback? onOpenFinancialClarity;
  final VoidCallback? onOpenOperationalAlerts;
  final VoidCallback? onOpenBarberPerformance;
  final VoidCallback? onOpenServiceInsights;
  final VoidCallback? onOpenDemandInsights;
  final VoidCallback? onOpenBusinessSnapshot;

  @override
  Widget build(BuildContext context) {
    final customerTheme = Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.apply(
        fontFamily: 'Roboto',
        bodyColor: _moreCardTextColor(context),
        displayColor: _moreCardTextColor(context),
      ),
      primaryTextTheme: Theme.of(context).primaryTextTheme.apply(
        fontFamily: 'Roboto',
        bodyColor: _moreCardTextColor(context),
        displayColor: _moreCardTextColor(context),
      ),
    );
    return Theme(
      data: customerTheme,
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: _moreCardTextColor(context),
          fontFamily: 'Roboto',
          decoration: TextDecoration.none,
          decorationColor: Colors.transparent,
        ),
        child: Container(
          color: context.barberinBackground,
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Περισσότερα',
                              style: _customerIntelligenceStyle(
                                _reportsPageTitleStyle,
                              ).copyWith(color: _moreCardTextColor(context)),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Εργαλεία και insights για το κατάστημά σου',
                              style: _customerIntelligenceStyle(
                                _reportsPageSubtitleStyle,
                              ).copyWith(color: _moreCardTextColor(context)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      children: [
                        _MoreHubCard(
                          icon: Icons.auto_graph_rounded,
                          title: 'Δείκτης βιωσιμότητας',
                          subtitle:
                              'Αξιολόγηση της οικονομικής αντοχής του καταστήματος.',
                          enabled: onOpenSustainabilityIndex != null,
                          onTap: onOpenSustainabilityIndex,
                        ),
                        const SizedBox(height: 12),
                        _MoreHubCard(
                          icon: Icons.insights_rounded,
                          title: 'Συμπεριφορά πελατών',
                          subtitle:
                              'Κατανόηση πελατών, επισκέψεων και επιστροφών.',
                          enabled: onOpenCustomerIntelligence != null,
                          onTap: onOpenCustomerIntelligence,
                        ),
                        const SizedBox(height: 12),
                        _MoreHubCard(
                          icon: Icons.account_balance_wallet_outlined,
                          title: 'Οικονομική εικόνα',
                          subtitle: 'Έσοδα, τάσεις και καθαρό αποτέλεσμα.',
                          enabled: onOpenFinancialClarity != null,
                          onTap: onOpenFinancialClarity,
                        ),
                        const SizedBox(height: 12),
                        _MoreHubCard(
                          icon: Icons.warning_amber_rounded,
                          title: 'Λειτουργικές ειδοποιήσεις',
                          subtitle: 'Θέματα που χρειάζονται άμεση προσοχή.',
                          enabled: onOpenOperationalAlerts != null,
                          onTap: onOpenOperationalAlerts,
                        ),
                        const SizedBox(height: 12),
                        _MoreHubCard(
                          icon: Icons.bar_chart_rounded,
                          title: 'Απόδοση barber',
                          subtitle:
                              'Σύγκριση απόδοσης, εσόδων και αξιοποίησης.',
                          enabled: onOpenBarberPerformance != null,
                          onTap: onOpenBarberPerformance,
                        ),
                        const SizedBox(height: 12),
                        _MoreHubCard(
                          icon: Icons.content_cut_rounded,
                          title: 'Ανάλυση υπηρεσιών',
                          subtitle: 'Δημοφιλείς και πιο αποδοτικές υπηρεσίες.',
                          enabled: onOpenServiceInsights != null,
                          onTap: onOpenServiceInsights,
                        ),
                        const SizedBox(height: 12),
                        _MoreHubCard(
                          icon: Icons.timeline_rounded,
                          title: 'Πληροφορίες ζήτησης',
                          subtitle:
                              'Ώρες αιχμής και κενά σημεία στο πρόγραμμα.',
                          enabled: onOpenDemandInsights != null,
                          onTap: onOpenDemandInsights,
                        ),
                        const SizedBox(height: 12),
                        _MoreHubCard(
                          icon: Icons.dashboard_rounded,
                          title: 'Σύνοψη επιχείρησης',
                          subtitle: 'Η συνολική εικόνα του καταστήματος.',
                          enabled: onOpenBusinessSnapshot != null,
                          onTap: onOpenBusinessSnapshot,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreHubCard extends StatelessWidget {
  const _MoreHubCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cardTextColor = _moreCardTextColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: scheme.outline),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.outline),
                ),
                child: Icon(
                  icon,
                  color: enabled ? scheme.primary : scheme.onSurfaceVariant,
                  size: 21,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cardTextColor,
                        letterSpacing: -0.2,
                        decoration: TextDecoration.none,
                      ).copyWith(fontFamily: 'Roboto'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: cardTextColor,
                        height: 1.45,
                        decoration: TextDecoration.none,
                      ).copyWith(fontFamily: 'Roboto'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: enabled ? scheme.primary : scheme.onSurfaceVariant,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerIntelligencePageState extends State<CustomerIntelligencePage> {
  _RevenuePeriod _period = _RevenuePeriod.month;

  @override
  Widget build(BuildContext context) {
    final periodAppointments = _appointmentsForPeriod(
      period: _period,
      selectedDate: widget.selectedDate,
      appointments: widget.appointments,
    );
    final insights = _buildCustomerInsights(
      periodAppointments: periodAppointments,
      allAppointments: widget.appointments,
      period: _period,
      selectedDate: widget.selectedDate,
    );
    final periodLabel = _periodLabel(_period, widget.selectedDate);
    final customerTheme = Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.apply(
        fontFamily: 'Roboto',
        bodyColor: _moreCardTextColor(context),
        displayColor: _moreCardTextColor(context),
      ),
      primaryTextTheme: Theme.of(context).primaryTextTheme.apply(
        fontFamily: 'Roboto',
        bodyColor: _moreCardTextColor(context),
        displayColor: _moreCardTextColor(context),
      ),
    );

    return Theme(
      data: customerTheme,
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: _moreCardTextColor(context),
          fontFamily: 'Roboto',
          decoration: TextDecoration.none,
          decorationColor: Colors.transparent,
        ),
        child: Container(
          color: context.barberinBackground,
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Νοημοσύνη πελατών',
                              style: _customerIntelligenceStyle(
                                _reportsPageTitleStyle,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Συμπεριφορά, πιστότητα, δαπάνη και μοτίβα κινδύνου',
                              style: _customerIntelligenceStyle(
                                _reportsPageSubtitleStyle,
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
                      color: context.barberinSurfaceAlt,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: context.barberinBorder),
                    ),
                    child: Row(
                      children: [
                        _ReportsPeriodButton(
                          label: 'Ημέρα',
                          selected: _period == _RevenuePeriod.day,
                          onTap: () =>
                              setState(() => _period = _RevenuePeriod.day),
                        ),
                        _ReportsPeriodButton(
                          label: 'Μήνας',
                          selected: _period == _RevenuePeriod.month,
                          onTap: () =>
                              setState(() => _period = _RevenuePeriod.month),
                        ),
                        _ReportsPeriodButton(
                          label: 'Έτος',
                          selected: _period == _RevenuePeriod.year,
                          onTap: () =>
                              setState(() => _period = _RevenuePeriod.year),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                          decoration: BoxDecoration(
                            color: context.barberinSurface,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: context.barberinBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                periodLabel,
                                style: _customerIntelligenceStyle(
                                  _reportsHeroEyebrowStyle,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Επισκόπηση πελατών',
                                style: _customerIntelligenceStyle(
                                  _reportsHeroTitleStyle,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                insights.activeCustomers > 0
                                    ? '${insights.activeCustomers} ενεργοί πελάτες αυτή την περίοδο. Οι ${insights.returningCustomers} επιστρέφουν, με μέσο όρο ${insights.averageVisitsPerCustomer.toStringAsFixed(1)} επισκέψεις ο καθένας.'
                                    : 'Δεν έχει καταγραφεί ακόμη δραστηριότητα πελατών για αυτή την περίοδο.',
                                style: _customerIntelligenceStyle(
                                  _reportsHeroBodyStyle,
                                ),
                              ),
                            ],
                          ),
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
                              label: 'Ενεργοί πελάτες',
                              value: '${insights.activeCustomers}',
                            ),
                            _ReportsMetricCard(
                              label: 'Νέοι πελάτες',
                              value: '${insights.newCustomers}',
                            ),
                            _ReportsMetricCard(
                              label: 'Πελάτες που επιστρέφουν',
                              value: '${insights.returningCustomers}',
                            ),
                            _ReportsMetricCard(
                              label: 'Ποσοστό επιστροφής',
                              value: '${insights.repeatRate.round()}%',
                            ),
                            _ReportsMetricCard(
                              label: 'Μέσες επισκέψεις / πελάτη',
                              value: insights.averageVisitsPerCustomer
                                  .toStringAsFixed(1),
                            ),
                            _ReportsMetricCard(
                              label: 'Κορυφαίοι πελάτες',
                              value: '${insights.detailedCustomers.length}',
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                          decoration: BoxDecoration(
                            color: context.barberinSurface,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: context.barberinBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Κορυφαίοι πελάτες',
                                style: _customerIntelligenceStyle(
                                  _reportsSectionTitleStyle,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                periodLabel,
                                style: _customerIntelligenceStyle(
                                  _reportsSectionSubtitleStyle,
                                ),
                              ),
                              const SizedBox(height: 14),
                              if (insights.detailedCustomers.isEmpty)
                                Text(
                                  'Δεν υπάρχει ακόμη δραστηριότητα πελατών.',
                                  style: TextStyle(
                                    color: _moreCardTextColor(context),
                                    fontSize: 12.5,
                                    decoration: TextDecoration.none,
                                  ).copyWith(fontFamily: 'Roboto'),
                                )
                              else
                                ...insights.detailedCustomers.map(
                                  (row) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _DetailedCustomerInsightCard(
                                      row: row,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FinancialClarityPageState extends State<FinancialClarityPage> {
  _RevenuePeriod _period = _RevenuePeriod.month;

  @override
  Widget build(BuildContext context) {
    final periodAppointments = _appointmentsForPeriod(
      period: _period,
      selectedDate: widget.selectedDate,
      appointments: widget.appointments,
    );
    final summary = _buildRevenueSummary(periodAppointments);
    final insights = _buildFinancialClarityInsights(
      selectedDate: widget.selectedDate,
      allAppointments: widget.appointments,
      periodSummary: summary,
    );
    final periodLabel = _periodLabel(_period, widget.selectedDate);
    final customerTheme = Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.apply(
        fontFamily: 'Roboto',
        bodyColor: _moreCardTextColor(context),
        displayColor: _moreCardTextColor(context),
      ),
      primaryTextTheme: Theme.of(context).primaryTextTheme.apply(
        fontFamily: 'Roboto',
        bodyColor: _moreCardTextColor(context),
        displayColor: _moreCardTextColor(context),
      ),
    );

    return Theme(
      data: customerTheme,
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: _moreCardTextColor(context),
          fontFamily: 'Roboto',
          decoration: TextDecoration.none,
          decorationColor: Colors.transparent,
        ),
        child: Container(
          color: context.barberinBackground,
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Οικονομική εικόνα',
                              style: _customerIntelligenceStyle(
                                _reportsPageTitleStyle,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Εκτιμώμενα και πραγματικά έσοδα, μηνιαία τάση και ετήσια σύγκριση',
                              style: _customerIntelligenceStyle(
                                _reportsPageSubtitleStyle,
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
                      color: context.barberinSurfaceAlt,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: context.barberinBorder),
                    ),
                    child: Row(
                      children: [
                        _ReportsPeriodButton(
                          label: 'Ημέρα',
                          selected: _period == _RevenuePeriod.day,
                          onTap: () =>
                              setState(() => _period = _RevenuePeriod.day),
                        ),
                        _ReportsPeriodButton(
                          label: 'Μήνας',
                          selected: _period == _RevenuePeriod.month,
                          onTap: () =>
                              setState(() => _period = _RevenuePeriod.month),
                        ),
                        _ReportsPeriodButton(
                          label: 'Έτος',
                          selected: _period == _RevenuePeriod.year,
                          onTap: () =>
                              setState(() => _period = _RevenuePeriod.year),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                          decoration: BoxDecoration(
                            color: context.barberinSurface,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: context.barberinBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                periodLabel,
                                style: _customerIntelligenceStyle(
                                  _reportsHeroEyebrowStyle,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Οικονομική επισκόπηση',
                                style: _customerIntelligenceStyle(
                                  _reportsHeroTitleStyle,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Τα πραγματικά έσοδα είναι ${insights.periodActualRevenue} EUR έναντι εκτιμώμενων ${insights.periodEstimatedRevenue} EUR, με διαφορά ${insights.periodGap} EUR.',
                                style: _customerIntelligenceStyle(
                                  _reportsHeroBodyStyle,
                                ),
                              ),
                            ],
                          ),
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
                              label: 'Εκτιμώμενα',
                              value: 'EUR ${insights.periodEstimatedRevenue}',
                            ),
                            _ReportsMetricCard(
                              label: 'Πραγματικά',
                              value: 'EUR ${insights.periodActualRevenue}',
                            ),
                            _ReportsMetricCard(
                              label: 'Διαφορά',
                              value: 'EUR ${insights.periodGap}',
                            ),
                            const _ReportsMetricCard(
                              label: 'Πληρωμένα / απλήρωτα',
                              value: 'Αργότερα',
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _FinancialClaritySection(insights: insights),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OperationalAlertsPageState extends State<OperationalAlertsPage> {
  _RevenuePeriod _period = _RevenuePeriod.month;

  @override
  Widget build(BuildContext context) {
    final periodAppointments = _appointmentsForPeriod(
      period: _period,
      selectedDate: widget.selectedDate,
      appointments: widget.appointments,
    );
    final alerts = _buildOperationalAlerts(
      period: _period,
      selectedDate: widget.selectedDate,
      periodAppointments: periodAppointments,
      allAppointments: widget.appointments,
      weeklySchedule: widget.weeklySchedule,
    );
    final periodLabel = _periodLabel(_period, widget.selectedDate);
    final customerTheme = Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.apply(
        fontFamily: 'Roboto',
        bodyColor: _moreCardTextColor(context),
        displayColor: _moreCardTextColor(context),
      ),
      primaryTextTheme: Theme.of(context).primaryTextTheme.apply(
        fontFamily: 'Roboto',
        bodyColor: _moreCardTextColor(context),
        displayColor: _moreCardTextColor(context),
      ),
    );

    return Theme(
      data: customerTheme,
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: _moreCardTextColor(context),
          fontFamily: 'Roboto',
          decoration: TextDecoration.none,
          decorationColor: Colors.transparent,
        ),
        child: Container(
          color: context.barberinBackground,
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Επιχειρησιακές ειδοποιήσεις',
                              style: _customerIntelligenceStyle(
                                _reportsPageTitleStyle,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Σήματα που χρειάζονται την προσοχή του ιδιοκτήτη',
                              style: _customerIntelligenceStyle(
                                _reportsPageSubtitleStyle,
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
                      color: context.barberinSurfaceAlt,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: context.barberinBorder),
                    ),
                    child: Row(
                      children: [
                        _ReportsPeriodButton(
                          label: 'Ημέρα',
                          selected: _period == _RevenuePeriod.day,
                          onTap: () =>
                              setState(() => _period = _RevenuePeriod.day),
                        ),
                        _ReportsPeriodButton(
                          label: 'Μήνας',
                          selected: _period == _RevenuePeriod.month,
                          onTap: () =>
                              setState(() => _period = _RevenuePeriod.month),
                        ),
                        _ReportsPeriodButton(
                          label: 'Έτος',
                          selected: _period == _RevenuePeriod.year,
                          onTap: () =>
                              setState(() => _period = _RevenuePeriod.year),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                          decoration: BoxDecoration(
                            color: context.barberinSurface,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: context.barberinBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                periodLabel,
                                style: _customerIntelligenceStyle(
                                  _reportsHeroEyebrowStyle,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Επισκόπηση προσοχής',
                                style: _customerIntelligenceStyle(
                                  _reportsHeroTitleStyle,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                alerts.isEmpty
                                    ? 'Δεν υπάρχουν ενεργές επιχειρησιακές ειδοποιήσεις για αυτή την περίοδο.'
                                    : '${alerts.length} επιχειρησιακές ειδοποιήσεις είναι ενεργές για αυτή την περίοδο.',
                                style: _customerIntelligenceStyle(
                                  _reportsHeroBodyStyle,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        _OperationalAlertsSection(alerts: alerts),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarberPerformancePageState extends State<BarberPerformancePage> {
  _RevenuePeriod _period = _RevenuePeriod.month;

  @override
  Widget build(BuildContext context) {
    final periodAppointments = _appointmentsForPeriod(
      period: _period,
      selectedDate: widget.selectedDate,
      appointments: widget.appointments,
    );
    final rows = _buildRevenueRows(periodAppointments);
    final periodLabel = _periodLabel(_period, widget.selectedDate);
    final totalBookedMinutes = rows.fold<int>(
      0,
      (sum, row) => sum + row.bookedMinutes,
    );
    final bestPerformer = rows.isEmpty ? null : rows.first;
    final lowestPerformer = rows.isEmpty ? null : rows.last;
    final customerTheme = Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.apply(
        fontFamily: 'Roboto',
        bodyColor: _moreCardTextColor(context),
        displayColor: _moreCardTextColor(context),
      ),
      primaryTextTheme: Theme.of(context).primaryTextTheme.apply(
        fontFamily: 'Roboto',
        bodyColor: _moreCardTextColor(context),
        displayColor: _moreCardTextColor(context),
      ),
    );

    return Theme(
      data: customerTheme,
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: _moreCardTextColor(context),
          fontFamily: 'Roboto',
          decoration: TextDecoration.none,
          decorationColor: Colors.transparent,
        ),
        child: Container(
          color: context.barberinBackground,
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Απόδοση barber',
                              style: _customerIntelligenceStyle(
                                _reportsPageTitleStyle,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Απόδοση και αποδοτικότητα ανά barber',
                              style: _customerIntelligenceStyle(
                                _reportsPageSubtitleStyle,
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
                      color: context.barberinSurfaceAlt,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: context.barberinBorder),
                    ),
                    child: Row(
                      children: [
                        _ReportsPeriodButton(
                          label: 'Ημέρα',
                          selected: _period == _RevenuePeriod.day,
                          onTap: () =>
                              setState(() => _period = _RevenuePeriod.day),
                        ),
                        _ReportsPeriodButton(
                          label: 'Μήνας',
                          selected: _period == _RevenuePeriod.month,
                          onTap: () =>
                              setState(() => _period = _RevenuePeriod.month),
                        ),
                        _ReportsPeriodButton(
                          label: 'Έτος',
                          selected: _period == _RevenuePeriod.year,
                          onTap: () =>
                              setState(() => _period = _RevenuePeriod.year),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                          decoration: BoxDecoration(
                            color: context.barberinSurface,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: context.barberinBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                periodLabel,
                                style: _customerIntelligenceStyle(
                                  _reportsHeroEyebrowStyle,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Επισκόπηση απόδοσης',
                                style: _customerIntelligenceStyle(
                                  _reportsHeroTitleStyle,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                rows.isEmpty
                                    ? 'Δεν έχει καταγραφεί ακόμη δραστηριότητα barber για αυτή την περίοδο.'
                                    : '${rows.length} barber ${rows.length == 1 ? 'είναι ενεργός' : 'είναι ενεργοί'} αυτή την περίοδο. ${bestPerformer?.barberName ?? 'Κανένας barber'} προηγείται αυτή τη στιγμή στα πραγματικά έσοδα.',
                                style: _customerIntelligenceStyle(
                                  _reportsHeroBodyStyle,
                                ),
                              ),
                            ],
                          ),
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
                              label: 'Ενεργοί barber',
                              value: '${rows.length}',
                            ),
                            _ReportsMetricCard(
                              label: 'Καλύτερη απόδοση',
                              value: bestPerformer?.barberName ?? 'Δεν υπάρχει',
                            ),
                            _ReportsMetricCard(
                              label: 'Χαμηλότερη απόδοση',
                              value:
                                  lowestPerformer?.barberName ?? 'Δεν υπάρχει',
                            ),
                            _ReportsMetricCard(
                              label: 'Συνολικές κλεισμένες ώρες',
                              value: (totalBookedMinutes / 60).toStringAsFixed(
                                1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _RevenueSection(
                          title: 'Απόδοση barber',
                          subtitle: periodLabel,
                          rows: rows,
                          totalBookedMinutes: totalBookedMinutes,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceInsightsPageState extends State<ServiceInsightsPage> {
  _RevenuePeriod _period = _RevenuePeriod.month;

  @override
  Widget build(BuildContext context) {
    final periodAppointments = _appointmentsForPeriod(
      period: _period,
      selectedDate: widget.selectedDate,
      appointments: widget.appointments,
    );
    final rows = _buildServiceRows(periodAppointments);
    final topService = rows.isEmpty ? null : rows.first;
    final topProfitableService = rows.isEmpty
        ? null
        : (rows.toList()
                ..sort((a, b) => b.actualRevenue.compareTo(a.actualRevenue)))
              .first;
    final topRiskService = rows.isEmpty
        ? null
        : (rows.toList()..sort(
                (a, b) => (b.cancelledCount + b.noShowCount).compareTo(
                  a.cancelledCount + a.noShowCount,
                ),
              ))
              .first;
    final periodLabel = _periodLabel(_period, widget.selectedDate);
    final customerTheme = Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.apply(
        fontFamily: 'Roboto',
        bodyColor: _moreCardTextColor(context),
        displayColor: _moreCardTextColor(context),
      ),
      primaryTextTheme: Theme.of(context).primaryTextTheme.apply(
        fontFamily: 'Roboto',
        bodyColor: _moreCardTextColor(context),
        displayColor: _moreCardTextColor(context),
      ),
    );

    return Theme(
      data: customerTheme,
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: _moreCardTextColor(context),
          fontFamily: 'Roboto',
          decoration: TextDecoration.none,
          decorationColor: Colors.transparent,
        ),
        child: Container(
          color: context.barberinBackground,
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Πληροφορίες υπηρεσιών',
                              style: _customerIntelligenceStyle(
                                _reportsPageTitleStyle,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Ζήτηση, κερδοφορία και κίνδυνος ανά υπηρεσία',
                              style: _customerIntelligenceStyle(
                                _reportsPageSubtitleStyle,
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
                      color: context.barberinSurfaceAlt,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: context.barberinBorder),
                    ),
                    child: Row(
                      children: [
                        _ReportsPeriodButton(
                          label: 'Ημέρα',
                          selected: _period == _RevenuePeriod.day,
                          onTap: () =>
                              setState(() => _period = _RevenuePeriod.day),
                        ),
                        _ReportsPeriodButton(
                          label: 'Μήνας',
                          selected: _period == _RevenuePeriod.month,
                          onTap: () =>
                              setState(() => _period = _RevenuePeriod.month),
                        ),
                        _ReportsPeriodButton(
                          label: 'Έτος',
                          selected: _period == _RevenuePeriod.year,
                          onTap: () =>
                              setState(() => _period = _RevenuePeriod.year),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                          decoration: BoxDecoration(
                            color: context.barberinSurface,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: context.barberinBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                periodLabel,
                                style: _customerIntelligenceStyle(
                                  _reportsHeroEyebrowStyle,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Επισκόπηση υπηρεσιών',
                                style: _customerIntelligenceStyle(
                                  _reportsHeroTitleStyle,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                rows.isEmpty
                                    ? 'Δεν έχει καταγραφεί ακόμη δραστηριότητα υπηρεσιών για αυτή την περίοδο.'
                                    : '${topService?.label ?? 'Καμία υπηρεσία'} προηγείται στη ζήτηση, ενώ ${topProfitableService?.label ?? 'καμία υπηρεσία'} προηγείται στα πραγματικά έσοδα.',
                                style: _customerIntelligenceStyle(
                                  _reportsHeroBodyStyle,
                                ),
                              ),
                            ],
                          ),
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
                              label: 'Υπηρεσίες που παρακολουθούνται',
                              value: '${rows.length}',
                            ),
                            _ReportsMetricCard(
                              label: 'Κορυφαία υπηρεσία',
                              value: topService?.label ?? 'Δεν υπάρχει',
                            ),
                            _ReportsMetricCard(
                              label: 'Πιο κερδοφόρα',
                              value:
                                  topProfitableService?.label ?? 'Δεν υπάρχει',
                            ),
                            _ReportsMetricCard(
                              label: 'Πιο ευάλωτη',
                              value:
                                  topRiskService == null ||
                                      (topRiskService.cancelledCount +
                                              topRiskService.noShowCount) ==
                                          0
                                  ? 'Δεν υπάρχει'
                                  : topRiskService.label,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _ServiceMixSection(subtitle: periodLabel, rows: rows),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DemandInsightsPageState extends State<DemandInsightsPage> {
  _RevenuePeriod _period = _RevenuePeriod.month;

  @override
  Widget build(BuildContext context) {
    final periodAppointments = _appointmentsForPeriod(
      period: _period,
      selectedDate: widget.selectedDate,
      appointments: widget.appointments,
    );
    final insights = _buildDemandInsights(periodAppointments);
    final periodLabel = _periodLabel(_period, widget.selectedDate);
    final customerTheme = Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.apply(
        fontFamily: 'Roboto',
        bodyColor: _moreCardTextColor(context),
        displayColor: _moreCardTextColor(context),
      ),
      primaryTextTheme: Theme.of(context).primaryTextTheme.apply(
        fontFamily: 'Roboto',
        bodyColor: _moreCardTextColor(context),
        displayColor: _moreCardTextColor(context),
      ),
    );

    return Theme(
      data: customerTheme,
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: _moreCardTextColor(context),
          fontFamily: 'Roboto',
          decoration: TextDecoration.none,
          decorationColor: Colors.transparent,
        ),
        child: Container(
          color: context.barberinBackground,
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Πληροφορίες ζήτησης',
                              style: _customerIntelligenceStyle(
                                _reportsPageTitleStyle,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Μοτίβα ζήτησης ραντεβού και αδύναμα σημεία',
                              style: _customerIntelligenceStyle(
                                _reportsPageSubtitleStyle,
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
                      color: context.barberinSurfaceAlt,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: context.barberinBorder),
                    ),
                    child: Row(
                      children: [
                        _ReportsPeriodButton(
                          label: 'Ημέρα',
                          selected: _period == _RevenuePeriod.day,
                          onTap: () =>
                              setState(() => _period = _RevenuePeriod.day),
                        ),
                        _ReportsPeriodButton(
                          label: 'Μήνας',
                          selected: _period == _RevenuePeriod.month,
                          onTap: () =>
                              setState(() => _period = _RevenuePeriod.month),
                        ),
                        _ReportsPeriodButton(
                          label: 'Έτος',
                          selected: _period == _RevenuePeriod.year,
                          onTap: () =>
                              setState(() => _period = _RevenuePeriod.year),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                          decoration: BoxDecoration(
                            color: context.barberinSurface,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: context.barberinBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                periodLabel,
                                style: _customerIntelligenceStyle(
                                  _reportsHeroEyebrowStyle,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Επισκόπηση ζήτησης',
                                style: _customerIntelligenceStyle(
                                  _reportsHeroTitleStyle,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                insights.bookedAppointmentCount == 0
                                    ? 'Δεν έχει καταγραφεί ακόμη ζήτηση για αυτή την περίοδο.'
                                    : '${insights.bookedAppointmentCount} κλεισμένα ραντεβού σε ${insights.activeDays} ενεργές ημέρες. Η ${insights.busiestDayLabel} είναι αυτή τη στιγμή η πιο πολυσύχναστη ημέρα.',
                                style: _customerIntelligenceStyle(
                                  _reportsHeroBodyStyle,
                                ),
                              ),
                            ],
                          ),
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
                              label: 'Κλεισμένα ραντεβού',
                              value: '${insights.bookedAppointmentCount}',
                            ),
                            _ReportsMetricCard(
                              label: 'Ενεργές ημέρες',
                              value: '${insights.activeDays}',
                            ),
                            _ReportsMetricCard(
                              label: 'Πιο πολυσύχναστη ημέρα',
                              value: insights.busiestDayLabel,
                            ),
                            _ReportsMetricCard(
                              label: 'Πιο πολυσύχναστη ώρα',
                              value: insights.busiestHourLabel,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _DemandInsightsSection(
                          subtitle: periodLabel,
                          insights: insights,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BusinessSnapshotPageState extends State<BusinessSnapshotPage> {
  _RevenuePeriod _period = _RevenuePeriod.month;

  @override
  Widget build(BuildContext context) {
    final periodAppointments = _appointmentsForPeriod(
      period: _period,
      selectedDate: widget.selectedDate,
      appointments: widget.appointments,
    );
    final summary = _buildRevenueSummary(periodAppointments);
    final rows = _buildRevenueRows(periodAppointments);
    final customerInsights = _buildCustomerInsights(
      periodAppointments: periodAppointments,
      allAppointments: widget.appointments,
      period: _period,
      selectedDate: widget.selectedDate,
    );
    final demandInsights = _buildDemandInsights(periodAppointments);
    final serviceRows = _buildServiceRows(periodAppointments);
    final alerts = _buildOperationalAlerts(
      period: _period,
      selectedDate: widget.selectedDate,
      periodAppointments: periodAppointments,
      allAppointments: widget.appointments,
      weeklySchedule: widget.weeklySchedule,
    );
    final bestPerformer = rows.isEmpty ? null : rows.first;
    final periodLabel = _periodLabel(_period, widget.selectedDate);
    final customerTheme = Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.apply(
        fontFamily: 'Roboto',
        bodyColor: _moreCardTextColor(context),
        displayColor: _moreCardTextColor(context),
      ),
      primaryTextTheme: Theme.of(context).primaryTextTheme.apply(
        fontFamily: 'Roboto',
        bodyColor: _moreCardTextColor(context),
        displayColor: _moreCardTextColor(context),
      ),
    );

    return Theme(
      data: customerTheme,
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: _moreCardTextColor(context),
          fontFamily: 'Roboto',
          decoration: TextDecoration.none,
          decorationColor: Colors.transparent,
        ),
        child: Container(
          color: context.barberinBackground,
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Σύνοψη επιχείρησης',
                              style: _customerIntelligenceStyle(
                                _reportsPageTitleStyle,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Σύντομη συνολική εικόνα για γρήγορο έλεγχο του ιδιοκτήτη',
                              style: _customerIntelligenceStyle(
                                _reportsPageSubtitleStyle,
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
                      color: context.barberinSurfaceAlt,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: context.barberinBorder),
                    ),
                    child: Row(
                      children: [
                        _ReportsPeriodButton(
                          label: 'Ημέρα',
                          selected: _period == _RevenuePeriod.day,
                          onTap: () =>
                              setState(() => _period = _RevenuePeriod.day),
                        ),
                        _ReportsPeriodButton(
                          label: 'Μήνας',
                          selected: _period == _RevenuePeriod.month,
                          onTap: () =>
                              setState(() => _period = _RevenuePeriod.month),
                        ),
                        _ReportsPeriodButton(
                          label: 'Έτος',
                          selected: _period == _RevenuePeriod.year,
                          onTap: () =>
                              setState(() => _period = _RevenuePeriod.year),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                          decoration: BoxDecoration(
                            color: context.barberinSurface,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: context.barberinBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                periodLabel,
                                style: _customerIntelligenceStyle(
                                  _reportsHeroEyebrowStyle,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Με μια ματιά',
                                style: _customerIntelligenceStyle(
                                  _reportsHeroTitleStyle,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Τα πραγματικά έσοδα είναι ${summary.actualRevenue} EUR, δραστηριοποιήθηκαν ${customerInsights.activeCustomers} πελάτες, καταγράφηκαν ${demandInsights.bookedAppointmentCount} ραντεβού και υπάρχουν ${alerts.length} ενεργές επιχειρησιακές ειδοποιήσεις.',
                                style: _customerIntelligenceStyle(
                                  _reportsHeroBodyStyle,
                                ),
                              ),
                            ],
                          ),
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
                              label: 'Πραγματικά έσοδα',
                              value: 'EUR ${summary.actualRevenue}',
                            ),
                            _ReportsMetricCard(
                              label: 'Ενεργοί πελάτες',
                              value: '${customerInsights.activeCustomers}',
                            ),
                            _ReportsMetricCard(
                              label: 'Κλεισμένα ραντεβού',
                              value: '${demandInsights.bookedAppointmentCount}',
                            ),
                            _ReportsMetricCard(
                              label: 'Ενεργές ειδοποιήσεις',
                              value: '${alerts.length}',
                            ),
                            _ReportsMetricCard(
                              label: 'Καλύτερη απόδοση',
                              value: bestPerformer?.barberName ?? 'Δεν υπάρχει',
                            ),
                            _ReportsMetricCard(
                              label: 'Κορυφαία υπηρεσία',
                              value: serviceRows.isEmpty
                                  ? 'Δεν υπάρχει'
                                  : serviceRows.first.label,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                          decoration: BoxDecoration(
                            color: context.barberinSurface,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: context.barberinBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Βασικά σημεία',
                                style: _customerIntelligenceStyle(
                                  _reportsSectionTitleStyle,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                periodLabel,
                                style: _customerIntelligenceStyle(
                                  _reportsSectionSubtitleStyle,
                                ),
                              ),
                              const SizedBox(height: 14),
                              _InlineMetricRow(
                                label: 'Ποσοστό ολοκλήρωσης',
                                value: '${summary.completionRate.round()}%',
                              ),
                              _InlineMetricRow(
                                label: 'Μέση αξία ραντεβού',
                                value: 'EUR ${summary.averageCompletedTicket}',
                              ),
                              _InlineMetricRow(
                                label: 'Επαναλαμβανόμενοι πελάτες',
                                value: '${customerInsights.returningCustomers}',
                              ),
                              _InlineMetricRow(
                                label: 'Πιο πολυσύχναστη ημέρα',
                                value: demandInsights.busiestDayLabel,
                              ),
                              _InlineMetricRow(
                                label: 'Πιο πολυσύχναστη ώρα',
                                value: demandInsights.busiestHourLabel,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailedCustomerInsightCard extends StatelessWidget {
  const _DetailedCustomerInsightCard({required this.row});

  final _TopCustomerRow row;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.customerName,
                  style: TextStyle(
                    color: _moreCardTextColor(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Text(
                'EUR ${row.actualSpend}',
                style: TextStyle(
                  color: _moreCardTextColor(context),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InlineMetricRow(
            label: 'Επισκέψεις περιόδου',
            value: '${row.visits}',
          ),
          _InlineMetricRow(
            label: 'Ολοκληρωμένες επισκέψεις',
            value: '${row.completedVisits}',
          ),
          _InlineMetricRow(
            label: 'Τελευταία επίσκεψη',
            value: barberinDateLabel(row.lastVisit),
          ),
          _InlineMetricRow(
            label: 'Μέση δαπάνη',
            value: 'EUR ${row.averageSpend}',
          ),
          _InlineMetricRow(
            label: 'Αγαπημένες υπηρεσίες',
            value: row.favoriteServicesLabel,
          ),
          _InlineMetricRow(
            label: 'Αγαπημένος barber',
            value: row.favoriteBarberLabel,
          ),
          _InlineMetricRow(
            label: 'Ιστορικό μη εμφάνισης',
            value: row.noShowCount == 0
                ? 'Καθαρό ιστορικό'
                : '${row.noShowCount} μη εμφανίσεις',
          ),
          _InlineMetricRow(
            label: 'Ρυθμός επιστροφής',
            value: row.returnCadenceLabel,
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
                  ? Theme.of(context).colorScheme.surface
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onSurfaceVariant,
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
    required this.bookedMinutes,
    required this.completedAppointments,
    required this.cancelledAppointments,
    required this.noShowAppointments,
  });

  final String barberName;
  final int estimatedRevenue;
  final int actualRevenue;
  final int bookedAppointments;
  final int bookedMinutes;
  final int completedAppointments;
  final int cancelledAppointments;
  final int noShowAppointments;

  int get averageTicket => completedAppointments <= 0
      ? 0
      : (actualRevenue / completedAppointments).round();

  double get completionRate => bookedAppointments <= 0
      ? 0
      : (completedAppointments / bookedAppointments) * 100;

  String utilizationLabel(int totalBookedMinutes) {
    if (bookedMinutes <= 0 || totalBookedMinutes <= 0) {
      return '0%';
    }
    final value = (bookedMinutes / totalBookedMinutes) * 100;
    return '${value.round()}%';
  }
}

List<_BarberRevenueRow> _buildRevenueRows(Iterable<Appointment> appointments) {
  final map = <String, _BarberRevenueRow>{};
  for (final appointment in appointments) {
    final barberName = appointment.barberName.trim().isEmpty
        ? 'Barber χωρίς ανάθεση'
        : appointment.barberName.trim();
    final current = map[barberName];
    final isEstimated =
        !appointment.isBlocked &&
        !appointment.isCancelled &&
        !appointment.isNoShow;
    map[barberName] = _BarberRevenueRow(
      barberName: barberName,
      estimatedRevenue:
          (current?.estimatedRevenue ?? 0) +
          (isEstimated ? appointment.price : 0),
      actualRevenue:
          (current?.actualRevenue ?? 0) +
          (appointment.isCompleted ? appointment.price : 0),
      bookedAppointments:
          (current?.bookedAppointments ?? 0) + (isEstimated ? 1 : 0),
      bookedMinutes:
          (current?.bookedMinutes ?? 0) +
          (isEstimated ? appointment.minutes : 0),
      completedAppointments:
          (current?.completedAppointments ?? 0) +
          (appointment.isCompleted ? 1 : 0),
      cancelledAppointments:
          (current?.cancelledAppointments ?? 0) +
          (appointment.isCancelled ? 1 : 0),
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

  int get openAppointments => pendingAppointments + confirmedAppointments;

  int get averageCompletedTicket => completedAppointments <= 0
      ? 0
      : (actualRevenue / completedAppointments).round();

  double get completionRate => totalAppointments <= 0
      ? 0
      : (completedAppointments / totalAppointments) * 100;

  double get cancellationRate => totalAppointments <= 0
      ? 0
      : (cancelledAppointments / totalAppointments) * 100;

  double get noShowRate => totalAppointments <= 0
      ? 0
      : (noShowAppointments / totalAppointments) * 100;

  int get lostRevenueEstimate => totalAppointments <= 0
      ? 0
      : (estimatedRevenue - actualRevenue).clamp(0, 1 << 30);
}

class _DemandInsights {
  const _DemandInsights({
    required this.bookedAppointmentCount,
    required this.activeDays,
    required this.busiestDayLabel,
    required this.busiestDayCount,
    required this.weakestDayLabel,
    required this.weakestDayCount,
    required this.busiestHourLabel,
    required this.busiestHourCount,
    required this.peakWindows,
    required this.weakWindows,
  });

  final int bookedAppointmentCount;
  final int activeDays;
  final String busiestDayLabel;
  final int busiestDayCount;
  final String weakestDayLabel;
  final int weakestDayCount;
  final String busiestHourLabel;
  final int busiestHourCount;
  final List<MapEntry<String, int>> peakWindows;
  final List<MapEntry<String, int>> weakWindows;
}

class _TopCustomerRow {
  const _TopCustomerRow({
    required this.customerKey,
    required this.customerName,
    required this.visits,
    required this.completedVisits,
    required this.actualSpend,
    required this.lastVisit,
    this.averageSpend = 0,
    this.favoriteServicesLabel = 'Δεν υπάρχει ακόμη μοτίβο',
    this.favoriteBarberLabel = 'Δεν υπάρχει ακόμη μοτίβο',
    this.noShowCount = 0,
    this.averageDaysBetweenVisits,
  });

  final String customerKey;
  final String customerName;
  final int visits;
  final int completedVisits;
  final int actualSpend;
  final DateTime lastVisit;
  final int averageSpend;
  final String favoriteServicesLabel;
  final String favoriteBarberLabel;
  final int noShowCount;
  final double? averageDaysBetweenVisits;

  String get returnCadenceLabel {
    final days = averageDaysBetweenVisits;
    if (days == null || days <= 0) {
      if (completedVisits <= 1) {
        return 'Μία ολοκληρωμένη επίσκεψη';
      }
      return 'Δεν υπάρχει αρκετό ιστορικό';
    }
    if (days < 10) {
      return 'Κάθε ${days.toStringAsFixed(0)} ημέρες';
    }
    if (days < 45) {
      return 'Κάθε ${days.toStringAsFixed(0)} ημέρες';
    }
    return 'Κάθε ${(days / 30).toStringAsFixed(1)} μήνες';
  }

  _TopCustomerRow copyWith({
    String? customerKey,
    String? customerName,
    int? visits,
    int? completedVisits,
    int? actualSpend,
    DateTime? lastVisit,
    int? averageSpend,
    String? favoriteServicesLabel,
    String? favoriteBarberLabel,
    int? noShowCount,
    double? averageDaysBetweenVisits,
  }) {
    return _TopCustomerRow(
      customerKey: customerKey ?? this.customerKey,
      customerName: customerName ?? this.customerName,
      visits: visits ?? this.visits,
      completedVisits: completedVisits ?? this.completedVisits,
      actualSpend: actualSpend ?? this.actualSpend,
      lastVisit: lastVisit ?? this.lastVisit,
      averageSpend: averageSpend ?? this.averageSpend,
      favoriteServicesLabel:
          favoriteServicesLabel ?? this.favoriteServicesLabel,
      favoriteBarberLabel: favoriteBarberLabel ?? this.favoriteBarberLabel,
      noShowCount: noShowCount ?? this.noShowCount,
      averageDaysBetweenVisits:
          averageDaysBetweenVisits ?? this.averageDaysBetweenVisits,
    );
  }
}

class _CustomerInsights {
  const _CustomerInsights({
    required this.activeCustomers,
    required this.newCustomers,
    required this.returningCustomers,
    required this.repeatRate,
    required this.averageVisitsPerCustomer,
    required this.topCustomers,
    required this.detailedCustomers,
  });

  final int activeCustomers;
  final int newCustomers;
  final int returningCustomers;
  final double repeatRate;
  final double averageVisitsPerCustomer;
  final List<_TopCustomerRow> topCustomers;
  final List<_TopCustomerRow> detailedCustomers;
}

enum _AlertSeverity { low, medium, high }

class _OperationalAlert {
  const _OperationalAlert({
    required this.id,
    required this.title,
    required this.body,
    required this.severity,
  });

  final String id;
  final String title;
  final String body;
  final _AlertSeverity severity;
}

class _FinancialWindowRow {
  const _FinancialWindowRow({
    required this.label,
    required this.estimatedRevenue,
    required this.actualRevenue,
  });

  final String label;
  final int estimatedRevenue;
  final int actualRevenue;
}

class _FinancialClarityInsights {
  const _FinancialClarityInsights({
    required this.periodEstimatedRevenue,
    required this.periodActualRevenue,
    required this.monthlyTrend,
    required this.yearlyComparison,
  });

  final int periodEstimatedRevenue;
  final int periodActualRevenue;
  final List<_FinancialWindowRow> monthlyTrend;
  final List<_FinancialWindowRow> yearlyComparison;

  int get periodGap =>
      (periodEstimatedRevenue - periodActualRevenue).clamp(0, 1 << 30);
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

_FinancialClarityInsights _buildFinancialClarityInsights({
  required DateTime selectedDate,
  required List<Appointment> allAppointments,
  required _RevenueSummary periodSummary,
}) {
  final monthlyTrend = <_FinancialWindowRow>[];
  for (var offset = 2; offset >= 0; offset--) {
    final monthDate = DateTime(
      selectedDate.year,
      selectedDate.month - offset,
      1,
    );
    final appointments = _appointmentsForPeriod(
      period: _RevenuePeriod.month,
      selectedDate: monthDate,
      appointments: allAppointments,
    );
    final summary = _buildRevenueSummary(appointments);
    monthlyTrend.add(
      _FinancialWindowRow(
        label: _greekMonthYearLabel(monthDate),
        estimatedRevenue: summary.estimatedRevenue,
        actualRevenue: summary.actualRevenue,
      ),
    );
  }

  final yearlyComparison = <_FinancialWindowRow>[];
  for (var offset = 1; offset >= 0; offset--) {
    final yearDate = DateTime(selectedDate.year - offset, 1, 1);
    final appointments = _appointmentsForPeriod(
      period: _RevenuePeriod.year,
      selectedDate: yearDate,
      appointments: allAppointments,
    );
    final summary = _buildRevenueSummary(appointments);
    yearlyComparison.add(
      _FinancialWindowRow(
        label: '${yearDate.year}',
        estimatedRevenue: summary.estimatedRevenue,
        actualRevenue: summary.actualRevenue,
      ),
    );
  }

  return _FinancialClarityInsights(
    periodEstimatedRevenue: periodSummary.estimatedRevenue,
    periodActualRevenue: periodSummary.actualRevenue,
    monthlyTrend: monthlyTrend,
    yearlyComparison: yearlyComparison,
  );
}

_DemandInsights _buildDemandInsights(Iterable<Appointment> appointments) {
  final bookedAppointments = appointments
      .where(
        (appointment) =>
            !appointment.isBlocked &&
            !appointment.isCancelled &&
            !appointment.isNoShow,
      )
      .toList(growable: false);

  if (bookedAppointments.isEmpty) {
    return const _DemandInsights(
      bookedAppointmentCount: 0,
      activeDays: 0,
      busiestDayLabel: 'Καμία δραστηριότητα',
      busiestDayCount: 0,
      weakestDayLabel: 'Καμία δραστηριότητα',
      weakestDayCount: 0,
      busiestHourLabel: 'Καμία δραστηριότητα',
      busiestHourCount: 0,
      peakWindows: <MapEntry<String, int>>[],
      weakWindows: <MapEntry<String, int>>[],
    );
  }

  final byDay = <String, int>{};
  final byHour = <String, int>{};
  for (final appointment in bookedAppointments) {
    final dateTime = _appointmentDateTime(appointment);
    if (dateTime == null) continue;
    final dayLabel = _weekdayLabel(dateTime.weekday);
    byDay[dayLabel] = (byDay[dayLabel] ?? 0) + 1;
    final hourLabel =
        '${dateTime.hour.toString().padLeft(2, '0')}:00 - ${dateTime.hour.toString().padLeft(2, '0')}:59';
    byHour[hourLabel] = (byHour[hourLabel] ?? 0) + 1;
  }

  final sortedDays = byDay.entries.toList()
    ..sort((left, right) {
      final compare = right.value.compareTo(left.value);
      if (compare != 0) return compare;
      return left.key.compareTo(right.key);
    });
  final weakestDays = byDay.entries.toList()
    ..sort((left, right) {
      final compare = left.value.compareTo(right.value);
      if (compare != 0) return compare;
      return left.key.compareTo(right.key);
    });
  final sortedHours = byHour.entries.toList()
    ..sort((left, right) {
      final compare = right.value.compareTo(left.value);
      if (compare != 0) return compare;
      return left.key.compareTo(right.key);
    });

  return _DemandInsights(
    bookedAppointmentCount: bookedAppointments.length,
    activeDays: byDay.length,
    busiestDayLabel: sortedDays.first.key,
    busiestDayCount: sortedDays.first.value,
    weakestDayLabel: weakestDays.first.key,
    weakestDayCount: weakestDays.first.value,
    busiestHourLabel: sortedHours.first.key,
    busiestHourCount: sortedHours.first.value,
    peakWindows: sortedHours.take(3).toList(growable: false),
    weakWindows: sortedHours.reversed.take(3).toList(growable: false),
  );
}

_CustomerInsights _buildCustomerInsights({
  required Iterable<Appointment> periodAppointments,
  required List<Appointment> allAppointments,
  required _RevenuePeriod period,
  required DateTime selectedDate,
}) {
  final activePeriodAppointments = periodAppointments
      .where(
        (appointment) =>
            !appointment.isBlocked &&
            !appointment.isCancelled &&
            !appointment.isNoShow,
      )
      .toList(growable: false);
  final allCustomerAppointments = allAppointments
      .where((appointment) => !appointment.isBlocked)
      .toList(growable: false);

  final earliestVisitByCustomer = <String, DateTime>{};
  for (final appointment in allCustomerAppointments) {
    final customerKey = _appointmentCustomerKey(appointment);
    if (customerKey.isEmpty) continue;
    final dateTime = _appointmentDateTime(appointment);
    if (dateTime == null) continue;
    final current = earliestVisitByCustomer[customerKey];
    if (current == null || dateTime.isBefore(current)) {
      earliestVisitByCustomer[customerKey] = dateTime;
    }
  }

  final periodStart = _periodStart(period, selectedDate);
  final periodEnd = _periodEnd(period, selectedDate);
  final activeCustomers = <String>{};
  final countedCustomers = <String>{};
  final topCustomerMap = <String, _TopCustomerRow>{};
  final appointmentHistoryByCustomer = <String, List<Appointment>>{};
  var newCustomers = 0;
  var returningCustomers = 0;

  for (final appointment in allCustomerAppointments) {
    final customerKey = _appointmentCustomerKey(appointment);
    if (customerKey.isEmpty) continue;
    appointmentHistoryByCustomer
        .putIfAbsent(customerKey, () => <Appointment>[])
        .add(appointment);
  }

  for (final appointment in activePeriodAppointments) {
    final customerKey = _appointmentCustomerKey(appointment);
    if (customerKey.isEmpty) continue;
    activeCustomers.add(customerKey);

    final firstVisit = earliestVisitByCustomer[customerKey];
    if (!countedCustomers.contains(customerKey) && firstVisit != null) {
      countedCustomers.add(customerKey);
      if (!firstVisit.isBefore(periodStart) && !firstVisit.isAfter(periodEnd)) {
        newCustomers += 1;
      } else {
        returningCustomers += 1;
      }
    }

    final dateTime = _appointmentDateTime(appointment) ?? periodStart;
    final current = topCustomerMap[customerKey];
    topCustomerMap[customerKey] = _TopCustomerRow(
      customerKey: customerKey,
      customerName: appointment.name.trim().isEmpty
          ? 'Πελάτης χωρίς όνομα'
          : appointment.name.trim(),
      visits: (current?.visits ?? 0) + 1,
      completedVisits:
          (current?.completedVisits ?? 0) + (appointment.isCompleted ? 1 : 0),
      actualSpend:
          (current?.actualSpend ?? 0) +
          (appointment.isCompleted ? appointment.price : 0),
      lastVisit: current == null || dateTime.isAfter(current.lastVisit)
          ? dateTime
          : current.lastVisit,
    );
  }

  final topCustomers = topCustomerMap.values.toList()
    ..sort((left, right) {
      final spendCompare = right.actualSpend.compareTo(left.actualSpend);
      if (spendCompare != 0) return spendCompare;
      final visitsCompare = right.visits.compareTo(left.visits);
      if (visitsCompare != 0) return visitsCompare;
      return left.customerName.toLowerCase().compareTo(
        right.customerName.toLowerCase(),
      );
    });

  final enrichedCustomers = topCustomers
      .map((row) {
        final history =
            appointmentHistoryByCustomer[row.customerKey] ??
            const <Appointment>[];
        final attendedAppointments = history
            .where(
              (appointment) =>
                  !appointment.isBlocked &&
                  !appointment.isCancelled &&
                  !appointment.isNoShow,
            )
            .toList(growable: false);
        final completedAppointments = history
            .where((appointment) => appointment.isCompleted)
            .toList(growable: false);
        final noShowCount = history
            .where((appointment) => appointment.isNoShow)
            .length;

        final serviceCounts = <String, int>{};
        final barberCounts = <String, int>{};
        for (final appointment in attendedAppointments) {
          final serviceLabel = _reportServiceLabel(appointment.service);
          serviceCounts[serviceLabel] = (serviceCounts[serviceLabel] ?? 0) + 1;
          final barberLabel = appointment.barberName.trim().isEmpty
              ? 'Barber χωρίς ανάθεση'
              : appointment.barberName.trim();
          barberCounts[barberLabel] = (barberCounts[barberLabel] ?? 0) + 1;
        }

        final sortedServices = serviceCounts.entries.toList()
          ..sort((left, right) {
            final compare = right.value.compareTo(left.value);
            if (compare != 0) return compare;
            return left.key.compareTo(right.key);
          });
        final sortedBarbers = barberCounts.entries.toList()
          ..sort((left, right) {
            final compare = right.value.compareTo(left.value);
            if (compare != 0) return compare;
            return left.key.compareTo(right.key);
          });

        final completedDates =
            completedAppointments
                .map(_appointmentDateTime)
                .whereType<DateTime>()
                .toList()
              ..sort();
        double? averageDaysBetweenVisits;
        if (completedDates.length >= 2) {
          var totalDays = 0.0;
          for (var index = 1; index < completedDates.length; index++) {
            totalDays +=
                completedDates[index]
                    .difference(completedDates[index - 1])
                    .inHours /
                24;
          }
          averageDaysBetweenVisits = totalDays / (completedDates.length - 1);
        }

        final latestAttendedVisit = attendedAppointments
            .map(_appointmentDateTime)
            .whereType<DateTime>()
            .fold<DateTime?>(null, (latest, date) {
              if (latest == null || date.isAfter(latest)) {
                return date;
              }
              return latest;
            });

        return row.copyWith(
          lastVisit: latestAttendedVisit ?? row.lastVisit,
          averageSpend: completedAppointments.isEmpty
              ? 0
              : (completedAppointments.fold<int>(
                          0,
                          (sum, item) => sum + item.price,
                        ) /
                        completedAppointments.length)
                    .round(),
          favoriteServicesLabel: sortedServices.isEmpty
              ? 'Δεν υπάρχει μοτίβο ακόμη'
              : sortedServices.take(2).map((entry) => entry.key).join(' + '),
          favoriteBarberLabel: sortedBarbers.isEmpty
              ? 'Δεν υπάρχει μοτίβο ακόμη'
              : sortedBarbers.first.key,
          noShowCount: noShowCount,
          averageDaysBetweenVisits: averageDaysBetweenVisits,
        );
      })
      .toList(growable: false);

  return _CustomerInsights(
    activeCustomers: activeCustomers.length,
    newCustomers: newCustomers,
    returningCustomers: returningCustomers,
    repeatRate: activeCustomers.isEmpty
        ? 0
        : (returningCustomers / activeCustomers.length) * 100,
    averageVisitsPerCustomer: activeCustomers.isEmpty
        ? 0
        : activePeriodAppointments.length / activeCustomers.length,
    topCustomers: enrichedCustomers.take(5).toList(growable: false),
    detailedCustomers: enrichedCustomers.take(12).toList(growable: false),
  );
}

List<_OperationalAlert> _buildOperationalAlerts({
  required _RevenuePeriod period,
  required DateTime selectedDate,
  required Iterable<Appointment> periodAppointments,
  required List<Appointment> allAppointments,
  required List<ScheduleDay> weeklySchedule,
}) {
  final alerts = <_OperationalAlert>[];
  final cancelledPeriodAppointments = periodAppointments
      .where((appointment) => appointment.isCancelled)
      .toList(growable: false);
  final cancellationRate = periodAppointments.isEmpty
      ? 0.0
      : (cancelledPeriodAppointments.length / periodAppointments.length) * 100;
  if (cancelledPeriodAppointments.length >= 2 && cancellationRate >= 15) {
    alerts.add(
      _OperationalAlert(
        id: 'cancellation-${period.name}-${_dateKey(selectedDate)}-${cancelledPeriodAppointments.length}',
        title: 'Αυξημένες ακυρώσεις',
        body:
            'Καταγράφηκαν ${cancelledPeriodAppointments.length} ακυρώσεις σε αυτή την περίοδο. Το ποσοστό ακυρώσεων είναι ${cancellationRate.toStringAsFixed(0)}%.',
        severity:
            cancellationRate >= 25 || cancelledPeriodAppointments.length >= 4
            ? _AlertSeverity.high
            : _AlertSeverity.medium,
      ),
    );
  }

  final scheduleDay = _scheduleDayForDate(weeklySchedule, selectedDate);
  if (scheduleDay != null && scheduleDay.enabled) {
    final activeToday =
        allAppointments
            .where(
              (appointment) =>
                  appointment.date == _dateKey(selectedDate) &&
                  !appointment.isBlocked &&
                  !appointment.isCancelled &&
                  !appointment.isNoShow,
            )
            .toList()
          ..sort(
            (left, right) => _parseClockValue(
              left.time,
            ).compareTo(_parseClockValue(right.time)),
          );
    final largestGap = _largestScheduleGapMinutes(
      scheduleDay: scheduleDay,
      appointments: activeToday,
    );
    if (largestGap >= 120) {
      alerts.add(
        _OperationalAlert(
          id: 'gaps-${_dateKey(selectedDate)}-$largestGap',
          title: 'Μεγάλα κενά στο σημερινό πρόγραμμα',
          body:
              'Το σημερινό πρόγραμμα έχει ακόμη κενό περίπου ${(largestGap / 60).toStringAsFixed(1)} ώρες. Ίσως χρειάζεται υπενθύμιση ή επιπλέον κρατήσεις.',
          severity: largestGap >= 180
              ? _AlertSeverity.high
              : _AlertSeverity.medium,
        ),
      );
    }
  }

  final completedByCustomer = <String, List<Appointment>>{};
  for (final appointment in allAppointments) {
    if (!appointment.isCompleted || appointment.isBlocked) continue;
    final customerKey = _appointmentCustomerKey(appointment);
    if (customerKey.isEmpty) continue;
    completedByCustomer
        .putIfAbsent(customerKey, () => <Appointment>[])
        .add(appointment);
  }
  final lostCustomers = <String>[];
  final now = athensDateOnly(athensNow());
  for (final entry in completedByCustomer.entries) {
    final latest = entry.value
        .map(_appointmentDateTime)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (latest, date) {
          if (latest == null || date.isAfter(latest)) {
            return date;
          }
          return latest;
        });
    if (latest == null) continue;
    if (now.difference(latest).inDays >= 45) {
      lostCustomers.add(
        entry.value.first.name.trim().isEmpty
            ? 'Ανώνυμος πελάτης'
            : entry.value.first.name.trim(),
      );
    }
  }
  if (lostCustomers.isNotEmpty) {
    final preview = lostCustomers.take(3).join(', ');
    alerts.add(
      _OperationalAlert(
        id: 'lost-customers-${now.year}-${now.month}-${lostCustomers.length}',
        title: 'Πελάτες που έχουν χαθεί καιρό',
        body:
            '${lostCustomers.length} πελάτες που επέστρεφαν δεν έχουν έρθει εδώ και τουλάχιστον 45 ημέρες. Πρώτα ονόματα για επαναπροσέγγιση: $preview.',
        severity: lostCustomers.length >= 5
            ? _AlertSeverity.medium
            : _AlertSeverity.low,
      ),
    );
  }

  final lowOccupancyDays = <String>[];
  for (var offset = 0; offset < 7; offset++) {
    final day = athensDateOnly(now.add(Duration(days: offset)));
    final daySchedule = _scheduleDayForDate(weeklySchedule, day);
    if (daySchedule == null || !daySchedule.enabled) continue;
    final count = allAppointments.where((appointment) {
      return appointment.date == _dateKey(day) &&
          !appointment.isBlocked &&
          !appointment.isCancelled &&
          !appointment.isNoShow;
    }).length;
    if (count <= 1) {
      lowOccupancyDays.add(barberinDateLabel(day));
    }
  }
  if (lowOccupancyDays.isNotEmpty) {
    alerts.add(
      _OperationalAlert(
        id: 'low-occupancy-${now.year}-${now.month}-${now.day}-${lowOccupancyDays.length}',
        title: 'Πολύ χαμηλή επερχόμενη πληρότητα',
        body:
            'Αυτές οι ημέρες δείχνουν αυτή τη στιγμή πολύ χαμηλή κίνηση: ${lowOccupancyDays.take(3).join(', ')}.',
        severity: lowOccupancyDays.length >= 3
            ? _AlertSeverity.medium
            : _AlertSeverity.low,
      ),
    );
  }

  return alerts;
}

ScheduleDay? _scheduleDayForDate(
  List<ScheduleDay> weeklySchedule,
  DateTime date,
) {
  if (weeklySchedule.isEmpty) {
    return null;
  }
  final index = date.weekday - 1;
  if (index < 0 || index >= weeklySchedule.length) {
    return null;
  }
  return weeklySchedule[index];
}

int _largestScheduleGapMinutes({
  required ScheduleDay scheduleDay,
  required List<Appointment> appointments,
}) {
  final start = _parseClockValue(scheduleDay.start);
  final end = _parseClockValue(scheduleDay.end);
  if (start <= 0 || end <= 0 || end <= start) {
    return 0;
  }
  var cursor = start;
  var largestGap = 0;
  for (final appointment in appointments) {
    final appointmentStart = _parseClockValue(appointment.time);
    if (appointmentStart > cursor) {
      largestGap = math.max(largestGap, appointmentStart - cursor);
    }
    final appointmentEnd = appointmentStart + appointment.minutes;
    if (appointmentEnd > cursor) {
      cursor = appointmentEnd;
    }
  }
  if (end > cursor) {
    largestGap = math.max(largestGap, end - cursor);
  }
  return largestGap;
}

List<Appointment> _appointmentsForPeriod({
  required _RevenuePeriod period,
  required DateTime selectedDate,
  required List<Appointment> appointments,
}) {
  return appointments
      .where((appointment) {
        switch (period) {
          case _RevenuePeriod.day:
            return appointment.date == _dateKey(selectedDate);
          case _RevenuePeriod.month:
            return appointment.date.startsWith(_monthKey(selectedDate));
          case _RevenuePeriod.year:
            return appointment.date.startsWith('${selectedDate.year}-');
        }
      })
      .toList(growable: false);
}

DateTime _periodStart(_RevenuePeriod period, DateTime selectedDate) {
  switch (period) {
    case _RevenuePeriod.day:
      return DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    case _RevenuePeriod.month:
      return DateTime(selectedDate.year, selectedDate.month, 1);
    case _RevenuePeriod.year:
      return DateTime(selectedDate.year, 1, 1);
  }
}

DateTime _periodEnd(_RevenuePeriod period, DateTime selectedDate) {
  switch (period) {
    case _RevenuePeriod.day:
      return DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        23,
        59,
        59,
      );
    case _RevenuePeriod.month:
      return DateTime(selectedDate.year, selectedDate.month + 1, 0, 23, 59, 59);
    case _RevenuePeriod.year:
      return DateTime(selectedDate.year, 12, 31, 23, 59, 59);
  }
}

String _appointmentCustomerKey(Appointment appointment) {
  final uid = appointment.customerUid.trim();
  if (uid.isNotEmpty) {
    return 'uid:$uid';
  }
  final email = appointment.customerEmail.trim().toLowerCase();
  if (email.isNotEmpty) {
    return 'email:$email';
  }
  final phone = appointment.customerPhone.trim();
  if (phone.isNotEmpty) {
    return 'phone:$phone';
  }
  final name = appointment.name.trim().toLowerCase();
  return name.isEmpty ? '' : 'name:$name';
}

DateTime? _appointmentDateTime(Appointment appointment) {
  final date = appointment.date.trim();
  final time = appointment.time.trim();
  if (date.isEmpty || time.isEmpty) {
    return null;
  }
  return DateTime.tryParse('${date}T$time:00');
}

String _periodLabel(_RevenuePeriod period, DateTime selectedDate) {
  switch (period) {
    case _RevenuePeriod.day:
      return barberinDateLabel(selectedDate);
    case _RevenuePeriod.month:
      return _greekMonthYearLabel(selectedDate);
    case _RevenuePeriod.year:
      return '${selectedDate.year}';
  }
}

String _weekdayLabel(int weekday) {
  switch (weekday) {
    case DateTime.monday:
      return 'Δευτέρα';
    case DateTime.tuesday:
      return 'Τρίτη';
    case DateTime.wednesday:
      return 'Τετάρτη';
    case DateTime.thursday:
      return 'Πέμπτη';
    case DateTime.friday:
      return 'Παρασκευή';
    case DateTime.saturday:
      return 'Σάββατο';
    case DateTime.sunday:
      return 'Κυριακή';
    default:
      return 'Άγνωστη ημέρα';
  }
}

class _ServiceReportRow {
  const _ServiceReportRow({
    required this.label,
    required this.count,
    required this.completedCount,
    required this.cancelledCount,
    required this.noShowCount,
    required this.estimatedRevenue,
    required this.actualRevenue,
  });

  final String label;
  final int count;
  final int completedCount;
  final int cancelledCount;
  final int noShowCount;
  final int estimatedRevenue;
  final int actualRevenue;

  int get averageTicket =>
      completedCount <= 0 ? 0 : (actualRevenue / completedCount).round();

  double get completionRate => count <= 0 ? 0 : (completedCount / count) * 100;
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
      cancelledCount:
          (current?.cancelledCount ?? 0) + (appointment.isCancelled ? 1 : 0),
      noShowCount: (current?.noShowCount ?? 0) + (appointment.isNoShow ? 1 : 0),
      estimatedRevenue:
          (current?.estimatedRevenue ?? 0) +
          (isEstimated ? appointment.price : 0),
      actualRevenue:
          (current?.actualRevenue ?? 0) +
          (appointment.isCompleted ? appointment.price : 0),
    );
  }
  final rows = map.values.toList()
    ..sort((left, right) => right.count.compareTo(left.count));
  return rows;
}

String _reportServiceLabel(String raw) {
  final value = raw.trim();
  switch (value) {
    case 'Classic Haircut':
      return 'Classic haircut';
    case 'Beard Trim':
      return 'Beard trim';
    case 'Kids Haircut':
      return 'Kids haircut';
    case 'Haircut & Beard':
      return 'Haircut & beard';
    case 'Fade & Beard':
      return 'Fade & beard';
    default:
      return value.isEmpty ? 'Άλλη υπηρεσία' : value;
  }
}

class _ServiceMixSection extends StatelessWidget {
  const _ServiceMixSection({required this.subtitle, required this.rows});

  final String subtitle;
  final List<_ServiceReportRow> rows;

  @override
  Widget build(BuildContext context) {
    final topService = rows.isEmpty
        ? null
        : (rows.toList()..sort((a, b) => b.count.compareTo(a.count))).first;
    final topProfitableService = rows.isEmpty
        ? null
        : (rows.toList()
                ..sort((a, b) => b.actualRevenue.compareTo(a.actualRevenue)))
              .first;
    final topRiskService = rows.isEmpty
        ? null
        : (rows.toList()..sort(
                (a, b) => (b.cancelledCount + b.noShowCount).compareTo(
                  a.cancelledCount + a.noShowCount,
                ),
              ))
              .first;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: context.barberinSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.barberinBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Μείγμα υπηρεσιών',
            style: TextStyle(
              color: context.barberinTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(color: _moreCardTextColor(context), fontSize: 12),
          ),
          const SizedBox(height: 14),
          if (topService != null)
            _InlineMetricRow(
              label: 'Κορυφαία υπηρεσία',
              value: '${topService.label} (${topService.count})',
            ),
          if (topProfitableService != null)
            _InlineMetricRow(
              label: 'Πιο κερδοφόρα υπηρεσία',
              value:
                  '${topProfitableService.label} (EUR ${topProfitableService.actualRevenue})',
            ),
          if (topRiskService != null &&
              (topRiskService.cancelledCount + topRiskService.noShowCount) > 0)
            _InlineMetricRow(
              label: 'Πιο ευάλωτη υπηρεσία',
              value:
                  '${topRiskService.label} (${topRiskService.cancelledCount} ακυρώσεις, ${topRiskService.noShowCount} χωρίς εμφάνιση)',
            ),
          if (topService != null || topProfitableService != null)
            const SizedBox(height: 12),
          if (rows.isEmpty)
            Text(
              'Δεν υπάρχει ακόμη δραστηριότητα υπηρεσιών.',
              style: TextStyle(
                color: context.barberinTextSecondary,
                fontSize: 12.5,
              ),
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
        color: context.barberinSurfaceAlt,
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
                  style: TextStyle(
                    color: context.barberinTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Text(
                '${row.count} ραντεβού',
                style: TextStyle(
                  color: context.barberinTextSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InlineMetricRow(
            label: 'Ολοκληρωμένα ραντεβού',
            value: '${row.completedCount}',
          ),
          _InlineMetricRow(
            label: 'Ποσοστό ολοκλήρωσης',
            value: '${row.completionRate.round()}%',
          ),
          _InlineMetricRow(
            label: 'Εκτιμώμενα έσοδα',
            value: 'EUR ${row.estimatedRevenue}',
          ),
          _InlineMetricRow(
            label: 'Πραγματικά έσοδα',
            value: 'EUR ${row.actualRevenue}',
          ),
          _InlineMetricRow(
            label: 'Μέση αξία ραντεβού',
            value: 'EUR ${row.averageTicket}',
          ),
          if (row.cancelledCount > 0)
            _InlineMetricRow(
              label: 'Ακυρωμένα ραντεβού',
              value: '${row.cancelledCount}',
            ),
          if (row.noShowCount > 0)
            _InlineMetricRow(
              label: 'Ραντεβού χωρίς εμφάνιση',
              value: '${row.noShowCount}',
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
  if (barberinUsesEnglish) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[value.month - 1]} ${value.year}';
  }
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

class _DesktopShellScope extends InheritedWidget {
  const _DesktopShellScope({required super.child});

  static bool enabledOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_DesktopShellScope>() !=
        null;
  }

  @override
  bool updateShouldNotify(_DesktopShellScope oldWidget) => false;
}

class _DesktopBarberWorkspace extends StatelessWidget {
  const _DesktopBarberWorkspace({
    required this.currentIndex,
    required this.session,
    required this.canViewClients,
    required this.canViewStats,
    required this.hasMultipleShops,
    required this.onTabTap,
    required this.onSwitchShop,
    required this.child,
  });

  final int currentIndex;
  final BarberoSession session;
  final bool canViewClients;
  final bool canViewStats;
  final bool hasMultipleShops;
  final ValueChanged<int> onTabTap;
  final VoidCallback onSwitchShop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ColoredBox(
        color: context.barberinBackground,
        child: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DesktopSidebar(
                currentIndex: currentIndex,
                session: session,
                canViewClients: canViewClients,
                canViewStats: canViewStats,
                hasMultipleShops: hasMultipleShops,
                onTabTap: onTabTap,
                onSwitchShop: onSwitchShop,
              ),
              Expanded(
                child: _DesktopShellScope(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(30, 24, 30, 26),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1540),
                        child: child,
                      ),
                    ),
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

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.currentIndex,
    required this.session,
    required this.canViewClients,
    required this.canViewStats,
    required this.hasMultipleShops,
    required this.onTabTap,
    required this.onSwitchShop,
  });

  final int currentIndex;
  final BarberoSession session;
  final bool canViewClients;
  final bool canViewStats;
  final bool hasMultipleShops;
  final ValueChanged<int> onTabTap;
  final VoidCallback onSwitchShop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shopName = session.shopName.trim().isEmpty
        ? 'Κατάστημα χωρίς όνομα'
        : session.shopName.trim();
    final displayName = session.displayName.trim().isEmpty
        ? session.userEmail.trim()
        : session.displayName.trim();

    const navigation = <_DesktopNavigationItem>[
      _DesktopNavigationItem('Επισκόπηση', Icons.dashboard_outlined, 0),
      _DesktopNavigationItem('Πρόγραμμα', Icons.calendar_month_outlined, 1),
      _DesktopNavigationItem('Πελάτες', Icons.people_outline_rounded, 2),
      _DesktopNavigationItem('Αναφορές', Icons.insights_outlined, 3),
      _DesktopNavigationItem('Περισσότερα', Icons.grid_view_rounded, 4),
    ];

    return Container(
      width: 264,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(right: BorderSide(color: context.barberinBorder)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BrandWordmark(width: 144),
            const SizedBox(height: 12),
            Text(
              'ΔΙΑΧΕΙΡΙΣΗ ΚΑΤΑΣΤΗΜΑΤΟΣ',
              style: TextStyle(
                color: context.barberinTextSecondary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.barberinBorder),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shopName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.barberinTextPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.barberinTextSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'ΧΩΡΟΣ ΕΡΓΑΣΙΑΣ',
              style: TextStyle(
                color: context.barberinTextSecondary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final item in navigation)
                    _DesktopSidebarRow(
                      icon: item.icon,
                      label: item.label,
                      selected: currentIndex == item.index,
                      enabled: item.index != 2
                          ? item.index != 3 || canViewStats
                          : canViewClients,
                      onTap: () => onTabTap(item.index),
                    ),
                ],
              ),
            ),
            if (hasMultipleShops) ...[
              Divider(color: context.barberinBorder, height: 1),
              const SizedBox(height: 10),
              _DesktopSidebarRow(
                icon: Icons.sync_alt_rounded,
                label: 'Αλλαγή καταστήματος',
                onTap: onSwitchShop,
              ),
            ],
            Divider(color: context.barberinBorder, height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  session.isOwner
                      ? Icons.verified_user_outlined
                      : Icons.badge_outlined,
                  size: 17,
                  color: scheme.primary,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    session.isOwner ? 'Ιδιοκτήτης' : 'Ομάδα',
                    style: TextStyle(
                      color: context.barberinTextSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!canViewStats)
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: context.barberinTextSecondary,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopNavigationItem {
  const _DesktopNavigationItem(this.label, this.icon, this.index);

  final String label;
  final IconData icon;
  final int index;
}

class _DesktopSidebarRow extends StatelessWidget {
  const _DesktopSidebarRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = !enabled
        ? context.barberinTextSecondary.withValues(alpha: 0.45)
        : selected
        ? scheme.primary
        : context.barberinTextPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: selected ? context.barberinAccentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (selected)
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AppHamburgerMenu extends StatelessWidget {
  const AppHamburgerMenu({super.key});

  @override
  Widget build(BuildContext context) {
    if (_DesktopShellScope.enabledOf(context)) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showAppSideMenu(context),
        child: SizedBox(
          width: 46,
          height: 46,
          child: Center(
            child: Icon(
              Icons.menu_rounded,
              color: context.barberinAccent,
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
    MaterialPageRoute<void>(builder: (_) => _ReturnToPreviousPage(child: page)),
  );
}

class _ReturnToPreviousPage extends StatelessWidget {
  const _ReturnToPreviousPage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        Navigator.of(context).pop();
      },
      child: child,
    );
  }
}

Future<void> showAppSideMenu(BuildContext context) async {
  await showGeneralDialog<void>(
    context: context,
    barrierLabel: 'Μενού',
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
      const SnackBar(
        content: Text('Δεν βρέθηκε ενεργός λογαριασμός Barberin.'),
      ),
    );
    return;
  }

  final isOwner = session.isOwner;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(
          'Διαγραφή λογαριασμού',
          style: TextStyle(color: context.barberinTextPrimary),
        ),
        content: Text(
          isOwner
              ? 'Αυτό θα αφαιρέσει οριστικά τον λογαριασμό ιδιοκτήτη σου στο Barberin από την ενεργή χρήση και θα διαγράψει ολόκληρο τον ενεργό χώρο εργασίας του καταστήματος, μαζί με barber, πελάτες, ραντεβού, προγράμματα, αναφορές και ρυθμίσεις. Ένα περιορισμένο αρχείο διαγραφής μπορεί να διατηρηθεί για λόγους ασφάλειας, ελέγχου ανάκτησης, νομικής συμμόρφωσης ή ελέγχου. Θέλεις να συνεχίσεις;'
              : 'Αυτό θα διαγράψει οριστικά την πρόσβασή σου στο Barberin για αυτό το κατάστημα. Η ενεργή πρόσβασή σου θα αφαιρεθεί αμέσως. Περιορισμένα ιστορικά λειτουργικά δεδομένα μπορεί να παραμείνουν για το ιστορικό ραντεβού, την ακρίβεια των αναφορών, την ασφάλεια ή νομικούς λόγους. Θέλεις να συνεχίσεις;',
          style: TextStyle(color: context.barberinTextSecondary, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8A1F1F),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Διαγραφή λογαριασμού'),
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
      body: jsonEncode({'idToken': idToken, 'shopId': session.shopId}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('barbero-delete-account-failed');
    }
    final decoded =
        jsonDecode(response.body) as Map<String, dynamic>? ??
        <String, dynamic>{};
    final remainingShopCount =
        (decoded['remainingShopCount'] as num?)?.toInt() ?? 0;
    final nextShopId = '${decoded['nextShopId'] ?? ''}'.trim();
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          remainingShopCount > 0
              ? 'Αυτός ο χώρος εργασίας αφαιρέθηκε. Μετάβαση στο επόμενο κατάστημα.'
              : isOwner
              ? 'Ο ενεργός λογαριασμός του καταστήματος διαγράφηκε.'
              : 'Ο λογαριασμός Barberin διαγράφηκε.',
        ),
      ),
    );
    if (remainingShopCount > 0 && nextShopId.isNotEmpty) {
      await switchBarberoActiveShop(nextShopId);
      return;
    }
    currentBarberoAccessibleShops.value = const <BarberoAccessibleShop>[];
    currentBarberoSession.value = null;
    currentBarberoBilling.value = null;
    await _clearPreferredBarberoShopId();
    await FirebaseAuth.instance.signOut();
  } catch (_) {
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      const SnackBar(
        content: Text('Δεν ήταν δυνατή η διαγραφή αυτού του λογαριασμού.'),
      ),
    );
  }
}

Future<void> _openBarberoShopSwitcher(BuildContext context) async {
  final accessibleShops = currentBarberoAccessibleShops.value;
  final currentShopId = currentBarberoSession.value?.shopId ?? '';
  if (accessibleShops.length < 2) {
    return;
  }
  final selectedShopId = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Αλλαγή καταστήματος',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.barberinTextPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Επίλεξε το κατάστημα που θέλεις να διαχειριστείς τώρα.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: context.barberinTextSecondary,
                ),
              ),
              const SizedBox(height: 18),
              ...accessibleShops.map((shop) {
                final isActive = shop.shopId == currentShopId;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: isActive
                          ? null
                          : () => Navigator.of(sheetContext).pop(shop.shopId),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? (sheetContext.barberinIsLight
                                    ? sheetContext.barberinSurfaceAlt
                                    : const Color(0xFF22190E))
                              : (sheetContext.barberinIsLight
                                    ? sheetContext.barberinSurface
                                    : const Color(0xFF161616)),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isActive
                                ? sheetContext.barberinAccent
                                : sheetContext.barberinBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isActive
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.storefront_outlined,
                              size: 18,
                              color: isActive
                                  ? sheetContext.barberinAccent
                                  : sheetContext.barberinTextSecondary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    shop.shopName.isEmpty
                                        ? 'Κατάστημα χωρίς όνομα'
                                        : shop.shopName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: sheetContext.barberinTextPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${shop.roleLabel}${shop.displayName.trim().isEmpty ? '' : ' • ${shop.displayName.trim()}'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: sheetContext.barberinTextSecondary,
                                    ),
                                  ),
                                  if (shop.billing != null) ...[
                                    const SizedBox(height: 7),
                                    Row(
                                      children: [
                                        Container(
                                          width: 7,
                                          height: 7,
                                          decoration: BoxDecoration(
                                            color: shop.billing!.isInTrial
                                                ? const Color(0xFFD9A441)
                                                : shop.billing!.allowsAccess
                                                ? const Color(0xFF4C9A72)
                                                : const Color(0xFFB45D5D),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            shop.billing!.switcherStatusLabel,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: sheetContext
                                                  .barberinTextPrimary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (isActive)
                              Padding(
                                padding: EdgeInsets.only(left: 10),
                                child: Text(
                                  'Ενεργό',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: sheetContext.barberinAccent,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      );
    },
  );

  if (selectedShopId == null || selectedShopId.trim().isEmpty) {
    return;
  }
  if (!context.mounted) {
    return;
  }

  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: Theme.of(dialogContext).colorScheme.surface,
        content: Row(
          children: [
            CircularProgressIndicator(color: dialogContext.barberinAccent),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'Γίνεται αλλαγή καταστήματος...',
                style: TextStyle(color: dialogContext.barberinTextPrimary),
              ),
            ),
          ],
        ),
      );
    },
  );

  try {
    await switchBarberoActiveShop(selectedShopId);
  } catch (_) {
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      const SnackBar(
        content: Text('Δεν ήταν δυνατή η αλλαγή καταστήματος αυτή τη στιγμή.'),
      ),
    );
  } finally {
    navigator.pop();
  }
}

class CustomerAppLinkPage extends StatefulWidget {
  const CustomerAppLinkPage({super.key});

  @override
  State<CustomerAppLinkPage> createState() => _CustomerAppLinkPageState();
}

class _CustomerAppLinkPageState extends State<CustomerAppLinkPage> {
  String _playStoreUrl = '';
  String _appStoreUrl = '';
  String _shopName = '';
  String _status = '';
  String _packageName = '';
  String _bundleId = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLink();
  }

  Future<void> _loadLink() async {
    final user = FirebaseAuth.instance.currentUser;
    final shopId = currentBarberoSession.value?.shopId.trim() ?? '';
    if (user == null || shopId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final response = await http.post(
        Uri.parse(
          'https://europe-west1-barbero-88d00.cloudfunctions.net/barberoGetCustomerAppLink',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'idToken': await user.getIdToken(),
          'shopId': shopId,
        }),
      );
      final decoded = jsonDecode(response.body);
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          decoded is Map<String, dynamic>) {
        final app = decoded['customerApp'] is Map
            ? (decoded['customerApp'] as Map).cast<String, dynamic>()
            : const <String, dynamic>{};
        if (mounted) {
          setState(() {
            _playStoreUrl = '${app['playStoreUrl'] ?? ''}'.trim();
            _appStoreUrl = '${app['appStoreUrl'] ?? ''}'.trim();
            _shopName = '${decoded['shopName'] ?? ''}'.trim();
            _status = '${app['status'] ?? 'provisioning_required'}'.trim();
            _packageName = '${app['packageName'] ?? ''}'.trim();
            _bundleId = '${app['bundleId'] ?? ''}'.trim();
            _loading = false;
          });
        }
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _shopName.isEmpty ? 'Shop application' : _shopName;
    return Scaffold(
      appBar: AppBar(title: const Text('Shop application')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),
          const Text(
            'Η εφαρμογή αυτή είναι μοναδική για το συγκεκριμένο shop και διατίθεται με το δικό του όνομα, branding και store listing.',
          ),
          const SizedBox(height: 24),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            const Text(
              'Το shop έχει ξεχωριστή customer εφαρμογή. Δεν χρησιμοποιείται κοινός κατάλογος ή κοινό join link.',
            ),
            const SizedBox(height: 18),
            _CustomerAppDetailRow(label: 'Κατάσταση', value: _status),
            if (_packageName.isNotEmpty)
              _CustomerAppDetailRow(
                label: 'Android package',
                value: _packageName,
              ),
            if (_bundleId.isNotEmpty)
              _CustomerAppDetailRow(label: 'iOS bundle', value: _bundleId),
            const SizedBox(height: 18),
            if (_playStoreUrl.isNotEmpty)
              FilledButton.icon(
                onPressed: () => _openUrl(_playStoreUrl),
                icon: const Icon(Icons.android_rounded),
                label: const Text('Άνοιγμα Google Play'),
              ),
            if (_appStoreUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _openUrl(_appStoreUrl),
                icon: const Icon(Icons.apple_rounded),
                label: const Text('Άνοιγμα App Store'),
              ),
            ],
            if (_playStoreUrl.isEmpty && _appStoreUrl.isEmpty)
              const Text(
                'Τα links των stores θα εμφανιστούν μόλις ολοκληρωθεί η καταχώριση της εφαρμογής.',
              ),
          ],
        ],
      ),
    );
  }
}

class _CustomerAppDetailRow extends StatelessWidget {
  const _CustomerAppDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: TextStyle(color: context.barberinTextSecondary),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class AddShopPage extends StatefulWidget {
  const AddShopPage({super.key});

  @override
  State<AddShopPage> createState() => _AddShopPageState();
}

class _AddShopPageState extends State<AddShopPage> {
  final ShopRegistrationRepository _repository = ShopRegistrationRepository();
  final ImagePicker _logoPicker = ImagePicker();
  final TextEditingController _ownerNameController = TextEditingController();
  final TextEditingController _ownerPhoneController = TextEditingController();
  final TextEditingController _shopNameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  XFile? _logoFile;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _ownerNameController.text =
        currentBarberoSession.value?.displayName.trim() ?? '';
  }

  @override
  void dispose() {
    _ownerNameController.dispose();
    _ownerPhoneController.dispose();
    _shopNameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _pickShopLogo() async {
    final file = await _logoPicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 88,
    );
    if (!mounted || file == null) return;
    setState(() => _logoFile = file);
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    final ownerName = _ownerNameController.text.trim();
    final ownerPhone = _ownerPhoneController.text.trim();
    final ownerEmail = user?.email?.trim() ?? '';
    final shopName = _shopNameController.text.trim();
    final address = _addressController.text.trim();
    final city = _cityController.text.trim();

    if (user == null || ownerEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Λείπει το ηλεκτρονικό ταχυδρομείο του λογαριασμού ιδιοκτήτη.',
          ),
        ),
      );
      return;
    }
    if (ownerName.isEmpty ||
        ownerPhone.isEmpty ||
        shopName.isEmpty ||
        address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Συμπλήρωσε πρώτα όλα τα πεδία.')),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      var logoBase64 = '';
      var logoContentType = '';
      if (_logoFile != null) {
        final logoBytes = await _logoFile!.readAsBytes();
        final logoPath = _logoFile!.path.toLowerCase();
        logoContentType = logoPath.endsWith('.png')
            ? 'image/png'
            : logoPath.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg';
        logoBase64 = base64Encode(logoBytes);
      }
      final newShopId = await _repository.registerShop(
        ShopRegistrationData(
          shopId: '',
          ownerName: ownerName,
          ownerPhone: ownerPhone,
          ownerEmail: ownerEmail,
          shopName: shopName,
          address: address,
          city: city,
          logoBase64: logoBase64,
          logoContentType: logoContentType,
        ),
      );
      await switchBarberoActiveShop(newShopId);
      if (!mounted) return;
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text(
            'Το νέο κατάστημα δημιουργήθηκε. Ανοίγει ο νέος χώρος εργασίας.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Δεν ήταν δυνατή η δημιουργία του νέου καταστήματος αυτή τη στιγμή.',
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
    final ownerEmail = FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
    return Scaffold(
      backgroundColor: context.barberinBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AuthTopBar(onBack: () => Navigator.of(context).pop()),
              const SizedBox(height: 24),
              Text(
                'Προσθήκη καταστήματος',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: context.barberinTextPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Δημιούργησε άλλο κατάστημα κάτω από τον ίδιο λογαριασμό ιδιοκτήτη. Το νέο κατάστημα θα έχει τη δική του συνδρομή, ομάδα, πρόγραμμα, πελάτες και αναφορές.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: context.barberinTextSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Στοιχεία ιδιοκτήτη'),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: 'Όνομα ιδιοκτήτη',
                    icon: Icons.person_outline_rounded,
                    controller: _ownerNameController,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: 'Τηλέφωνο ιδιοκτήτη',
                    icon: Icons.phone_rounded,
                    controller: _ownerPhoneController,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: 'Ηλεκτρονικό ταχυδρομείο ιδιοκτήτη',
                    icon: Icons.email_outlined,
                    value: ownerEmail,
                  ),
                  const SizedBox(height: 18),
                  const SectionLabel('Στοιχεία καταστήματος'),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: 'Όνομα καταστήματος',
                    icon: Icons.storefront_outlined,
                    controller: _shopNameController,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: 'Διεύθυνση',
                    icon: Icons.location_on_outlined,
                    controller: _addressController,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: '\u03a0\u03cc\u03bb\u03b7',
                    icon: Icons.location_city_outlined,
                    controller: _cityController,
                  ),
                  const SizedBox(height: 18),
                  const SectionLabel('Ταυτότητα καταστήματος'),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: _isSubmitting ? null : _pickShopLogo,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.barberinSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: context.barberinBorder),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: context.barberinSurfaceAlt,
                              borderRadius: BorderRadius.circular(14),
                              image: _logoFile == null
                                  ? null
                                  : DecorationImage(
                                      image: FileImage(File(_logoFile!.path)),
                                      fit: BoxFit.cover,
                                    ),
                            ),
                            child: _logoFile == null
                                ? Icon(
                                    Icons.add_photo_alternate_outlined,
                                    color: context.barberinTextSecondary,
                                    size: 26,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _logoFile == null
                                      ? 'Πρόσθεσε logo καταστήματος (προαιρετικό)'
                                      : 'Το logo επιλέχθηκε',
                                  style: TextStyle(
                                    color: context.barberinTextPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Αν υπάρχει, θα εμφανίζεται στο Customer App και στο shortcut. Διαφορετικά θα χρησιμοποιείται το μονόγραμμα του Barberin.',
                                  style: TextStyle(
                                    color: context.barberinTextSecondary,
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: context.barberinTextSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: _isSubmitting
                        ? 'Δημιουργείται το κατάστημα...'
                        : 'Δημιουργία καταστήματος',
                    onPressed: _isSubmitting ? () {} : _submit,
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

class _AppSideMenuSheet extends StatelessWidget {
  const _AppSideMenuSheet();

  @override
  Widget build(BuildContext context) {
    final session = currentBarberoSession.value;
    final permissions = session?.permissions;
    final scheme = Theme.of(context).colorScheme;
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
              decoration: BoxDecoration(
                color: scheme.surface,
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
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.menu_rounded,
                                    color: scheme.primary,
                                    size: 22,
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    '\u039c\u0395\u039d\u039f\u03a5',
                                    style: TextStyle(
                                      fontSize: 12,
                                      letterSpacing: 1.3,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 22),
                              if (currentBarberoAccessibleShops.value.length >
                                  1) ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.only(bottom: 14),
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
                                        'Τρέχον κατάστημα',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.6,
                                          color: scheme.primary,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        session?.shopName.trim().isNotEmpty ==
                                                true
                                            ? session!.shopName.trim()
                                            : 'Κατάστημα χωρίς όνομα',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: context.barberinTextPrimary,
                                        ),
                                      ),
                                      if (session?.displayName
                                              .trim()
                                              .isNotEmpty ==
                                          true) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          '${session!.isOwner ? 'Ιδιοκτήτης' : 'Ομάδα'} • ${session.displayName.trim()}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color:
                                                context.barberinTextSecondary,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 12),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: OutlinedButton.icon(
                                          onPressed: () {
                                            final rootContext =
                                                rootScaffoldMessengerKey
                                                    .currentContext ??
                                                context;
                                            Navigator.of(context).pop();
                                            unawaited(
                                              _openBarberoShopSwitcher(
                                                rootContext,
                                              ),
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.sync_alt_rounded,
                                            size: 16,
                                          ),
                                          label: const Text(
                                            'Αλλαγή καταστήματος',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                              ],
                              if (session?.isOwner == true &&
                                  currentBarberoAccessibleShops.value.length >
                                      1) ...[
                                _SideMenuItem(
                                  icon: Icons.dashboard_outlined,
                                  label: 'Ενιαίο dashboard',
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    _openBarberoMenuPage(
                                      context,
                                      const UnifiedDashboardPage(),
                                    );
                                  },
                                ),
                              ],
                              if (isBarberinPlatformAdmin) ...[
                                _SideMenuItem(
                                  icon: Icons.admin_panel_settings_outlined,
                                  label: 'Barberin Admin',
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    _openBarberoMenuPage(
                                      context,
                                      const PlatformAdminPage(),
                                    );
                                  },
                                ),
                              ],
                              if (permissions?.manageCrew == true) ...[
                                _SideMenuItem(
                                  icon: Icons.groups_rounded,
                                  label: 'Barbers',
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    _openBarberoMenuPage(
                                      context,
                                      CrewManagementPage(
                                        initialMembers:
                                            currentBarberoLiveBarbers.value,
                                      ),
                                    );
                                  },
                                ),
                              ],
                              if (permissions?.editSchedule == true) ...[
                                _SideMenuItem(
                                  icon: Icons.tune_rounded,
                                  label:
                                      '\u0394\u03b9\u03b1\u03c7\u03b5\u03af\u03c1\u03b9\u03c3\u03b7 \u03c5\u03c0\u03b7\u03c1\u03b5\u03c3\u03b9\u03ce\u03bd',
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    _openBarberoMenuPage(
                                      context,
                                      const ServicesManagementPage(),
                                    );
                                  },
                                ),
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
                                _SideMenuItem(
                                  icon: Icons.event_busy_rounded,
                                  label:
                                      '\u0391\u03c1\u03b3\u03af\u03b5\u03c2 \u03ba\u03b1\u03b9 \u0394\u03b9\u03b1\u03ba\u03bf\u03c0\u03ad\u03c2',
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    _openBarberoMenuPage(
                                      context,
                                      const GreekHolidaysPage(),
                                    );
                                  },
                                ),
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
                              ],
                              if (session?.isOwner == true) ...[
                                _SideMenuItem(
                                  icon: Icons.qr_code_2_rounded,
                                  label: 'Customer app link',
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    _openBarberoMenuPage(
                                      context,
                                      const CustomerAppLinkPage(),
                                    );
                                  },
                                ),
                                _SideMenuItem(
                                  icon: Icons.add_business_rounded,
                                  label: 'Προσθήκη καταστήματος',
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    _openBarberoMenuPage(
                                      context,
                                      const AddShopPage(),
                                    );
                                  },
                                ),
                                _SideMenuItem(
                                  icon: Icons.workspace_premium_outlined,
                                  label: 'Συνδρομή',
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    _openBarberoMenuPage(
                                      context,
                                      const BarberoBillingPage(),
                                    );
                                  },
                                ),
                              ],
                              _SideMenuItem(
                                icon: Icons.settings_outlined,
                                label: 'Ρυθμίσεις',
                                onTap: () {
                                  Navigator.of(context).pop();
                                  _openBarberoMenuPage(
                                    context,
                                    const BarberinSettingsPage(),
                                  );
                                },
                              ),
                              _SideMenuItem(
                                icon: Icons.help_outline_rounded,
                                label: 'Κέντρο βοήθειας',
                                onTap: () {
                                  Navigator.of(context).pop();
                                  _openBarberoMenuPage(
                                    context,
                                    const BarberoHelpCenterPage(),
                                  );
                                },
                              ),
                              _SideMenuItem(
                                icon: Icons.privacy_tip_outlined,
                                label: 'Πολιτική απορρήτου',
                                onTap: () {
                                  Navigator.of(context).pop();
                                  _openBarberoMenuPage(
                                    context,
                                    const BarberoPrivacyPolicyPage(),
                                  );
                                },
                              ),
                              _SideMenuItem(
                                icon: Icons.gavel_rounded,
                                label: 'Όροι και προϋποθέσεις',
                                onTap: () {
                                  Navigator.of(context).pop();
                                  _openBarberoMenuPage(
                                    context,
                                    const BarberoTermsPage(),
                                  );
                                },
                              ),
                              _SideMenuItem(
                                icon: Icons.logout_rounded,
                                label: 'Αποσύνδεση',
                                onTap: () async {
                                  Navigator.of(context).pop();
                                  await FirebaseAuth.instance.signOut();
                                },
                              ),
                              const SizedBox(height: 14),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: null,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () async {
                                final dialogContext =
                                    rootScaffoldMessengerKey.currentContext ??
                                    context;
                                Navigator.of(context).pop();
                                await _openBarberoDeleteAccountFlow(
                                  dialogContext,
                                );
                              },
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                size: 16,
                                color: scheme.onSurfaceVariant,
                              ),
                              label: Text(
                                'Διαγραφή λογαριασμού',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 4,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 13),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.barberinBorder)),
          ),
          child: Row(
            children: [
              Icon(icon, color: scheme.primary, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.barberinTextPrimary,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: context.barberinTextSecondary,
                size: 18,
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
  })
  onLoadSlots;
  final Future<void> Function({
    required String barberId,
    required String barberName,
    required DateTime date,
    required String startTime,
  })
  onSave;

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
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Theme.of(context).colorScheme.primary,
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
        const SnackBar(
          content: Text(
            'Δεν ήταν δυνατός ο επαναπρογραμματισμός του ραντεβού.',
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
              Text(
                'Επαναπρογραμματισμός ραντεβού',
                style: TextStyle(
                  color: context.barberinTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.appointment.name,
                style: TextStyle(
                  color: context.barberinTextSecondary,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Barber',
                style: TextStyle(
                  color: context.barberinTextPrimary,
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
                    selectedColor: context.barberinAccent,
                    backgroundColor: context.barberinSurfaceAlt,
                    labelStyle: TextStyle(
                      color: selected
                          ? Theme.of(context).colorScheme.onPrimary
                          : context.barberinTextPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    side: BorderSide(color: context.barberinBorder),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              Text(
                'Ημερομηνία',
                style: TextStyle(
                  color: context.barberinTextPrimary,
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
                    color: context.barberinSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.barberinBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        color: context.barberinAccent,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        barberinDateLabel(_selectedDate),
                        style: TextStyle(
                          color: context.barberinTextPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Διαθέσιμες ώρες',
                style: TextStyle(
                  color: context.barberinTextPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              if (_loadingSlots)
                Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: CircularProgressIndicator(
                      color: context.barberinAccent,
                    ),
                  ),
                )
              else if (_slots.isEmpty)
                Text(
                  'Δεν υπάρχουν διαθέσιμα slot για αυτή την ημερομηνία.',
                  style: TextStyle(color: context.barberinTextSecondary),
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
                      selectedColor: context.barberinAccent,
                      backgroundColor: context.barberinSurfaceAlt,
                      labelStyle: TextStyle(
                        color: selected
                            ? Theme.of(context).colorScheme.onPrimary
                            : context.barberinTextPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      side: BorderSide(color: context.barberinBorder),
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
                        side: BorderSide(color: context.barberinBorder),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        foregroundColor: context.barberinTextPrimary,
                      ),
                      child: const Text('ΚΛΕΙΣΙΜΟ'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saving || _selectedTime == null
                          ? null
                          : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.barberinAccent,
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _saving
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            )
                          : const Text(
                              'ΑΠΟΘΗΚΕΥΣΗ',
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
    required this.serviceAddOns,
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
  final List<ServiceAddOnSetting> serviceAddOns;
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
    required List<String> addOnKeys,
    required String blockReason,
  })
  onSave;

  @override
  State<_QuickAddAppointmentSheet> createState() =>
      _QuickAddAppointmentSheetState();
}

class _QuickAddAppointmentSheetState extends State<_QuickAddAppointmentSheet> {
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerPhoneController =
      TextEditingController();
  final TextEditingController _customerEmailController =
      TextEditingController();
  final TextEditingController _blockReasonController = TextEditingController();
  bool _blocked = false;
  bool _loadingSlots = false;
  bool _saving = false;
  late CrewMember _selectedBarber;
  late DateTime _selectedDate;
  late List<ServiceDurationSetting> _serviceOptions;
  late Map<String, int> _priceByServiceKey;
  ServiceDurationSetting? _selectedService;
  final Set<String> _selectedAddOnKeys = <String>{};
  int _blockedMinutes = 30;
  List<String> _availableSlots = const <String>[];
  String? _selectedTime;
  String? _preferredTime;

  List<ServiceDurationSetting> get _servicesForSelectedBarber => widget
      .serviceDurations
      .where((service) => service.isAvailableForBarber(_selectedBarber.id))
      .toList(growable: false);

  List<ServiceAddOnSetting> get _availableAddOns {
    final serviceKey = _selectedService?.key.trim() ?? '';
    if (serviceKey.isEmpty || serviceKey == 'beard_trim') {
      return const <ServiceAddOnSetting>[];
    }
    return widget.serviceAddOns
        .where((addOn) => addOn.appliesToService(serviceKey))
        .toList(growable: false);
  }

  int get _effectiveMinutes {
    if (_blocked) {
      return _blockedMinutes;
    }
    final addOnMinutes = _availableAddOns
        .where((addOn) => _selectedAddOnKeys.contains(addOn.key))
        .fold<int>(0, (total, addOn) => total + addOn.minutes);
    return (_selectedService?.minutes ?? widget.slotMinutes) + addOnMinutes;
  }

  int get _effectivePrice {
    if (_blocked) {
      return 0;
    }
    final key = _selectedService?.key ?? '';
    final addOnPrice = _availableAddOns
        .where((addOn) => _selectedAddOnKeys.contains(addOn.key))
        .fold<int>(0, (total, addOn) => total + addOn.price);
    return (_priceByServiceKey[key] ?? 0) + addOnPrice;
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
    _serviceOptions = _servicesForSelectedBarber;
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
        _selectedTime = slots.contains(preferredTime)
            ? preferredTime
            : slots.first;
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
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: const Color(0xFFD1A45C)),
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
        serviceLabel: _blocked
            ? 'Κλειστό slot'
            : (_selectedService?.label ?? ''),
        addOnKeys: _blocked ? const <String>[] : _selectedAddOnKeys.toList(),
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
                ? 'Δεν ήταν δυνατό το κλείσιμο αυτού του slot.'
                : 'Δεν ήταν δυνατή η δημιουργία χειροκίνητου ραντεβού.',
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
    final scheme = Theme.of(context).colorScheme;
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
              Text(
                'Γρήγορη προσθήκη',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Χειροκίνητο ραντεβού'),
                    icon: Icon(Icons.event_available_rounded),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Κλείσιμο slot'),
                    icon: Icon(Icons.block_rounded),
                  ),
                ],
                selected: {_blocked},
                style: ButtonStyle(
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? scheme.onPrimary
                        : scheme.onSurface,
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? scheme.primary
                        : scheme.surfaceContainerHighest,
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
                decoration: _darkFieldDecoration('barber'),
                dropdownColor: scheme.surface,
                items: widget.barbers
                    .map(
                      (barber) => DropdownMenuItem<String>(
                        value: barber.id,
                        child: Text(
                          barber.fullName,
                          style: TextStyle(color: scheme.onSurface),
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
                    _serviceOptions = _servicesForSelectedBarber;
                    _selectedService = _serviceOptions.isEmpty
                        ? null
                        : _serviceOptions.first;
                    _selectedAddOnKeys.clear();
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
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: scheme.outline),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        color: scheme.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          barberinDateLabel(_selectedDate),
                          style: TextStyle(
                            color: scheme.onSurface,
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
                  decoration: _darkFieldDecoration('Διάρκεια κλεισίματος'),
                  dropdownColor: scheme.surface,
                  items: blockedDurations
                      .map(
                        (minutes) => DropdownMenuItem<int>(
                          value: minutes,
                          child: Text(
                            "$minutes'",
                            style: TextStyle(color: scheme.onSurface),
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
                  isExpanded: true,
                  initialValue: _selectedService?.key,
                  decoration: _darkFieldDecoration('Υπηρεσία'),
                  dropdownColor: scheme.surface,
                  items: _serviceOptions
                      .map(
                        (service) => DropdownMenuItem<String>(
                          value: service.key,
                          child: Text(
                            '${service.label} • ${service.minutes} λεπτά • EUR ${_priceByServiceKey[service.key] ?? 0}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: TextStyle(color: scheme.onSurface),
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
                      _selectedAddOnKeys.clear();
                    });
                    await _reloadSlots();
                  },
                ),
              if (_availableAddOns.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  '\u03a0\u03c1\u03bf\u03b1\u03b9\u03c1\u03b5\u03c4\u03b9\u03ba\u03ac \u03c0\u03c1\u03cc\u03c3\u03b8\u03b5\u03c4\u03b1',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                ..._availableAddOns.map(
                  (addOn) => CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _selectedAddOnKeys.contains(addOn.key),
                    title: Text(
                      addOn.label,
                      style: TextStyle(color: scheme.onSurface),
                    ),
                    subtitle: Text(
                      '+${addOn.minutes} λεπτά · +${addOn.price} EUR',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    activeColor: scheme.primary,
                    onChanged: (value) async {
                      setState(() {
                        if (value == true) {
                          _selectedAddOnKeys.add(addOn.key);
                        } else {
                          _selectedAddOnKeys.remove(addOn.key);
                        }
                      });
                      await _reloadSlots();
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (_loadingSlots)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                    child: CircularProgressIndicator(color: scheme.primary),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _selectedTime,
                  decoration: _darkFieldDecoration('Ώρα'),
                  dropdownColor: scheme.surface,
                  items: _availableSlots
                      .map(
                        (time) => DropdownMenuItem<String>(
                          value: time,
                          child: Text(
                            time,
                            style: TextStyle(color: scheme.onSurface),
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
                Text(
                  'Δεν υπάρχουν διαθέσιμα slot για την τρέχουσα επιλογή.',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (_blocked)
                TextField(
                  controller: _blockReasonController,
                  style: TextStyle(color: scheme.onSurface),
                  decoration: _darkFieldDecoration(
                    'Αιτία κλεισίματος (προαιρετικά)',
                  ),
                  maxLines: 2,
                )
              else ...[
                TextField(
                  controller: _customerNameController,
                  style: TextStyle(color: scheme.onSurface),
                  decoration: _darkFieldDecoration('Όνομα πελάτη'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _customerPhoneController,
                  keyboardType: TextInputType.phone,
                  style: TextStyle(color: scheme.onSurface),
                  decoration: _darkFieldDecoration('Τηλέφωνο'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _customerEmailController,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(color: scheme.onSurface),
                  decoration: _darkFieldDecoration(
                    'Ηλεκτρονικό ταχυδρομείο (προαιρετικά)',
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: scheme.primary,
                        side: BorderSide(color: scheme.outline),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('ΚΛΕΙΣΙΜΟ'),
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
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _saving
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: scheme.onPrimary,
                              ),
                            )
                          : Text(
                              _blocked ? 'ΚΛΕΙΣΙΜΟ SLOT' : 'ΑΠΟΘΗΚΕΥΣΗ',
                              style: const TextStyle(
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
  }
}

InputDecoration _darkFieldDecoration(String label) {
  final isLight = barberinThemeMode.value == ThemeMode.light;
  final fieldBorder = isLight
      ? const Color(0xFFD9E0E8)
      : const Color(0xFF2A2A2A);
  final fieldLabel = isLight
      ? const Color(0xFF64748B)
      : const Color(0xFFB9B1A5);
  return InputDecoration(
    labelText: barberinTranslate(label),
    labelStyle: TextStyle(color: fieldLabel),
    filled: false,
    enabledBorder: UnderlineInputBorder(
      borderSide: BorderSide(color: fieldBorder),
    ),
    focusedBorder: UnderlineInputBorder(
      borderSide: BorderSide(
        color: isLight ? const Color(0xFF1F2937) : const Color(0xFFD1A45C),
      ),
    ),
  );
}
