part of 'main.dart';

class _HolidayDisplayItem {
  const _HolidayDisplayItem({
    required this.date,
    required this.dateKey,
    required this.label,
    required this.isClosed,
    required this.isDefaultHoliday,
  });

  final DateTime date;
  final String dateKey;
  final String label;
  final bool isClosed;
  final bool isDefaultHoliday;
}

enum _ClosedDateMode { singleDay, dateRange }

String _dateKeyFromDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

DateTime? _tryParseDateKey(String value) {
  final parts = value.split('-');
  if (parts.length != 3) {
    return null;
  }
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) {
    return null;
  }
  return DateTime(year, month, day);
}

DateTime _orthodoxEasterSunday(int year) {
  final a = year % 4;
  final b = year % 7;
  final c = year % 19;
  final d = (19 * c + 15) % 30;
  final e = (2 * a + 4 * b - d + 34) % 7;
  final month = ((d + e + 114) ~/ 31);
  final day = ((d + e + 114) % 31) + 1;
  final julian = DateTime.utc(
    year,
    month - 1,
    day,
  ).add(const Duration(days: 13));
  return DateTime(julian.year, julian.month, julian.day);
}

Map<String, String> _buildGreekHolidayMapForYear(int year) {
  final easter = _orthodoxEasterSunday(year);
  final cleanMonday = easter.subtract(const Duration(days: 48));
  final goodFriday = easter.subtract(const Duration(days: 2));
  final easterMonday = easter.add(const Duration(days: 1));
  final holySpiritMonday = easter.add(const Duration(days: 50));
  final holidays = <DateTime, String>{
    DateTime(year, 1, 1): 'Πρωτοχρονιά',
    DateTime(year, 1, 6): 'Θεοφάνια',
    cleanMonday: 'Καθαρά Δευτέρα',
    DateTime(year, 3, 25): 'Εθνική εορτή',
    goodFriday: 'Μεγάλη Παρασκευή',
    easter: 'Ορθόδοξο Πάσχα',
    easterMonday: 'Δευτέρα του Πάσχα',
    DateTime(year, 5, 1): 'Πρωτομαγιά',
    holySpiritMonday: 'Αγίου Πνεύματος',
    DateTime(year, 8, 15): 'Δεκαπενταύγουστος',
    DateTime(year, 10, 28): 'Επέτειος του Όχι',
    DateTime(year, 12, 25): 'Χριστούγεννα',
    DateTime(year, 12, 26): 'Σύναξη της Θεοτόκου',
  };
  return {
    for (final entry in holidays.entries)
      _dateKeyFromDate(entry.key): entry.value,
  };
}

String _formatClosedDateLabel(DateTime date) {
  return barberinDateLabel(date, includeYear: true);
}

List<_HolidayDisplayItem> _buildHolidayDisplayItems(
  List<ClosedDateOverride> closedDateOverrides,
) {
  final now = DateTime.now();
  final activeYear = now.year;
  final defaultHolidayMap = <String, String>{
    ..._buildGreekHolidayMapForYear(activeYear),
  };
  final overrideByDate = <String, ClosedDateOverride>{
    for (final item in closedDateOverrides) item.dateKey: item,
  };
  final items = <_HolidayDisplayItem>[];

  for (final entry in defaultHolidayMap.entries) {
    final date = _tryParseDateKey(entry.key);
    if (date == null) continue;
    final override = overrideByDate[entry.key];
    items.add(
      _HolidayDisplayItem(
        date: date,
        dateKey: entry.key,
        label: override?.label.isNotEmpty == true
            ? override!.label
            : entry.value,
        isClosed: override?.isClosed ?? true,
        isDefaultHoliday: true,
      ),
    );
  }

  for (final override in closedDateOverrides) {
    if (defaultHolidayMap.containsKey(override.dateKey)) {
      continue;
    }
    final date = _tryParseDateKey(override.dateKey);
    if (date == null || date.year != activeYear) continue;
    items.add(
      _HolidayDisplayItem(
        date: date,
        dateKey: override.dateKey,
        label: override.label.isEmpty ? 'Κλειστή ημέρα' : override.label,
        isClosed: override.isClosed,
        isDefaultHoliday: false,
      ),
    );
  }

  items.sort((left, right) => left.date.compareTo(right.date));
  return items;
}

