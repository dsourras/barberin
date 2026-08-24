part of 'main.dart';

class SustainabilityIndexPage extends StatefulWidget {
  const SustainabilityIndexPage({
    super.key,
    required this.selectedDate,
    required this.appointments,
  });

  final DateTime selectedDate;
  final List<Appointment> appointments;

  @override
  State<SustainabilityIndexPage> createState() =>
      _SustainabilityIndexPageState();
}

class _SustainabilityResultsPage extends StatelessWidget {
  const _SustainabilityResultsPage({required this.report});

  final _ShopSustainabilityReport report;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.barberinBackground,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: context.barberinTextPrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Αποτελέσματα βιωσιμότητας',
                          style: _customerIntelligenceStyle(
                            _reportsPageTitleStyle,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Αποτέλεσμα βιωσιμότητας με βάση τα πιο πρόσφατα οικονομικά στοιχεία του καταστήματος',
                          style: _customerIntelligenceStyle(
                            _reportsPageSubtitleStyle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _SustainabilityHero(report: report),
                    const SizedBox(height: 18),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.5,
                      children: [
                        _ReportsMetricCard(
                          label: 'Βαθμολογία βιωσιμότητας',
                          value: report.sustainabilityScore.toStringAsFixed(0),
                        ),
                        _ReportsMetricCard(
                          label: 'Βιώσιμο καθαρό αποτέλεσμα',
                          value:
                              'EUR ${report.sustainableNet.toStringAsFixed(0)}',
                        ),
                        _ReportsMetricCard(
                          label: 'Έσοδα ισορροπίας',
                          value:
                              'EUR ${report.breakEvenIncome.toStringAsFixed(0)}',
                        ),
                        _ReportsMetricCard(
                          label: 'Μήνες αποθεματικού',
                          value: report.bufferMonths.toStringAsFixed(1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _SustainabilityRatiosCard(report: report),
                    const SizedBox(height: 18),
                    ...report.dimensions.map(
                      (dimension) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _SustainabilityDimensionCard(
                          dimension: dimension,
                        ),
                      ),
                    ),
                    if (report.recommendations.isNotEmpty)
                      _SustainabilityRecommendationsCard(
                        recommendations: report.recommendations,
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

class _SustainabilityDimension {
  const _SustainabilityDimension({
    required this.title,
    required this.score,
    required this.status,
    required this.detail,
    required this.implication,
  });

  final String title;
  final double score;
  final String status;
  final String detail;
  final String implication;
}

class _ShopSustainabilityReport {
  const _ShopSustainabilityReport({
    required this.totalIncome,
    required this.totalExpenses,
    required this.net,
    required this.sustainableNet,
    required this.realHourly,
    required this.breakEvenIncome,
    required this.expenseRatio,
    required this.payrollRatio,
    required this.bufferMonths,
    required this.sustainabilityScore,
    required this.stabilityIndex,
    required this.resilienceScore,
    required this.longTermViability,
    required this.financialVerdict,
    required this.summary,
    required this.primaryConcern,
    required this.strongestPoint,
    required this.nextMove,
    required this.recommendations,
    required this.dimensions,
  });

  final double totalIncome;
  final double totalExpenses;
  final double net;
  final double sustainableNet;
  final double realHourly;
  final double breakEvenIncome;
  final double expenseRatio;
  final double payrollRatio;
  final double bufferMonths;
  final double sustainabilityScore;
  final double stabilityIndex;
  final double resilienceScore;
  final String longTermViability;
  final String financialVerdict;
  final String summary;
  final String primaryConcern;
  final String strongestPoint;
  final String nextMove;
  final List<String> recommendations;
  final List<_SustainabilityDimension> dimensions;
}

String _formatEditableNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(2);
}

double _readEditableNumber(String raw) {
  return double.tryParse(raw.trim().replaceAll(',', '.')) ?? 0;
}

_ShopSustainabilityReport _buildShopSustainabilityReport(
  ShopSustainabilityProfile profile,
) {
  final totalIncome = profile.totalIncome;
  final totalExpenses = profile.totalExpenses;
  final net = totalIncome - totalExpenses;
  final reinvestmentReserve = totalIncome * 0.08;
  final sustainableNet = net - reinvestmentReserve;
  final realHourly = profile.workingHoursMonth <= 0
      ? 0.0
      : sustainableNet / profile.workingHoursMonth;
  final breakEvenIncome = totalExpenses + reinvestmentReserve;
  final expenseRatio = totalIncome <= 0 ? 1.0 : totalExpenses / totalIncome;
  final payrollRatio = totalIncome <= 0
      ? 1.0
      : profile.payrollCost / totalIncome;
  final bufferMonths = totalExpenses <= 0
      ? 0.0
      : profile.cashReserve / totalExpenses;
  final marginRatio = totalIncome <= 0 ? -1.0 : sustainableNet / totalIncome;

  final marginScore = (marginRatio * 100).clamp(0, 25).toDouble() * 1.4;
  final bufferScore = (bufferMonths * 12).clamp(0, 20).toDouble();
  final hourlyScore = (realHourly.clamp(0, 25) / 25) * 15;
  final expenseScore = ((1 - expenseRatio).clamp(0, 1) * 15).toDouble();
  final payrollScore = ((1 - payrollRatio).clamp(0, 1) * 10).toDouble();
  final headroomScore = totalIncome <= 0
      ? 0
      : (((totalIncome - breakEvenIncome) / totalIncome).clamp(0, 0.15) /
                0.15) *
            10;
  final sustainabilityScore =
      (marginScore +
              bufferScore +
              hourlyScore +
              expenseScore +
              payrollScore +
              headroomScore)
          .clamp(0, 100)
          .toDouble();
  final stabilityIndex =
      ((bufferMonths * 20) + ((1 - expenseRatio).clamp(0, 1) * 40))
          .clamp(0, 100)
          .toDouble();
  final resilienceScore =
      ((bufferMonths * 25) + ((1 - payrollRatio).clamp(0, 1) * 30))
          .clamp(0, 100)
          .toDouble();

  final longTermViability = sustainabilityScore >= 75
      ? 'Βιώσιμο'
      : sustainabilityScore >= 55
      ? 'Σταθερό αλλά εκτεθειμένο'
      : sustainabilityScore >= 35
      ? 'Εύθραυστο'
      : 'Σε κίνδυνο';
  final financialVerdict = sustainabilityScore >= 75
      ? 'Το κατάστημα φαίνεται βιώσιμα κερδοφόρο.'
      : sustainabilityScore >= 55
      ? 'Το κατάστημα είναι βιώσιμο, αλλά τα περιθώρια είναι εκτεθειμένα.'
      : sustainabilityScore >= 35
      ? 'Το κατάστημα είναι οικονομικά εύθραυστο.'
      : 'Το κατάστημα δεν είναι αυτή τη στιγμή οικονομικά βιώσιμο.';

  final dimensions = <_SustainabilityDimension>[
    _SustainabilityDimension(
      title: 'Κερδοφορία',
      score: (marginRatio * 100).clamp(0, 100).toDouble(),
      status: marginRatio >= 0.2
          ? 'Ισχυρή'
          : marginRatio >= 0.08
          ? 'Αποδεκτή'
          : marginRatio >= 0
          ? 'Οριακή'
          : 'Αρνητική',
      detail:
          'Το βιώσιμο καθαρό αποτέλεσμα είναι ${sustainableNet.round()} EUR μετά τα λειτουργικά κόστη και το αποθεματικό επανεπένδυσης.',
      implication: marginRatio < 0.08
          ? 'Η κερδοφορία είναι πολύ οριακή για να απορροφήσει άνετα απρόβλεπτες πιέσεις.'
          : 'Η κερδοφορία δίνει στο κατάστημα χώρο για επανεπένδυση και ανάπτυξη.',
    ),
    _SustainabilityDimension(
      title: 'Πίεση κόστους',
      score: ((1 - expenseRatio).clamp(0, 1) * 100).toDouble(),
      status: expenseRatio <= 0.65
          ? 'Υγιής'
          : expenseRatio <= 0.8
          ? 'Αυξημένη'
          : 'Υψηλή',
      detail:
          'Τα έξοδα καταναλώνουν το ${(expenseRatio * 100).clamp(0, 999).toStringAsFixed(0)}% των συνολικών εσόδων.',
      implication: expenseRatio > 0.8
          ? 'Η βάση κόστους απορροφά το μεγαλύτερο μέρος των εσόδων του καταστήματος.'
          : 'Η δομή κόστους παραμένει διαχειρίσιμη.',
    ),
    _SustainabilityDimension(
      title: 'Αποθεματικό μετρητών',
      score: (bufferMonths * 20).clamp(0, 100).toDouble(),
      status: bufferMonths >= 3
          ? 'Προστατευμένο'
          : bufferMonths >= 1
          ? 'Περιορισμένο'
          : 'Αδύναμο',
      detail:
          'Το τρέχον αποθεματικό καλύπτει περίπου ${bufferMonths.toStringAsFixed(1)} μήνες λειτουργικών εξόδων.',
      implication: bufferMonths < 1
          ? 'Το αδύναμο αποθεματικό αφήνει το κατάστημα εκτεθειμένο σε ξαφνικές περιόδους χαμηλής κίνησης.'
          : 'Το κατάστημα διαθέτει χρήσιμο περιθώριο ασφάλειας.',
    ),
    _SustainabilityDimension(
      title: 'Αποδοτικότητα προσωπικού',
      score: ((1 - payrollRatio).clamp(0, 1) * 100).toDouble(),
      status: payrollRatio <= 0.35
          ? 'Αποδοτική'
          : payrollRatio <= 0.5
          ? 'Οριακή'
          : 'Δαπανηρή',
      detail:
          'Η μισθοδοσία απορροφά το ${(payrollRatio * 100).clamp(0, 999).toStringAsFixed(0)}% των εσόδων, με πραγματικό ωριαίο αποτέλεσμα ${realHourly.toStringAsFixed(1)} EUR.',
      implication: payrollRatio > 0.5
          ? 'Το κόστος προσωπικού είναι πολύ υψηλό σε σχέση με τα τρέχοντα έσοδα.'
          : 'Το κόστος προσωπικού παραμένει σε βιώσιμο επίπεδο.',
    ),
  ];

  final primaryConcern = expenseRatio > 0.8
      ? 'Η βάση εξόδων είναι πολύ υψηλή σε σχέση με τα τρέχοντα έσοδα.'
      : bufferMonths < 1
      ? 'Το κατάστημα έχει αδύναμο αποθεματικό και δεν μπορεί να απορροφήσει καλά περιόδους χαμηλής κίνησης.'
      : payrollRatio > 0.5
      ? 'Η μισθοδοσία απορροφά υπερβολικά μεγάλο μέρος των μηνιαίων εσόδων.'
      : 'Δεν υπάρχει ένας κυρίαρχος κίνδυνος, αλλά η κερδοφορία χρειάζεται παρακολούθηση.';
  final strongestPoint = marginRatio >= 0.2
      ? 'Το κατάστημα εξακολουθεί να μετατρέπει τα έσοδα σε ισχυρό βιώσιμο καθαρό αποτέλεσμα.'
      : bufferMonths >= 3
      ? 'Το αποθεματικό μετρητών δίνει στην επιχείρηση χρόνο να αντιδράσει σε πιέσεις.'
      : payrollRatio <= 0.35
      ? 'Το κόστος προσωπικού ελέγχεται σε σχέση με τα έσοδα.'
      : 'Το κατάστημα έχει ακόμη μια λειτουργική βάση πάνω στην οποία μπορεί να βελτιωθεί.';
  final nextMove = sustainableNet < 0
      ? 'Αύξησε τα έσοδα ή μείωσε τα επαναλαμβανόμενα κόστη μέχρι το βιώσιμο καθαρό αποτέλεσμα να γίνει θετικό.'
      : expenseRatio > 0.75
      ? 'Έλεγξε τα επαναλαμβανόμενα κόστη ένα προς ένα και μείωσε τις μη απαραίτητες μηνιαίες δαπάνες.'
      : bufferMonths < 2
      ? 'Χρησιμοποίησε τους επόμενους κερδοφόρους μήνες για να δημιουργήσεις αποθεματικό τουλάχιστον 2-3 μηνών.'
      : 'Διατήρησε πειθαρχία στις τιμές και συνέχισε να ενισχύεις το αποθεματικό.';

  final recommendations = <String>[
    if (sustainableNet < 0)
      'Αύξησε τη μέση αξία ραντεβού, βελτίωσε την πληρότητα ή μείωσε τα σταθερά μηνιαία κόστη μέχρι το βιώσιμο καθαρό αποτέλεσμα να γίνει θετικό.',
    if (expenseRatio > 0.75)
      'Έλεγξε ενοίκιο, παροχές, προμήθειες και συνδρομές για να μειώσεις τον λόγο εξόδων.',
    if (payrollRatio > 0.45)
      'Έλεγξε αν το κόστος προσωπικού αντιστοιχεί στον πραγματικό όγκο κρατήσεων και στις παραγωγικές ώρες.',
    if (bufferMonths < 2)
      'Δημιούργησε ισχυρότερο αποθεματικό ώστε η επιχείρηση να καλύπτει τουλάχιστον 2 μήνες εξόδων.',
    if (realHourly < 15)
      'Έλεγξε τις τιμές και το μείγμα υπηρεσιών, επειδή η πραγματική ωριαία απόδοση είναι πολύ χαμηλή.',
  ];

  return _ShopSustainabilityReport(
    totalIncome: totalIncome,
    totalExpenses: totalExpenses,
    net: net,
    sustainableNet: sustainableNet,
    realHourly: realHourly,
    breakEvenIncome: breakEvenIncome,
    expenseRatio: expenseRatio,
    payrollRatio: payrollRatio,
    bufferMonths: bufferMonths,
    sustainabilityScore: sustainabilityScore,
    stabilityIndex: stabilityIndex,
    resilienceScore: resilienceScore,
    longTermViability: longTermViability,
    financialVerdict: financialVerdict,
    summary:
        'Έσοδα ${totalIncome.round()} EUR έναντι εξόδων ${totalExpenses.round()} EUR αφήνουν βιώσιμο μηνιαίο αποτέλεσμα ${sustainableNet.round()} EUR.',
    primaryConcern: primaryConcern,
    strongestPoint: strongestPoint,
    nextMove: nextMove,
    recommendations: recommendations,
    dimensions: dimensions,
  );
}

class _SustainabilityIndexPageState extends State<SustainabilityIndexPage> {
  final ShopSustainabilityRepository _repository =
      ShopSustainabilityRepository();
  late final Map<String, TextEditingController> _controllers;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  static const _fieldLabels = <String, String>{
    'monthlyRevenue': 'Μηνιαία έσοδα υπηρεσιών',
    'otherRevenue': 'Άλλα μηνιαία έσοδα',
    'fixedCosts': 'Γενικά σταθερά κόστη',
    'rentCost': 'Ενοίκιο',
    'payrollCost': 'Μισθοδοσία',
    'utilitiesCost': 'Παροχές',
    'suppliesCost': 'Προμήθειες και προϊόντα',
    'taxesCost': 'Φόροι και ασφάλιση',
    'marketingCost': 'Μάρκετινγκ',
    'equipmentCost': 'Εξοπλισμός / χρηματοδότηση',
    'cashReserve': 'Αποθεματικό μετρητών',
    'workingHoursMonth': 'Ώρες εργασίας ανά μήνα',
  };

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final key in _fieldLabels.keys) key: TextEditingController(),
    };
    _loadProfile();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _repository.load();
      _applyProfile(profile);
    } catch (error) {
      _error = '$error';
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _applyProfile(ShopSustainabilityProfile profile) {
    _controllers['monthlyRevenue']!.text = _formatEditableNumber(
      profile.monthlyRevenue,
    );
    _controllers['otherRevenue']!.text = _formatEditableNumber(
      profile.otherRevenue,
    );
    _controllers['fixedCosts']!.text = _formatEditableNumber(
      profile.fixedCosts,
    );
    _controllers['rentCost']!.text = _formatEditableNumber(profile.rentCost);
    _controllers['payrollCost']!.text = _formatEditableNumber(
      profile.payrollCost,
    );
    _controllers['utilitiesCost']!.text = _formatEditableNumber(
      profile.utilitiesCost,
    );
    _controllers['suppliesCost']!.text = _formatEditableNumber(
      profile.suppliesCost,
    );
    _controllers['taxesCost']!.text = _formatEditableNumber(profile.taxesCost);
    _controllers['marketingCost']!.text = _formatEditableNumber(
      profile.marketingCost,
    );
    _controllers['equipmentCost']!.text = _formatEditableNumber(
      profile.equipmentCost,
    );
    _controllers['cashReserve']!.text = _formatEditableNumber(
      profile.cashReserve,
    );
    _controllers['workingHoursMonth']!.text = _formatEditableNumber(
      profile.workingHoursMonth,
    );
  }

  ShopSustainabilityProfile _profileFromInputs() {
    return ShopSustainabilityProfile(
      monthlyRevenue: _readEditableNumber(_controllers['monthlyRevenue']!.text),
      otherRevenue: _readEditableNumber(_controllers['otherRevenue']!.text),
      fixedCosts: _readEditableNumber(_controllers['fixedCosts']!.text),
      rentCost: _readEditableNumber(_controllers['rentCost']!.text),
      payrollCost: _readEditableNumber(_controllers['payrollCost']!.text),
      utilitiesCost: _readEditableNumber(_controllers['utilitiesCost']!.text),
      suppliesCost: _readEditableNumber(_controllers['suppliesCost']!.text),
      taxesCost: _readEditableNumber(_controllers['taxesCost']!.text),
      marketingCost: _readEditableNumber(_controllers['marketingCost']!.text),
      equipmentCost: _readEditableNumber(_controllers['equipmentCost']!.text),
      cashReserve: _readEditableNumber(_controllers['cashReserve']!.text),
      workingHoursMonth: math
          .max(1, _readEditableNumber(_controllers['workingHoursMonth']!.text))
          .toDouble(),
    );
  }

  Future<void> _calculateAndOpenResults() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await _repository.save(_profileFromInputs());
      _applyProfile(saved);
      final report = _buildShopSustainabilityReport(saved);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Theme(
            data: Theme.of(context).copyWith(
              textTheme: Theme.of(context).textTheme.apply(
                fontFamily: 'Roboto',
                bodyColor: context.barberinTextPrimary,
                displayColor: context.barberinTextPrimary,
              ),
              primaryTextTheme: Theme.of(context).primaryTextTheme.apply(
                fontFamily: 'Roboto',
                bodyColor: context.barberinTextPrimary,
                displayColor: context.barberinTextPrimary,
              ),
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                fontFamily: 'Roboto',
                decoration: TextDecoration.none,
                decorationColor: Colors.transparent,
                color: context.barberinTextPrimary,
              ),
              child: Material(
                color: Colors.transparent,
                child: _SustainabilityResultsPage(report: report),
              ),
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _useCurrentMonthRevenue() {
    final appointments = _appointmentsForPeriod(
      period: _RevenuePeriod.month,
      selectedDate: widget.selectedDate,
      appointments: widget.appointments,
    );
    final summary = _buildRevenueSummary(appointments);
    _controllers['monthlyRevenue']!.text = _formatEditableNumber(
      summary.actualRevenue.toDouble(),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final customerTheme = Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.apply(
        fontFamily: 'Roboto',
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      primaryTextTheme: Theme.of(context).primaryTextTheme.apply(
        fontFamily: 'Roboto',
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
    );

    return Theme(
      data: customerTheme,
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          fontFamily: 'Roboto',
          decoration: TextDecoration.none,
          decorationColor: Colors.transparent,
        ),
        child: Material(
          color: Colors.transparent,
          child: Container(
            color: context.barberinBackground,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
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
                                      'Δείκτης βιωσιμότητας',
                                      style: _customerIntelligenceStyle(
                                        _reportsPageTitleStyle,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Βιωσιμότητα καταστήματος με βάση έσοδα, κόστη, ανθεκτικότητα και λειτουργική πίεση',
                                      style: _customerIntelligenceStyle(
                                        _reportsPageSubtitleStyle,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Expanded(
                            child: ListView(
                              physics: const BouncingScrollPhysics(),
                              children: [
                                _SustainabilityInputCard(
                                  fieldLabels: _fieldLabels,
                                  controllers: _controllers,
                                  error: _error,
                                  saving: _saving,
                                  onChanged: () => setState(() {}),
                                  onUseCurrentMonthRevenue:
                                      _useCurrentMonthRevenue,
                                  onSave: _calculateAndOpenResults,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SustainabilityInsightRow extends StatelessWidget {
  const _SustainabilityInsightRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: context.barberinTextSecondary,
              fontSize: 12.5,
            ).copyWith(fontFamily: 'Roboto'),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: context.barberinTextPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ).copyWith(fontFamily: 'Roboto'),
          ),
        ],
      ),
    );
  }
}

class _SustainabilityHero extends StatelessWidget {
  const _SustainabilityHero({required this.report});

  final _ShopSustainabilityReport report;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: context.barberinSurface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: context.barberinBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Τρέχον προφίλ καταστήματος',
            style: _customerIntelligenceStyle(_reportsHeroEyebrowStyle),
          ),
          const SizedBox(height: 12),
          Text(
            report.financialVerdict,
            style: _customerIntelligenceStyle(_reportsHeroTitleStyle),
          ),
          const SizedBox(height: 8),
          Text(
            report.summary,
            style: _customerIntelligenceStyle(_reportsHeroBodyStyle),
          ),
          const SizedBox(height: 14),
          _SustainabilityInsightRow(
            label: 'Μακροπρόθεσμη βιωσιμότητα',
            value: report.longTermViability,
          ),
          _SustainabilityInsightRow(
            label: 'Κύρια ανησυχία',
            value: report.primaryConcern,
          ),
          _SustainabilityInsightRow(
            label: 'Ισχυρότερο σημείο',
            value: report.strongestPoint,
          ),
          _SustainabilityInsightRow(
            label: 'Επόμενη κίνηση',
            value: report.nextMove,
          ),
        ],
      ),
    );
  }
}

class _SustainabilityInputCard extends StatelessWidget {
  const _SustainabilityInputCard({
    required this.fieldLabels,
    required this.controllers,
    required this.error,
    required this.saving,
    required this.onChanged,
    required this.onUseCurrentMonthRevenue,
    required this.onSave,
  });

  final Map<String, String> fieldLabels;
  final Map<String, TextEditingController> controllers;
  final String? error;
  final bool saving;
  final VoidCallback onChanged;
  final VoidCallback onUseCurrentMonthRevenue;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: context.barberinSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.barberinBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Οικονομικά καταστήματος',
            style: _customerIntelligenceStyle(_reportsSectionTitleStyle),
          ),
          const SizedBox(height: 4),
          Text(
            'Αποθήκευσε αυτά τα στοιχεία για το κατάστημα και χρησιμοποίησέ τα για την αξιολόγηση της βιωσιμότητας.',
            style: _customerIntelligenceStyle(_reportsSectionSubtitleStyle),
          ),
          const SizedBox(height: 14),
          ...fieldLabels.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: controllers[entry.key],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => onChanged(),
                style: TextStyle(color: context.barberinTextPrimary),
                decoration: _darkFieldDecoration(entry.value),
              ),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12.5,
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: saving ? null : onUseCurrentMonthRevenue,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.barberinTextPrimary,
                    side: BorderSide(color: context.barberinBorder),
                  ),
                  child: const Text('Χρήση πραγματικών εσόδων τρέχοντος μήνα'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: saving ? null : onSave,
              style: FilledButton.styleFrom(
                backgroundColor: context.barberinAccent,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              child: Text(
                saving ? 'Γίνεται υπολογισμός...' : 'Υπολογισμός βιωσιμότητας',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SustainabilityRatiosCard extends StatelessWidget {
  const _SustainabilityRatiosCard({required this.report});

  final _ShopSustainabilityReport report;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: context.barberinSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.barberinBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Βασικοί δείκτες',
            style: _customerIntelligenceStyle(_reportsSectionTitleStyle),
          ),
          const SizedBox(height: 14),
          _InlineMetricRow(
            label: 'Συνολικά έσοδα',
            value: 'EUR ${report.totalIncome.toStringAsFixed(0)}',
          ),
          _InlineMetricRow(
            label: 'Συνολικά έξοδα',
            value: 'EUR ${report.totalExpenses.toStringAsFixed(0)}',
          ),
          _InlineMetricRow(
            label: 'Καθαρό αποτέλεσμα',
            value: 'EUR ${report.net.toStringAsFixed(0)}',
          ),
          _InlineMetricRow(
            label: 'Λόγος εξόδων',
            value: '${(report.expenseRatio * 100).toStringAsFixed(0)}%',
          ),
          _InlineMetricRow(
            label: 'Λόγος μισθοδοσίας',
            value: '${(report.payrollRatio * 100).toStringAsFixed(0)}%',
          ),
          _InlineMetricRow(
            label: 'Πραγματικό ωριαίο αποτέλεσμα',
            value: 'EUR ${report.realHourly.toStringAsFixed(1)}',
          ),
        ],
      ),
    );
  }
}

