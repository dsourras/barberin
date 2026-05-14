part of 'main.dart';

class BarberoNotificationsPage extends StatefulWidget {
  const BarberoNotificationsPage({super.key});

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
      backgroundColor: const Color(0xFF090909),
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
                      child: const SizedBox(
                        width: 46,
                        height: 46,
                        child: Center(
                          child: Icon(
                            Icons.arrow_back_rounded,
                            color: Color(0xFFD1A45C),
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Notifications',
                      style: TextStyle(
                        color: Color(0xFFF3E7D3),
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
                          color: const Color(0xFF111111),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFF242424)),
                        ),
                        child: const Text(
                          'No notifications yet.',
                          style: TextStyle(
                            color: Color(0xFFBFB7AA),
                            fontSize: 13,
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      itemCount: notifications.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = notifications[index];
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: item.read
                                ? const Color(0xFF111111)
                                : const Color(0xFF18120B),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: item.read
                                  ? const Color(0xFF242424)
                                  : const Color(0xFF5B4326),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.title,
                                      style: const TextStyle(
                                        color: Color(0xFFF3E7D3),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    _barberoNotificationDateLabel(
                                      item.receivedAt,
                                    ),
                                    style: const TextStyle(
                                      color: Color(0xFF9E9588),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              if (item.body.trim().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  item.body,
                                  style: const TextStyle(
                                    color: Color(0xFFD7CCBC),
                                    fontSize: 12.5,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ],
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
    return '$hour:$minute';
  }
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month $hour:$minute';
}
