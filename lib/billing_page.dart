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
  final BarberoStoreBillingService _storeBilling =
      BarberoStoreBillingService.instance;
  late BarberoBillingPlan _selectedPlan;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedPlan = widget.billing.selectedPlan;
    if (widget.session.isOwner && widget.billing.requiresPlanSelection) {
      // Recover a completed store purchase silently when the server has not
      // received its purchase event yet. Active entitlements still open the
      // workspace directly through the normal app-flow gate.
      unawaited(_recoverStorePurchaseSilently());
    }
  }

  Future<void> _recoverStorePurchaseSilently() async {
    try {
      await _storeBilling.restorePurchases();
    } catch (_) {
      // Keep the normal subscription screen visible when there is nothing to
      // recover or the store is temporarily unavailable.
    }
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
      await _storeBilling.purchasePlan(_selectedPlan);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ολοκλήρωσε την αγορά από το παράθυρο του καταστήματος.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Δεν ήταν δυνατό να ανοίξει η διαδικασία αγοράς.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _manageSubscription() async {
    setState(() => _isSubmitting = true);
    try {
      await _storeBilling.openManageSubscription(_selectedPlan);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Δεν ήταν δυνατό να ανοίξει η διαχείριση συνδρομής.'),
        ),
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
      await _storeBilling.purchasePlan(_selectedPlan, requireFreeTrial: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Η δωρεάν δοκιμή ενός μήνα είναι πλέον ενεργή.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Δεν ήταν δυνατή η έναρξη της δωρεάν δοκιμής.'),
        ),
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
    final actionLabel = billing.requiresPlanSelection
        ? 'Έναρξη δωρεάν δοκιμής ενός μήνα'
        : 'Ενεργοποίηση επιλεγμένου προγράμματος';
    final title = billing.requiresPlanSelection
        ? 'Επίλεξε τη συνδρομή σου'
        : 'Απαιτείται συνδρομή';
    final subtitle = isOwner
        ? billing.requiresPlanSelection
              ? 'Το κατάστημα ξεκινά με δωρεάν δοκιμή ενός μήνα και μετά ανανεώνεται με το επιλεγμένο πρόγραμμα.'
              : 'Ο χώρος εργασίας είναι κλειδωμένος μέχρι να ενεργοποιηθεί συνδρομή για αυτό το κατάστημα.'
        : 'Αυτό το κατάστημα είναι προσωρινά κλειδωμένο μέχρι ο ιδιοκτήτης να ολοκληρώσει τη ρύθμιση συνδρομής.';
    final canSwitchShops = currentBarberoAccessibleShops.value.length > 1;
    final textPrimary = context.barberinTextPrimary;
    final textSecondary = context.barberinTextSecondary;

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
                  const BrandWordmark(width: 154),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  if (canSwitchShops) ...[
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _isSubmitting
                          ? null
                          : () => _openBarberoShopSwitcher(context),
                      icon: const Icon(Icons.sync_alt_rounded, size: 16),
                      label: const Text('Αλλαγή καταστήματος'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _BillingStatusCard(billing: billing, showTrialSummary: true),
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
                          _BillingPlanRow(
                            title: 'Μηνιαία',
                            subtitle: monthlyOffer != null
                                ? 'Δωρεάν δοκιμή ενός μήνα και μετά ${monthlyOffer.displayPrice} / μήνα'
                                : '1 μήνας δωρεάν δοκιμή, μετά 29,99 EUR / μήνα',
                            trailing:
                                monthlyOffer?.displayPrice ??
                                '${billing.monthlyPriceEur} EUR',
                            selected:
                                _selectedPlan == BarberoBillingPlan.monthly,
                            badgeText: '',
                            onTap: isOwner
                                ? () => setState(
                                    () => _selectedPlan =
                                        BarberoBillingPlan.monthly,
                                  )
                                : null,
                          ),
                          const SizedBox(height: 12),
                          _BillingPlanRow(
                            title: 'Ετήσια',
                            subtitle: yearlyOffer != null
                                ? 'Δωρεάν δοκιμή ενός μήνα και μετά ${yearlyOffer.displayPrice} / έτος'
                                : '1 μήνας δωρεάν δοκιμή, μετά 299,99 EUR / έτος',
                            trailing:
                                yearlyOffer?.displayPrice ??
                                '${billing.yearlyPriceEur} EUR',
                            selected:
                                _selectedPlan == BarberoBillingPlan.yearly,
                            badgeText: 'Καλύτερη αξία',
                            detailText:
                                'Εξοικονόμηση ${billing.yearlySavingsEur} EUR',
                            onTap: isOwner
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
                      color: context.barberinSurface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: context.barberinBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Τι περιλαμβάνει',
                          style: TextStyle(
                            color: textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 12),
                        _BillingFactRow(
                          'Χώρος εργασίας ιδιοκτήτη και έλεγχος καταστήματος',
                        ),
                        _BillingFactRow(
                          'Σύνδεση με την εφαρμογή κρατήσεων πελατών',
                        ),
                        _BillingFactRow(
                          'Δικαιώματα ομάδας, αναφορές και υπενθυμίσεις',
                        ),
                        _BillingFactRow('Ραντεβού, πελάτες και αναλύσεις'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (isOwner)
                    PrimaryButton(
                      label: _isSubmitting ? 'Περίμενε...' : actionLabel,
                      onPressed: _isSubmitting
                          ? () {}
                          : (billing.requiresPlanSelection
                                ? _startTrial
                                : _purchaseSelectedPlan),
                    )
                  else
                    PrimaryButton(
                      label: 'Αποσύνδεση',
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                      },
                    ),
                  if (!isOwner && !billing.requiresPlanSelection) ...[
                    const SizedBox(height: 12),
                    SecondaryButton(
                      label: 'Ανανέωση κατάστασης',
                      onPressed: () async {
                        setState(() {});
                      },
                    ),
                  ],
                  if (isOwner && !billing.requiresPlanSelection) ...[
                    const SizedBox(height: 12),
                    SecondaryButton(
                      label: 'Διαχείριση συνδρομής',
                      onPressed: _isSubmitting ? () {} : _manageSubscription,
                    ),
                  ],
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
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
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

class _LegacyBarberoBillingPage extends StatefulWidget {
  const _LegacyBarberoBillingPage();

  @override
  State<_LegacyBarberoBillingPage> createState() =>
      _LegacyBarberoBillingPageState();
}

class _LegacyBarberoBillingPageState extends State<_LegacyBarberoBillingPage> {
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
        monthlyPriceEur: 29.99,
        yearlyPriceEur: 299.99,
        yearlySavingsEur: 59.89,
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
        const SnackBar(content: Text('Το πρόγραμμα συνδρομής ενημερώθηκε.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Δεν ήταν δυνατή η αποθήκευση του προγράμματος συνδρομής.',
          ),
        ),
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
        const SnackBar(
          content: Text('Δεν ήταν δυνατή η ανανέωση της κατάστασης συνδρομής.'),
        ),
      );
    }
  }

  Future<void> _purchaseSelectedPlan() async {
    if (_billing.canOpenWorkspace) {
      // Do not start a second subscription. Google Play must handle a plan
      // change so the existing purchase is replaced correctly.
      await _manageSubscription();
      return;
    }
    setState(() => _isSaving = true);
    try {
      await _storeBilling.purchasePlan(
        _selectedPlan,
        requireFreeTrial: _billing.requiresPlanSelection,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ολοκλήρωσε την αγορά από το παράθυρο του καταστήματος.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Δεν ήταν δυνατό να ανοίξει η διαδικασία αγοράς.'),
        ),
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
        const SnackBar(content: Text('Έλεγχος προηγούμενων αγορών...')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Δεν ήταν δυνατή η επαναφορά των αγορών.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _manageSubscription() async {
    setState(() => _isSaving = true);
    try {
      await _storeBilling.openManageSubscription(_selectedPlan);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Δεν ήταν δυνατό να ανοίξει η διαχείριση συνδρομής.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final billing = _billing;
    final trialEndsText = billing.trialEndsAt != null
        ? _formatBillingDate(billing.trialEndsAt)
        : 'Δεν ξεκίνησε';
    final renewalText = billing.currentPeriodEnd != null
        ? _formatBillingDate(billing.currentPeriodEnd)
        : 'Δεν είναι ακόμη διαθέσιμο';
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: scheme.primary,
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: AppHamburgerMenu(),
              ),
              const SizedBox(height: 20),
              Text(
                'Συνδρομή',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Διαχειρίσου το ενεργό πρόγραμμα, τη δοκιμαστική περίοδο και την επόμενη ανανέωση αυτού του καταστήματος.',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
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
                      label: 'Κατάσταση',
                      value: billing.statusLabel,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _BillingMetricTile(
                      label: 'Λήξη δοκιμής',
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
                      label: 'Επιλεγμένο πρόγραμμα',
                      value: billing.selectedPlanLabel,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _BillingMetricTile(
                      label: 'Λήξη τρέχουσας περιόδου',
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
                      _BillingPlanRow(
                        title: 'Μηνιαία',
                        subtitle: monthlyOffer != null
                            ? '1 μήνας δωρεάν δοκιμή, μετά ${monthlyOffer.displayPrice} / μήνα'
                            : '1 μήνας δωρεάν δοκιμή, μετά 29,99 EUR / μήνα',
                        trailing:
                            monthlyOffer?.displayPrice ??
                            '${billing.monthlyPriceEur} EUR',
                        selected: _selectedPlan == BarberoBillingPlan.monthly,
                        onTap: () => setState(
                          () => _selectedPlan = BarberoBillingPlan.monthly,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _BillingPlanRow(
                        title: 'Ετήσια',
                        subtitle: yearlyOffer != null
                            ? '1 μήνας δωρεάν δοκιμή, μετά ${yearlyOffer.displayPrice} / έτος'
                            : '1 μήνας δωρεάν δοκιμή, μετά 299,99 EUR / έτος',
                        trailing:
                            yearlyOffer?.displayPrice ??
                            '${billing.yearlyPriceEur} EUR',
                        selected: _selectedPlan == BarberoBillingPlan.yearly,
                        badgeText: 'Καλύτερη αξία',
                        detailText:
                            'Εξοικονόμηση ${billing.yearlySavingsEur} EUR',
                        onTap: () => setState(
                          () => _selectedPlan = BarberoBillingPlan.yearly,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: _isSaving
                    ? 'Περίμενε...'
                    : 'Αποθήκευση προτίμησης ανανέωσης',
                onPressed: _isSaving ? () {} : _savePlan,
              ),
              const SizedBox(height: 12),
              SecondaryButton(
                label: billing.canOpenWorkspace
                    ? 'Επαναφορά αγορών'
                    : 'Ενεργοποίηση επιλεγμένου προγράμματος',
                onPressed: _isSaving
                    ? () {}
                    : (billing.canOpenWorkspace
                          ? _restorePurchases
                          : _purchaseSelectedPlan),
              ),
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'Ανανέωση κατάστασης',
                onPressed: _refresh,
              ),
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'Διαχείριση συνδρομής',
                onPressed: _isSaving ? () {} : _manageSubscription,
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
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
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

  String _planLabel() {
    return billing.isYearly
        ? barberinLabel('\u0395\u03c4\u03ae\u03c3\u03b9\u03bf', 'Yearly')
        : barberinLabel(
            '\u039c\u03b7\u03bd\u03b9\u03b1\u03af\u03bf',
            'Monthly',
          );
  }

  String _statusDetailLabel() {
    if (billing.isTrialing) {
      return barberinLabel(
        '\u0394\u03c9\u03c1\u03b5\u03ac\u03bd \u03b4\u03bf\u03ba\u03b9\u03bc\u03ae',
        'Free trial',
      );
    }
    if (billing.status == BarberoBillingStatus.gracePeriod) {
      return barberinLabel(
        '\u03a0\u03b5\u03c1\u03af\u03bf\u03b4\u03bf\u03c2 \u03c7\u03ac\u03c1\u03b9\u03c4\u03bf\u03c2',
        'Grace period',
      );
    }
    return barberinLabel('\u0395\u03bd\u03b5\u03c1\u03b3\u03ae', 'Active');
  }

  @override
  Widget build(BuildContext context) {
    final accent = switch (billing.status) {
      BarberoBillingStatus.trialing => context.barberinAccent,
      BarberoBillingStatus.active => const Color(0xFF8FB98B),
      BarberoBillingStatus.gracePeriod => context.barberinAccent,
      _ => const Color(0xFFE39A8A),
    };
    final summary = billing.requiresPlanSelection
        ? 'Επίλεξε πρόγραμμα για να ενεργοποιήσεις τη δωρεάν δοκιμή ενός μήνα.'
        : billing.isTrialing
        ? 'Η δοκιμαστική περίοδος είναι ενεργή και ο πλήρης χώρος εργασίας παραμένει ξεκλείδωτος.'
        : billing.isActive
        ? 'Το κατάστημα έχει ενεργή κατάσταση χρέωσης.'
        : 'Απαιτείται ενέργεια από τον ιδιοκτήτη πριν χρησιμοποιηθεί ξανά ο χώρος εργασίας.';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [context.barberinSurface, context.barberinSurfaceAlt],
        ),
        border: Border.all(color: context.barberinBorder),
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
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (billing.planConfirmed ||
              billing.isActive ||
              billing.currentPeriodEnd != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: context.barberinSurface.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.barberinBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    barberinLabel(
                      '\u03a4\u03c1\u03ad\u03c7\u03bf\u03c5\u03c3\u03b1 \u03c3\u03c5\u03bd\u03b4\u03c1\u03bf\u03bc\u03ae',
                      'Current subscription',
                    ),
                    style: TextStyle(
                      color: context.barberinTextSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _planLabel(),
                    style: TextStyle(
                      color: context.barberinTextPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    billing.currentPeriodEnd != null
                        ? '${_statusDetailLabel()}  •  ${barberinLabel('\u0391\u03bd\u03b1\u03bd\u03ad\u03c9\u03c3\u03b7', 'Renews')} ${_formatBillingDate(billing.currentPeriodEnd)}'
                        : _statusDetailLabel(),
                    style: TextStyle(
                      color: context.barberinTextSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            summary,
            style: TextStyle(
              color: context.barberinTextPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          if (showTrialSummary && billing.trialEndsAt != null) ...[
            const SizedBox(height: 10),
            Text(
              'Η δοκιμή λήγει στις ${_formatBillingDate(billing.trialEndsAt)}.',
              style: TextStyle(
                color: context.barberinTextSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BillingPlanRow extends StatelessWidget {
  const _BillingPlanRow({
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
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border(bottom: BorderSide(color: context.barberinBorder)),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 4,
                height: 42,
                decoration: BoxDecoration(
                  color: selected ? scheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: context.barberinTextPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          trailing,
                          style: TextStyle(
                            color: context.barberinTextPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: context.barberinTextSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    if (badgeText.isNotEmpty || detailText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          badgeText,
                          detailText,
                        ].where((item) => item.isNotEmpty).join('  ·  '),
                        style: TextStyle(
                          color: scheme.primary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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

class _BillingMetricTile extends StatelessWidget {
  const _BillingMetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.barberinSurfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.barberinBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: context.barberinTextSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: context.barberinTextPrimary,
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
          Icon(
            Icons.check_circle_rounded,
            size: 17,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: context.barberinTextSecondary,
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
    return 'Δεν είναι διαθέσιμο';
  }
  return barberinDateLabel(value, includeYear: true);
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
        monthlyPriceEur: 29.99,
        yearlyPriceEur: 299.99,
        yearlySavingsEur: 59.89,
      );

  @override
  void initState() {
    super.initState();
    _selectedPlan = _billing.selectedPlan;
    unawaited(_storeBilling.initialize());
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
        const SnackBar(content: Text('Δεν ήταν δυνατή η ανανέωση.')),
      );
    }
  }

  Future<void> _purchaseSelectedPlan() async {
    if (_billing.canOpenWorkspace) {
      // Do not start a second subscription. Google Play must handle a plan
      // change so the existing purchase is replaced correctly.
      await _manageSubscription();
      return;
    }
    setState(() => _isSaving = true);
    try {
      await _storeBilling.purchasePlan(
        _selectedPlan,
        requireFreeTrial: _billing.requiresPlanSelection,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Δεν ήταν δυνατή η έναρξη της αγοράς.')),
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
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Δεν ήταν δυνατή η επαναφορά αγορών.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _manageSubscription() async {
    setState(() => _isSaving = true);
    try {
      await _storeBilling.openManageSubscription(_selectedPlan);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Δεν ήταν δυνατή η διαχείριση της συνδρομής.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final billing = _billing;
    final trialEndsText = billing.trialEndsAt != null
        ? _formatBillingDate(billing.trialEndsAt)
        : 'Δεν έχει οριστεί';
    final primaryLabel = billing.requiresPlanSelection
        ? 'Έναρξη δωρεάν δοκιμής'
        : (billing.canOpenWorkspace
              ? 'Διαχείριση συνδρομής'
              : 'Ενεργοποίηση επιλεγμένου προγράμματος');

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: scheme.primary,
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: AppHamburgerMenu(),
              ),
              const SizedBox(height: 24),
              Text(
                'Συνδρομή',
                style: TextStyle(
                  color: context.barberinTextPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Επίλεξε το πρόγραμμα που ταιριάζει στο κατάστημά σου.',
                style: TextStyle(
                  color: context.barberinTextSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: context.barberinBorder),
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
                            'Κατάσταση',
                            style: TextStyle(
                              color: context.barberinTextSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            billing.statusLabel,
                            style: TextStyle(
                              color: context.barberinTextPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (billing.planConfirmed || billing.isActive) ...[
                          Text(
                            'Τρέχον πλάνο',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: context.barberinTextSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            billing.currentPlanLabel,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: context.barberinTextPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (billing.trialEndsAt != null) ...[
                          if (billing.planConfirmed || billing.isActive)
                            const SizedBox(height: 8),
                          Text(
                            'Trial έως $trialEndsText',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: context.barberinTextSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Πρόγραμμα',
                style: TextStyle(
                  color: context.barberinTextPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
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
                      _BillingPlanRow(
                        title: 'Μηνιαία',
                        subtitle: monthlyOffer != null
                            ? '1 μήνας δωρεάν · μετά ${monthlyOffer.displayPrice} / μήνα'
                            : '1 μήνας δωρεάν · μετά 29,99 EUR / μήνα',
                        trailing:
                            monthlyOffer?.displayPrice ??
                            '${billing.monthlyPriceEur} EUR',
                        selected: _selectedPlan == BarberoBillingPlan.monthly,
                        onTap: () => setState(
                          () => _selectedPlan = BarberoBillingPlan.monthly,
                        ),
                      ),
                      _BillingPlanRow(
                        title: 'Ετήσια',
                        subtitle: yearlyOffer != null
                            ? '1 μήνας δωρεάν · μετά ${yearlyOffer.displayPrice} / έτος'
                            : '1 μήνας δωρεάν · μετά 299,99 EUR / έτος',
                        trailing:
                            yearlyOffer?.displayPrice ??
                            '${billing.yearlyPriceEur} EUR',
                        selected: _selectedPlan == BarberoBillingPlan.yearly,
                        badgeText: 'Καλύτερη αξία',
                        detailText:
                            'Εξοικονόμηση ${billing.yearlySavingsEur} EUR',
                        onTap: () => setState(
                          () => _selectedPlan = BarberoBillingPlan.yearly,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: _isSaving ? 'Περίμενε...' : primaryLabel,
                onPressed: _isSaving ? () {} : _purchaseSelectedPlan,
              ),
              const SizedBox(height: 4),
              _BillingActionRow(
                label: 'Έλεγχος προηγούμενων αγορών',
                description: 'Μόνο αν μια ενεργή αγορά δεν εμφανίζεται εδώ.',
                onTap: _isSaving ? null : _restorePurchases,
              ),
              if (billing.canOpenWorkspace)
                _BillingActionRow(
                  label: 'Διαχείριση συνδρομής',
                  description:
                      'Αλλαγή πλάνου, ακύρωση, ανανέωση και τρόπος πληρωμής στο κατάστημα της συσκευής.',
                  onTap: _isSaving ? null : _manageSubscription,
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
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
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

class _BillingActionRow extends StatelessWidget {
  const _BillingActionRow({
    required this.label,
    required this.onTap,
    this.description,
  });

  final String label;
  final VoidCallback? onTap;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
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
                      label,
                      style: TextStyle(
                        color: context.barberinTextPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        description!,
                        style: TextStyle(
                          color: context.barberinTextSecondary,
                          fontSize: 11.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: context.barberinTextSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
