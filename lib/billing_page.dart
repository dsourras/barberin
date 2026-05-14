part of 'main.dart';

class BarberoSubscriptionGatePage extends StatefulWidget {
  const BarberoSubscriptionGatePage({
    super.key,
    required this.session,
    required this.billing,
  });

  final BarberoSession session;
  final BarberoBillingSnapshot billing;

  @override
  State<BarberoSubscriptionGatePage> createState() =>
      _BarberoSubscriptionGatePageState();
}

class _BarberoSubscriptionGatePageState
    extends State<BarberoSubscriptionGatePage> {
  final BillingRepository _billingRepository = BillingRepository();
  final BarberoStoreBillingService _storeBilling =
      BarberoStoreBillingService.instance;
  late BarberoBillingPlan _selectedPlan;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedPlan = widget.billing.selectedPlan;
  }

  @override
  void didUpdateWidget(covariant BarberoSubscriptionGatePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.billing.selectedPlan != widget.billing.selectedPlan &&
        !_isSubmitting) {
      _selectedPlan = widget.billing.selectedPlan;
    }
  }

  Future<void> _purchaseSelectedPlan() async {
    setState(() => _isSubmitting = true);
    try {
      await _billingRepository.savePlan(_selectedPlan);
      await _storeBilling.purchasePlan(_selectedPlan);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complete the purchase in the store sheet.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the store purchase flow.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _isSubmitting = true);
    try {
      await _storeBilling.restorePurchases();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Checking existing store purchases...')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to restore store purchases.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _startTrial() async {
    setState(() => _isSubmitting = true);
    try {
      final billing = await _billingRepository.startTrial(_selectedPlan);
      currentBarberoBilling.value = billing;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your 1-month free trial is now active.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to start the free trial.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final billing = currentBarberoBilling.value ?? widget.billing;
    final isOwner = widget.session.isOwner;
    final actionLabel =
        billing.requiresPlanSelection
            ? 'Start 1-month free trial'
            : 'Activate selected plan';
    final title =
        billing.requiresPlanSelection
            ? 'Choose your subscription'
            : 'Subscription required';
    final subtitle =
        isOwner
            ? billing.requiresPlanSelection
                ? 'Your shop will start with a 1-month free trial, then renew on the selected plan.'
                : 'The workspace is locked until an active subscription is available for this shop.'
            : 'This shop is temporarily locked until the owner completes the subscription setup.';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Barbero',
                    style: TextStyle(
                      color: Color(0xFFD1A45C),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFFF3E7D2),
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFFB8AF9E),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _BillingStatusCard(
                    billing: billing,
                    showTrialSummary: true,
                  ),
                  const SizedBox(height: 18),
                  ValueListenableBuilder<List<BarberoStoreProductOffer>>(
                    valueListenable: _storeBilling.offers,
                    builder: (context, offers, _) {
                      final monthlyOffer = _storeBilling.offerForPlan(
                        BarberoBillingPlan.monthly,
                      );
                      final yearlyOffer = _storeBilling.offerForPlan(
                        BarberoBillingPlan.yearly,
                      );
                      return Column(
                        children: [
                          _BillingPlanCard(
                            title: 'Monthly',
                            subtitle:
                                monthlyOffer != null
                                    ? '1 month free trial, then ${monthlyOffer.displayPrice} / month'
                                    : '1 month free trial, then 29 EUR / month',
                            trailing:
                                monthlyOffer?.displayPrice ??
                                '${billing.monthlyPriceEur} EUR',
                            selected: _selectedPlan == BarberoBillingPlan.monthly,
                            badgeText: '',
                            onTap:
                                isOwner
                                    ? () => setState(
                                      () => _selectedPlan =
                                          BarberoBillingPlan.monthly,
                                    )
                                    : null,
                          ),
                          const SizedBox(height: 12),
                          _BillingPlanCard(
                            title: 'Yearly',
                            subtitle:
                                yearlyOffer != null
                                    ? '1 month free trial, then ${yearlyOffer.displayPrice} / year'
                                    : '1 month free trial, then 290 EUR / year',
                            trailing:
                                yearlyOffer?.displayPrice ??
                                '${billing.yearlyPriceEur} EUR',
                            selected: _selectedPlan == BarberoBillingPlan.yearly,
                            badgeText: 'Best value',
                            detailText: 'Save ${billing.yearlySavingsEur} EUR',
                            onTap:
                                isOwner
                                    ? () => setState(
                                      () => _selectedPlan =
                                          BarberoBillingPlan.yearly,
                                    )
                                    : null,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0x22FFFFFF)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'What is included',
                          style: TextStyle(
                            color: Color(0xFFF3E7D2),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 12),
                        _BillingFactRow('Owner workspace and shop controls'),
                        _BillingFactRow('Customer booking app connection'),
                        _BillingFactRow('Crew permissions, reports, reminders'),
                        _BillingFactRow('Appointments, clients, and analytics'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (isOwner)
                    PrimaryButton(
                      label: _isSubmitting ? 'Please wait...' : actionLabel,
                      onPressed:
                          _isSubmitting
                              ? () {}
                              : (billing.requiresPlanSelection
                                  ? _startTrial
                                  : _purchaseSelectedPlan),
                    )
                  else
                    PrimaryButton(
                      label: 'Sign out',
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                      },
                    ),
                  const SizedBox(height: 12),
                  SecondaryButton(
                    label:
                        isOwner
                            ? (billing.requiresPlanSelection
                                ? 'Sign out'
                                : 'Restore purchases')
                            : 'Refresh status',
                    onPressed: () async {
                      if (isOwner) {
                        if (billing.requiresPlanSelection) {
                          await FirebaseAuth.instance.signOut();
                        } else {
                          await _restorePurchases();
                        }
                        return;
                      }
                      setState(() {});
                    },
                  ),
                  ValueListenableBuilder<String?>(
                    valueListenable: _storeBilling.lastStoreError,
                    builder: (context, error, _) {
                      if (error == null || error.trim().isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          error,
                          style: const TextStyle(
                            color: Color(0xFFE1A49A),
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      );
                    },
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

class BarberoBillingPage extends StatefulWidget {
  const BarberoBillingPage({super.key});

  @override
  State<BarberoBillingPage> createState() => _BarberoBillingPageState();
}

class _BarberoBillingPageState extends State<BarberoBillingPage> {
  final BillingRepository _billingRepository = BillingRepository();
  final BarberoStoreBillingService _storeBilling =
      BarberoStoreBillingService.instance;
  late BarberoBillingPlan _selectedPlan;
  bool _isSaving = false;

  BarberoBillingSnapshot get _billing =>
      currentBarberoBilling.value ??
      const BarberoBillingSnapshot(
        status: BarberoBillingStatus.setupRequired,
        selectedPlan: BarberoBillingPlan.monthly,
        planConfirmed: false,
        allowsAccess: false,
        requiresOwnerAction: true,
        monthlyPriceEur: 29,
        yearlyPriceEur: 290,
        yearlySavingsEur: 58,
      );

  @override
  void initState() {
    super.initState();
    _selectedPlan = _billing.selectedPlan;
    unawaited(_storeBilling.initialize());
  }

  Future<void> _savePlan() async {
    setState(() => _isSaving = true);
    try {
      final billing = await _billingRepository.savePlan(_selectedPlan);
      currentBarberoBilling.value = billing;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subscription plan updated.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save the subscription plan.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _refresh() async {
    try {
      final billing = await _billingRepository.loadCurrentBilling();
      currentBarberoBilling.value = billing;
      await _storeBilling.refreshProducts();
      if (!mounted) return;
      setState(() => _selectedPlan = billing.selectedPlan);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to refresh subscription status.')),
      );
    }
  }

  Future<void> _purchaseSelectedPlan() async {
    setState(() => _isSaving = true);
    try {
      await _billingRepository.savePlan(_selectedPlan);
      await _storeBilling.purchasePlan(_selectedPlan);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complete the purchase in the store sheet.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the store purchase flow.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _isSaving = true);
    try {
      await _storeBilling.restorePurchases();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Checking existing store purchases...')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to restore store purchases.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final billing = _billing;
    final trialEndsText =
        billing.trialEndsAt != null
            ? _formatBillingDate(billing.trialEndsAt)
            : 'Not started';
    final renewalText =
        billing.currentPeriodEnd != null
            ? _formatBillingDate(billing.currentPeriodEnd)
            : 'Not available yet';
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFFD1A45C),
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: AppHamburgerMenu(),
              ),
              const SizedBox(height: 20),
              const Text(
                'Subscription',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Manage the active plan, trial status, and upcoming renewal direction for this shop.',
                style: TextStyle(
                  color: Color(0xFFB8AF9E),
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              _BillingStatusCard(billing: billing, showTrialSummary: true),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _BillingMetricTile(
                      label: 'Status',
                      value: billing.statusLabel,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _BillingMetricTile(
                      label: 'Trial ends',
                      value: trialEndsText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _BillingMetricTile(
                      label: 'Selected plan',
                      value: billing.selectedPlanLabel,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _BillingMetricTile(
                      label: 'Current period end',
                      value: renewalText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ValueListenableBuilder<List<BarberoStoreProductOffer>>(
                valueListenable: _storeBilling.offers,
                builder: (context, offers, _) {
                  final monthlyOffer = _storeBilling.offerForPlan(
                    BarberoBillingPlan.monthly,
                  );
                  final yearlyOffer = _storeBilling.offerForPlan(
                    BarberoBillingPlan.yearly,
                  );
                  return Column(
                    children: [
                      _BillingPlanCard(
                        title: 'Monthly',
                        subtitle:
                            monthlyOffer != null
                                ? '1 month free trial, then ${monthlyOffer.displayPrice} / month'
                                : '1 month free trial, then 29 EUR / month',
                        trailing:
                            monthlyOffer?.displayPrice ??
                            '${billing.monthlyPriceEur} EUR',
                        selected: _selectedPlan == BarberoBillingPlan.monthly,
                        onTap:
                            () => setState(
                              () => _selectedPlan = BarberoBillingPlan.monthly,
                            ),
                      ),
                      const SizedBox(height: 12),
                      _BillingPlanCard(
                        title: 'Yearly',
                        subtitle:
                            yearlyOffer != null
                                ? '1 month free trial, then ${yearlyOffer.displayPrice} / year'
                                : '1 month free trial, then 290 EUR / year',
                        trailing:
                            yearlyOffer?.displayPrice ??
                            '${billing.yearlyPriceEur} EUR',
                        selected: _selectedPlan == BarberoBillingPlan.yearly,
                        badgeText: 'Best value',
                        detailText: 'Save ${billing.yearlySavingsEur} EUR',
                        onTap:
                            () => setState(
                              () => _selectedPlan = BarberoBillingPlan.yearly,
                            ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: _isSaving ? 'Please wait...' : 'Save renewal preference',
                onPressed: _isSaving ? () {} : _savePlan,
              ),
              const SizedBox(height: 12),
              SecondaryButton(
                label:
                    billing.canOpenWorkspace
                        ? 'Restore purchases'
                        : 'Activate selected plan',
                onPressed:
                    _isSaving
                        ? () {}
                        : (billing.canOpenWorkspace
                            ? _restorePurchases
                            : _purchaseSelectedPlan),
              ),
              const SizedBox(height: 12),
              SecondaryButton(label: 'Refresh status', onPressed: _refresh),
              ValueListenableBuilder<String?>(
                valueListenable: _storeBilling.lastStoreError,
                builder: (context, error, _) {
                  if (error == null || error.trim().isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error,
                      style: const TextStyle(
                        color: Color(0xFFE1A49A),
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BillingStatusCard extends StatelessWidget {
  const _BillingStatusCard({
    required this.billing,
    this.showTrialSummary = false,
  });

  final BarberoBillingSnapshot billing;
  final bool showTrialSummary;

  @override
  Widget build(BuildContext context) {
    final accent =
        switch (billing.status) {
          BarberoBillingStatus.trialing => const Color(0xFFD1A45C),
          BarberoBillingStatus.active => const Color(0xFF8FB98B),
          BarberoBillingStatus.gracePeriod => const Color(0xFFE7C98F),
          _ => const Color(0xFFE39A8A),
        };
    final summary =
        billing.requiresPlanSelection
            ? 'Select a plan to activate the 1-month free trial.'
            : billing.isTrialing
            ? 'The trial is active and the full workspace remains unlocked.'
            : billing.isActive
            ? 'The shop has an active billing state.'
            : 'Owner action is required before the workspace can be used again.';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF191919), Color(0xFF101010)],
        ),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
            ),
            child: Text(
              billing.statusLabel,
              style: TextStyle(
                color: accent,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            summary,
            style: const TextStyle(
              color: Color(0xFFF3E7D2),
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          if (showTrialSummary && billing.trialEndsAt != null) ...[
            const SizedBox(height: 10),
            Text(
              'Trial ends on ${_formatBillingDate(billing.trialEndsAt)}.',
              style: const TextStyle(
                color: Color(0xFFB8AF9E),
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BillingPlanCard extends StatelessWidget {
  const _BillingPlanCard({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.selected,
    required this.onTap,
    this.badgeText = '',
    this.detailText = '',
  });

  final String title;
  final String subtitle;
  final String trailing;
  final bool selected;
  final VoidCallback? onTap;
  final String badgeText;
  final String detailText;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF191612) : const Color(0xFF121212),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color:
                  selected
                      ? const Color(0x66D1A45C)
                      : const Color(0x22FFFFFF),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color:
                        selected
                            ? const Color(0xFFD1A45C)
                            : const Color(0xFF565656),
                    width: 1.6,
                  ),
                ),
                child:
                    selected
                        ? const Center(
                          child: CircleAvatar(
                            radius: 5,
                            backgroundColor: Color(0xFFD1A45C),
                          ),
                        )
                        : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Color(0xFFF3E7D2),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (badgeText.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0x1FD1A45C),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              badgeText,
                              style: const TextStyle(
                                color: Color(0xFFD1A45C),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFFB8AF9E),
                        fontSize: 12.8,
                        height: 1.45,
                      ),
                    ),
                    if (detailText.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        detailText,
                        style: const TextStyle(
                          color: Color(0xFFD1A45C),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Text(
                trailing,
                style: const TextStyle(
                  color: Color(0xFFF3E7D2),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BillingMetricTile extends StatelessWidget {
  const _BillingMetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF9F9789), fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFF3E7D2),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _BillingFactRow extends StatelessWidget {
  const _BillingFactRow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 17,
            color: Color(0xFFD1A45C),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFFCEC2AE),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatBillingDate(DateTime? value) {
  if (value == null) {
    return 'Not available';
  }
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$day/$month/${value.year}';
}
