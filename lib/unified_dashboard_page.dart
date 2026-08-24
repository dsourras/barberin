part of 'main.dart';

class UnifiedDashboardAlert {
  const UnifiedDashboardAlert({
    required this.type,
    required this.title,
    required this.body,
    required this.severity,
    required this.shopId,
    required this.shopName,
  });

  final String type;
  final String title;
  final String body;
  final String severity;
  final String shopId;
  final String shopName;

  factory UnifiedDashboardAlert.fromJson(Map<String, dynamic> json) {
    return UnifiedDashboardAlert(
      type: '${json['type'] ?? ''}'.trim(),
      title: '${json['title'] ?? ''}'.trim(),
      body: '${json['body'] ?? ''}'.trim(),
      severity: '${json['severity'] ?? 'medium'}'.trim(),
      shopId: '${json['shopId'] ?? ''}'.trim(),
      shopName: '${json['shopName'] ?? ''}'.trim(),
    );
  }
}

class UnifiedDashboardShop {
  const UnifiedDashboardShop({
    required this.shopId,
    required this.shopName,
    required this.billingStatus,
    required this.totalAppointments,
    required this.completedAppointments,
    required this.pendingAppointments,
    required this.cancelledAppointments,
    required this.noShowAppointments,
    required this.estimatedRevenue,
    required this.actualRevenue,
    required this.occupancyPercent,
    required this.alerts,
  });

  final String shopId;
  final String shopName;
  final String billingStatus;
  final int totalAppointments;
  final int completedAppointments;
  final int pendingAppointments;
  final int cancelledAppointments;
  final int noShowAppointments;
  final int estimatedRevenue;
  final int actualRevenue;
  final int occupancyPercent;
  final List<UnifiedDashboardAlert> alerts;

  factory UnifiedDashboardShop.fromJson(Map<String, dynamic> json) {
    final rawAlerts = json['alerts'];
    return UnifiedDashboardShop(
      shopId: '${json['shopId'] ?? ''}'.trim(),
      shopName: '${json['shopName'] ?? ''}'.trim(),
      billingStatus: '${json['billingStatus'] ?? ''}'.trim(),
      totalAppointments: (json['totalAppointments'] as num?)?.toInt() ?? 0,
      completedAppointments:
          (json['completedAppointments'] as num?)?.toInt() ?? 0,
      pendingAppointments: (json['pendingAppointments'] as num?)?.toInt() ?? 0,
      cancelledAppointments:
          (json['cancelledAppointments'] as num?)?.toInt() ?? 0,
      noShowAppointments: (json['noShowAppointments'] as num?)?.toInt() ?? 0,
      estimatedRevenue: (json['estimatedRevenue'] as num?)?.toInt() ?? 0,
      actualRevenue: (json['actualRevenue'] as num?)?.toInt() ?? 0,
      occupancyPercent: (json['occupancyPercent'] as num?)?.toInt() ?? 0,
      alerts: rawAlerts is List
          ? rawAlerts
                .whereType<Map>()
                .map(
                  (item) => UnifiedDashboardAlert.fromJson(
                    item.cast<String, dynamic>(),
                  ),
                )
                .toList(growable: false)
          : const <UnifiedDashboardAlert>[],
    );
  }

  String get billingStatusLabel {
    switch (billingStatus) {
      case 'active':
      case 'grace_period':
        return 'Ενεργή';
      case 'trialing':
        return 'Σε δωρεάν δοκιμή';
      case 'expired':
      case 'canceled':
        return 'Έληξε';
      default:
        return 'Απαιτείται ρύθμιση';
    }
  }
}

class UnifiedDashboardSnapshot {
  const UnifiedDashboardSnapshot({
    required this.startDate,
    required this.endDate,
    required this.shopCount,
    required this.totalAppointments,
    required this.completedAppointments,
    required this.estimatedRevenue,
    required this.actualRevenue,
    required this.occupancyPercent,
    required this.alertCount,
    required this.shops,
    required this.alerts,
  });

  final String startDate;
  final String endDate;
  final int shopCount;
  final int totalAppointments;
  final int completedAppointments;
  final int estimatedRevenue;
  final int actualRevenue;
  final int occupancyPercent;
  final int alertCount;
  final List<UnifiedDashboardShop> shops;
  final List<UnifiedDashboardAlert> alerts;

