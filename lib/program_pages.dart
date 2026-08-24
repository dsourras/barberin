part of 'main.dart';

class ProgramPage extends StatefulWidget {
  const ProgramPage({
    super.key,
    required this.selectedDate,
    required this.entries,
    required this.onPreviousDay,
    required this.onNextDay,
    required this.onPickDate,
    required this.onQuickAdd,
    this.onQuickAddForSlot,
    required this.customerPhotoUrlForEntry,
    required this.onOpenCustomer,
    required this.onManageAppointment,
  });

  final DateTime selectedDate;
  final List<ProgramEntry> entries;
  final VoidCallback onPreviousDay;
  final VoidCallback onNextDay;
  final VoidCallback onPickDate;
  final VoidCallback onQuickAdd;
  final ValueChanged<ProgramEntry>? onQuickAddForSlot;
  final String Function(ProgramEntry entry) customerPhotoUrlForEntry;
  final ValueChanged<ProgramEntry> onOpenCustomer;
  final ValueChanged<ProgramEntry> onManageAppointment;

  @override
  State<ProgramPage> createState() => _ProgramPageState();
}

class _ProgramPageState extends State<ProgramPage> {
  bool _showAvailableSlots = true;
  String _statusFilter = 'all';
  String? _barberFilter;

  List<String> get _barberNames {
    final names = widget.entries
        .where((entry) => !entry.isBreak && entry.barberName.trim().isNotEmpty)
        .map((entry) => entry.barberName.trim())
        .toSet()
        .toList();
    names.sort();
    return names;
  }

