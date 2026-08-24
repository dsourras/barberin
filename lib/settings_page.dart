part of 'main.dart';

class BarberinSettingsPage extends StatefulWidget {
  const BarberinSettingsPage({super.key});

  @override
  State<BarberinSettingsPage> createState() => _BarberinSettingsPageState();
}

class _BarberinSettingsPageState extends State<BarberinSettingsPage> {
  final AppointmentSettingsRepository _appointmentSettingsRepository =
      AppointmentSettingsRepository();
  AppointmentSettings? _appointmentSettings;
  bool _loadingAppointmentSettings = true;
  bool _savingAppointmentSettings = false;
  String? _appointmentSettingsError;

  bool get _isOwner => currentBarberoSession.value?.isOwner == true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAppointmentSettings());
  }

  Future<void> _loadAppointmentSettings() async {
    try {
      final settings = await _appointmentSettingsRepository.load();
      if (!mounted) return;
      setState(() {
        _appointmentSettings = settings;
        _appointmentSettingsError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _appointmentSettingsError = barberinLabel(
          'Δεν ήταν δυνατή η φόρτωση των ρυθμίσεων ραντεβού.',
          'Appointment settings could not be loaded.',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _loadingAppointmentSettings = false);
      }
    }
  }

  Future<void> _saveAppointmentSettings(AppointmentSettings next) async {
    if (!_isOwner || _savingAppointmentSettings) return;
    final previous = _appointmentSettings;
    setState(() {
      _savingAppointmentSettings = true;
      _appointmentSettings = next;
      _appointmentSettingsError = null;
    });
    try {
      final saved = await _appointmentSettingsRepository.save(
        settings: next,
      );
      if (!mounted) return;
      setState(() => _appointmentSettings = saved);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _appointmentSettings = previous ?? const AppointmentSettings();
        _appointmentSettingsError = barberinLabel(
          'Η ρύθμιση δεν αποθηκεύτηκε. Δοκιμάστε ξανά.',
          'The setting could not be saved. Try again.',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _savingAppointmentSettings = false);
      }
    }
  }

  Future<void> _setAutoConfirmAppointments(bool enabled) async {
    final current = _appointmentSettings ?? const AppointmentSettings();
    await _saveAppointmentSettings(
      current.copyWith(autoConfirmAppointments: enabled),
    );
  }

  Future<void> _setRemindersEnabled(bool enabled) async {
    final current = _appointmentSettings ?? const AppointmentSettings();
    await _saveAppointmentSettings(
      current.copyWith(remindersEnabled: enabled),
    );
  }

  Future<void> _setCancellationCutoff(int minutes) async {
    final current = _appointmentSettings ?? const AppointmentSettings();
    await _saveAppointmentSettings(
      current.copyWith(customerCancellationCutoffMinutes: minutes),
    );
  }

  Future<void> _setRescheduleCutoff(int minutes) async {
    final current = _appointmentSettings ?? const AppointmentSettings();
    await _saveAppointmentSettings(
      current.copyWith(customerRescheduleCutoffMinutes: minutes),
    );
  }

  String _cutoffLabel(int minutes) {
    if (minutes <= 0) {
      return barberinLabel('Χωρίς περιορισμό', 'No restriction');
    }
    if (minutes % 60 == 0) {
      final hours = minutes ~/ 60;
      return barberinLabel(
        '$hours ${hours == 1 ? 'ώρα' : 'ώρες'} πριν',
        '$hours ${hours == 1 ? 'hour' : 'hours'} before',
      );
    }
    return barberinLabel('$minutes λεπτά πριν', '$minutes minutes before');
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
              const SizedBox(height: 24),
              Text(
                barberinLabel('Ρυθμίσεις', 'Settings'),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: context.barberinTextPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                barberinLabel(
                  'Προσαρμόστε την εμφάνιση και τις προτιμήσεις του χώρου εργασίας σας.',
                  'Adjust the appearance and preferences of your workspace.',
                ),
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
                            SectionLabel(
                              barberinLabel('Εμφάνιση', 'Appearance'),
                            ),
                            const SizedBox(height: 12),
                            ValueListenableBuilder<ThemeMode>(
                              valueListenable: barberinThemeMode,
                              builder: (context, mode, child) {
                                return Column(
                                  children: [
                                    _ThemeOptionTile(
                                      icon: Icons.dark_mode_outlined,
                                      title: barberinLabel(
                                        'Σκούρα εμφάνιση',
                                        'Dark appearance',
                                      ),
                                      subtitle: barberinLabel(
                                        'Η σκούρα εμφάνιση του Barberin.',
                                        'Use the dark Barberin appearance.',
                                      ),
                                      selected: mode == ThemeMode.dark,
                                      onTap: () => unawaited(
                                        setBarberinThemeMode(ThemeMode.dark),
                                      ),
                                    ),
                                    Divider(
                                      height: 20,
                                      color: context.barberinBorder,
                                    ),
                                    _ThemeOptionTile(
                                      icon: Icons.light_mode_outlined,
                                      title: barberinLabel(
                                        'Ανοιχτόχρωμη εμφάνιση',
                                        'Light appearance',
                                      ),
                                      subtitle: barberinLabel(
                                        'Φωτεινό θέμα με καθαρή αντίθεση.',
                                        'Use the light theme with clear contrast.',
                                      ),
                                      selected: mode == ThemeMode.light,
                                      onTap: () => unawaited(
                                        setBarberinThemeMode(ThemeMode.light),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            Text(
                              barberinLabel(
                                'Η επιλογή αποθηκεύεται στη συσκευή και εφαρμόζεται σε όλη την εφαρμογή.',
                                'Your choice is saved on this device and applied throughout the app.',
                              ),
                              style: TextStyle(
                                color: context.barberinTextSecondary,
                                fontSize: 12,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SectionLabel(
                              barberinLabel('Προτιμήσεις', 'Preferences'),
                            ),
                            const SizedBox(height: 12),
                            ValueListenableBuilder<BarberinLanguage>(
                              valueListenable: barberinLanguage,
                              builder: (context, language, child) {
                                return _SettingsNavigationTile(
                                  icon: Icons.translate_rounded,
                                  title: barberinLabel('Γλώσσα', 'Language'),
                                  subtitle: language == BarberinLanguage.greek
                                      ? barberinLabel('Ελληνικά', 'Greek')
                                      : 'English',
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            const BarberinLanguagePage(),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SectionLabel(
                              barberinLabel('Ραντεβού', 'Appointments'),
                            ),
                            const SizedBox(height: 12),
                            if (_loadingAppointmentSettings)
                              const SizedBox(
                                height: 44,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            else if (_appointmentSettingsError != null)
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _appointmentSettingsError!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: context.barberinTextSecondary,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _loadingAppointmentSettings = true;
                                      });
                                      unawaited(_loadAppointmentSettings());
                                    },
                                    child: Text(barberinLabel('Ξανά', 'Retry')),
                                  ),
                                ],
                              )
                            else
                              Column(
                                children: [
                                  _AppointmentConfirmationTile(
                                    value:
                                        _appointmentSettings
                                            ?.autoConfirmAppointments ??
                                        false,
                                    enabled: _isOwner,
                                    loading: _savingAppointmentSettings,
                                    onChanged: _setAutoConfirmAppointments,
                                  ),
                                  Divider(
                                    height: 24,
                                    color: context.barberinBorder,
                                  ),
                                  _AppointmentConfirmationTile(
                                    value:
                                        _appointmentSettings?.remindersEnabled ??
                                        true,
                                    enabled: _isOwner,
                                    loading: _savingAppointmentSettings,
                                    icon: Icons.notifications_none_outlined,
                                    title: barberinLabel(
                                      'Υπενθυμίσεις πελατών',
                                      'Customer reminders',
                                    ),
                                    onLabel: barberinLabel(
                                      'Οι υπενθυμίσεις στέλνονται 24 ώρες και 1 ώρα πριν.',
                                      'Reminders are sent 24 hours and 1 hour before.',
                                    ),
                                    offLabel: barberinLabel(
                                      'Οι αυτόματες υπενθυμίσεις είναι απενεργοποιημένες.',
                                      'Automatic reminders are disabled.',
                                    ),
                                    onChanged: _setRemindersEnabled,
                                  ),
                                  Divider(
                                    height: 24,
                                    color: context.barberinBorder,
                                  ),
                                  _AppointmentCutoffTile(
                                    icon: Icons.event_busy_outlined,
                                    title: barberinLabel(
                                      'Ακύρωση από πελάτη',
                                      'Customer cancellation',
                                    ),
                                    value: _cutoffLabel(
                                      _appointmentSettings
                                              ?.customerCancellationCutoffMinutes ??
                                          0,
                                    ),
                                    enabled: _isOwner &&
                                        !_savingAppointmentSettings,
                                    onChanged: _setCancellationCutoff,
                                  ),
                                  Divider(
                                    height: 24,
                                    color: context.barberinBorder,
                                  ),
                                  _AppointmentCutoffTile(
                                    icon: Icons.edit_calendar_outlined,
                                    title: barberinLabel(
                                      'Επαναπρογραμματισμός από πελάτη',
                                      'Customer rescheduling',
                                    ),
                                    value: _cutoffLabel(
                                      _appointmentSettings
                                              ?.customerRescheduleCutoffMinutes ??
                                          0,
                                    ),
                                    enabled: _isOwner &&
                                        !_savingAppointmentSettings,
                                    onChanged: _setRescheduleCutoff,
                                  ),
                                ],
                              ),
                            const SizedBox(height: 10),
                            Text(
                              barberinLabel(
                                _isOwner
                                    ? 'Οι χρονικοί περιορισμοί είναι προαιρετικοί. Με «Χωρίς περιορισμό» διατηρείται η σημερινή συμπεριφορά.'
                                    : 'Οι ρυθμίσεις ελέγχονται από τον ιδιοκτήτη του καταστήματος.',
                                _isOwner
                                    ? 'Time limits are optional. “No restriction” keeps the current behavior.'
                                    : 'These settings are controlled by the shop owner.',
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.45,
                                color: context.barberinTextSecondary,
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

class BarberinLanguagePage extends StatelessWidget {
  const BarberinLanguagePage({super.key});

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
              const SizedBox(height: 24),
              Text(
                barberinLabel('Γλώσσα', 'Language'),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: context.barberinTextPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                barberinLabel(
                  'Επίλεξε τη γλώσσα που θα χρησιμοποιεί το Barberin.',
                  'Choose the language used throughout Barberin.',
                ),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: context.barberinTextSecondary,
                ),
              ),
              const SizedBox(height: 18),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionLabel(
                      barberinLabel('Επιλογή γλώσσας', 'Language selection'),
                    ),
                    const SizedBox(height: 12),
                    ValueListenableBuilder<BarberinLanguage>(
                      valueListenable: barberinLanguage,
                      builder: (context, language, child) {
                        return Column(
                          children: [
                            _LanguageOptionTile(
                              icon: Icons.translate_rounded,
                              title: 'Ελληνικά',
                              subtitle: barberinLabel(
                                'Χρησιμοποίησε το Barberin στα Ελληνικά.',
                                'Use Barberin in Greek.',
                              ),
                              selected: language == BarberinLanguage.greek,
                              onTap: () => unawaited(
                                setBarberinLanguage(BarberinLanguage.greek),
                              ),
                            ),
                            Divider(height: 20, color: context.barberinBorder),
                            _LanguageOptionTile(
                              icon: Icons.language_rounded,
                              title: 'English',
                              subtitle: barberinLabel(
                                'Χρησιμοποίησε το Barberin στα Αγγλικά.',
                                'Use Barberin in English.',
                              ),
                              selected: language == BarberinLanguage.english,
                              onTap: () => unawaited(
                                setBarberinLanguage(BarberinLanguage.english),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      barberinLabel(
                        'Η επιλογή αποθηκεύεται στη συσκευή και εφαρμόζεται σε όλο το Barberin.',
                        'Your choice is saved on this device and applied throughout Barberin.',
                      ),
                      style: TextStyle(
                        color: context.barberinTextSecondary,
                        fontSize: 12,
                        height: 1.45,
                      ),
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

class _ThemeOptionTile extends StatelessWidget {
  const _ThemeOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected
                      ? context.barberinSurfaceAlt
                      : context.barberinBackground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.barberinBorder),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: selected
                      ? context.barberinTextPrimary
                      : context.barberinTextSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: context.barberinTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: context.barberinTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected
                    ? context.barberinTextPrimary
                    : context.barberinTextSecondary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsNavigationTile extends StatelessWidget {
  const _SettingsNavigationTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: context.barberinSurfaceAlt,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 20, color: context.barberinTextPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: context.barberinTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.barberinTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: context.barberinTextSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppointmentConfirmationTile extends StatelessWidget {
  const _AppointmentConfirmationTile({
    required this.value,
    required this.enabled,
    required this.loading,
    required this.onChanged,
    this.icon = Icons.event_available_outlined,
    this.title,
    this.onLabel,
    this.offLabel,
  });

  final bool value;
  final bool enabled;
  final bool loading;
  final ValueChanged<bool> onChanged;
  final IconData icon;
  final String? title;
  final String? onLabel;
  final String? offLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 22,
          color: context.barberinTextPrimary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title ??
                    barberinLabel(
                      'Αυτόματη επιβεβαίωση',
                      'Automatic confirmation',
                    ),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: context.barberinTextPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value
                    ? onLabel ??
                        barberinLabel(
                          'Τα νέα ραντεβού επιβεβαιώνονται άμεσα.',
                          'New appointments are confirmed immediately.',
                        )
                    : offLabel ??
                        barberinLabel(
                          'Τα νέα ραντεβού χρειάζονται χειροκίνητη επιβεβαίωση.',
                          'New appointments require manual confirmation.',
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
        const SizedBox(width: 10),
        if (loading)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.barberinTextPrimary,
            ),
          )
        else
          Switch.adaptive(value: value, onChanged: enabled ? onChanged : null),
      ],
    );
  }
}

class _AppointmentCutoffTile extends StatelessWidget {
  const _AppointmentCutoffTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  static const _options = <int>[0, 30, 60, 120, 180, 360, 720, 1440];

  final IconData icon;
  final String title;
  final String value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22, color: context.barberinTextPrimary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: context.barberinTextPrimary,
            ),
          ),
        ),
        PopupMenuButton<int>(
          enabled: enabled,
          onSelected: onChanged,
          itemBuilder: (context) => _options
              .map(
                (minutes) => PopupMenuItem<int>(
                  value: minutes,
                  child: Text(
                    minutes == 0
                        ? barberinLabel('Χωρίς περιορισμό', 'No restriction')
                        : minutes % 60 == 0
                        ? barberinLabel(
                            '${minutes ~/ 60} ${(minutes ~/ 60) == 1 ? 'ώρα' : 'ώρες'} πριν',
                            '${minutes ~/ 60} ${(minutes ~/ 60) == 1 ? 'hour' : 'hours'} before',
                          )
                        : barberinLabel(
                            '$minutes λεπτά πριν',
                            '$minutes minutes before',
                          ),
                  ),
                ),
              )
              .toList(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  color: context.barberinTextSecondary,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: context.barberinTextSecondary,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LanguageOptionTile extends StatelessWidget {
  const _LanguageOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected
                      ? context.barberinSurfaceAlt
                      : context.barberinBackground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.barberinBorder),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: selected
                      ? context.barberinTextPrimary
                      : context.barberinTextSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: context.barberinTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: context.barberinTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected
                    ? context.barberinTextPrimary
                    : context.barberinTextSecondary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
