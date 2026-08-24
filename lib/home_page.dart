part of 'main.dart';

class BarberHomePage extends StatelessWidget {
  const BarberHomePage({
    super.key,
    required this.onOpenSchedule,
    required this.onOpenProgram,
    required this.onQuickAdd,
    required this.onOpenNotifications,
    required this.selectedDate,
    required this.ownerFirstName,
    required this.shopName,
    required this.appointments,
    required this.customerPhotoUrlForAppointment,
    required this.onOpenCustomer,
    required this.onManageAppointment,
    required this.onQuickAddForSlot,
  });

  final VoidCallback onOpenSchedule;
  final VoidCallback onOpenProgram;
  final VoidCallback onQuickAdd;
  final VoidCallback onOpenNotifications;
  final DateTime selectedDate;
  final String ownerFirstName;
  final String shopName;
  final List<Appointment> appointments;
  final String Function(Appointment appointment) customerPhotoUrlForAppointment;
  final ValueChanged<Appointment> onOpenCustomer;
  final ValueChanged<Appointment> onManageAppointment;
  final ValueChanged<Appointment> onQuickAddForSlot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bookedAppointments = appointments
        .where((appointment) => appointment.isBooked)
        .toList();
    final totalRevenue = bookedAppointments.fold<int>(
      0,
      (sum, item) => sum + item.price,
    );
    final currentWeek = _homeWeekSnapshot(
      selectedDate: selectedDate,
      appointments: appointments,
    );
    final previousWeek = _homeWeekSnapshot(
      selectedDate: selectedDate.subtract(const Duration(days: 7)),
      appointments: appointments,
    );

