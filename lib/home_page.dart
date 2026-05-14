part of 'main.dart';

class BarberHomePage extends StatelessWidget {
  const BarberHomePage({
    super.key,
    required this.onOpenSchedule,
    required this.onOpenProgram,
    required this.onOpenNotifications,
    required this.currentAthensTime,
    required this.selectedDate,
    required this.ownerFirstName,
    required this.appointments,
    required this.customerPhotoUrlForAppointment,
    required this.onOpenCustomer,
    required this.onManageAppointment,
    required this.onQuickAddForSlot,
  });

  final VoidCallback onOpenSchedule;
  final VoidCallback onOpenProgram;
  final VoidCallback onOpenNotifications;
  final DateTime currentAthensTime;
  final DateTime selectedDate;
  final String ownerFirstName;
  final List<Appointment> appointments;
  final String Function(Appointment appointment) customerPhotoUrlForAppointment;
  final ValueChanged<Appointment> onOpenCustomer;
  final ValueChanged<Appointment> onManageAppointment;
  final ValueChanged<Appointment> onQuickAddForSlot;

  @override
  Widget build(BuildContext context) {
    final bookedAppointments = appointments
        .where((appointment) => appointment.isBooked)
        .toList();
    final appointmentCount = bookedAppointments.length;
    final totalMinutes = bookedAppointments.fold<int>(
      0,
      (sum, item) => sum + item.minutes,
    );
    final totalRevenue = bookedAppointments.fold<int>(
      0,
      (sum, item) => sum + item.price,
    );

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
              _HomeTopBar(
                currentAthensTime: currentAthensTime,
                selectedDate: selectedDate,
                ownerFirstName: ownerFirstName,
                onOpenProgram: onOpenProgram,
                onOpenNotifications: onOpenNotifications,
              ),
              const SizedBox(height: 18),
              const Text(
                '\u03a3\u0397\u039c\u0395\u03a1\u0391',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: Color(0xFFDADADA),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: HomeStatCard(
                      value: '$appointmentCount',
                      caption:
                          '\u03a1\u0391\u039d\u03a4\u0395\u0392\u039f\u03a5',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: HomeStatCard(
                      value:
                          '${(totalMinutes / 60).toStringAsFixed(totalMinutes % 60 == 0 ? 0 : 1)}h',
                      caption:
                          '\u03a3\u03a5\u039d\u039f\u039b\u0399\u039a\u0395\u03a3 \u03a9\u03a1\u0395\u03a3',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: HomeStatCard(
                      value: '\u20AC$totalRevenue',
                      caption:
                          '\u0395\u039a\u03a4\u0399\u039c\u03a9\u039c\u0395\u039d\u0391 \u0395\u03a3\u039f\u0394\u0391',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                '\u0395\u03a0\u039f\u039c\u0395\u039d\u0391 \u03a1\u0391\u039d\u03a4\u0395\u0392\u039f\u03a5',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: Color(0xFFDADADA),
                  fontWeight: FontWeight.w600,
                ),
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
                        (appointment) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: AppointmentCard(
                            appointment: appointment,
                            customerPhotoUrl:
                                customerPhotoUrlForAppointment(appointment),
                            onTap: appointment.isBooked
                                ? () => onOpenCustomer(appointment)
                                : null,
                            onLongPress: () {
                              if (appointment.isBooked) {
                                onManageAppointment(appointment);
                                return;
                              }
                              onQuickAddForSlot(appointment);
                            },
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
    );
  }
}

class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar({
    required this.currentAthensTime,
    required this.selectedDate,
    required this.ownerFirstName,
    required this.onOpenProgram,
    required this.onOpenNotifications,
  });

  final DateTime currentAthensTime;
  final DateTime selectedDate;
  final String ownerFirstName;
  final VoidCallback onOpenProgram;
  final VoidCallback onOpenNotifications;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppHamburgerMenu(),
        const SizedBox(width: 14),
        Expanded(
          child: GestureDetector(
            onTap: onOpenProgram,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${greekGreeting(currentAthensTime)}, $ownerFirstName',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFF5ECDD),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  greekDateLabel(selectedDate),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF969696),
                  ),
                ),
              ],
            ),
          ),
        ),
        ValueListenableBuilder<List<BarberoNotificationItem>>(
          valueListenable: barberoNotifications,
          builder: (context, notifications, child) {
            final unreadCount =
                notifications.where((item) => !item.read).length;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onOpenNotifications,
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Center(
                        child: Icon(
                          Icons.notifications_none_rounded,
                          color: Color(0xFFD1A45C),
                          size: 20,
                        ),
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD1A45C),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            constraints: const BoxConstraints(minWidth: 18),
                            child: Text(
                              unreadCount > 9 ? '9+' : '$unreadCount',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF111111),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
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
    );
  }
}

