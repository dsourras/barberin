part of 'main.dart';

class WeeklySchedulePage extends StatefulWidget {
  const WeeklySchedulePage({super.key});

  @override
  State<WeeklySchedulePage> createState() => _WeeklySchedulePageState();
}

class _WeeklySchedulePageState extends State<WeeklySchedulePage> {
  late final List<ScheduleDay> schedule = [
    const ScheduleDay(
      name: 'Monday',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
    const ScheduleDay(
      name: 'Tuesday',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
    const ScheduleDay(
      name: 'Wednesday',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
    const ScheduleDay(
      name: 'Thursday',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
    const ScheduleDay(
      name: 'Friday',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
    const ScheduleDay(
      name: 'Saturday',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
    const ScheduleDay(
      name: 'Sunday',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
  ];

  int slotMinutes = 30;
  int appointmentsPerSlot = 1;
  List<SlotCapacityOverride> slotCapacityOverrides =
      const <SlotCapacityOverride>[];
  List<BarberWeeklySchedule> barberSchedules =
      const <BarberWeeklySchedule>[];
  List<ServiceDurationSetting> serviceDurations =
      buildDefaultServiceDurations();
  List<ServicePriceSetting> servicePrices = buildDefaultServicePrices();
  bool showPrices = false;
  bool isLoading = true;
  bool isSaving = false;
  bool _editingPerBarber = false;
  List<CrewMember> _barbers = const <CrewMember>[];
  String? _selectedBarberId;
  static final scheduleRepository = WeeklyScheduleRepository();

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  int get enabledDays => schedule.where((day) => day.enabled).length;
  int get closedDays => schedule.length - enabledDays;

  List<ScheduleDay> get _activeScheduleDays {
    if (!_editingPerBarber || (_selectedBarberId?.trim().isEmpty ?? true)) {
      return schedule;
    }
    final selectedBarberId = _selectedBarberId!.trim();
    final existing = barberSchedules.cast<BarberWeeklySchedule?>().firstWhere(
          (item) => item?.barberId.trim() == selectedBarberId,
          orElse: () => null,
        );
    if (existing != null) {
      return existing.days;
    }
    return schedule.map((day) => day.copyWith()).toList(growable: false);
  }

  int get totalHours {
    int minutes = 0;
    for (final day in _activeScheduleDays.where((day) => day.enabled)) {
      minutes += _toMinutes(day.end) - _toMinutes(day.start);
      if (day.breakStart != '--:--' && day.breakEnd != '--:--') {
        minutes -= _toMinutes(day.breakEnd) - _toMinutes(day.breakStart);
      }
    }
    return minutes ~/ 60;
  }

  int _toMinutes(String value) {
    if (value == '--:--') {
      return 0;
    }
    final parts = value.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  void _updateDay(int index, ScheduleDay value) {
    setState(() {
      if (!_editingPerBarber || (_selectedBarberId?.trim().isEmpty ?? true)) {
        schedule[index] = value;
        return;
      }
      final selectedBarberId = _selectedBarberId!.trim();
      final next = List<BarberWeeklySchedule>.from(barberSchedules);
      final existingIndex = next.indexWhere(
        (item) => item.barberId.trim() == selectedBarberId,
      );
      final baseDays = existingIndex >= 0
          ? List<ScheduleDay>.from(next[existingIndex].days)
          : schedule.map((day) => day.copyWith()).toList();
      baseDays[index] = value;
      final nextEntry = BarberWeeklySchedule(
        barberId: selectedBarberId,
        days: baseDays,
      );
      if (existingIndex >= 0) {
        next[existingIndex] = nextEntry;
      } else {
        next.add(nextEntry);
      }
      barberSchedules = next;
    });
    _saveSchedule();
  }

  Future<void> _loadBarbers() async {
    try {
      final shopId = requireCurrentBarberoSession().shopId;
      final snapshot =
          await FirebaseDatabase.instance.ref('shops/$shopId/barbers').get();
      final rawBarbers = _mapFromRawValue(snapshot.value) ?? <String, dynamic>{};
      final parsed = <CrewMember>[];
      for (final entry in rawBarbers.entries) {
        final value = _mapFromRawValue(entry.value);
        if (value == null) {
          continue;
        }
        final member = CrewMember.fromJson(entry.key, value);
        if (member.fullName.trim().isEmpty) {
          continue;
        }
        parsed.add(member);
      }
      parsed.sort(
        (left, right) =>
            left.fullName.toLowerCase().compareTo(right.fullName.toLowerCase()),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _barbers = parsed;
        _selectedBarberId ??=
            parsed.isEmpty ? null : parsed.first.id.trim();
      });
    } catch (_) {}
  }

  Future<void> _loadSchedule() async {
    try {
      final remote = await scheduleRepository.loadOrCreateDefault();
      await _loadBarbers();
      if (!mounted) return;
      setState(() {
        slotMinutes = remote.slotMinutes;
        appointmentsPerSlot = remote.appointmentsPerSlot;
        slotCapacityOverrides = List<SlotCapacityOverride>.from(
          remote.slotCapacityOverrides,
        );
        barberSchedules = List<BarberWeeklySchedule>.from(
          remote.barberSchedules,
        );
        serviceDurations = List<ServiceDurationSetting>.from(
          remote.serviceDurations,
        );
        servicePrices = List<ServicePriceSetting>.from(remote.servicePrices);
        showPrices = remote.showPrices;
        schedule
          ..clear()
          ..addAll(remote.days);
        if (_selectedBarberId == null && _barbers.isNotEmpty) {
          _selectedBarberId = _barbers.first.id.trim();
        }
      });
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _saveSchedule() async {
    if (!mounted) return;
    setState(() => isSaving = true);
    try {
      await scheduleRepository.save(
        slotMinutes: slotMinutes,
        appointmentsPerSlot: appointmentsPerSlot,
        slotCapacityOverrides: slotCapacityOverrides,
        barberSchedules: barberSchedules,
        serviceDurations: serviceDurations,
        servicePrices: servicePrices,
        showPrices: showPrices,
        days: schedule,
      );
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  TimeOfDay _parseTime(String value) {
    if (value == '--:--') {
      return const TimeOfDay(hour: 9, minute: 0);
    }
    final parts = value.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _formatTime(TimeOfDay value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _pickStartTime(int index) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _parseTime(_activeScheduleDays[index].start),
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
    _updateDay(
      index,
      _activeScheduleDays[index].copyWith(start: _formatTime(picked)),
    );
  }

  Future<void> _pickEndTime(int index) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _parseTime(_activeScheduleDays[index].end),
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
    _updateDay(
      index,
      _activeScheduleDays[index].copyWith(end: _formatTime(picked)),
    );
  }

  Future<void> _pickBreakStart(int index) async {
    final day = _activeScheduleDays[index];
    final initialValue = day.breakStart == '--:--'
        ? day.start
        : day.breakStart;
    final picked = await showTimePicker(
      context: context,
      initialTime: _parseTime(initialValue),
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
    final formatted = _formatTime(picked);
    _updateDay(
      index,
      day.copyWith(
        breakStart: formatted,
        breakEnd: day.breakEnd == '--:--'
            ? formatted
            : day.breakEnd,
      ),
    );
  }

  Future<void> _pickBreakEnd(int index) async {
    final day = _activeScheduleDays[index];
    final initialValue = day.breakEnd == '--:--'
        ? day.end
        : day.breakEnd;
    final picked = await showTimePicker(
      context: context,
      initialTime: _parseTime(initialValue),
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
    final formatted = _formatTime(picked);
    _updateDay(
      index,
      day.copyWith(
        breakStart: day.breakStart == '--:--'
            ? formatted
            : day.breakStart,
        breakEnd: formatted,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF121212), Color(0xFF090909)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    AppHamburgerMenu(),
                    SizedBox(width: 8),
                    Text(
                      '\u03a1\u03a5\u0398\u039c\u0399\u03a3\u0395\u0399\u03a3',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFD1A45C),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  '\u0395\u03b2\u03b4\u03bf\u03bc\u03b1\u03b4\u03b9\u03b1\u03af\u03bf \u03c0\u03c1\u03cc\u03b3\u03c1\u03b1\u03bc\u03bc\u03b1',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF5ECDD),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '\u0399\u03c3\u03c7\u03cd\u03b5\u03b9 \u03bc\u03cc\u03bd\u03b9\u03bc\u03b1 \u03b3\u03b9\u03b1 \u03cc\u03bb\u03b5\u03c2 \u03c4\u03b9\u03c2 \u03b5\u03b2\u03b4\u03bf\u03bc\u03ac\u03b4\u03b5\u03c2.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF8C8C8C)),
                ),
                const SizedBox(height: 10),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('General'),
                      icon: Icon(Icons.storefront_outlined),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('Per barber'),
                      icon: Icon(Icons.content_cut_rounded),
                    ),
                  ],
                  selected: {_editingPerBarber},
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
                  onSelectionChanged: (selection) {
                    setState(() {
                      _editingPerBarber = selection.first;
                      if (_editingPerBarber &&
                          (_selectedBarberId == null || _selectedBarberId!.isEmpty) &&
                          _barbers.isNotEmpty) {
                        _selectedBarberId = _barbers.first.id.trim();
                      }
                    });
                  },
                ),
                if (_editingPerBarber) ...[
                  const SizedBox(height: 10),
                  if (_barbers.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF242424)),
                      ),
                      child: const Text(
                        'No barbers available yet. Add a barber first to set a personal weekly schedule.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFFB9B1A5),
                        ),
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _selectedBarberId,
                      decoration: _darkFieldDecoration('Barber'),
                      dropdownColor: const Color(0xFF181818),
                      items: _barbers
                          .map(
                            (barber) => DropdownMenuItem<String>(
                              value: barber.id.trim(),
                              child: Text(
                                barber.fullName,
                                style: const TextStyle(
                                  color: Color(0xFFF0E5D1),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _selectedBarberId = value.trim());
                      },
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'If a barber does not have a personal schedule, they automatically inherit the general shop schedule.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF8C8C8C)),
                  ),
                ],
                const SizedBox(height: 10),
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: Color(0xFFD1A45C),
                      backgroundColor: Color(0xFF242424),
                    ),
                  ),
                if (!isLoading && isSaving)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: Color(0xFFD1A45C),
                      backgroundColor: Color(0xFF242424),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: CompactStatCard(
                        value: '$enabledDays',
                        caption: '\u0395\u039d\u0395\u03a1\u0393\u0395\u03a3',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CompactStatCard(
                        value: '${totalHours}h',
                        caption: '\u03a9\u03a1\u0395\u03a3',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CompactStatCard(
                        value: '$closedDays',
                        caption:
                            '\u039a\u039b\u0395\u0399\u03a3\u03a4\u0395\u03a3',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    itemCount: _activeScheduleDays.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final activeDay = _activeScheduleDays[index];
                      return ScheduleDayCard(
                        day: activeDay,
                        onChanged: (value) => _updateDay(index, value),
                        onTapStart: activeDay.enabled
                            ? () => _pickStartTime(index)
                            : null,
                        onTapEnd: activeDay.enabled
                            ? () => _pickEndTime(index)
                            : null,
                        onTapBreakStart: activeDay.enabled
                            ? () => _pickBreakStart(index)
                            : null,
                        onTapBreakEnd: activeDay.enabled
                            ? () => _pickBreakEnd(index)
                            : null,
                      );
                    },
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

class CompactStatCard extends StatelessWidget {
  const CompactStatCard({
    super.key,
    required this.value,
    required this.caption,
  });

  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1C1A18), Color(0xFF131313)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3127)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFFF2E3C8),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            style: const TextStyle(
              fontSize: 8.5,
              color: Color(0xFFC7B18A),
              letterSpacing: .7,
            ),
          ),
        ],
      ),
    );
  }
}

class SlotSettingsCard extends StatelessWidget {
  const SlotSettingsCard({
    super.key,
    required this.appointmentsPerSlot,
    required this.serviceDurations,
    required this.onServiceDurationsTap,
    required this.onAppointmentsPerSlotTap,
  });

  final int appointmentsPerSlot;
  final List<ServiceDurationSetting> serviceDurations;
  final VoidCallback onServiceDurationsTap;
  final VoidCallback onAppointmentsPerSlotTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ScheduleInfoTile(
              label:
                  '\u0394\u0399\u0391\u03a1\u039a\u0395\u0399\u0395\u03a3 \u03a5\u03a0\u0397\u03a1\u0395\u03a3\u0399\u03a9\u039d',
              value:
                  '${serviceDurations.length} \u03c5\u03c0\u03b7\u03c1\u03b5\u03c3\u03af\u03b5\u03c2',
              onTap: onServiceDurationsTap,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ScheduleInfoTile(
              label:
                  '\u03a1\u0391\u039d\u03a4\u0395\u0392\u039f\u03a5 \u0391\u039d\u0391 SLOT',
              value: '$appointmentsPerSlot',
              onTap: onAppointmentsPerSlotTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleInfoTile extends StatelessWidget {
  const _ScheduleInfoTile({
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9.5,
            letterSpacing: 1,
            fontWeight: FontWeight.w700,
            color: Color(0xFF9A8158),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFFF2E3C8),
          ),
        ),
      ],
    );
    if (onTap == null) return body;
    return GestureDetector(onTap: onTap, child: body);
  }
}

class _ServiceDurationEditor extends StatelessWidget {
  const _ServiceDurationEditor({
    required this.service,
    required this.onChanged,
  });