class _SustainabilityDimensionCard extends StatelessWidget {
  const _SustainabilityDimensionCard({required this.dimension});

  final _SustainabilityDimension dimension;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: context.barberinSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.barberinBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  dimension.title,
                  style: _customerIntelligenceStyle(_reportsSectionTitleStyle),
                ),
              ),
              Text(
                dimension.score.toStringAsFixed(0),
                style: TextStyle(
                  color: context.barberinAccent,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ).copyWith(fontFamily: 'Roboto'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            dimension.status,
            style: _customerIntelligenceStyle(_reportsSectionSubtitleStyle),
          ),
          const SizedBox(height: 10),
          Text(
            dimension.detail,
            style: _customerIntelligenceStyle(_reportsHeroBodyStyle),
          ),
          const SizedBox(height: 8),
          Text(
            dimension.implication,
            style: _customerIntelligenceStyle(
              TextStyle(
                color: context.barberinTextSecondary,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SustainabilityRecommendationsCard extends StatelessWidget {
  const _SustainabilityRecommendationsCard({required this.recommendations});

  final List<String> recommendations;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: context.barberinSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.barberinBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Προτεινόμενες επόμενες κινήσεις',
            style: _customerIntelligenceStyle(_reportsSectionTitleStyle),
          ),
          const SizedBox(height: 12),
          ...recommendations.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(
                      Icons.circle,
                      size: 8,
                      color: context.barberinAccent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: _customerIntelligenceStyle(
                        TextStyle(
                          color: context.barberinTextPrimary,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