class HomeStatCard extends StatelessWidget {
  const HomeStatCard({super.key, required this.value, required this.caption});

  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1C1A18), Color(0xFF131313)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3127)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFFF2E3C8),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              caption,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 8.5,
                color: Color(0xFFC7B18A),
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
    final isBooked = appointment.isBooked;
    final barberName = appointment.barberName.trim();
    final barberAccent = [
      const Color(0xFFB98A52),
      const Color(0xFF8F6A45),
      const Color(0xFF6E7E63),
    ][barberName.isEmpty ? 0 : barberName.hashCode.abs() % 3];
    final isMultiService =
        isBooked &&
        (appointment.service.contains('&') ||
            appointment.service.contains('+'));
    final isSingleServiceBooked = isBooked && !isMultiService;
    final baseGradientColors = isMultiService
        ? const [Color(0xFF8C6738), Color(0xFF6F5534)]
        : isSingleServiceBooked
        ? const [Color(0xFFA88452), Color(0xFF87653A)]
        : const [Color(0xFF101113), Color(0xFF101113)];
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
    final baseBorderColor = isMultiService
        ? const Color(0xFF9E7A44)
        : isSingleServiceBooked
        ? const Color(0xFFC39A5D)
        : const Color(0xFF2E3135);
    final cardBorderColor = barberName.isNotEmpty
        ? Color.alphaBlend(
            barberAccent.withValues(alpha: 0.28),
            baseBorderColor,
          )
        : baseBorderColor;
    final statusTone = switch (appointment.status) {
      'pending' => const Color(0xFFD1A45C),
      'confirmed' => const Color(0xFF7DB37D),
      'completed' => const Color(0xFF7AA6D1),
      'cancelled' => const Color(0xFFE08A7A),
      'no_show' => const Color(0xFFB08AE0),
      _ => const Color(0xFF7DB37D),
    };
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: cardGradientColors,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cardBorderColor),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 14,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 42,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    appointment.time,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isBooked
                          ? const Color(0xFFF1E8D8)
                          : const Color(0xFFD2D7DE),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isBooked
                          ? const Color(0xFF618C52)
                          : const Color(0xFF4A4F55),
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
              gradientColors: isMultiService
                  ? const [Color(0xFF44311E), Color(0xFF202020)]
                  : isSingleServiceBooked
                  ? const [Color(0xFF5B4326), Color(0xFF2B2115)]
                  : const [Color(0xFF25292E), Color(0xFF15181B)],
              borderColor: isMultiService
                  ? const Color(0xFFC49A5C)
                  : isSingleServiceBooked
                  ? const Color(0xFFD0A86A)
                  : const Color(0xFF3B4046),
              iconColor: isMultiService
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
                      color: isBooked
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
                        color: statusTone.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: statusTone.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Text(
                        appointment.statusLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: statusTone,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    appointment.service,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isMultiService
                          ? const Color(0xFFF2E3C8)
                          : isSingleServiceBooked
                          ? const Color(0xFFF1DFC0)
                          : const Color(0xFF7F8790),
                    ),
                  ),
                  if (isBooked && barberName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Barber: $barberName',
                      style: TextStyle(
                        fontSize: 10.2,
                        fontWeight: FontWeight.w600,
                        color: isMultiService || isSingleServiceBooked
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
                color: isMultiService
                    ? const Color(0xFF705434)
                    : isSingleServiceBooked
                    ? const Color(0xFF775634)
                    : const Color(0xFF181B1F),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isMultiService
                      ? const Color(0xFFBF955A)
                      : isSingleServiceBooked
                      ? const Color(0xFFD6AD73)
                      : const Color(0xFF3A3F45),
                ),
              ),
              child: Text(
                appointment.duration,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: isBooked
                      ? const Color(0xFFE6DED1)
                      : const Color(0xFFC4CBD2),
                ),
              ),
            ),
          ],
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
          : Icon(
              placeholderIcon,
              color: iconColor,
              size: size * 0.42,
            ),
    );
  }
}

class _EmptyDayCard extends StatelessWidget {
  const _EmptyDayCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '\u0394\u03b5\u03bd \u03c5\u03c0\u03ac\u03c1\u03c7\u03bf\u03c5\u03bd \u03c0\u03c1\u03bf\u03b3\u03c1\u03b1\u03bc\u03bc\u03b1\u03c4\u03b9\u03c3\u03bc\u03ad\u03bd\u03b1 \u03c1\u03b1\u03bd\u03c4\u03b5\u03b2\u03bf\u03cd \u03b3\u03b9\u03b1 \u03c4\u03b7\u03bd \u03c4\u03c1\u03ad\u03c7\u03bf\u03c5\u03c3\u03b1 \u03b7\u03bc\u03ad\u03c1\u03b1.',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFFF5ECDD),
            ),
          ),
          SizedBox(height: 6),
          Text(
            '\u0388\u03bd\u03b1 \u03bd\u03ad\u03bf \u03c1\u03b1\u03bd\u03c4\u03b5\u03b2\u03bf\u03cd \u03b8\u03b1 \u03b5\u03bc\u03c6\u03b1\u03bd\u03b9\u03c3\u03c4\u03b5\u03af \u03b5\u03b4\u03ce \u03bc\u03cc\u03bb\u03b9\u03c2 \u03c0\u03c1\u03bf\u03c3\u03c4\u03b5\u03b8\u03b5\u03af \u03ba\u03ac\u03c0\u03bf\u03b9\u03b1 \u03bd\u03ad\u03b1 \u03ba\u03c1\u03ac\u03c4\u03b7\u03c3\u03b7.',
            style: TextStyle(fontSize: 11, color: Color(0xFF8F8F8F)),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF171614), Color(0xFF111111)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2F2A22)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '\u0395\u03b2\u03b4\u03bf\u03bc\u03b1\u03b4\u03b9\u03b1\u03af\u03bf \u03bc\u03bf\u03c4\u03af\u03b2\u03bf \u03bb\u03b5\u03b9\u03c4\u03bf\u03c5\u03c1\u03b3\u03af\u03b1\u03c2',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFFF2E3C8),
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
            day: 'Barbers',
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
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF9F9F9F)),
          ),
        ),
        Text(
          time,
          style: const TextStyle(
            fontSize: 10.5,
            color: Color(0xFFD6B179),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