  factory UnifiedDashboardSnapshot.fromJson(Map<String, dynamic> json) {
    final period = json['period'];
    final totals = json['totals'];
    final rawShops = json['shops'];
    final rawAlerts = json['alerts'];
    final periodMap = period is Map
        ? period.cast<String, dynamic>()
        : const <String, dynamic>{};
    final totalsMap = totals is Map
        ? totals.cast<String, dynamic>()
        : const <String, dynamic>{};
    return UnifiedDashboardSnapshot(
      startDate: '${periodMap['startDate'] ?? ''}'.trim(),
      endDate: '${periodMap['endDate'] ?? ''}'.trim(),
      shopCount: (totalsMap['shopCount'] as num?)?.toInt() ?? 0,
      totalAppointments: (totalsMap['totalAppointments'] as num?)?.toInt() ?? 0,
      completedAppointments:
          (totalsMap['completedAppointments'] as num?)?.toInt() ?? 0,
      estimatedRevenue: (totalsMap['estimatedRevenue'] as num?)?.toInt() ?? 0,
      actualRevenue: (totalsMap['actualRevenue'] as num?)?.toInt() ?? 0,
      occupancyPercent: (totalsMap['occupancyPercent'] as num?)?.toInt() ?? 0,
      alertCount: (totalsMap['alerts'] as num?)?.toInt() ?? 0,
      shops: rawShops is List
          ? rawShops
                .whereType<Map>()
                .map(
                  (item) => UnifiedDashboardShop.fromJson(
                    item.cast<String, dynamic>(),
                  ),
                )
                .toList(growable: false)
          : const <UnifiedDashboardShop>[],
      alerts: rawAlerts is List
          ? rawAlerts
                .whereType<Map>()
                .map(
                  (item) => UnifiedDashboardAlert.fromJson(
                    item.cast<String, dynamic>(),
                  ),
                )
                .toList(growable: false)
          : const <UnifiedDashboardAlert>[],
    );
  }
}

class UnifiedDashboardRepository {
  static const _endpoint =
      'https://europe-west1-barbero-88d00.cloudfunctions.net/barberoGetUnifiedDashboard';

  Future<UnifiedDashboardSnapshot> load() async {
    final now = athensDateOnly(athensNow());
    final start = DateTime(now.year, now.month, 1);
    final session = currentBarberoSession.value;
    if (isBarberinWindows) {
      if (session == null) {
        throw Exception('missing-unified-dashboard-session');
      }
      final decoded = await WindowsBackendAdapter.instance.loadReports(
        shopId: session.shopId,
        startDate: _unifiedDashboardDateKey(start),
        endDate: _unifiedDashboardDateKey(now),
      );
      return UnifiedDashboardSnapshot.fromJson(decoded);
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('missing-unified-dashboard-user');
    }
    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': await user.getIdToken(),
        'startDate': _unifiedDashboardDateKey(start),
        'endDate': _unifiedDashboardDateKey(now),
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('unified-dashboard-load-failed');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('invalid-unified-dashboard-response');
    }
    return UnifiedDashboardSnapshot.fromJson(decoded);
  }
}