    return Container(
      color: scheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HomeTopBar(
                selectedDate: selectedDate,
                ownerFirstName: ownerFirstName,
                shopName: shopName,
                onOpenProgram: onOpenProgram,
                onOpenNotifications: onOpenNotifications,
              ),
              const SizedBox(height: 18),
              Text(
                'ΕΠΙΣΚΟΠΗΣΗ',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  color: context.barberinTextSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: HomeStatCard(
                      value: '€$totalRevenue',
                      caption: 'Έσοδα',
                      icon: Icons.payments_outlined,
                      delta: _homePercentDelta(
                        currentWeek.revenue,
                        previousWeek.revenue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: HomeStatCard(
                      value: '${currentWeek.appointments}',
                      caption: 'Ραντεβού',
                      icon: Icons.calendar_month_outlined,
                      delta: _homePercentDelta(
                        currentWeek.appointments,
                        previousWeek.appointments,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: HomeStatCard(
                      value: '${currentWeek.newClients}',
                      caption: 'Νέοι πελάτες',
                      icon: Icons.person_add_alt_1_outlined,
                      delta: _homePercentDelta(
                        currentWeek.newClients,
                        previousWeek.newClients,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: HomeStatCard(
                      value: '${currentWeek.rebookRate.round()}%',
                      caption: 'Επιστροφές',
                      icon: Icons.refresh_rounded,
                      delta: _homePercentDelta(
                        currentWeek.rebookRate.round(),
                        previousWeek.rebookRate.round(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'ΕΠΟΜΕΝΑ ΡΑΝΤΕΒΟΥ',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        color: context.barberinTextSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ManualAppointmentAction(onPressed: onQuickAdd),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    if (appointments.isEmpty)
                      const _EmptyDayCard()
                    else
                      ...appointments.map(
                        (appointment) => AppointmentCard(
                          appointment: appointment,
                          customerPhotoUrl: customerPhotoUrlForAppointment(
                            appointment,
                          ),
                          onTap: () {
                            if (appointment.isBooked) {
                              onManageAppointment(appointment);
                              return;
                            }
                            onQuickAddForSlot(appointment);
                          },
                          onLongPress: appointment.isBooked
                              ? () => onOpenCustomer(appointment)
                              : null,
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

class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar({
    required this.selectedDate,
    required this.ownerFirstName,
    required this.shopName,
    required this.onOpenProgram,
    required this.onOpenNotifications,
  });

  final DateTime selectedDate;
  final String ownerFirstName;
  final String shopName;
  final VoidCallback onOpenProgram;
  final VoidCallback onOpenNotifications;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final greetingName = ownerFirstName.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const AppHamburgerMenu(),
            const SizedBox(width: 8),
            const BrandWordmark(width: 124),
            const Spacer(),
            ValueListenableBuilder<List<BarberoNotificationItem>>(
              valueListenable: barberoNotifications,
              builder: (context, notifications, child) {
                final unreadCount = notifications
                    .where((item) => !item.read)
                    .length;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: onOpenNotifications,
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Center(
                            child: Icon(
                              Icons.notifications_none_rounded,
                              color: scheme.onSurface,
                              size: 20,
                            ),
                          ),
                          if (unreadCount > 0)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: scheme.surface,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${greekGreeting(athensNow())}${greetingName.isEmpty ? '' : ', $greetingName'}',
          style: TextStyle(fontSize: 12, color: context.barberinTextSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          'Αυτά συμβαίνουν σήμερα στο',
          style: TextStyle(fontSize: 11, color: context.barberinTextSecondary),
        ),
        const SizedBox(height: 2),
        GestureDetector(
          onTap: onOpenProgram,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  shopName,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: context.barberinTextPrimary,
                  ),
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
        const SizedBox(height: 2),
        Text(
          barberinDateLabel(selectedDate),
          style: TextStyle(fontSize: 11, color: context.barberinTextSecondary),
        ),
      ],
    );
  }
}

class HomeStatCard extends StatelessWidget {
  const HomeStatCard({
    super.key,
    required this.value,
    required this.caption,
    this.icon,
    this.delta = '',
  });

  final String value;
  final String caption;
  final IconData? icon;
  final String delta;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final displayValue = value.replaceFirst('\u03b2\u201a\u00ac', 'EUR ');
    return Container(
      height: 116,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(9, 9, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon ?? Icons.insights_outlined,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 5),
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w500,
                color: context.barberinTextSecondary,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  displayValue,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.barberinTextPrimary,
                  ),
                ),
              ),
            ),
            if (delta.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                delta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: delta.startsWith('-')
                      ? const Color(0xFFB45353)
                      : const Color(0xFF3F8F5B),
                ),
              ),
              Text(
                'σε σχέση με την προηγούμενη εβδομάδα',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 8,
                  color: context.barberinTextSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HomeWeekSnapshot {
  const _HomeWeekSnapshot({
    required this.revenue,
    required this.appointments,
    required this.newClients,
    required this.rebookRate,
  });

  final int revenue;
  final int appointments;
  final int newClients;
  final double rebookRate;
}

_HomeWeekSnapshot _homeWeekSnapshot({
  required DateTime selectedDate,
  required List<Appointment> appointments,
}) {
  final start = DateTime(
    selectedDate.year,
    selectedDate.month,
    selectedDate.day,
  ).subtract(const Duration(days: 6));
  final end = start.add(const Duration(days: 7));
  final weekAppointments = appointments
      .where((appointment) {
        final date = DateTime.tryParse(appointment.date.trim());
        return date != null &&
            !appointment.isBlocked &&
            !appointment.isCancelled &&
            !appointment.isNoShow &&
            !date.isBefore(start) &&
            date.isBefore(end);
      })
      .toList(growable: false);
  final firstVisitByCustomer = <String, DateTime>{};
  for (final appointment in appointments) {
    final date = DateTime.tryParse(appointment.date.trim());
    final key = _homeCustomerKey(appointment);
    if (date == null || key.isEmpty) continue;
    final firstVisit = firstVisitByCustomer[key];
    if (firstVisit == null || date.isBefore(firstVisit)) {
      firstVisitByCustomer[key] = date;
    }
  }
  final newClients = firstVisitByCustomer.values
      .where((date) => !date.isBefore(start) && date.isBefore(end))
      .length;
  final completed = weekAppointments
      .where((appointment) => appointment.isCompleted)
      .length;
  return _HomeWeekSnapshot(
    revenue: weekAppointments.fold(0, (sum, item) => sum + item.price),
    appointments: weekAppointments.length,
    newClients: newClients,
    rebookRate: weekAppointments.isEmpty
        ? 0
        : completed / weekAppointments.length * 100,
  );
}

String _homeCustomerKey(Appointment appointment) {
  final uid = appointment.customerUid.trim();
  if (uid.isNotEmpty) return 'uid:$uid';
  final email = appointment.customerEmail.trim().toLowerCase();
  if (email.isNotEmpty) return 'email:$email';
  final phone = appointment.customerPhone.trim();
  if (phone.isNotEmpty) return 'phone:$phone';
  final name = appointment.name.trim().toLowerCase();
  return name.isEmpty ? '' : 'name:$name';
}

String _homePercentDelta(num current, num previous) {
  if (previous == 0) return current == 0 ? '0%' : '+100%';
  final percent = ((current - previous) / previous * 100).round();
  return '${percent >= 0 ? '+' : ''}$percent%';
}

String _homeAppointmentDateLabel(String rawDate) {
  final date = DateTime.tryParse(rawDate.trim());
  if (date == null) return rawDate.trim();
  return barberinDateLabel(date);
}

class AppointmentCard extends StatelessWidget {
  const AppointmentCard({
    super.key,
    required this.appointment,
    this.customerPhotoUrl = '',
    this.onTap,
    this.onLongPress,
  });

  final Appointment appointment;
  final String customerPhotoUrl;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final isLight = context.barberinIsLight;
    final isBooked = appointment.isBooked;
    final barberName = appointment.barberName.trim();
    final isMultiService =
        isBooked &&
        (appointment.service.contains('&') ||
            appointment.service.contains('+'));
    final isSingleServiceBooked = isBooked && !isMultiService;
    final statusTone = barberinAppointmentTone(
      appointment.status,
      isAvailable: !isBooked,
    );
    final statusForeground = barberinAppointmentForeground(
      appointment.status,
      isAvailable: !isBooked,
    );
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
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
                width: 64,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      appointment.time,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isLight
                            ? context.barberinTextPrimary
                            : isBooked
                            ? const Color(0xFFF1E8D8)
                            : const Color(0xFFD2D7DE),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _homeAppointmentDateLabel(appointment.date),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: isLight
                            ? context.barberinTextSecondary
                            : isBooked
                            ? const Color(0xFFDCCDB8)
                            : const Color(0xFF9BA2AB),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusForeground,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CustomerAvatarBadge(
                photoUrl: customerPhotoUrl,
                size: 42,
                placeholderIcon: isBooked
                    ? Icons.person_outline_rounded
                    : Icons.schedule_rounded,
                gradientColors: isLight
                    ? [
                        statusTone.withValues(alpha: 0.16),
                        context.barberinSurfaceAlt,
                      ]
                    : isMultiService
                    ? const [Color(0xFF44311E), Color(0xFF202020)]
                    : isSingleServiceBooked
                    ? const [Color(0xFF5B4326), Color(0xFF2B2115)]
                    : const [Color(0xFF25292E), Color(0xFF15181B)],
                borderColor: isLight
                    ? statusForeground.withValues(alpha: 0.38)
                    : isMultiService
                    ? const Color(0xFFC49A5C)
                    : isSingleServiceBooked
                    ? const Color(0xFFD0A86A)
                    : const Color(0xFF3B4046),
                iconColor: isLight
                    ? statusForeground
                    : isMultiService
                    ? const Color(0xFFF0E5D1)
                    : isSingleServiceBooked
                    ? const Color(0xFFF8EBD4)
                    : const Color(0xFF8E959E),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      appointment.name,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: isLight
                            ? context.barberinTextPrimary
                            : isBooked
                            ? const Color(0xFFF5ECDD)
                            : const Color(0xFFD8DCE2),
                      ),
                    ),
                    if (isBooked) ...[
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
                          appointment.statusLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: statusForeground,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      appointment.service,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isLight
                            ? context.barberinTextSecondary
                            : isMultiService
                            ? const Color(0xFFF2E3C8)
                            : isSingleServiceBooked
                            ? const Color(0xFFF1DFC0)
                            : const Color(0xFF7F8790),
                      ),
                    ),
                    if (isBooked && barberName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'barber: $barberName',
                        style: TextStyle(
                          fontSize: 10.2,
                          fontWeight: FontWeight.w600,
                          color: isLight
                              ? context.barberinTextSecondary
                              : isMultiService || isSingleServiceBooked
                              ? const Color(0xFFF6E9D1)
                              : const Color(0xFFD7D0C6),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: isLight
                      ? statusTone.withValues(alpha: 0.12)
                      : isMultiService
                      ? statusTone.withValues(alpha: 0.16)
                      : statusTone.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isLight
                        ? statusForeground.withValues(alpha: 0.5)
                        : statusForeground.withValues(alpha: 0.48),
                  ),
                ),
                child: Text(
                  appointment.duration,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: isLight
                        ? context.barberinTextPrimary
                        : isBooked
                        ? const Color(0xFFE6DED1)
                        : const Color(0xFFC4CBD2),
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

class CustomerAvatarBadge extends StatelessWidget {
  const CustomerAvatarBadge({
    super.key,
    required this.photoUrl,
    required this.size,
    required this.placeholderIcon,
    required this.gradientColors,
    required this.borderColor,
    required this.iconColor,
  });

  final String photoUrl;
  final double size;
  final IconData placeholderIcon;
  final List<Color> gradientColors;
  final Color borderColor;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final normalizedPhotoUrl = photoUrl.trim();
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: gradientColors),
        border: Border.all(color: borderColor),
      ),
      child: normalizedPhotoUrl.isNotEmpty
          ? Image.network(
              normalizedPhotoUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  placeholderIcon,
                  color: iconColor,
                  size: size * 0.42,
                );
              },
            )
          : Icon(placeholderIcon, color: iconColor, size: size * 0.42),
    );
  }
}

class _EmptyDayCard extends StatelessWidget {
  const _EmptyDayCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Δεν υπάρχουν προγραμματισμένα ραντεβού για σήμερα.',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Ένα νέο ραντεβού θα εμφανιστεί εδώ μόλις καταχωριστεί.',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class AvailabilityPanel extends StatelessWidget {
  const AvailabilityPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.surfaceContainerHighest, scheme.surface],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '\u0395\u03b2\u03b4\u03bf\u03bc\u03b1\u03b4\u03b9\u03b1\u03af\u03bf \u03bc\u03bf\u03c4\u03af\u03b2\u03bf \u03bb\u03b5\u03b9\u03c4\u03bf\u03c5\u03c1\u03b3\u03af\u03b1\u03c2',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          SizedBox(height: 10),
          AvailabilityRow(
            day:
                '\u0394\u03b5\u03c5\u03c4\u03ad\u03c1\u03b1 - \u03a0\u03b1\u03c1\u03b1\u03c3\u03ba\u03b5\u03c5\u03ae',
            time: '09:00 - 19:00',
          ),
          SizedBox(height: 8),
          AvailabilityRow(
            day: '\u03a3\u03ac\u03b2\u03b2\u03b1\u03c4\u03bf',
            time: '10:00 - 16:00',
          ),
          SizedBox(height: 8),
          AvailabilityRow(
            day: 'barber',
            time: '\u0395\u03c3\u03cd, \u039c\u03ac\u03c1\u03b9\u03bf\u03c2',
          ),
        ],
      ),
    );
  }
}

class AvailabilityRow extends StatelessWidget {
  const AvailabilityRow({super.key, required this.day, required this.time});

  final String day;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            day,
            style: TextStyle(
              fontSize: 10.5,
              color: context.barberinTextSecondary,
            ),
          ),
        ),
        Text(
          time,
          style: TextStyle(
            fontSize: 10.5,
            color: context.barberinAccent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