  List<ProgramEntry> get _visibleEntries {
    return widget.entries.where((entry) {
      if (entry.isBreak) {
        return true;
      }
      if (entry.isAvailable) {
        return _showAvailableSlots &&
            (_statusFilter == 'all' || _statusFilter == 'available');
      }
      if (_statusFilter == 'available') {
        return false;
      }
      if (_statusFilter != 'all' && entry.status != _statusFilter) {
        return false;
      }
      if (_barberFilter != null && entry.barberName.trim() != _barberFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  bool get _hasActiveFilters =>
      !_showAvailableSlots || _statusFilter != 'all' || _barberFilter != null;

  Future<void> _openFilters() async {
    var showAvailableSlots = _showAvailableSlots;
    var statusFilter = _statusFilter;
    var barberFilter = _barberFilter;
    var applied = false;
    final barberNames = _barberNames;
    const statusOptions = [
      ('all', '\u038c\u03bb\u03b1'),
      ('pending', '\u03a3\u03b5 \u03b1\u03bd\u03b1\u03bc\u03bf\u03bd\u03ae'),
      (
        'confirmed',
        '\u0395\u03c0\u03b9\u03b2\u03b5\u03b2\u03b1\u03b9\u03c9\u03bc\u03ad\u03bd\u03b1',
      ),
      (
        'completed',
        '\u039f\u03bb\u03bf\u03ba\u03bb\u03b7\u03c1\u03c9\u03bc\u03ad\u03bd\u03b1',
      ),
      ('cancelled', '\u0391\u03ba\u03c5\u03c1\u03c9\u03bc\u03ad\u03bd\u03b1'),
      ('no_show', 'Δεν εμφανίστηκε'),
      ('available', '\u0394\u03b9\u03b1\u03b8\u03ad\u03c3\u03b9\u03bc\u03b1'),
    ];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.barberinSurface,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '\u03a6\u03af\u03bb\u03c4\u03c1\u03b1',
                            style: TextStyle(
                              color: context.barberinTextPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: Icon(
                            Icons.close_rounded,
                            color: context.barberinTextSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '\u0394\u03b9\u03b1\u03b8\u03ad\u03c3\u03b9\u03bc\u03b1 slots',
                        style: TextStyle(
                          color: context.barberinTextPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        '\u0395\u03bc\u03c6\u03ac\u03bd\u03b9\u03c3\u03b7 \u03c4\u03c9\u03bd \u03ba\u03b5\u03bd\u03ce\u03bd \u03c3\u03c4\u03bf\u03bd \u03c1\u03bf\u03ae',
                        style: TextStyle(
                          color: context.barberinTextSecondary,
                          fontSize: 11,
                        ),
                      ),
                      value: showAvailableSlots,
                      activeThumbColor: Theme.of(context).colorScheme.primary,
                      onChanged: (value) =>
                          setSheetState(() => showAvailableSlots = value),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '\u039a\u03b1\u03c4\u03ac\u03c3\u03c4\u03b1\u03c3\u03b7',
                      style: TextStyle(
                        color: context.barberinTextSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: statusOptions.map((option) {
                        final selected = statusFilter == option.$1;
                        return ChoiceChip(
                          label: Text(option.$2),
                          selected: selected,
                          onSelected: (_) => setSheetState(() {
                            statusFilter = option.$1;
                            if (option.$1 == 'available') {
                              showAvailableSlots = true;
                            }
                          }),
                          selectedColor: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.16),
                          labelStyle: TextStyle(
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : context.barberinTextSecondary,
                            fontSize: 11,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                          side: BorderSide(color: context.barberinBorder),
                          backgroundColor: context.barberinSurface,
                        );
                      }).toList(),
                    ),
                    if (barberNames.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        'Barber',
                        style: TextStyle(
                          color: context.barberinTextSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String?>(
                        initialValue: barberFilter,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: barberinTranslate(
                            '\u038c\u03bb\u03bf\u03b9 \u03bf\u03b9 barber',
                          ),
                          labelStyle: TextStyle(
                            color: context.barberinTextSecondary,
                            fontSize: 12,
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: context.barberinBorder,
                            ),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(
                              '\u038c\u03bb\u03bf\u03b9 \u03bf\u03b9 barber',
                              style: TextStyle(
                                color: context.barberinTextPrimary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          ...barberNames.map(
                            (name) => DropdownMenuItem<String?>(
                              value: name,
                              child: Text(
                                name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.barberinTextPrimary,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) =>
                            setSheetState(() => barberFilter = value),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _showAvailableSlots = true;
                                _statusFilter = 'all';
                                _barberFilter = null;
                              });
                              Navigator.of(sheetContext).pop();
                            },
                            child: const Text(
                              '\u039a\u03b1\u03b8\u03b1\u03c1\u03b9\u03c3\u03bc\u03cc\u03c2',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              applied = true;
                              Navigator.of(sheetContext).pop();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onPrimary,
                            ),
                            child: const Text(
                              '\u0395\u03c6\u03b1\u03c1\u03bc\u03bf\u03b3\u03ae',
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

    if (applied && mounted) {
      setState(() {
        _showAvailableSlots = showAvailableSlots;
        _statusFilter = statusFilter;
        _barberFilter = barberFilter;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleEntries = _visibleEntries;
    return Container(
      color: context.barberinBackground,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Stack(
            children: [
              Column(
                children: [
                  _ProgramTopBar(
                    onOpenFilters: _openFilters,
                    hasActiveFilter: _hasActiveFilters,
                  ),
                  const SizedBox(height: 12),
                  _ProgramDateBar(
                    selectedDate: widget.selectedDate,
                    onPreviousDay: widget.onPreviousDay,
                    onNextDay: widget.onNextDay,
                    onPickDate: widget.onPickDate,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: visibleEntries.isEmpty
                        ? Center(
                            child: Text(
                              '\u0394\u03b5\u03bd \u03b2\u03c1\u03ad\u03b8\u03b7\u03ba\u03b1\u03bd \u03c1\u03b1\u03bd\u03c4\u03b5\u03b2\u03bf\u03cd \u03ae \u03b4\u03b9\u03b1\u03b8\u03ad\u03c3\u03b9\u03bc\u03b1 slots.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: context.barberinTextSecondary,
                                fontSize: 13,
                              ),
                            ),
                          )
                        : ListView.builder(
                            physics: const BouncingScrollPhysics(),
                            itemCount: visibleEntries.length,
                            itemBuilder: (context, index) {
                              final entry = visibleEntries[index];
                              if (entry.isBreak) {
                                return _BreakTimelineRow(hour: entry.hour);
                              }
                              return _ProgramTimelineCard(
                                entry: entry,
                                customerPhotoUrl: widget
                                    .customerPhotoUrlForEntry(entry),
                                onTap: entry.isAvailable
                                    ? widget.onQuickAddForSlot == null
                                          ? widget.onQuickAdd
                                          : () =>
                                                widget.onQuickAddForSlot!(entry)
                                    : () => widget.onManageAppointment(entry),
                                onLongPress:
                                    entry.isAvailable ||
                                        entry.blocked ||
                                        entry.name.trim().isEmpty
                                    ? null
                                    : () => widget.onOpenCustomer(entry),
                              );
                            },
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

class CustomersListPage extends StatefulWidget {
  const CustomersListPage({
    super.key,
    required this.customers,
    required this.onOpenCustomer,
    required this.onManageCustomer,
  });

  final List<CustomerProfile> customers;
  final ValueChanged<CustomerProfile> onOpenCustomer;
  final ValueChanged<CustomerProfile> onManageCustomer;

  @override
  State<CustomersListPage> createState() => _CustomersListPageState();
}

class _CustomersListPageState extends State<CustomersListPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filteredCustomers = widget.customers.where((customer) {
      if (query.isEmpty) {
        return true;
      }
      return customer.name.trim().toLowerCase().contains(query) ||
          customer.phone.trim().toLowerCase().contains(query) ||
          customer.email.trim().toLowerCase().contains(query);
    }).toList();
    return Container(
      color: context.barberinBackground,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const AppHamburgerMenu(),
                  const Spacer(),
                  Text(
                    'ΠΕΛΑΤΕΣ',
                    style: TextStyle(
                      fontSize: 13,
                      letterSpacing: .9,
                      fontWeight: FontWeight.w500,
                      color: context.barberinTextPrimary,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 22),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: context.barberinBorder),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(
                          color: context.barberinTextPrimary,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          fillColor: Colors.transparent,
                          hintText: barberinTranslate('Αναζήτηση πελατών'),
                          hintStyle: TextStyle(
                            color: context.barberinTextSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    if (_searchController.text.trim().isNotEmpty)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          child: SizedBox(
                            width: 36,
                            height: 36,
                            child: Center(
                              child: Icon(
                                Icons.close_rounded,
                                color: context.barberinTextSecondary,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: filteredCustomers.isEmpty
                    ? const _EmptyCustomersCard()
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        itemCount: filteredCustomers.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 0),
                        itemBuilder: (context, index) {
                          final customer = filteredCustomers[index];
                          return _CustomerListTile(
                            customer: customer,
                            onTap: () => widget.onOpenCustomer(customer),
                            onLongPress: () =>
                                widget.onManageCustomer(customer),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomerProfilePage extends StatelessWidget {
  const CustomerProfilePage({
    super.key,
    required this.customer,
    this.showBack = false,
  });

  final CustomerProfile customer;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final hasCallablePhone = customer.phone.trim().isNotEmpty;
    return Container(
      color: context.barberinBackground,
      child: SafeArea(
        child: DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    showBack
                        ? GestureDetector(
                            onTap: () => Navigator.of(context).maybePop(),
                            child: Icon(
                              Icons.arrow_back_rounded,
                              color: Theme.of(context).colorScheme.primary,
                              size: 22,
                            ),
                          )
                        : const AppHamburgerMenu(),
                    const Spacer(),
                    Text(
                      'ΠΕΛΑΤΗΣ',
                      style: TextStyle(
                        fontSize: 13,
                        letterSpacing: .9,
                        fontWeight: FontWeight.w500,
                        color: context.barberinTextPrimary,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 22),
                  ],
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  context.barberinAccentSoft,
                                  context.barberinSurfaceAlt,
                                ],
                              ),
                              border: Border.all(color: context.barberinBorder),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: customer.photoUrl.isNotEmpty
                                ? Image.network(
                                    customer.photoUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(
                                        Icons.person_rounded,
                                        size: 82,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      );
                                    },
                                  )
                                : Icon(
                                    Icons.person_rounded,
                                    size: 82,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          customer.name,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: context.barberinTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: context.barberinBorder),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.call_rounded,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  hasCallablePhone
                                      ? customer.phone
                                      : '\u0394\u03b5\u03bd \u03c5\u03c0\u03ac\u03c1\u03c7\u03b5\u03b9 \u03c4\u03b7\u03bb\u03ad\u03c6\u03c9\u03bd\u03bf',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: context.barberinTextPrimary,
                                  ),
                                ),
                              ),
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: hasCallablePhone
                                      ? () => launchPhoneCall(customer.phone)
                                      : null,
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: hasCallablePhone
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : context.barberinBorder,
                                      ),
                                      color: hasCallablePhone
                                          ? context.barberinAccentSoft
                                          : context.barberinSurfaceAlt,
                                    ),
                                    child: Icon(
                                      Icons.phone_forwarded_rounded,
                                      color: hasCallablePhone
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : context.barberinTextSecondary,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (customer.email.trim().isNotEmpty) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: context.barberinBorder,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.alternate_email_rounded,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    customer.email,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: context.barberinTextPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        _ProfilePanel(
                          title:
                              '\u03a0\u03a1\u039f\u03a4\u0399\u039c\u0397\u03a3\u0395\u0399\u03a3',
                          child: customer.preferences.isEmpty
                              ? Text(
                                  '\u0394\u03b5\u03bd \u03c5\u03c0\u03ac\u03c1\u03c7\u03bf\u03c5\u03bd \u03b1\u03ba\u03cc\u03bc\u03b1 \u03c0\u03c1\u03bf\u03c4\u03b9\u03bc\u03ae\u03c3\u03b5\u03b9\u03c2.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.barberinTextSecondary,
                                  ),
                                )
                              : SizedBox(
                                  height: 116,
                                  child: Scrollbar(
                                    thumbVisibility: true,
                                    child: ListView.separated(
                                      physics: const BouncingScrollPhysics(),
                                      itemCount: customer.preferences.length,
                                      separatorBuilder: (context, index) =>
                                          const SizedBox(height: 0),
                                      itemBuilder: (context, index) {
                                        final item =
                                            customer.preferences[index];
                                        return Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: context.barberinBorder,
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            item,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              height: 1.4,
                                              color:
                                                  context.barberinTextPrimary,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(height: 12),
                        _ProfilePanel(
                          title:
                              '\u0399\u03a3\u03a4\u039f\u03a1\u0399\u039a\u039f \u0395\u03a0\u0399\u03a3\u039a\u0395\u03a8\u0395\u03a9\u039d',
                          child: customer.history.isEmpty
                              ? Text(
                                  '\u0394\u03b5\u03bd \u03c5\u03c0\u03ac\u03c1\u03c7\u03b5\u03b9 \u03b1\u03ba\u03cc\u03bc\u03b1 \u03b9\u03c3\u03c4\u03bf\u03c1\u03b9\u03ba\u03cc \u03c1\u03b1\u03bd\u03c4\u03b5\u03b2\u03bf\u03cd.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.barberinTextSecondary,
                                  ),
                                )
                              : SizedBox(
                                  height: 112,
                                  child: Scrollbar(
                                    thumbVisibility: true,
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 10),
                                      child: ListView.separated(
                                        physics: const BouncingScrollPhysics(),
                                        itemCount: customer.history.length,
                                        separatorBuilder: (context, index) =>
                                            Divider(
                                              height: 1,
                                              color: context.barberinBorder,
                                            ),
                                        itemBuilder: (context, index) {
                                          final visit = customer.history[index];
                                          return Row(
                                            children: [
                                              Expanded(
                                                flex: 3,
                                                child: Text(
                                                  barberinDateLabelFromRaw(
                                                    visit.date,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: context
                                                        .barberinTextPrimary,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                flex: 3,
                                                child: Text(
                                                  visit.service,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: context
                                                        .barberinTextSecondary,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                '\u20ac${visit.price}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: context
                                                      .barberinTextPrimary,
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                        if (customer.notes.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _ProfilePanel(
                            title:
                                '\u03a3\u0397\u039c\u0395\u0399\u03a9\u03a3\u0395\u0399\u03a3',
                            child: Text(
                              customer.notes,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: context.barberinTextSecondary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
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

class _CustomerListTile extends StatelessWidget {
  const _CustomerListTile({
    required this.customer,
    required this.onTap,
    required this.onLongPress,
  });

  final CustomerProfile customer;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.barberinBorder)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 46,
              height: 46,
              child: CustomerAvatarBadge(
                photoUrl: customer.photoUrl,
                size: 46,
                placeholderIcon: Icons.person_rounded,
                gradientColors: [
                  context.barberinAccentSoft,
                  context.barberinSurfaceAlt,
                ],
                borderColor: context.barberinBorder,
                iconColor: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.barberinTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    customer.history.isEmpty
                        ? 'Δεν υπάρχουν επισκέψεις ακόμη'
                        : 'Τελευταία επίσκεψη ${barberinDateLabelFromRaw(customer.history.first.date)}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: context.barberinTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${customer.history.length}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.barberinTextPrimary,
                  ),
                ),
                Text(
                  'Επισκέψεις',
                  style: TextStyle(
                    fontSize: 10,
                    color: context.barberinTextSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCustomersCard extends StatelessWidget {
  const _EmptyCustomersCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.barberinSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.barberinBorder),
      ),
      child: Text(
        '\u0394\u03b5\u03bd \u03c5\u03c0\u03ac\u03c1\u03c7\u03bf\u03c5\u03bd \u03b1\u03ba\u03cc\u03bc\u03b1 \u03c0\u03b5\u03bb\u03ac\u03c4\u03b5\u03c2 \u03c3\u03c4\u03b7 \u03bb\u03af\u03c3\u03c4\u03b1.',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: context.barberinTextPrimary,
        ),
      ),
    );
  }
}

class _ProfilePanel extends StatelessWidget {
  const _ProfilePanel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 14),
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
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                    color: context.barberinTextPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ProgramTopBar extends StatelessWidget {
  const _ProgramTopBar({
    required this.onOpenFilters,
    required this.hasActiveFilter,
  });

  final VoidCallback onOpenFilters;
  final bool hasActiveFilter;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const AppHamburgerMenu(),
        const Spacer(),
        Text(
          'ΠΡΟΓΡΑΜΜΑ',
          style: TextStyle(
            fontSize: 13,
            letterSpacing: .9,
            fontWeight: FontWeight.w500,
            color: context.barberinTextPrimary,
          ),
        ),
        const Spacer(),
        _TouchIconButton(
          onTap: onOpenFilters,
          icon: Icons.tune_rounded,
          color: hasActiveFilter
              ? Theme.of(context).colorScheme.primary
              : context.barberinTextSecondary,
          size: 21,
        ),
      ],
    );
  }
}

class _ProgramDateBar extends StatelessWidget {
  const _ProgramDateBar({
    required this.selectedDate,
    required this.onPreviousDay,
    required this.onNextDay,
    required this.onPickDate,
  });

  final DateTime selectedDate;
  final VoidCallback onPreviousDay;
  final VoidCallback onNextDay;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: context.barberinSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.barberinBorder),
      ),
      child: Row(
        children: [
          _TouchIconButton(
            onTap: onPreviousDay,
            icon: Icons.chevron_left_rounded,
            color: context.barberinTextPrimary,
            size: 22,
          ),
          Expanded(
            child: Center(
              child: Text(
                barberinDateLabel(selectedDate),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: context.barberinTextPrimary,
                ),
              ),
            ),
          ),
          _TouchIconButton(
            onTap: onNextDay,
            icon: Icons.chevron_right_rounded,
            color: context.barberinTextPrimary,
            size: 22,
          ),
          const SizedBox(width: 10),
          _TouchIconButton(
            onTap: onPickDate,
            icon: Icons.calendar_today_outlined,
            color: Theme.of(context).colorScheme.primary,
            size: 18,
          ),
        ],
      ),
    );
  }
}

class _TouchIconButton extends StatelessWidget {
  const _TouchIconButton({
    required this.onTap,
    required this.icon,
    required this.color,
    required this.size,
  });

  final VoidCallback onTap;
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Icon(icon, color: color, size: size),
          ),
        ),
      ),
    );
  }
}

class _ProgramTimelineCard extends StatelessWidget {
  const _ProgramTimelineCard({
    required this.entry,
    this.customerPhotoUrl = '',
    this.onTap,
    this.onLongPress,
  });

  final ProgramEntry entry;
  final String customerPhotoUrl;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final isLight = context.barberinIsLight;
    final isAvailable = entry.isAvailable;
    final barberName = entry.barberName.trim();
    final isBlocked = entry.blocked;
    final statusTone = barberinAppointmentTone(
      entry.status,
      isAvailable: isAvailable || isBlocked,
    );
    final statusForeground = barberinAppointmentForeground(
      entry.status,
      isAvailable: isAvailable || isBlocked,
    );
    final statusLabel = isAvailable
        ? 'Διαθέσιμο slot'
        : switch (entry.status) {
            'pending' => 'Σε αναμονή',
            'confirmed' => 'Επιβεβαιωμένο',
            'completed' => 'Ολοκληρωμένο',
            'cancelled' => 'Ακυρωμένο',
            'no_show' => 'Δεν εμφανίστηκε',
            _ => 'Επιβεβαιωμένο',
          };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.barberinBorder)),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        color: statusTone.withValues(alpha: isLight ? 0.20 : 0.22),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 40,
              child: Text(
                entry.hour,
                style: TextStyle(
                  fontSize: 12,
                  color: context.barberinTextSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: isBlocked ? null : onTap,
                onLongPress: onLongPress,
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: CustomerAvatarBadge(
                        photoUrl: isBlocked ? '' : customerPhotoUrl,
                        size: 36,
                        placeholderIcon: isAvailable
                            ? Icons.schedule_rounded
                            : Icons.person_rounded,
                        gradientColors: isLight
                            ? [
                                statusTone.withValues(alpha: 0.16),
                                context.barberinSurfaceAlt,
                              ]
                            : const [Color(0xFF44311E), Color(0xFF202020)],
                        borderColor: isLight
                            ? statusForeground.withValues(alpha: 0.38)
                            : const Color(0xFFC49A5C),
                        iconColor: isLight
                            ? Theme.of(context).colorScheme.primary
                            : const Color(0xFFF0E5D1),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isBlocked ? 'Κλειστό slot' : entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: context.barberinTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusTone.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: statusForeground.withValues(alpha: 0.58),
                              ),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: statusForeground,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isBlocked && entry.blockReason.trim().isNotEmpty
                                ? entry.blockReason
                                : entry.service,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: isLight
                                  ? context.barberinTextSecondary
                                  : entry.highlighted
                                  ? const Color(0xFFF2E3C8)
                                  : const Color(0xFFF1DFC0),
                            ),
                          ),
                          if (barberName.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'barber: $barberName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.2,
                                fontWeight: FontWeight.w600,
                                color: context.barberinTextSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      entry.duration,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: context.barberinTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakTimelineRow extends StatelessWidget {
  const _BreakTimelineRow({required this.hour});

  final String hour;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            hour,
            style: TextStyle(
              fontSize: 12,
              color: context.barberinTextSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: Divider(color: context.barberinBorder, thickness: .7),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  '\u0394\u0399\u0391\u039b\u0395\u0399\u039c\u039c\u0391',
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: .8,
                    color: context.barberinTextSecondary,
                  ),
                ),
              ),
              Expanded(
                child: Divider(color: context.barberinBorder, thickness: .7),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