String _unifiedDashboardDateKey(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class UnifiedDashboardPage extends StatefulWidget {
  const UnifiedDashboardPage({super.key});

  @override
  State<UnifiedDashboardPage> createState() => _UnifiedDashboardPageState();
}

class _UnifiedDashboardPageState extends State<UnifiedDashboardPage> {
  final UnifiedDashboardRepository _repository = UnifiedDashboardRepository();
  UnifiedDashboardSnapshot? _snapshot;
  Object? _error;
  bool _loading = true;
  bool _switchingShop = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final snapshot = await _repository.load();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _openShop(UnifiedDashboardShop shop) async {
    if (_switchingShop || shop.shopId.trim().isEmpty) return;
    if (shop.shopId == currentBarberoSession.value?.shopId) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _switchingShop = true);
    try {
      await switchBarberoActiveShop(shop.shopId);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _switchingShop = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Δεν ήταν δυνατή η αλλαγή καταστήματος αυτή τη στιγμή.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.barberinBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const AppHamburgerMenu(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ενιαίο dashboard',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            color: context.barberinTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Η συνολική εικόνα όλων των καταστημάτων σου',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: context.barberinTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Ανανέωση',
                    onPressed: _loading ? null : _load,
                    icon: Icon(
                      Icons.refresh_rounded,
                      color: context.barberinAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(child: _buildBody(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _snapshot == null) {
      return Center(
        child: CircularProgressIndicator(color: context.barberinAccent),
      );
    }
    if (_error != null && _snapshot == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 34,
              color: context.barberinTextSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              'Δεν ήταν δυνατή η φόρτωση των συνολικών στοιχείων.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.barberinTextPrimary),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Δοκιμή ξανά')),
          ],
        ),
      );
    }
    final snapshot = _snapshot!;
    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        Text(
          '${snapshot.startDate} έως ${snapshot.endDate}',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 0.8,
            color: context.barberinTextSecondary,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 650 ? 4 : 2;
            final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _UnifiedMetric(
                  width: width,
                  label: 'Ραντεβού',
                  value: '${snapshot.totalAppointments}',
                  icon: Icons.calendar_today_outlined,
                ),
                _UnifiedMetric(
                  width: width,
                  label: 'Έσοδα',
                  value: '€${snapshot.actualRevenue}',
                  icon: Icons.payments_outlined,
                ),
                _UnifiedMetric(
                  width: width,
                  label: 'Πληρότητα',
                  value: '${snapshot.occupancyPercent}%',
                  icon: Icons.donut_large_outlined,
                ),
                _UnifiedMetric(
                  width: width,
                  label: 'Alerts',
                  value: '${snapshot.alertCount}',
                  icon: Icons.warning_amber_outlined,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 26),
        _UnifiedSectionHeading(
          title: 'Καταστήματα',
          subtitle: 'Πάτησε ένα shop για να ανοίξεις τον χώρο εργασίας του.',
        ),
        const SizedBox(height: 8),
        ...snapshot.shops.map(
          (shop) => _UnifiedShopRow(
            shop: shop,
            disabled: _switchingShop,
            onTap: () => _openShop(shop),
          ),
        ),
        const SizedBox(height: 24),
        _UnifiedSectionHeading(
          title: 'Alerts',
          subtitle: snapshot.alerts.isEmpty
              ? 'Δεν υπάρχει κάτι που χρειάζεται άμεση προσοχή.'
              : 'Σημεία που χρειάζονται έλεγχο ανά κατάστημα.',
        ),
        const SizedBox(height: 8),
        if (snapshot.alerts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'Όλα είναι ήσυχα για την τρέχουσα περίοδο.',
              style: TextStyle(color: context.barberinTextSecondary),
            ),
          )
        else
          ...snapshot.alerts.map((alert) => _UnifiedAlertRow(alert: alert)),
      ],
    );
  }
}

class _UnifiedMetric extends StatelessWidget {
  const _UnifiedMetric({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 13),
        decoration: BoxDecoration(
          color: context.barberinSurface,
          border: Border.all(color: context.barberinBorder),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: context.barberinAccent),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.barberinTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: context.barberinTextPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnifiedSectionHeading extends StatelessWidget {
  const _UnifiedSectionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: context.barberinTextPrimary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: context.barberinTextSecondary),
        ),
      ],
    );
  }
}

class _UnifiedShopRow extends StatelessWidget {
  const _UnifiedShopRow({
    required this.shop,
    required this.disabled,
    required this.onTap,
  });

  final UnifiedDashboardShop shop;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: disabled ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
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
                      shop.shopName.isEmpty
                          ? 'Κατάστημα χωρίς όνομα'
                          : shop.shopName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.barberinTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${shop.totalAppointments} ραντεβού  •  ${shop.occupancyPercent}% πληρότητα  •  ${shop.billingStatusLabel}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.barberinTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '€${shop.actualRevenue}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.barberinTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: context.barberinAccent,
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

class _UnifiedAlertRow extends StatelessWidget {
  const _UnifiedAlertRow({required this.alert});

  final UnifiedDashboardAlert alert;

  @override
  Widget build(BuildContext context) {
    final color = switch (alert.severity) {
      'high' => const Color(0xFFB45D5D),
      'low' => context.barberinTextSecondary,
      _ => context.barberinAccent,
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.barberinBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(Icons.circle, size: 8, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${alert.shopName}  •  ${alert.title}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.barberinTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  alert.body,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: context.barberinTextSecondary,
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
