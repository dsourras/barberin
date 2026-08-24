part of 'main.dart';

class BarberoNotificationsPage extends StatefulWidget {
  const BarberoNotificationsPage({super.key, this.onOpenAppointment});

  final ValueChanged<BarberoNotificationItem>? onOpenAppointment;

  @override
  State<BarberoNotificationsPage> createState() =>
      _BarberoNotificationsPageState();
}

class _BarberoNotificationsPageState extends State<BarberoNotificationsPage> {
  @override
  void initState() {
    super.initState();
    unawaited(_markAllBarberoNotificationsRead());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.barberinBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.of(context).maybePop(),
                      child: SizedBox(
                        width: 46,
                        height: 46,
                        child: Center(
                          child: Icon(
                            Icons.arrow_back_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Ειδοποιήσεις',
                      style: TextStyle(
                        color: context.barberinTextPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ValueListenableBuilder<List<BarberoNotificationItem>>(
                  valueListenable: barberoNotifications,
                  builder: (context, notifications, child) {
                    if (notifications.isEmpty) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: context.barberinSurface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: context.barberinBorder),
                        ),
                        child: Text(
                          'Δεν υπάρχουν ειδοποιήσεις ακόμη.',
                          style: TextStyle(
                            color: context.barberinTextSecondary,
                            fontSize: 13,
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      itemCount: notifications.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 0),
                      itemBuilder: (context, index) {
                        final item = notifications[index];
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: item.appointmentId.isEmpty
                                ? null
                                : () => widget.onOpenAppointment?.call(item),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: context.barberinBorder,
                                  ),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: item.read
                                            ? Colors.transparent
                                            : Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.title,
                                          style: TextStyle(
                                            color: context.barberinTextPrimary,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (item.body.trim().isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            item.body,
                                            style: TextStyle(
                                              color:
                                                  context.barberinTextSecondary,
                                              fontSize: 12.5,
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                        if (item.appointmentId.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            '\u03a0\u03ac\u03c4\u03b7\u03c3\u03b5 \u03b3\u03b9\u03b1 \u03bd\u03b1 \u03b1\u03bd\u03bf\u03af\u03be\u03b5\u03b9\u03c2 \u03c4\u03bf \u03c1\u03b1\u03bd\u03c4\u03b5\u03b2\u03bf\u03cd',
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    _barberoNotificationDateLabel(
                                      item.receivedAt,
                                    ),
                                    style: TextStyle(
                                      color: context.barberinTextSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
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

String _barberoNotificationDateLabel(DateTime value) {
  final now = DateTime.now();
  final local = value.toLocal();
  final sameDay =
      now.year == local.year &&
      now.month == local.month &&
      now.day == local.day;
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  if (sameDay) {
    return barberinUsesEnglish
        ? 'Today, $hour:$minute'
        : 'Σήμερα, $hour:$minute';
  }
  return '${barberinDateLabel(local)}, $hour:$minute';
}