class WeeklySchedulePage extends StatefulWidget {
  const WeeklySchedulePage({super.key});

  @override
  State<WeeklySchedulePage> createState() => _WeeklySchedulePageState();
}

class _WeeklySchedulePageState extends State<WeeklySchedulePage> {
  late final List<ScheduleDay> schedule = [
    const ScheduleDay(
      name: 'Δευτέρα',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
    const ScheduleDay(
      name: 'Τρίτη',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
    const ScheduleDay(
      name: 'Τετάρτη',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
    const ScheduleDay(
      name: 'Πέμπτη',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
    const ScheduleDay(
      name: 'Παρασκευή',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
    const ScheduleDay(
      name: 'Σάββατο',
      enabled: false,
      start: '--:--',
      end: '--:--',
      breakStart: '--:--',
      breakEnd: '--:--',
    ),
    const ScheduleDay(
      name: 'Κυριακή',
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
  List<ClosedDateOverride> closedDateOverrides = const <ClosedDateOverride>[];
  List<BarberWeeklySchedule> barberSchedules = const <BarberWeeklySchedule>[];
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
      if (isBarberinWindows) {
        final parsed = await CrewRepository().loadCrewMembers();
        if (!mounted) {
          return;
        }
        setState(() {
          _barbers = parsed;
          _selectedBarberId ??= parsed.isEmpty ? null : parsed.first.id.trim();
        });
        return;
      }
      final shopId = requireCurrentBarberoSession().shopId;
      final snapshot = await FirebaseDatabase.instance
          .ref('shops/$shopId/barbers')
          .get();
      final rawBarbers =
          _mapFromRawValue(snapshot.value) ?? <String, dynamic>{};
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
        _selectedBarberId ??= parsed.isEmpty ? null : parsed.first.id.trim();
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
        closedDateOverrides = List<ClosedDateOverride>.from(
          remote.closedDateOverrides,
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
        closedDateOverrides: closedDateOverrides,
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
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: context.barberinAccent),
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
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: context.barberinAccent),
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
    final initialValue = day.breakStart == '--:--' ? day.start : day.breakStart;
    final picked = await showTimePicker(
      context: context,
      initialTime: _parseTime(initialValue),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: context.barberinAccent),
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
        breakEnd: day.breakEnd == '--:--' ? formatted : day.breakEnd,
      ),
    );
  }

  Future<void> _pickBreakEnd(int index) async {
    final day = _activeScheduleDays[index];
    final initialValue = day.breakEnd == '--:--' ? day.end : day.breakEnd;
    final picked = await showTimePicker(
      context: context,
      initialTime: _parseTime(initialValue),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: context.barberinAccent),
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
        breakStart: day.breakStart == '--:--' ? formatted : day.breakStart,
        breakEnd: formatted,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        color: context.barberinBackground,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppHamburgerMenu(),
                    SizedBox(width: 8),
                    Text(
                      '\u03a1\u03a5\u0398\u039c\u0399\u03a3\u0395\u0399\u03a3',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w700,
                        color: context.barberinAccent,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  '\u0395\u03b2\u03b4\u03bf\u03bc\u03b1\u03b4\u03b9\u03b1\u03af\u03bf \u03c0\u03c1\u03cc\u03b3\u03c1\u03b1\u03bc\u03bc\u03b1',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.barberinTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '\u0399\u03c3\u03c7\u03cd\u03b5\u03b9 \u03bc\u03cc\u03bd\u03b9\u03bc\u03b1 \u03b3\u03b9\u03b1 \u03cc\u03bb\u03b5\u03c2 \u03c4\u03b9\u03c2 \u03b5\u03b2\u03b4\u03bf\u03bc\u03ac\u03b4\u03b5\u03c2.',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.barberinTextSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('Γενικό'),
                      icon: Icon(Icons.storefront_outlined),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('Ανά barber'),
                      icon: Icon(Icons.content_cut_rounded),
                    ),
                  ],
                  selected: {_editingPerBarber},
                  style: ButtonStyle(
                    foregroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? Theme.of(context).colorScheme.onPrimary
                          : context.barberinTextPrimary,
                    ),
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? context.barberinAccent
                          : context.barberinSurfaceAlt,
                    ),
                  ),
                  onSelectionChanged: (selection) {
                    setState(() {
                      _editingPerBarber = selection.first;
                      if (_editingPerBarber &&
                          (_selectedBarberId == null ||
                              _selectedBarberId!.isEmpty) &&
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
                        color: context.barberinSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: context.barberinBorder),
                      ),
                      child: Text(
                        'Δεν υπάρχουν ακόμη barber. Πρόσθεσε πρώτα έναν barber για να ορίσεις προσωπικό εβδομαδιαίο πρόγραμμα.',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.barberinTextSecondary,
                        ),
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _selectedBarberId,
                      decoration: _darkFieldDecoration('barber'),
                      dropdownColor: Theme.of(context).colorScheme.surface,
                      items: _barbers
                          .map(
                            (barber) => DropdownMenuItem<String>(
                              value: barber.id.trim(),
                              child: Text(
                                barber.fullName,
                                style: TextStyle(
                                  color: context.barberinTextPrimary,
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
                  Text(
                    'Αν ένας barber δεν έχει προσωπικό πρόγραμμα, χρησιμοποιεί αυτόματα το γενικό πρόγραμμα του καταστήματος.',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.barberinTextSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                if (isLoading)
                  Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: context.barberinAccent,
                      backgroundColor: context.barberinSurfaceAlt,
                    ),
                  ),
                if (!isLoading && isSaving)
                  Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: context.barberinAccent,
                      backgroundColor: context.barberinSurfaceAlt,
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
                        value: '$totalHours ώρες',
                        caption: '\u03a9\u03a1\u0395\u03a3',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CompactStatCard(
                        value:
                            '${closedDateOverrides.where((item) => item.isClosed).length}',
                        caption: 'ΑΡΓΙΕΣ',
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
                        const SizedBox(height: 0),
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

class GreekHolidaysPage extends StatefulWidget {
  const GreekHolidaysPage({super.key});

  @override
  State<GreekHolidaysPage> createState() => _GreekHolidaysPageState();
}

class _GreekHolidaysPageState extends State<GreekHolidaysPage> {
  static final scheduleRepository = WeeklyScheduleRepository();

  bool isLoading = true;
  bool isSaving = false;
  WeeklyScheduleData? _scheduleData;
  List<ClosedDateOverride> closedDateOverrides = const <ClosedDateOverride>[];

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  List<_HolidayDisplayItem> get _holidayDisplayItems =>
      _buildHolidayDisplayItems(closedDateOverrides);

  Future<void> _loadSchedule() async {
    try {
      final remote = await scheduleRepository.loadOrCreateDefault();
      if (!mounted) return;
      setState(() {
        _scheduleData = remote;
        closedDateOverrides = remote.closedDateOverrides;
        isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Δεν ήταν δυνατή η φόρτωση των ελληνικών αργιών'),
        ),
      );
    }
  }

  Future<void> _saveClosedDateOverrides() async {
    final current = _scheduleData;
    if (current == null) {
      return;
    }
    setState(() => isSaving = true);
    try {
      await scheduleRepository.save(
        slotMinutes: current.slotMinutes,
        appointmentsPerSlot: current.appointmentsPerSlot,
        slotCapacityOverrides: current.slotCapacityOverrides,
        closedDateOverrides: closedDateOverrides,
        barberSchedules: current.barberSchedules,
        showPrices: current.showPrices,
        serviceDurations: current.serviceDurations,
        servicePrices: current.servicePrices,
        days: current.days,
      );
      if (!mounted) return;
      setState(() {
        _scheduleData = WeeklyScheduleData(
          slotMinutes: current.slotMinutes,
          appointmentsPerSlot: current.appointmentsPerSlot,
          slotCapacityOverrides: current.slotCapacityOverrides,
          closedDateOverrides: closedDateOverrides,
          barberSchedules: current.barberSchedules,
          showPrices: current.showPrices,
          serviceDurations: current.serviceDurations,
          servicePrices: current.servicePrices,
          days: current.days,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Οι ελληνικές αργίες ενημερώθηκαν')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Δεν ήταν δυνατή η αποθήκευση των ελληνικών αργιών'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  Future<void> _setClosedDateOverride({
    required String dateKey,
    required String label,
    required bool isClosed,
  }) async {
    setState(() {
      final next = List<ClosedDateOverride>.from(closedDateOverrides);
      final index = next.indexWhere((item) => item.dateKey == dateKey);
      final value = ClosedDateOverride(
        dateKey: dateKey,
        label: label,
        isClosed: isClosed,
      );
      if (index >= 0) {
        next[index] = value;
      } else {
        next.add(value);
      }
      next.sort((left, right) => left.dateKey.compareTo(right.dateKey));
      closedDateOverrides = next;
    });
    await _saveClosedDateOverrides();
  }

  Future<void> _upsertClosedDateOverrides(
    List<ClosedDateOverride> overrides,
  ) async {
    setState(() {
      final next = List<ClosedDateOverride>.from(closedDateOverrides);
      for (final override in overrides) {
        final index = next.indexWhere(
          (item) => item.dateKey == override.dateKey,
        );
        if (index >= 0) {
          next[index] = override;
        } else {
          next.add(override);
        }
      }
      next.sort((left, right) => left.dateKey.compareTo(right.dateKey));
      closedDateOverrides = next;
    });
    await _saveClosedDateOverrides();
  }

  Future<void> _deleteClosedDateOverride(String dateKey) async {
    setState(() {
      final next = List<ClosedDateOverride>.from(closedDateOverrides);
      next.removeWhere((item) => item.dateKey == dateKey);
      closedDateOverrides = next;
    });
    await _saveClosedDateOverrides();
  }

  Future<void> _addCustomClosedDate() async {
    final now = DateTime.now();
    final currentYear = now.year;
    final initialDate = DateTime(
      currentYear,
      now.month,
      now.day,
    ).add(const Duration(days: 1));
    final mode = await showModalBottomSheet<_ClosedDateMode>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Προσθήκη ολοήμερου κλεισίματος',
                  style: TextStyle(
                    color: context.barberinTextPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Επίλεξε αν θέλεις να κλείσεις μία ημέρα ή ένα ολόκληρο χρονικό διάστημα.',
                  style: TextStyle(
                    color: context.barberinTextSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                _ClosedDateModeTile(
                  title: 'Μία ημέρα',
                  subtitle: 'Κλείσιμο μίας συγκεκριμένης ημέρας',
                  onTap: () =>
                      Navigator.of(context).pop(_ClosedDateMode.singleDay),
                ),
                const SizedBox(height: 10),
                _ClosedDateModeTile(
                  title: 'Χρονικό διάστημα',
                  subtitle: 'Κλείσιμο από μία ημέρα έως μία άλλη',
                  onTap: () =>
                      Navigator.of(context).pop(_ClosedDateMode.dateRange),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (mode == null || !mounted) {
      return;
    }

    DateTimeRange? range;
    if (mode == _ClosedDateMode.singleDay) {
      final picked = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: DateTime(currentYear, 1, 1),
        lastDate: DateTime(currentYear, 12, 31),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(
                context,
              ).colorScheme.copyWith(primary: context.barberinAccent),
            ),
            child: child!,
          );
        },
      );
      if (picked == null || !mounted) {
        return;
      }
      range = DateTimeRange(start: picked, end: picked);
    } else {
      final initialEnd = initialDate.add(const Duration(days: 1));
      range = await showDateRangePicker(
        context: context,
        initialDateRange: DateTimeRange(
          start: initialDate,
          end: initialEnd.year == currentYear ? initialEnd : initialDate,
        ),
        firstDate: DateTime(currentYear, 1, 1),
        lastDate: DateTime(currentYear, 12, 31),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(
                context,
              ).colorScheme.copyWith(primary: context.barberinAccent),
            ),
            child: child!,
          );
        },
      );
      if (range == null || !mounted) {
        return;
      }
    }

    final start = range.start;
    final end = range.end;
    final dateLabel = start == end
        ? _formatClosedDateLabel(start)
        : '${_formatClosedDateLabel(start)} - ${_formatClosedDateLabel(end)}';
    final defaultLabel = start == end ? 'Κλειστή ημέρα' : 'Κλειστές ημέρες';
    final controller = TextEditingController(text: defaultLabel);
    final label = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
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
                  'Προσθήκη ολοήμερου κλεισίματος',
                  style: TextStyle(
                    color: context.barberinTextPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  dateLabel,
                  style: TextStyle(
                    color: context.barberinAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  decoration: _darkFieldDecoration('Ονομασία'),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('ΚΛΕΙΣΙΜΟ'),
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop(controller.text.trim());
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.barberinAccent,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onPrimary,
                        ),
                        child: const Text(
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
        );
      },
    );
    controller.dispose();
    if (label == null) {
      return;
    }
    final effectiveLabel = label.isEmpty ? defaultLabel : label;
    final overrides = <ClosedDateOverride>[];
    for (
      var date = DateTime(start.year, start.month, start.day);
      !date.isAfter(end);
      date = date.add(const Duration(days: 1))
    ) {
      overrides.add(
        ClosedDateOverride(
          dateKey: _dateKeyFromDate(date),
          label: effectiveLabel,
          isClosed: true,
        ),
      );
    }
    await _upsertClosedDateOverrides(overrides);
  }

  @override
  Widget build(BuildContext context) {
    final closedCount = closedDateOverrides
        .where((item) => item.isClosed)
        .length;
    return Scaffold(
      backgroundColor: context.barberinBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Container(
            decoration: BoxDecoration(
              color: context.barberinSurface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: context.barberinBorder),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Αργίες και Διακοπές',
                    style: TextStyle(
                      color: context.barberinTextPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Κλείσε ολόκληρες ημέρες για αργίες, διακοπές, άδειες προσωπικού ή ειδικές περιπτώσεις. Οι ελληνικές αργίες είναι κλειστές από προεπιλογή, αλλά μπορείς να τις ανοίξεις όποτε θέλεις.',
                    style: TextStyle(
                      color: context.barberinTextSecondary,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                  SizedBox(height: 12),
                  if (isLoading)
                    Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        color: context.barberinAccent,
                        backgroundColor: Color(0xFF242424),
                      ),
                    ),
                  if (!isLoading && isSaving)
                    Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        color: context.barberinAccent,
                        backgroundColor: Color(0xFF242424),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: CompactStatCard(
                          value: '$closedCount',
                          caption: 'ΚΛΕΙΣΤΕΣ ΗΜΕΡΕΣ',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _ClosedDatesCard(
                      items: _holidayDisplayItems,
                      onAddCustom: _addCustomClosedDate,
                      onToggleDefaultHoliday: (item, isClosed) async {
                        await _setClosedDateOverride(
                          dateKey: item.dateKey,
                          label: item.label,
                          isClosed: isClosed,
                        );
                      },
                      onDeleteCustom: _deleteClosedDateOverride,
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [context.barberinSurface, context.barberinSurfaceAlt],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.barberinBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.barberinTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            style: TextStyle(
              fontSize: 8.5,
              color: context.barberinTextSecondary,
              letterSpacing: .7,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClosedDateModeTile extends StatelessWidget {
  const _ClosedDateModeTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.barberinBorder)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: context.barberinTextPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: context.barberinTextSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.barberinAccent),
          ],
        ),
      ),
    );
  }
}

class _ClosedDatesCard extends StatelessWidget {
  const _ClosedDatesCard({
    required this.items,
    required this.onAddCustom,
    required this.onToggleDefaultHoliday,
    required this.onDeleteCustom,
  });

  final List<_HolidayDisplayItem> items;
  final VoidCallback onAddCustom;
  final Future<void> Function(_HolidayDisplayItem item, bool isClosed)
  onToggleDefaultHoliday;
  final Future<void> Function(String dateKey) onDeleteCustom;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Κλειστές ημέρες και ελληνικές αργίες',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.barberinTextPrimary,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: onAddCustom,
              icon: Icon(
                Icons.add_rounded,
                size: 18,
                color: context.barberinAccent,
              ),
              label: Text(
                'Προσθήκη κλεισίματος',
                style: TextStyle(color: context.barberinAccent),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Οι ελληνικές αργίες είναι κλειστές από προεπιλογή. Άνοιξέ τες αν το κατάστημα θα λειτουργήσει εκείνη την ημέρα ή πρόσθεσε δικά σου ολοήμερα κλεισίματα.',
          style: TextStyle(fontSize: 11, color: context.barberinTextSecondary),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final subtitle =
                  '${_formatClosedDateLabel(item.date)} • ${item.isClosed ? 'Κλειστό' : 'Ανοιχτό'}';
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: context.barberinBorder),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.label,
                            style: TextStyle(
                              color: context.barberinTextPrimary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: item.isClosed
                                  ? context.barberinTextSecondary
                                  : context.barberinAccent,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (item.isDefaultHoliday)
                      Switch(
                        value: item.isClosed,
                        activeThumbColor: context.barberinAccent,
                        onChanged: (value) {
                          onToggleDefaultHoliday(item, value);
                        },
                      )
                    else
                      IconButton(
                        onPressed: () => onDeleteCustom(item.dateKey),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Color(0xFFE08A7A),
                          size: 18,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
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
    return Column(
      children: [
        _ScheduleInfoTile(
          label:
              '\u0394\u0399\u0391\u03a1\u039a\u0395\u0399\u0395\u03a3 \u03a5\u03a0\u0397\u03a1\u0395\u03a3\u0399\u03a9\u039d',
          value:
              '${serviceDurations.length} \u03c5\u03c0\u03b7\u03c1\u03b5\u03c3\u03af\u03b5\u03c2',
          onTap: onServiceDurationsTap,
        ),
        Divider(height: 1, color: context.barberinBorder),
        _ScheduleInfoTile(
          label:
              '\u03a1\u0391\u039d\u03a4\u0395\u0392\u039f\u03a5 \u0391\u039d\u0391 SLOT',
          value: '$appointmentsPerSlot',
          onTap: onAppointmentsPerSlotTap,
        ),
      ],
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
          style: TextStyle(
            fontSize: 9.5,
            letterSpacing: 1,
            fontWeight: FontWeight.w700,
            color: context.barberinAccent,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.barberinTextPrimary,
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
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.barberinBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  service.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.barberinTextPrimary,
                  ),
                ),
              ),
              Text(
                '${service.minutes} \u03bb\u03b5\u03c0\u03c4\u03ac',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.barberinAccent,
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: context.barberinAccent,
              inactiveTrackColor: Color(0xFF2A2A2A),
              thumbColor: context.barberinAccent,
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
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.barberinBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  service.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.barberinTextPrimary,
                  ),
                ),
              ),
              Text(
                '\u20ac${service.price}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.barberinAccent,
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: context.barberinAccent,
              inactiveTrackColor: Color(0xFF2A2A2A),
              thumbColor: context.barberinAccent,
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
  List<ClosedDateOverride> closedDateOverrides = const <ClosedDateOverride>[];
  List<BarberWeeklySchedule> barberSchedules = const <BarberWeeklySchedule>[];
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
        closedDateOverrides = List<ClosedDateOverride>.from(
          remote.closedDateOverrides,
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
        closedDateOverrides: closedDateOverrides,
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
        color: context.barberinBackground,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppHamburgerMenu(),
                    SizedBox(width: 8),
                    Text(
                      '\u03a1\u03a5\u0398\u039c\u0399\u03a3\u0395\u0399\u03a3',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w700,
                        color: context.barberinAccent,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  '\u0394\u03b9\u03b1\u03c1\u03ba\u03b5\u03af\u03b5\u03c2 \u03c5\u03c0\u03b7\u03c1\u03b5\u03c3\u03b9\u03ce\u03bd',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.barberinTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '\u03a1\u03cd\u03b8\u03bc\u03b9\u03c3\u03b5 \u03c4\u03bf \u03b2\u03b1\u03c3\u03b9\u03ba\u03cc slot \u03ba\u03b1\u03b9 \u03ba\u03ac\u03b8\u03b5 \u03c5\u03c0\u03b7\u03c1\u03b5\u03c3\u03af\u03b1 \u03be\u03b5\u03c7\u03c9\u03c1\u03b9\u03c3\u03c4\u03ac.',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.barberinTextSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                if (isLoading || isSaving)
                  Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: context.barberinAccent,
                      backgroundColor: Color(0xFF242424),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: context.barberinSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.barberinBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '\u0392\u03b1\u03c3\u03b9\u03ba\u03cc slot',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: context.barberinTextPrimary,
                              ),
                            ),
                          ),
                          Text(
                            '$slotMinutes \u03bb\u03b5\u03c0\u03c4\u03ac',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: context.barberinAccent,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 10),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: context.barberinAccent,
                          inactiveTrackColor: Color(0xFF2A2A2A),
                          thumbColor: context.barberinAccent,
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
                    separatorBuilder: (_, _) => const SizedBox(height: 0),
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
  List<ClosedDateOverride> closedDateOverrides = const <ClosedDateOverride>[];
  List<BarberWeeklySchedule> barberSchedules = const <BarberWeeklySchedule>[];
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
        closedDateOverrides = List<ClosedDateOverride>.from(
          remote.closedDateOverrides,
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
        closedDateOverrides: closedDateOverrides,
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
        color: context.barberinBackground,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppHamburgerMenu(),
                    SizedBox(width: 8),
                    Text(
                      '\u03a1\u03a5\u0398\u039c\u0399\u03a3\u0395\u0399\u03a3',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w700,
                        color: context.barberinAccent,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  '\u03a4\u03b9\u03bc\u03ad\u03c2 \u03c5\u03c0\u03b7\u03c1\u03b5\u03c3\u03b9\u03ce\u03bd',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.barberinTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '\u03a1\u03cd\u03b8\u03bc\u03b9\u03c3\u03b5 \u03c4\u03b7\u03bd \u03c7\u03c1\u03ad\u03c9\u03c3\u03b7 \u03b3\u03b9\u03b1 \u03ba\u03ac\u03b8\u03b5 \u03c5\u03c0\u03b7\u03c1\u03b5\u03c3\u03af\u03b1 \u03be\u03b5\u03c7\u03c9\u03c1\u03b9\u03c3\u03c4\u03ac.',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.barberinTextSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                if (isLoading || isSaving)
                  Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: context.barberinAccent,
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
                    color: context.barberinSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.barberinBorder),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Εμφάνιση τιμών στην εφαρμογή πελάτη',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: context.barberinTextPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Από προεπιλογή οι τιμές παραμένουν κρυφές από τους πελάτες.',
                              style: TextStyle(
                                fontSize: 11,
                                color: context.barberinTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 12),
                      Switch(
                        value: showPrices,
                        activeThumbColor: context.barberinAccent,
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
                    separatorBuilder: (_, _) => const SizedBox(height: 0),
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
  List<ClosedDateOverride> closedDateOverrides = const <ClosedDateOverride>[];
  List<BarberWeeklySchedule> barberSchedules = const <BarberWeeklySchedule>[];
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
        closedDateOverrides = List<ClosedDateOverride>.from(
          remote.closedDateOverrides,
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
        closedDateOverrides: closedDateOverrides,
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
    final existing = index == null ? null : slotCapacityOverrides[index];
    var selectedDayIndex = existing?.dayIndex ?? 0;
    var selectedStart = existing?.start ?? '09:00';
    var selectedEnd = existing?.end ?? '17:00';
    var selectedCapacity = existing?.appointmentsPerSlot ?? 1;

    Future<void> pickTime({
      required bool isStart,
      required StateSetter modalSetState,
    }) async {
      final initial = TimeOfDay(
        hour:
            int.tryParse(
              (isStart ? selectedStart : selectedEnd).split(':').first,
            ) ??
            9,
        minute:
            int.tryParse(
              (isStart ? selectedStart : selectedEnd).split(':').last,
            ) ??
            0,
      );
      final picked = await showTimePicker(
        context: context,
        initialTime: initial,
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(
                context,
              ).colorScheme.copyWith(primary: context.barberinAccent),
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
      backgroundColor: Theme.of(context).colorScheme.surface,
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
                          ? 'Προσθήκη ωριαίας εξαίρεσης'
                          : 'Επεξεργασία ωριαίας εξαίρεσης',
                      style: TextStyle(
                        color: context.barberinTextPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Όρισε διαφορετική χωρητικότητα slot για συγκεκριμένη ημέρα και χρονικό διάστημα.',
                      style: TextStyle(
                        color: context.barberinTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      initialValue: selectedDayIndex,
                      decoration: _darkFieldDecoration('Ημέρα'),
                      dropdownColor: Theme.of(context).colorScheme.surface,
                      items: List.generate(
                        7,
                        (dayIndex) => DropdownMenuItem<int>(
                          value: dayIndex,
                          child: Text(
                            _dayLabel(dayIndex),
                            style: TextStyle(
                              color: context.barberinTextPrimary,
                            ),
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
                              label: 'Έναρξη',
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
                              label: 'Λήξη',
                              value: selectedEnd,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Ραντεβού ανά slot',
                            style: TextStyle(
                              color: context.barberinTextPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          '$selectedCapacity',
                          style: TextStyle(
                            color: context.barberinAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: context.barberinAccent,
                        inactiveTrackColor: Color(0xFF2A2A2A),
                        thumbColor: context.barberinAccent,
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
                              foregroundColor: context.barberinTextPrimary,
                              side: const BorderSide(color: Color(0xFF3A3A3A)),
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
                            onPressed: () {
                              final start = _parseClockValue(selectedStart);
                              final end = _parseClockValue(selectedEnd);
                              if (start < 0 || end <= start) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Η ώρα λήξης πρέπει να είναι μετά την ώρα έναρξης.',
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
                              backgroundColor: context.barberinAccent,
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
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
        return _parseClockValue(
          left.start,
        ).compareTo(_parseClockValue(right.start));
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
        color: context.barberinBackground,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppHamburgerMenu(),
                    SizedBox(width: 8),
                    Text(
                      '\u03a1\u03a5\u0398\u039c\u0399\u03a3\u0395\u0399\u03a3',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w700,
                        color: context.barberinAccent,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  '\u03a1\u03b1\u03bd\u03c4\u03b5\u03b2\u03bf\u03cd \u03b1\u03bd\u03ac slot',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.barberinTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '\u03a0\u03cc\u03c3\u03b1 \u03c1\u03b1\u03bd\u03c4\u03b5\u03b2\u03bf\u03cd \u03bc\u03c0\u03bf\u03c1\u03b5\u03af \u03bd\u03b1 \u03b4\u03ad\u03c7\u03b5\u03c4\u03b1\u03b9 \u03c4\u03bf \u03ba\u03b1\u03c4\u03ac\u03c3\u03c4\u03b7\u03bc\u03b1 \u03c3\u03b5 \u03ba\u03ac\u03b8\u03b5 slot.',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.barberinTextSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                if (isLoading || isSaving)
                  Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: context.barberinAccent,
                      backgroundColor: Color(0xFF242424),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: context.barberinSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.barberinBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '\u03a1\u03b1\u03bd\u03c4\u03b5\u03b2\u03bf\u03cd \u03b1\u03bd\u03ac slot',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: context.barberinTextPrimary,
                              ),
                            ),
                          ),
                          Text(
                            '$appointmentsPerSlot',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: context.barberinAccent,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 10),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: context.barberinAccent,
                          inactiveTrackColor: Color(0xFF2A2A2A),
                          thumbColor: context.barberinAccent,
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
                    color: context.barberinSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.barberinBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Ωριαίες εξαιρέσεις',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: context.barberinTextPrimary,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _openOverrideEditor(),
                            icon: Icon(
                              Icons.add_rounded,
                              size: 18,
                              color: context.barberinAccent,
                            ),
                            label: Text(
                              'Προσθήκη',
                              style: TextStyle(color: context.barberinAccent),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Χρησιμοποίησέ το όταν συγκεκριμένες ώρες ή ημέρες πρέπει να επιτρέπουν λιγότερα ραντεβού από τη γενική ρύθμιση.',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.barberinTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (slotCapacityOverrides.isEmpty)
                        Text(
                          'Δεν υπάρχουν ακόμη ωριαίες εξαιρέσεις.',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.barberinTextSecondary,
                          ),
                        )
                      else
                        ...slotCapacityOverrides.asMap().entries.map((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                12,
                                12,
                                10,
                              ),
                              decoration: BoxDecoration(
                                color: context.barberinSurfaceAlt,
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
                                          style: TextStyle(
                                            color: context.barberinTextPrimary,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'Έως ${item.appointmentsPerSlot} ραντεβού ανά slot',
                                          style: TextStyle(
                                            color: context.barberinAccent,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () =>
                                        _openOverrideEditor(index: index),
                                    icon: Icon(
                                      Icons.edit_outlined,
                                      color: context.barberinAccent,
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
  const _TimeFieldCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: context.barberinSurfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.barberinBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, color: context.barberinAccent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: context.barberinTextSecondary,
                    fontSize: 10.5,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: context.barberinTextPrimary,
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
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.barberinBorder)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    day.name,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: context.barberinTextPrimary,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: day.enabled,
                  activeThumbColor: context.barberinAccent,
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
        color: context.barberinSurfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.barberinBorder),
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
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              color: context.barberinTextSecondary,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.2,
              fontWeight: FontWeight.w700,
              color: context.barberinTextPrimary,
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