  final ServiceDurationSetting service;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  service.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF2E3C8),
                  ),
                ),
              ),
              Text(
                '${service.minutes} \u03bb\u03b5\u03c0\u03c4\u03ac',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFD1A45C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFFD1A45C),
              inactiveTrackColor: const Color(0xFF2A2A2A),
              thumbColor: const Color(0xFFD1A45C),
              overlayColor: const Color(0x33D1A45C),
            ),
            child: Slider(
              min: 5,
              max: 120,
              divisions: 23,
              value: service.minutes.clamp(5, 120).toDouble(),
              label: '${service.minutes}',
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServicePriceEditor extends StatelessWidget {
  const _ServicePriceEditor({required this.service, required this.onChanged});

  final ServicePriceSetting service;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  service.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF2E3C8),
                  ),
                ),
              ),
              Text(
                '\u20ac${service.price}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFD1A45C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFFD1A45C),
              inactiveTrackColor: const Color(0xFF2A2A2A),
              thumbColor: const Color(0xFFD1A45C),
              overlayColor: const Color(0x33D1A45C),
            ),
            child: Slider(
              min: 0,
              max: 100,
              divisions: 100,
              value: service.price.clamp(0, 100).toDouble(),
              label: '${service.price}',
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class ServiceDurationsPage extends StatefulWidget {
  const ServiceDurationsPage({super.key});

  @override
  State<ServiceDurationsPage> createState() => _ServiceDurationsPageState();
}

class _ServiceDurationsPageState extends State<ServiceDurationsPage> {
  final WeeklyScheduleRepository _repository = WeeklyScheduleRepository();
  int slotMinutes = 30;
  int appointmentsPerSlot = 1;
  List<SlotCapacityOverride> slotCapacityOverrides =
      const <SlotCapacityOverride>[];
  List<BarberWeeklySchedule> barberSchedules =
      const <BarberWeeklySchedule>[];
  List<ScheduleDay> days = buildDefaultWeeklySchedule();
  List<ServiceDurationSetting> serviceDurations =
      buildDefaultServiceDurations();
  List<ServicePriceSetting> servicePrices = buildDefaultServicePrices();
  bool showPrices = false;
  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final remote = await _repository.loadOrCreateDefault();
      if (!mounted) return;
      setState(() {
        slotMinutes = remote.slotMinutes;
        appointmentsPerSlot = remote.appointmentsPerSlot;
        slotCapacityOverrides = List<SlotCapacityOverride>.from(
          remote.slotCapacityOverrides,
        );
        barberSchedules = List<BarberWeeklySchedule>.from(
          remote.barberSchedules,
        );
        serviceDurations = List<ServiceDurationSetting>.from(
          remote.serviceDurations,
        );
        servicePrices = List<ServicePriceSetting>.from(remote.servicePrices);
        showPrices = remote.showPrices;
        days = List<ScheduleDay>.from(remote.days);
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _save() async {
    if (!mounted) return;
    setState(() => isSaving = true);
    try {
      await _repository.save(
        slotMinutes: slotMinutes,
        appointmentsPerSlot: appointmentsPerSlot,
        slotCapacityOverrides: slotCapacityOverrides,
        barberSchedules: barberSchedules,
        serviceDurations: serviceDurations,
        servicePrices: servicePrices,
        showPrices: showPrices,
        days: days,
      );
    } catch (_) {
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF121212), Color(0xFF090909)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    AppHamburgerMenu(),
                    SizedBox(width: 8),
                    Text(
                      '\u03a1\u03a5\u0398\u039c\u0399\u03a3\u0395\u0399\u03a3',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFD1A45C),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  '\u0394\u03b9\u03b1\u03c1\u03ba\u03b5\u03af\u03b5\u03c2 \u03c5\u03c0\u03b7\u03c1\u03b5\u03c3\u03b9\u03ce\u03bd',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF5ECDD),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '\u03a1\u03cd\u03b8\u03bc\u03b9\u03c3\u03b5 \u03c4\u03bf \u03b2\u03b1\u03c3\u03b9\u03ba\u03cc slot \u03ba\u03b1\u03b9 \u03ba\u03ac\u03b8\u03b5 \u03c5\u03c0\u03b7\u03c1\u03b5\u03c3\u03af\u03b1 \u03be\u03b5\u03c7\u03c9\u03c1\u03b9\u03c3\u03c4\u03ac.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF8C8C8C)),
                ),
                const SizedBox(height: 10),
                if (isLoading || isSaving)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: Color(0xFFD1A45C),
                      backgroundColor: Color(0xFF242424),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF242424)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '\u0392\u03b1\u03c3\u03b9\u03ba\u03cc slot',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFF2E3C8),
                              ),
                            ),
                          ),
                          Text(
                            '$slotMinutes \u03bb\u03b5\u03c0\u03c4\u03ac',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFD1A45C),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFFD1A45C),
                          inactiveTrackColor: const Color(0xFF2A2A2A),
                          thumbColor: const Color(0xFFD1A45C),
                          overlayColor: const Color(0x33D1A45C),
                        ),
                        child: Slider(
                          min: 5,
                          max: 60,
                          divisions: 55,
                          value: slotMinutes.toDouble().clamp(5, 60),
                          label: '$slotMinutes',
                          onChanged: (value) {
                            setState(() => slotMinutes = value.round());
                          },
                          onChangeEnd: (_) => _save(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    itemCount: serviceDurations.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final service = serviceDurations[index];
                      return _ServiceDurationEditor(
                        service: service,
                        onChanged: (value) {
                          setState(() {
                            serviceDurations[index] = service.copyWith(
                              minutes: value.round(),
                            );
                          });
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  label:
                      '\u0391\u03c0\u03bf\u03b8\u03ae\u03ba\u03b5\u03c5\u03c3\u03b7',
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ServicePricesPage extends StatefulWidget {
  const ServicePricesPage({super.key});

  @override
  State<ServicePricesPage> createState() => _ServicePricesPageState();
}

class _ServicePricesPageState extends State<ServicePricesPage> {
  final WeeklyScheduleRepository _repository = WeeklyScheduleRepository();
  int slotMinutes = 30;
  int appointmentsPerSlot = 1;
  List<SlotCapacityOverride> slotCapacityOverrides =
      const <SlotCapacityOverride>[];
  List<BarberWeeklySchedule> barberSchedules =
      const <BarberWeeklySchedule>[];
  List<ScheduleDay> days = buildDefaultWeeklySchedule();
  List<ServiceDurationSetting> serviceDurations =
      buildDefaultServiceDurations();
  List<ServicePriceSetting> servicePrices = buildDefaultServicePrices();
  bool showPrices = false;
  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final remote = await _repository.loadOrCreateDefault();
      if (!mounted) return;
      setState(() {
        slotMinutes = remote.slotMinutes;
        appointmentsPerSlot = remote.appointmentsPerSlot;
        slotCapacityOverrides = List<SlotCapacityOverride>.from(
          remote.slotCapacityOverrides,
        );
        barberSchedules = List<BarberWeeklySchedule>.from(
          remote.barberSchedules,
        );
        serviceDurations = List<ServiceDurationSetting>.from(
          remote.serviceDurations,
        );
        servicePrices = List<ServicePriceSetting>.from(remote.servicePrices);
        showPrices = remote.showPrices;
        days = List<ScheduleDay>.from(remote.days);
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _save() async {
    if (!mounted) return;
    setState(() => isSaving = true);
    try {
      await _repository.save(
        slotMinutes: slotMinutes,
        appointmentsPerSlot: appointmentsPerSlot,
        slotCapacityOverrides: slotCapacityOverrides,
        barberSchedules: barberSchedules,
        serviceDurations: serviceDurations,
        servicePrices: servicePrices,
        showPrices: showPrices,
        days: days,
      );
    } catch (_) {
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF121212), Color(0xFF090909)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    AppHamburgerMenu(),
                    SizedBox(width: 8),
                    Text(
                      '\u03a1\u03a5\u0398\u039c\u0399\u03a3\u0395\u0399\u03a3',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFD1A45C),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  '\u03a4\u03b9\u03bc\u03ad\u03c2 \u03c5\u03c0\u03b7\u03c1\u03b5\u03c3\u03b9\u03ce\u03bd',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF5ECDD),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '\u03a1\u03cd\u03b8\u03bc\u03b9\u03c3\u03b5 \u03c4\u03b7\u03bd \u03c7\u03c1\u03ad\u03c9\u03c3\u03b7 \u03b3\u03b9\u03b1 \u03ba\u03ac\u03b8\u03b5 \u03c5\u03c0\u03b7\u03c1\u03b5\u03c3\u03af\u03b1 \u03be\u03b5\u03c7\u03c9\u03c1\u03b9\u03c3\u03c4\u03ac.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF8C8C8C)),
                ),
                const SizedBox(height: 10),
                if (isLoading || isSaving)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: Color(0xFFD1A45C),
                      backgroundColor: Color(0xFF242424),
                    ),
                  ),
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF242424)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Show prices in customer app',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFF5ECDD),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'By default prices stay hidden from customers.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF8C8C8C),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Switch(
                        value: showPrices,
                        activeThumbColor: const Color(0xFFD1A45C),
                        onChanged: (value) {
                          setState(() => showPrices = value);
                          _save();
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    itemCount: servicePrices.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final service = servicePrices[index];
                      return _ServicePriceEditor(
                        service: service,
                        onChanged: (value) {
                          setState(() {
                            servicePrices[index] = service.copyWith(
                              price: value.round(),
                            );
                          });
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  label:
                      '\u0391\u03c0\u03bf\u03b8\u03ae\u03ba\u03b5\u03c5\u03c3\u03b7',
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AppointmentsPerSlotPage extends StatefulWidget {
  const AppointmentsPerSlotPage({super.key});

  @override
  State<AppointmentsPerSlotPage> createState() =>
      _AppointmentsPerSlotPageState();
}

class _AppointmentsPerSlotPageState extends State<AppointmentsPerSlotPage> {
  final WeeklyScheduleRepository _repository = WeeklyScheduleRepository();
  int slotMinutes = 30;
  int appointmentsPerSlot = 1;
  List<SlotCapacityOverride> slotCapacityOverrides =
      const <SlotCapacityOverride>[];
  List<BarberWeeklySchedule> barberSchedules =
      const <BarberWeeklySchedule>[];
  List<ScheduleDay> days = buildDefaultWeeklySchedule();
  List<ServiceDurationSetting> serviceDurations =
      buildDefaultServiceDurations();
  List<ServicePriceSetting> servicePrices = buildDefaultServicePrices();
  bool showPrices = false;
  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final remote = await _repository.loadOrCreateDefault();
      if (!mounted) return;
      setState(() {
        slotMinutes = remote.slotMinutes;
        appointmentsPerSlot = remote.appointmentsPerSlot;
        slotCapacityOverrides = List<SlotCapacityOverride>.from(
          remote.slotCapacityOverrides,
        );
        barberSchedules = List<BarberWeeklySchedule>.from(
          remote.barberSchedules,
        );
        serviceDurations = List<ServiceDurationSetting>.from(
          remote.serviceDurations,
        );
        servicePrices = List<ServicePriceSetting>.from(remote.servicePrices);
        showPrices = remote.showPrices;
        days = List<ScheduleDay>.from(remote.days);
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _save() async {
    if (!mounted) return;
    setState(() => isSaving = true);
    try {
      await _repository.save(
        slotMinutes: slotMinutes,
        appointmentsPerSlot: appointmentsPerSlot,
        slotCapacityOverrides: slotCapacityOverrides,
        barberSchedules: barberSchedules,
        serviceDurations: serviceDurations,
        servicePrices: servicePrices,
        showPrices: showPrices,
        days: days,
      );
    } catch (_) {
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  String _dayLabel(int index) {
    if (index >= 0 && index < days.length) {
      return days[index].name;
    }
    return scheduleDayNameForIndex(index);
  }

  String _formatOverrideSummary(SlotCapacityOverride item) {
    return '${_dayLabel(item.dayIndex)} • ${item.start}-${item.end}';
  }

  Future<void> _openOverrideEditor({int? index}) async {
    final existing =
        index == null ? null : slotCapacityOverrides[index];
    var selectedDayIndex = existing?.dayIndex ?? 0;
    var selectedStart = existing?.start ?? '09:00';
    var selectedEnd = existing?.end ?? '17:00';
    var selectedCapacity = existing?.appointmentsPerSlot ?? 1;

    Future<void> pickTime({
      required bool isStart,
      required StateSetter modalSetState,
    }) async {
      final initial = TimeOfDay(
        hour: int.tryParse((isStart ? selectedStart : selectedEnd).split(':').first) ?? 9,
        minute: int.tryParse((isStart ? selectedStart : selectedEnd).split(':').last) ?? 0,
      );
      final picked = await showTimePicker(
        context: context,
        initialTime: initial,
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
      if (picked == null) {
        return;
      }
      final nextValue =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      modalSetState(() {
        if (isStart) {
          selectedStart = nextValue;
        } else {
          selectedEnd = nextValue;
        }
      });
    }

    final result = await showModalBottomSheet<SlotCapacityOverride>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  18,
                  18,
                  18 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existing == null
                          ? 'Add hourly override'
                          : 'Edit hourly override',
                      style: const TextStyle(
                        color: Color(0xFFF5ECDD),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Set a different slot capacity for a specific day and time range.',
                      style: TextStyle(
                        color: Color(0xFF8C8C8C),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      initialValue: selectedDayIndex,
                      decoration: _darkFieldDecoration('Day'),
                      dropdownColor: const Color(0xFF181818),
                      items: List.generate(
                        7,
                        (dayIndex) => DropdownMenuItem<int>(
                          value: dayIndex,
                          child: Text(
                            _dayLabel(dayIndex),
                            style: const TextStyle(color: Color(0xFFF0E5D1)),
                          ),
                        ),
                      ),
                      onChanged: (value) {
                        if (value == null) return;
                        modalSetState(() => selectedDayIndex = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => pickTime(
                              isStart: true,
                              modalSetState: modalSetState,
                            ),
                            child: _TimeFieldCard(
                              label: 'Start',
                              value: selectedStart,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => pickTime(
                              isStart: false,
                              modalSetState: modalSetState,
                            ),
                            child: _TimeFieldCard(
                              label: 'End',
                              value: selectedEnd,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Appointments per slot',
                            style: TextStyle(
                              color: Color(0xFFF2E3C8),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          '$selectedCapacity',
                          style: const TextStyle(
                            color: Color(0xFFD1A45C),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: const Color(0xFFD1A45C),
                        inactiveTrackColor: const Color(0xFF2A2A2A),
                        thumbColor: const Color(0xFFD1A45C),
                        overlayColor: const Color(0x33D1A45C),
                      ),
                      child: Slider(
                        min: 1,
                        max: 10,
                        divisions: 9,
                        value: selectedCapacity.toDouble().clamp(1, 10),
                        label: '$selectedCapacity',
                        onChanged: (value) {
                          modalSetState(() {
                            selectedCapacity = value.round();
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
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
                            onPressed: () {
                              final start = _parseClockValue(selectedStart);
                              final end = _parseClockValue(selectedEnd);
                              if (start < 0 || end <= start) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'End time must be later than start time.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              Navigator.of(context).pop(
                                SlotCapacityOverride(
                                  dayIndex: selectedDayIndex,
                                  start: selectedStart,
                                  end: selectedEnd,
                                  appointmentsPerSlot: selectedCapacity,
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD1A45C),
                              foregroundColor: const Color(0xFF111111),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
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
            );
          },
        );
      },
    );

    if (result == null) {
      return;
    }

    setState(() {
      final next = List<SlotCapacityOverride>.from(slotCapacityOverrides);
      if (index == null) {
        next.add(result);
      } else {
        next[index] = result;
      }
      next.sort((left, right) {
        final byDay = left.dayIndex.compareTo(right.dayIndex);
        if (byDay != 0) {
          return byDay;
        }
        return _parseClockValue(left.start).compareTo(
          _parseClockValue(right.start),
        );
      });
      slotCapacityOverrides = next;
    });
    await _save();
  }

  Future<void> _deleteOverride(int index) async {
    setState(() {
      final next = List<SlotCapacityOverride>.from(slotCapacityOverrides);
      next.removeAt(index);
      slotCapacityOverrides = next;
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF121212), Color(0xFF090909)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    AppHamburgerMenu(),
                    SizedBox(width: 8),
                    Text(
                      '\u03a1\u03a5\u0398\u039c\u0399\u03a3\u0395\u0399\u03a3',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFD1A45C),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  '\u03a1\u03b1\u03bd\u03c4\u03b5\u03b2\u03bf\u03cd \u03b1\u03bd\u03ac slot',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF5ECDD),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '\u03a0\u03cc\u03c3\u03b1 \u03c1\u03b1\u03bd\u03c4\u03b5\u03b2\u03bf\u03cd \u03bc\u03c0\u03bf\u03c1\u03b5\u03af \u03bd\u03b1 \u03b4\u03ad\u03c7\u03b5\u03c4\u03b1\u03b9 \u03c4\u03bf \u03ba\u03b1\u03c4\u03ac\u03c3\u03c4\u03b7\u03bc\u03b1 \u03c3\u03b5 \u03ba\u03ac\u03b8\u03b5 slot.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF8C8C8C)),
                ),
                const SizedBox(height: 10),
                if (isLoading || isSaving)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: Color(0xFFD1A45C),
                      backgroundColor: Color(0xFF242424),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF242424)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '\u03a1\u03b1\u03bd\u03c4\u03b5\u03b2\u03bf\u03cd \u03b1\u03bd\u03ac slot',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFF2E3C8),
                              ),
                            ),
                          ),
                          Text(
                            '$appointmentsPerSlot',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFD1A45C),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFFD1A45C),
                          inactiveTrackColor: const Color(0xFF2A2A2A),
                          thumbColor: const Color(0xFFD1A45C),
                          overlayColor: const Color(0x33D1A45C),
                        ),
                        child: Slider(
                          min: 1,
                          max: 10,
                          divisions: 9,
                          value: appointmentsPerSlot.toDouble().clamp(1, 10),
                          label: '$appointmentsPerSlot',
                          onChanged: (value) {
                            setState(() => appointmentsPerSlot = value.round());
                          },
                          onChangeEnd: (_) => _save(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF242424)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Hourly overrides',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFF2E3C8),
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _openOverrideEditor(),
                            icon: const Icon(
                              Icons.add_rounded,
                              size: 18,
                              color: Color(0xFFD1A45C),
                            ),
                            label: const Text(
                              'Add',
                              style: TextStyle(color: Color(0xFFD1A45C)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Use this when certain hours or days should allow fewer appointments than the general setting.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8C8C8C),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (slotCapacityOverrides.isEmpty)
                        const Text(
                          'No hourly overrides yet.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFFB9B1A5),
                          ),
                        )
                      else
                        ...slotCapacityOverrides.asMap().entries.map((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF171717),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFF2A2A2A),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _formatOverrideSummary(item),
                                          style: const TextStyle(
                                            color: Color(0xFFF5ECDD),
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Max ${item.appointmentsPerSlot} appointments per slot',
                                          style: const TextStyle(
                                            color: Color(0xFFD1A45C),
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => _openOverrideEditor(
                                      index: index,
                                    ),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      color: Color(0xFFD1A45C),
                                      size: 18,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => _deleteOverride(index),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: Color(0xFFE08A7A),
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
                const Spacer(),
                PrimaryButton(
                  label:
                      '\u0391\u03c0\u03bf\u03b8\u03ae\u03ba\u03b5\u03c5\u03c3\u03b7',
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeFieldCard extends StatelessWidget {
  const _TimeFieldCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            Icons.schedule_rounded,
            color: Color(0xFFD1A45C),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF8C8C8C),
                    fontSize: 10.5,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFFF0E5D1),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ScheduleDayCard extends StatelessWidget {
  const ScheduleDayCard({
    super.key,
    required this.day,
    required this.onChanged,
    this.onTapStart,
    this.onTapEnd,
    this.onTapBreakStart,
    this.onTapBreakEnd,
  });

  final ScheduleDay day;
  final ValueChanged<ScheduleDay> onChanged;
  final VoidCallback? onTapStart;
  final VoidCallback? onTapEnd;
  final VoidCallback? onTapBreakStart;
  final VoidCallback? onTapBreakEnd;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: day.enabled
                ? const Color(0xFF2F2A22)
                : const Color(0xFF202020),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    day.name,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF5ECDD),
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: day.enabled,
                  activeThumbColor: const Color(0xFFD1A45C),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (value) => onChanged(day.copyWith(enabled: value)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ScheduleValueChip(
                    title: '\u0388\u03BD\u03B1\u03C1\u03BE\u03B7',
                    label: day.enabled ? day.start : '--',
                    onTap: onTapStart,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ScheduleValueChip(
                    title: '\u039B\u03AE\u03BE\u03B7',
                    label: day.enabled ? day.end : '--',
                    onTap: onTapEnd,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: ScheduleValueChip(
                    title: '\u0394/\u03BC\u03B1 \u0388\u03BD.',
                    label: day.enabled ? day.breakStart : '--',
                    onTap: onTapBreakStart,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ScheduleValueChip(
                    title: '\u0394/\u03BC\u03B1 \u039B\u03AE\u03BE.',
                    label: day.enabled ? day.breakEnd : '--',
                    onTap: onTapBreakEnd,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ScheduleValueChip extends StatelessWidget {
  const ScheduleValueChip({
    super.key,
    required this.title,
    required this.label,
    this.onTap,
  });

  final String title;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8F8F8F),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.2,
              fontWeight: FontWeight.w700,
              color: Color(0xFFDDB778),
            ),
          ),
        ],
      ),
    );

    final wrapped = onTap == null
        ? child
        : GestureDetector(onTap: onTap, child: child);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: onTap == null ? 0.65 : 1,
      child: wrapped,
    );
  }
}
