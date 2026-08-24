part of 'main.dart';

class ServicesManagementPage extends StatefulWidget {
  const ServicesManagementPage({super.key});

  @override
  State<ServicesManagementPage> createState() => _ServicesManagementPageState();
}

class _ServicesManagementPageState extends State<ServicesManagementPage> {
  final WeeklyScheduleRepository _scheduleRepository =
      WeeklyScheduleRepository();
  final CrewRepository _crewRepository = CrewRepository();
  List<ServiceDurationSetting> _services = <ServiceDurationSetting>[];
  List<ServicePriceSetting> _prices = <ServicePriceSetting>[];
  List<CrewMember> _barbers = <CrewMember>[];
  ServiceAddOnSetting _hairWash = buildDefaultServiceAddOns().first;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final scheduleFuture = _scheduleRepository.loadOrCreateDefault();
      final barbersFuture = _crewRepository.loadCrewMembers();
      final results = await Future.wait<dynamic>([
        scheduleFuture,
        barbersFuture,
      ]);
      if (!mounted) return;
      final schedule = results[0] as WeeklyScheduleData;
      setState(() {
        _services = List<ServiceDurationSetting>.from(
          schedule.serviceDurations,
        );
        _prices = List<ServicePriceSetting>.from(schedule.servicePrices);
        _hairWash = schedule.serviceAddOns.firstWhere(
          (item) => item.key == 'hair_wash',
          orElse: () => buildDefaultServiceAddOns().first,
        );
        _barbers = List<CrewMember>.from(results[1] as List<CrewMember>);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Δεν ήταν δυνατή η φόρτωση των υπηρεσιών.'),
        ),
      );
    }
  }

  Map<String, int> get _priceByKey => {
    for (final price in _prices) price.key.trim(): price.price,
  };

  String _priceLabel(String key) {
    return '${_priceByKey[key] ?? 0} EUR';
  }

  void _markChanged() {
    setState(() => _hasChanges = true);
  }

  Future<bool> _save() async {
    if (_isSaving) return false;
    setState(() => _isSaving = true);
    try {
      final current = await _scheduleRepository.loadOrCreateDefault();
      await _scheduleRepository.save(
        slotMinutes: current.slotMinutes,
        appointmentsPerSlot: current.appointmentsPerSlot,
        slotCapacityOverrides: current.slotCapacityOverrides,
        closedDateOverrides: current.closedDateOverrides,
        barberSchedules: current.barberSchedules,
        showPrices: current.showPrices,
        serviceDurations: _services,
        servicePrices: _prices,
        serviceAddOns: [_hairWash],
        days: current.days,
      );
      if (!mounted) return false;
      setState(() {
        _hasChanges = false;
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Οι υπηρεσίες αποθηκεύτηκαν.')),
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Δεν ήταν δυνατή η αποθήκευση των υπηρεσιών.'),
        ),
      );
      return false;
    }
  }

  Future<void> _editService([ServiceDurationSetting? existing]) async {
    final result = await showDialog<_ServiceFormResult>(
      context: context,
      builder: (_) => _ServiceEditorDialog(
        existing: existing,
        initialPrice: _priceByKey[existing?.key] ?? 0,
      ),
    );
    if (result == null || !mounted) return;

    // Let the dialog route finish deactivating its inherited dependencies
    // before rebuilding the page underneath it.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    if (existing == null) {
      final key = 'custom_service_${DateTime.now().microsecondsSinceEpoch}';
      _services = [
        ..._services,
        ServiceDurationSetting(
          key: key,
          label: result.label,
          minutes: result.minutes,
        ),
      ];
      _prices = [
        ..._prices,
        ServicePriceSetting(key: key, label: result.label, price: result.price),
      ];
    } else {
      _services = _services
          .map(
            (service) => service.key == existing.key
                ? service.copyWith(label: result.label, minutes: result.minutes)
                : service,
          )
          .toList();
      _prices = _prices
          .map(
            (price) => price.key == existing.key
                ? price.copyWith(label: result.label, price: result.price)
                : price,
          )
          .toList();
    }
    _markChanged();
  }

  Future<void> _assignBarbers(ServiceDurationSetting service) async {
    var allBarbers = service.barberIds.isEmpty;
    final selected = service.barberIds.toSet();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              title: Text('barber για ${service.label}'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    SwitchListTile(
                      value: allBarbers,
                      title: const Text('Όλοι οι barber'),
                      subtitle: const Text('Χωρίς περιορισμό ανά barber'),
                      onChanged: (value) {
                        setDialogState(() {
                          allBarbers = value;
                          if (value) selected.clear();
                        });
                      },
                    ),
                    if (!allBarbers)
                      ..._barbers.map(
                        (barber) => CheckboxListTile(
                          value: selected.contains(barber.id),
                          title: Text(barber.fullName),
                          onChanged: (value) {
                            setDialogState(() {
                              if (value == true) {
                                selected.add(barber.id);
                              } else {
                                selected.remove(barber.id);
                              }
                            });
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Ακύρωση'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(
                    dialogContext,
                  ).pop(allBarbers ? <String>[] : selected.toList()),
                  child: const Text('Εφαρμογή'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null || !mounted) return;
    setState(() {
      _services = _services
          .map(
            (item) => item.key == service.key
                ? item.copyWith(barberIds: result)
                : item,
          )
          .toList();
      _hasChanges = true;
    });
  }

  Future<void> _editHairWash() async {
    final result = await showDialog<_HairWashFormResult>(
      context: context,
      builder: (_) =>
          _HairWashEditorDialog(existing: _hairWash, services: _services),
    );
    if (result == null || !mounted) return;
    setState(() {
      _hairWash = _hairWash.copyWith(
        price: result.price,
        minutes: result.minutes,
        compatibleServiceKeys: result.compatibleServiceKeys,
      );
      _hasChanges = true;
    });
  }

  Future<void> _deleteService(ServiceDurationSetting service) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Διαγραφή υπηρεσίας;'),
        content: Text('Να αφαιρεθεί η ${service.label} από αυτό το κατάστημα;'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Διαγραφή'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final previousServices = List<ServiceDurationSetting>.from(_services);
    final previousPrices = List<ServicePriceSetting>.from(_prices);
    final previousHairWash = _hairWash;
    setState(() {
      _services = _services.where((item) => item.key != service.key).toList();
      _prices = _prices.where((item) => item.key != service.key).toList();
      _hairWash = _hairWash.copyWith(
        compatibleServiceKeys: _hairWash.compatibleServiceKeys
            .where((key) => key != service.key)
            .toList(),
      );
      _hasChanges = true;
    });
    final saved = await _save();
    if (!saved && mounted) {
      setState(() {
        _services = previousServices;
        _prices = previousPrices;
        _hairWash = previousHairWash;
        _hasChanges = true;
      });
    }
  }

  String _assignmentLabel(ServiceDurationSetting service) {
    if (service.barberIds.isEmpty) return 'Όλοι οι barber';
    final names = _barbers
        .where((barber) => service.barberIds.contains(barber.id))
        .map((barber) => barber.fullName)
        .where((name) => name.trim().isNotEmpty)
        .toList();
    return names.isEmpty ? 'Επιλεγμένοι barber' : names.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _services.where((service) => service.enabled).length;
    return Scaffold(
      backgroundColor: context.barberinBackground,
      body: SafeArea(
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
                    'ΔΙΑΧΕΙΡΙΣΗ ΥΠΗΡΕΣΙΩΝ',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: context.barberinAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Υπηρεσίες',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: context.barberinTextPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _isLoading ? null : () => _editService(),
                    icon: const Icon(Icons.add_rounded),
                    color: context.barberinAccent,
                    tooltip: barberinTranslate(
                      '\u03a0\u03c1\u03bf\u03c3\u03b8\u03ae\u03ba\u03b7 \u03c5\u03c0\u03b7\u03c1\u03b5\u03c3\u03af\u03b1\u03c2',
                    ),
                  ),
                ],
              ),
              Text(
                '$activeCount ενεργές από ${_services.length} υπηρεσίες',
                style: TextStyle(
                  color: context.barberinTextSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Container(
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
                            '\u039b\u03bf\u03cd\u03c3\u03b9\u03bc\u03bf \u03c9\u03c2 add-on',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: context.barberinTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '\u002b${_hairWash.price} EUR · ${_hairWash.minutes} \u03bb\u03b5\u03c0\u03c4\u03ac · ${_hairWash.compatibleServiceKeys.length} \u03c5\u03c0\u03b7\u03c1\u03b5\u03c3\u03af\u03b5\u03c2',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.barberinTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _hairWash.enabled,
                      activeThumbColor: context.barberinAccent,
                      onChanged: (value) {
                        setState(() {
                          _hairWash = _hairWash.copyWith(enabled: value);
                          _hasChanges = true;
                        });
                      },
                    ),
                    IconButton(
                      onPressed: _editHairWash,
                      icon: const Icon(Icons.tune_rounded),
                      color: context.barberinAccent,
                      tooltip: barberinTranslate(
                        '\u03a1\u03c5\u03b8\u03bc\u03af\u03c3\u03b7 \u03bb\u03bf\u03c5\u03c3\u03af\u03bc\u03b1\u03c4\u03bf\u03c2',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: context.barberinAccent,
                        ),
                      )
                    : _services.isEmpty
                    ? Center(
                        child: Text(
                          'Δεν έχουν ρυθμιστεί ακόμη υπηρεσίες.',
                          style: TextStyle(
                            color: context.barberinTextSecondary,
                          ),
                        ),
                      )
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        itemCount: _services.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 0),
                        itemBuilder: (context, index) {
                          final service = _services[index];
                          return Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: service.enabled
                                      ? context.barberinBorder
                                      : context.barberinSurfaceAlt,
                                ),
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            service.label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: service.enabled
                                                  ? context.barberinTextPrimary
                                                  : context
                                                        .barberinTextSecondary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${service.minutes} λεπτά • ${_priceLabel(service.key)}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color:
                                                  context.barberinTextSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: service.enabled,
                                      activeThumbColor: context.barberinAccent,
                                      onChanged: (value) {
                                        setState(() {
                                          _services = _services
                                              .map(
                                                (item) =>
                                                    item.key == service.key
                                                    ? item.copyWith(
                                                        enabled: value,
                                                      )
                                                    : item,
                                              )
                                              .toList();
                                          _hasChanges = true;
                                        });
                                      },
                                    ),
                                    PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'edit') {
                                          _editService(service);
                                        }
                                        if (value == 'barbers') {
                                          _assignBarbers(service);
                                        }
                                        if (value == 'delete') {
                                          _deleteService(service);
                                        }
                                      },
                                      itemBuilder: (context) => const [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Επεξεργασία'),
                                        ),
                                        PopupMenuItem(
                                          value: 'barbers',
                                          child: Text('Ανάθεση σε barber'),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Διαγραφή'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    _assignmentLabel(service),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSaving || !_hasChanges ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _isSaving ? 'Αποθήκευση...' : 'Αποθήκευση υπηρεσιών',
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

class _ServiceFormResult {
  const _ServiceFormResult({
    required this.label,
    required this.minutes,
    required this.price,
  });

  final String label;
  final int minutes;
  final int price;
}

class _HairWashFormResult {
  const _HairWashFormResult({
    required this.price,
    required this.minutes,
    required this.compatibleServiceKeys,
  });

  final int price;
  final int minutes;
  final List<String> compatibleServiceKeys;
}

class _HairWashEditorDialog extends StatefulWidget {
  const _HairWashEditorDialog({required this.existing, required this.services});

  final ServiceAddOnSetting existing;
  final List<ServiceDurationSetting> services;

  @override
  State<_HairWashEditorDialog> createState() => _HairWashEditorDialogState();
}

class _HairWashEditorDialogState extends State<_HairWashEditorDialog> {
  late final TextEditingController _priceController;
  late int _minutes;
  late Set<String> _selectedServiceKeys;

  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(text: '${widget.existing.price}');
    _minutes = widget.existing.minutes.clamp(1, 15);
    _selectedServiceKeys = widget.existing.compatibleServiceKeys.toSet();
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  void _submit() {
    final price = int.tryParse(_priceController.text.trim());
    if (price == null || price < 0) return;
    Navigator.of(context).pop(
      _HairWashFormResult(
        price: price,
        minutes: _minutes,
        compatibleServiceKeys: _selectedServiceKeys.toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compatibleServices = widget.services.where(
      (service) => service.key != 'beard_trim',
    );
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: const Text(
        '\u03a1\u03cd\u03b8\u03bc\u03b9\u03c3\u03b7 \u03bb\u03bf\u03c5\u03c3\u03af\u03bc\u03b1\u03c4\u03bf\u03c2',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: barberinTranslate(
                  '\u03a0\u03c1\u03cc\u03c3\u03b8\u03b5\u03c4\u03b7 \u03c4\u03b9\u03bc\u03ae (EUR)',
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _minutes,
              decoration: InputDecoration(
                labelText: barberinTranslate(
                  '\u0395\u03c0\u03b9\u03c0\u03bb\u03ad\u03bf\u03bd \u03c7\u03c1\u03cc\u03bd\u03bf',
                ),
              ),
              items: [
                for (var value = 1; value <= 15; value++)
                  DropdownMenuItem(
                    value: value,
                    child: Text('$value \u03bb\u03b5\u03c0\u03c4\u03ac'),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _minutes = value);
              },
            ),
            const SizedBox(height: 16),
            const Text(
              '\u0394\u03b9\u03b1\u03b8\u03ad\u03c3\u03b9\u03bc\u03bf \u03bc\u03b5 \u03c4\u03b9\u03c2 \u03b5\u03be\u03ae\u03c2 \u03c5\u03c0\u03b7\u03c1\u03b5\u03c3\u03af\u03b5\u03c2:',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            ...compatibleServices.map(
              (service) => CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _selectedServiceKeys.contains(service.key),
                title: Text(service.label),
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _selectedServiceKeys.add(service.key);
                    } else {
                      _selectedServiceKeys.remove(service.key);
                    }
                  });
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('\u0391\u03ba\u03cd\u03c1\u03c9\u03c3\u03b7'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text(
            '\u0391\u03c0\u03bf\u03b8\u03ae\u03ba\u03b5\u03c5\u03c3\u03b7',
          ),
        ),
      ],
    );
  }
}

class _ServiceEditorDialog extends StatefulWidget {
  const _ServiceEditorDialog({
    required this.existing,
    required this.initialPrice,
  });

  final ServiceDurationSetting? existing;
  final int initialPrice;

  @override
  State<_ServiceEditorDialog> createState() => _ServiceEditorDialogState();
}

class _ServiceEditorDialogState extends State<_ServiceEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late int _minutes;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.label ?? '');
    _priceController = TextEditingController(text: '${widget.initialPrice}');
    _minutes = widget.existing?.minutes ?? 30;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _submit() {
    final label = _nameController.text.trim();
    final price = int.tryParse(_priceController.text.trim());
    if (label.isEmpty || price == null || price < 0) return;
    Navigator.of(
      context,
    ).pop(_ServiceFormResult(label: label, minutes: _minutes, price: price));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: Text(
        widget.existing == null
            ? 'Προσθήκη υπηρεσίας'
            : 'Επεξεργασία υπηρεσίας',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: widget.existing == null,
              decoration: InputDecoration(
                labelText: barberinTranslate('Όνομα υπηρεσίας'),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _minutes,
              decoration: InputDecoration(
                labelText: barberinTranslate('Διάρκεια'),
              ),
              items: [
                for (var value = 5; value <= 120; value += 5)
                  DropdownMenuItem(value: value, child: Text('$value λεπτά')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _minutes = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: barberinTranslate('Τιμή (EUR)'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ακύρωση'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Αποθήκευση')),
      ],
    );
  }
}
