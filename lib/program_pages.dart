part of 'main.dart';

class ProgramPage extends StatelessWidget {
  const ProgramPage({
    super.key,
    required this.selectedDate,
    required this.entries,
    required this.onPreviousDay,
    required this.onNextDay,
    required this.onPickDate,
    required this.onQuickAdd,
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
  final String Function(ProgramEntry entry) customerPhotoUrlForEntry;
  final ValueChanged<ProgramEntry> onOpenCustomer;
  final ValueChanged<ProgramEntry> onManageAppointment;

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
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Stack(
            children: [
              Column(
                children: [
                  const _ProgramTopBar(),
                  const SizedBox(height: 12),
                  _ProgramDateBar(
                    selectedDate: selectedDate,
                    onPreviousDay: onPreviousDay,
                    onNextDay: onNextDay,
                    onPickDate: onPickDate,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      itemCount: entries.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        if (entry.isBreak) {
                          return _BreakTimelineRow(hour: entry.hour);
                        }
                        return _ProgramTimelineCard(
                          entry: entry,
                          customerPhotoUrl: customerPhotoUrlForEntry(entry),
                          onTap: () => onOpenCustomer(entry),
                          onLongPress: () => onManageAppointment(entry),
                        );
                      },
                    ),
                  ),
                ],
              ),
              Positioned(
                right: 4,
                bottom: 18,
                child: GestureDetector(
                  onTap: onQuickAdd,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFD1A45C), Color(0xFF8E6637)],
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 20,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: Color(0xFF0D0D0D),
                      size: 30,
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
    final filteredCustomers =
        widget.customers.where((customer) {
          if (query.isEmpty) {
            return true;
          }
          return customer.name.trim().toLowerCase().contains(query) ||
              customer.phone.trim().toLowerCase().contains(query) ||
              customer.email.trim().toLowerCase().contains(query);
        }).toList();
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
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  AppHamburgerMenu(),
                  Spacer(),
                  Text(
                    '\u03a0\u0395\u039b\u0391\u03a4\u0395\u03a3',
                    style: TextStyle(
                      fontSize: 13,
                      letterSpacing: .9,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFE9E1D2),
                    ),
                  ),
                  Spacer(),
                  SizedBox(width: 22),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF111315),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2A2C2F)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search_rounded,
                      color: Color(0xFFD1A45C),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                          color: Color(0xFFF2E3C8),
                          fontSize: 13,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Search customer',
                          hintStyle: TextStyle(
                            color: Color(0xFF8F8A82),
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
                          child: const SizedBox(
                            width: 36,
                            height: 36,
                            child: Center(
                              child: Icon(
                                Icons.close_rounded,
                                color: Color(0xFFB9B1A5),
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
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final customer = filteredCustomers[index];
                          return _CustomerListTile(
                            customer: customer,
                            onTap: () => widget.onOpenCustomer(customer),
                            onLongPress: () => widget.onManageCustomer(customer),
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
    final hasCallablePhone =
        customer.phone.trim().isNotEmpty;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF121212), Color(0xFF090909)],
        ),
      ),
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
                            child: const Icon(
                              Icons.arrow_back_rounded,
                              color: Color(0xFFD1A45C),
                              size: 22,
                            ),
                          )
                        : const AppHamburgerMenu(),
                    const Spacer(),
                    const Text(
                      '\u03a0\u0395\u039b\u0391\u03a4\u0397\u03a3',
                      style: TextStyle(
                        fontSize: 13,
                        letterSpacing: .9,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFE9E1D2),
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
                              gradient: const RadialGradient(
                                colors: [Color(0xFF3C3023), Color(0xFF171717)],
                              ),
                              border: Border.all(
                                color: const Color(0xFF7E5F35),
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: customer.photoUrl.isNotEmpty
                                ? Image.network(
                                    customer.photoUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Icon(
                                        Icons.person_rounded,
                                        size: 82,
                                        color: Color(0xFFF2E3C8),
                                      );
                                    },
                                  )
                                : const Icon(
                                    Icons.person_rounded,
                                    size: 82,
                                    color: Color(0xFFF2E3C8),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          customer.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF5ECDD),
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
                            color: const Color(0xFF111111),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF242424)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.call_rounded,
                                size: 16,
                                color: Color(0xFFD1A45C),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  hasCallablePhone
                                      ? customer.phone
                                      : '\u0394\u03b5\u03bd \u03c5\u03c0\u03ac\u03c1\u03c7\u03b5\u03b9 \u03c4\u03b7\u03bb\u03ad\u03c6\u03c9\u03bd\u03bf',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFFD5CEC4),
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
                                            ? const Color(0xFF3A3127)
                                            : const Color(0xFF2A2A2A),
                                      ),
                                      color: hasCallablePhone
                                          ? const Color(0xFF171717)
                                          : const Color(0xFF121212),
                                    ),
                                    child: Icon(
                                      Icons.phone_forwarded_rounded,
                                      color: hasCallablePhone
                                          ? const Color(0xFFF0E5D1)
                                          : const Color(0xFF6D6D6D),
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
                              color: const Color(0xFF111111),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFF242424),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.alternate_email_rounded,
                                  size: 16,
                                  color: Color(0xFFD1A45C),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    customer.email,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFFD5CEC4),
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
                              ? const Text(
                                  '\u0394\u03b5\u03bd \u03c5\u03c0\u03ac\u03c1\u03c7\u03bf\u03c5\u03bd \u03b1\u03ba\u03cc\u03bc\u03b1 \u03c0\u03c1\u03bf\u03c4\u03b9\u03bc\u03ae\u03c3\u03b5\u03b9\u03c2.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFD0C7BB),
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
                                          const SizedBox(height: 8),
                                      itemBuilder: (context, index) {
                                        final item = customer.preferences[index];
                                        return Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF171717),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFF303030),
                                            ),
                                          ),
                                          child: Text(
                                            item,
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              height: 1.4,
                                              color: Color(0xFFE8E0D2),
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
                              ? const Text(
                                  '\u0394\u03b5\u03bd \u03c5\u03c0\u03ac\u03c1\u03c7\u03b5\u03b9 \u03b1\u03ba\u03cc\u03bc\u03b1 \u03b9\u03c3\u03c4\u03bf\u03c1\u03b9\u03ba\u03cc \u03c1\u03b1\u03bd\u03c4\u03b5\u03b2\u03bf\u03cd.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFD0C7BB),
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
                                            const SizedBox(height: 8),
                                        itemBuilder: (context, index) {
                                          final visit = customer.history[index];
                                          return Row(
                                            children: [
                                              Expanded(
                                                flex: 3,
                                                child: Text(
                                                  visit.date,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xFFE8E0D2),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                flex: 3,
                                                child: Text(
                                                  visit.service,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xFFD0C7BB),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                '\u20ac${visit.price}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Color(0xFFE8E0D2),
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
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: Color(0xFFD0C7BB),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF242424)),
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
                gradientColors: const [Color(0xFF3C3023), Color(0xFF171717)],
                borderColor: const Color(0xFF7E5F35),
                iconColor: const Color(0xFFF2E3C8),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF5ECDD),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    customer.phone,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFFB9B1A5),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFD1A45C),
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
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: const Text(
        '\u0394\u03b5\u03bd \u03c5\u03c0\u03ac\u03c1\u03c7\u03bf\u03c5\u03bd \u03b1\u03ba\u03cc\u03bc\u03b1 \u03c0\u03b5\u03bb\u03ac\u03c4\u03b5\u03c2 \u03c3\u03c4\u03b7 \u03bb\u03af\u03c3\u03c4\u03b1.',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Color(0xFFE8E0D2),
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
      padding: const EdgeInsets.all(14),
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
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE8E0D2),
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
  const _ProgramTopBar();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        AppHamburgerMenu(),
        Spacer(),
        Text(
          '\u0397\u039c\u0395\u03a1\u039f\u039b\u039f\u0393\u0399\u039f',
          style: TextStyle(
            fontSize: 13,
            letterSpacing: .9,
            fontWeight: FontWeight.w500,
            color: Color(0xFFE9E1D2),
          ),
        ),
        Spacer(),
        Icon(Icons.tune_rounded, color: Color(0xFFD1A45C), size: 21),
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
        color: const Color(0xFF111315),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2C2F)),
      ),
      child: Row(
        children: [
          _TouchIconButton(
            onTap: onPreviousDay,
            icon: Icons.chevron_left_rounded,
            color: const Color(0xFFF0E5D1),
            size: 22,
          ),
          const Spacer(),
          Text(
            greekDateLabel(selectedDate),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFFE9E1D2),
            ),
          ),
          const Spacer(),
          _TouchIconButton(
            onTap: onNextDay,
            icon: Icons.chevron_right_rounded,
            color: const Color(0xFFF0E5D1),
            size: 22,
          ),
          const SizedBox(width: 10),
          _TouchIconButton(
            onTap: onPickDate,
            icon: Icons.calendar_today_outlined,
            color: const Color(0xFFD1A45C),
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
    final barberName = entry.barberName.trim();
    final barberAccent = [
      const Color(0xFFB98A52),
      const Color(0xFF8F6A45),
      const Color(0xFF6E7E63),
    ][barberName.isEmpty ? 0 : barberName.hashCode.abs() % 3];
    final baseGradientColors = entry.highlighted
        ? const [Color(0xFF8C6738), Color(0xFF6F5534)]
        : const [Color(0xFFA88452), Color(0xFF87653A)];
    final cardGradientColors = barberName.isNotEmpty
        ? [
            Color.alphaBlend(
              barberAccent.withValues(alpha: 0.18),
              baseGradientColors[0],
            ),
            Color.alphaBlend(
              barberAccent.withValues(alpha: 0.10),
              baseGradientColors[1],
            ),
          ]
        : baseGradientColors;
    final isBlocked = entry.blocked;
    final baseBorderColor = entry.highlighted
        ? const Color(0xFF9E7A44)
        : const Color(0xFFC39A5D);
    final cardBorderColor = barberName.isNotEmpty
        ? Color.alphaBlend(
            barberAccent.withValues(alpha: 0.28),
            baseBorderColor,
          )
        : baseBorderColor;
    final statusTone = switch (entry.status) {
      'pending' => const Color(0xFFD1A45C),
      'confirmed' => const Color(0xFF7DB37D),
      'completed' => const Color(0xFF7AA6D1),
      'cancelled' => const Color(0xFFE08A7A),
      'no_show' => const Color(0xFFB08AE0),
      _ => const Color(0xFF7DB37D),
    };
    final statusLabel = switch (entry.status) {
      'pending' => 'Pending',
      'confirmed' => 'Confirmed',
      'completed' => 'Completed',
      'cancelled' => 'Cancelled',
      'no_show' => 'No-show',
      _ => 'Confirmed',
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 40,
          child: Text(
            entry.hour,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFE8E0D2),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: isBlocked ? null : onTap,
            onLongPress: onLongPress,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: cardGradientColors,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cardBorderColor),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CustomerAvatarBadge(
                      photoUrl: isBlocked ? '' : customerPhotoUrl,
                      size: 36,
                      placeholderIcon: Icons.person_rounded,
                      gradientColors: const [
                        Color(0xFF44311E),
                        Color(0xFF202020),
                      ],
                      borderColor: const Color(0xFFC49A5C),
                      iconColor: const Color(0xFFF0E5D1),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isBlocked ? 'Blocked slot' : entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusTone.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: statusTone.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: statusTone,
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
                            color: entry.highlighted
                                ? const Color(0xFFF2E3C8)
                                : const Color(0xFFF1DFC0),
                          ),
                        ),
                        if (barberName.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Barber: $barberName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.2,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFF6E9D1),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 38,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: entry.highlighted
                          ? const Color(0xFF705434)
                          : const Color(0xFF775634),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: entry.highlighted
                            ? const Color(0xFFBF955A)
                            : const Color(0xFFD6AD73),
                      ),
                    ),
                    child: Text(
                      entry.duration,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF5ECDD),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFE8E0D2),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Row(
            children: [
              Expanded(child: Divider(color: Color(0xFF494949), thickness: .7)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  '\u0394\u0399\u0391\u039b\u0395\u0399\u039c\u039c\u0391',
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: .8,
                    color: Color(0xFF787878),
                  ),
                ),
              ),
              Expanded(child: Divider(color: Color(0xFF494949), thickness: .7)),
            ],
          ),
        ),
      ],
    );
  }
}
