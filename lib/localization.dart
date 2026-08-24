part of 'main.dart';

enum BarberinLanguage { greek, english }

final ValueNotifier<BarberinLanguage> barberinLanguage =
    ValueNotifier<BarberinLanguage>(BarberinLanguage.greek);

const String _barberinLanguageStorageKey = 'barberin_language_v1';

Future<void> loadBarberinLanguage() async {
  final prefs = await SharedPreferences.getInstance();
  barberinLanguage.value = prefs.getString(_barberinLanguageStorageKey) == 'en'
      ? BarberinLanguage.english
      : BarberinLanguage.greek;
}

Future<void> setBarberinLanguage(BarberinLanguage language) async {
  barberinLanguage.value = language;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    _barberinLanguageStorageKey,
    language == BarberinLanguage.english ? 'en' : 'el',
  );
}

bool get barberinUsesEnglish =>
    barberinLanguage.value == BarberinLanguage.english;

String barberinLabel(String greek, String english) {
  return barberinUsesEnglish ? english : greek;
}

String _decodeBarberinTranslationKey(String value) {
  return value.replaceAllMapped(
    RegExp(r'\\u\{([0-9a-fA-F]+)\}'),
    (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16)),
  );
}

Map<String, String>? _barberinTranslationLookup;

const Map<String, String> _barberinEnglishOverrides = <String, String>{
  'Πραγματικά': 'Actual',
  'Κλεισμένα': 'Booked',
  '\u{388}\u{3C3}\u{3BF}\u{3B4}\u{3B1}': 'Revenue',
  '\u{395}\u{3A0}\u{399}\u{3A3}\u{39A}\u{39F}\u{3A0}\u{397}': 'OVERVIEW',
  '\u{395}\u{3A0}\u{39F}\u{39C}\u{395}\u{39D}\u{391} \u{3A1}\u{391}\u{39D}\u{3A4}\u{395}\u{392}\u{39F}\u{3A5}':
      'UPCOMING APPOINTMENTS',
  '\u{395}\u{3C3}\u{3BF}\u{3B4}\u{3B1}': 'Revenue',
  '\u{3A1}\u{3B1}\u{3BD}\u{3C4}\u{3B5}\u{3B2}\u{3BF}\u{3CD}': 'Appointments',
  '\u{3A0}\u{3C1}\u{3CC}\u{3B3}\u{3C1}\u{3B1}\u{3BC}\u{3BC}\u{3B1}': 'Schedule',
  '\u{3A0}\u{3B5}\u{3BB}\u{3AC}\u{3C4}\u{3B5}\u{3C2}': 'Customers',
  '\u{3A0}\u{3B5}\u{3C1}\u{3B9}\u{3C3}\u{3C3}\u{3CC}\u{3C4}\u{3B5}\u{3C1}\u{3B1}':
      'More',
  '\u{39D}\u{3AD}\u{3BF} \u{3C1}\u{3B1}\u{3BD}\u{3C4}\u{3B5}\u{3B2}\u{3BF}\u{3CD}':
      'New appointment',
  '\u{395}\u{3C0}\u{3B9}\u{3C3}\u{3C4}\u{3C1}\u{3BF}\u{3C6}\u{3AD}\u{3C2}':
      'Return rate',
  '\u{391}\u{3C5}\u{3C4}\u{3AC} \u{3C3}\u{3C5}\u{3BC}\u{3B2}\u{3B1}\u{3AF}\u{3BD}\u{3BF}\u{3C5}\u{3BD} \u{3C3}\u{3AE}\u{3BC}\u{3B5}\u{3C1}\u{3B1} \u{3C3}\u{3C4}\u{3BF}':
      "Here's what's happening today at",
  '\u{39D}\u{3AD}\u{3BF}\u{3B9} \u{3C0}\u{3B5}\u{3BB}\u{3AC}\u{3C4}\u{3B5}\u{3C2}':
      'New customers',
  '\u{391}\u{3BD}\u{3B1}\u{3C6}\u{3BF}\u{3C1}\u{3AD}\u{3C2}': 'Reports',
  '\u{395}\u{3C0}\u{3B9}\u{3B2}\u{3B5}\u{3B2}\u{3B1}\u{3B9}\u{3C9}\u{3BC}\u{3AD}\u{3BD}\u{3BF}':
      'Confirmed',
  '\u{391}\u{3BA}\u{3C5}\u{3C1}\u{3C9}\u{3BC}\u{3AD}\u{3BD}\u{3BF}':
      'Cancelled',
  '\u{3A7}\u{3C9}\u{3C1}\u{3AF}\u{3C2} \u{3B5}\u{3BC}\u{3C6}\u{3AC}\u{3BD}\u{3B9}\u{3C3}\u{3B7}':
      'No-show',
  '\u{394}\u{3B9}\u{3B1}\u{3B8}\u{3AD}\u{3C3}\u{3B9}\u{3BC}\u{3BF} slot':
      'Available slot',
  '\u{39A}\u{3BB}\u{3B5}\u{3B9}\u{3C3}\u{3C4}\u{3CC} slot': 'Closed slot',
  '\u{395}\u{3BD}\u{3B5}\u{3C1}\u{3B3}\u{3AD}\u{3C2} \u{3B7}\u{3BC}\u{3AD}\u{3C1}\u{3B5}\u{3C2}':
      'Active days',
  '\u{397}\u{3BC}\u{3AD}\u{3C1}\u{3B1}': 'Day',
  '\u{39C}\u{3AE}\u{3BD}\u{3B1}\u{3C2}': 'Month',
  '\u{395}\u{3C4}\u{3BF}\u{3C2}': 'Year',
  '\u{3A0}\u{3AF}\u{3C3}\u{3C9}': 'Back',
  '\u{3A1}\u{3C5}\u{3B8}\u{3BC}\u{3AF}\u{3C3}\u{3B5}\u{3B9}\u{3C2}': 'Settings',
  '\u{39A}\u{3AD}\u{3BD}\u{3C4}\u{3C1}\u{3BF} \u{3B2}\u{3BF}\u{3AE}\u{3B8}\u{3B5}\u{3B9}\u{3B1}\u{3C2}':
      'Help center',
  'Κέντρο Βοήθειας': 'Help center',
  '\u{391}\u{3C0}\u{3BF}\u{3C3}\u{3CD}\u{3BD}\u{3B4}\u{3B5}\u{3C3}\u{3B7}':
      'Log out',
  '\u{3A0}\u{3BF}\u{3BB}\u{3B9}\u{3C4}\u{3B9}\u{3BA}\u{3AE} \u{3B1}\u{3C0}\u{3BF}\u{3C1}\u{3C1}\u{3AE}\u{3C4}\u{3BF}\u{3C5}':
      'Privacy policy',
  '\u{39F}\u{3C1}\u{3BF}\u{3B9} \u{3BA}\u{3B1}\u{3B9} \u{3C0}\u{3C1}\u{3BF}\u{3CB}\u{3C0}\u{3BF}\u{3B8}\u{3AD}\u{3C3}\u{3B5}\u{3B9}\u{3C2}':
      'Terms and conditions',
  '\u{391}\u{3C0}\u{3BF}\u{3C3}\u{3CD}\u{3BD}\u{3B4}\u{3B5}\u{3C3}\u{3B7} \u{3BB}\u{3BF}\u{3B3}\u{3B1}\u{3C1}\u{3B9}\u{3B1}\u{3C3}\u{3BC}\u{3BF}\u{3CD}':
      'Delete account',
};

Map<String, String> _barberinTranslations() {
  return _barberinTranslationLookup ??= <String, String>{
    for (final entry in _barberinEnglishTranslations.entries)
      _decodeBarberinTranslationKey(entry.key): entry.value,
  };
}

String barberinTranslate(String value) {
  if (!barberinUsesEnglish) {
    return value;
  }
  final override = _barberinEnglishOverrides[value];
  if (override != null) {
    return override;
  }
  final exact = _barberinTranslations()[value];
  if (exact != null) {
    return exact;
  }
  return _translateBarberinDynamicText(value);
}

String _translateBarberinDynamicText(String value) {
  if (value.startsWith(
    'Το Barberin μπορεί να επεξεργάζεται δεδομένα λογαριασμού',
  )) {
    return 'The Barberin app may process account data such as names, email addresses, phone numbers, profile images, identity identifiers and role assignments. It may also process shop data such as shop name, schedule settings, prices, barber profiles, service specialties, closed slots, operational notes, reports and notification badges. It may additionally process customer information entered by the shop, such as appointment history, selected services, preferences, notes, phone numbers, email addresses and profile images, when the shop chooses to store them.';
  }
  if (value.startsWith('Διατηρούμε ενεργά λειτουργικά δεδομένα')) {
    return 'We retain active operational data while the relevant shop account remains active and the information is needed for scheduling, customer management, reports, support, security or legal compliance. When the owner requests deletion of a shop account, active data may be removed from active flows and placed in a limited deletion archive for controlled retention, review, dispute management, fraud prevention, recovery checks or legal compliance. When a team member deletes an account, the user access is removed, while limited historical business records may remain in anonymous or operational form to preserve appointment history and report accuracy.';
  }
  var translated = value;
  const dynamicPhrases = <String, String>{
    'Τα πραγματικά έσοδα είναι': 'Actual revenue is',
    'Τα έξοδα καταναλώνουν το': 'Expenses consume',
    'Το τρέχον αποθεματικό καλύπτει περίπου':
        'The current cash reserve covers approximately',
    'Η μισθοδοσία απορροφά το': 'Payroll absorbs',
    'Έσοδα ': 'Revenue ',
    'έναντι εξόδων': 'versus expenses',
    'αφήνουν βιώσιμο μηνιαίο αποτέλεσμα':
        'leave a sustainable monthly result of',
    ' ενεργοί πελάτες αυτή την περίοδο. Οι ': ' active customers this period. ',
    ' επιστρέφουν, με μέσο όρο ': ' return, averaging ',
    ' επισκέψεις ο καθένας.': ' visits each.',
    'κλεισμένα ραντεβού σε': 'booked appointments across',
    ' ενεργές ημέρες. Η ': ' active days. The ',
    ' είναι αυτή τη στιγμή η πιο πολυσύχναστη ημέρα.':
        ' is currently the busiest day.',
    ' επιχειρησιακές ειδοποιήσεις είναι ενεργές για αυτή την περίοδο.':
        ' business notices are active for this period.',
    ' barber είναι ενεργός': ' barber is active',
    ' barber είναι ενεργοί': ' barbers are active',
    ' προηγείται αυτή τη στιγμή στα πραγματικά έσοδα.':
        ' currently leads actual revenue.',
    ' προηγείται στη ζήτηση, ενώ ': ' leads demand, while ',
    ' προηγείται στα πραγματικά έσοδα.': ' leads actual revenue.',
    'Καταγράφηκαν ': 'Recorded ',
    ' ακυρώσεις σε αυτή την περίοδο. Το ποσοστό ακυρώσεων είναι ':
        ' cancellations in this period. The cancellation rate is ',
    'Το σημερινό πρόγραμμα έχει ακόμη κενό περίπου ':
        "Today's schedule still has about ",
    ' ώρες. Ίσως χρειάζεται υπενθύμιση ή επιπλέον κρατήσεις.':
        ' hours. It may need a reminder or additional bookings.',
    ' πελάτες που επέστρεφαν δεν έχουν έρθει εδώ και τουλάχιστον 45 ημέρες. Πρώτα ονόματα για επαναπροσέγγιση: ':
        ' returning customers have not visited for at least 45 days. First names to re-engage: ',
    'Αυτές οι ημέρες δείχνουν αυτή τη στιγμή πολύ χαμηλή κίνηση: ':
        'These days currently show very low traffic: ',
    'Δωρεάν δοκιμή ενός μήνα και μετά ': 'One-month free trial, then ',
    '1 μήνας δωρεάν δοκιμή, μετά ': '1 month free trial, then ',
    'Εξοικονόμηση ': 'Savings ',
    'Η δοκιμή λήγει στις ': 'Trial ends on ',
    'Συγχωνεύτηκε με τον πελάτη ': 'Merged with customer ',
    'Να αφαιρεθεί η ': 'Remove ',
    ' από αυτό το κατάστημα;': ' from this shop?',
  };
  for (final entry in dynamicPhrases.entries) {
    translated = translated.replaceAll(entry.key, entry.value);
  }
  final mappedPhrases = _barberinTranslations().entries.toList()
    ..sort((left, right) => right.key.length.compareTo(left.key.length));
  for (final entry in mappedPhrases) {
    if (entry.key.length >= 3 && translated.contains(entry.key)) {
      translated = translated.replaceAll(entry.key, entry.value);
    }
  }
  const replacements = <String, String>{
    'Καλημέρα': 'Good morning',
    'Καλό απόγευμα': 'Good afternoon',
    'Καλησπέρα': 'Good evening',
    'Ιδιοκτήτη': 'Owner',
    'Ιδιοκτήτης': 'Owner',
    'Ομάδα': 'Team',
    'τρέχουσα κατάσταση': 'current status',
    'Τρέχουσα κατάσταση': 'Current status',
    'Τελευταία επίσκεψη': 'Last visit',
    'Ενεργοί': 'Active',
    'ενεργοί': 'active',
    'ενεργός': 'active',
    'ολοκληρωμένα': 'completed',
    'Ολοκληρωμένα': 'Completed',
    'κλεισμένα': 'booked',
    'Κλεισμένα': 'Booked',
    'υπηρεσίες': 'services',
    'Υπηρεσίες': 'Services',
    'κρατήσεις': 'bookings',
    'Κρατήσεις': 'Bookings',
    'περίοδο': 'period',
    'Περίοδο': 'Period',
    'ποσοστό': 'rate',
    'Ποσοστό': 'Rate',
    'επιστρέφουν': 'return',
    'Επιστρέφουν': 'Return',
    'πραγματικά έσοδα': 'actual revenue',
    'Πραγματικά έσοδα': 'Actual revenue',
    'εκτιμώμενα έσοδα': 'estimated revenue',
    'Εκτιμώμενα έσοδα': 'Estimated revenue',
    'επιχειρησιακές ειδοποιήσεις': 'business notices',
    'Επιχειρησιακές ειδοποιήσεις': 'Business notices',
    'χαμηλή κίνηση': 'low traffic',
    'Χαμηλή κίνηση': 'Low traffic',
    'πιο πολυσύχναστη': 'busiest',
    'Πιο πολυσύχναστη': 'Busiest',
    'Σήμερα': 'Today',
    'Αύριο': 'Tomorrow',
    'Χθες': 'Yesterday',
    'ραντεβού': 'appointments',
    'Ραντεβού': 'Appointments',
    'πελάτες': 'customers',
    'Πελάτες': 'Customers',
    'πελάτη': 'customer',
    'Πελάτη': 'Customer',
    'επισκέψεις': 'visits',
    'Επισκέψεις': 'Visits',
    'λεπτά': 'minutes',
    'ημέρες': 'days',
    'Ημέρες': 'Days',
    'ημέρα': 'day',
    'Ημέρα': 'Day',
    'ώρα': 'hour',
    'ώρες': 'hours',
    'διαθέσιμο': 'available',
    'Διαθέσιμο': 'Available',
    'κλειστό': 'closed',
    'Κλειστό': 'Closed',
    'χωρίς εμφάνιση': 'no-show',
    'Χωρίς εμφάνιση': 'No-show',
    'ακυρώσεις': 'cancellations',
    'Ακυρώσεις': 'Cancellations',
    'ενεργές': 'active',
    'Ενεργές': 'Active',
    'από': 'from',
    'για': 'for',
    'με': 'with',
    'και': 'and',
    'σε': 'in',
    'το': 'the',
    'την': 'the',
    'του': 'of the',
    'της': 'of the',
  };
  for (final entry in replacements.entries) {
    translated = translated.replaceAll(entry.key, entry.value);
  }
  return translated;
}

String englishDateLabel(DateTime value, {bool includeYear = false}) {
  const weekdays = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final base =
      '${weekdays[value.weekday - 1]}, ${months[value.month - 1]} '
      '${value.day}';
  return includeYear ? '$base, ${value.year}' : base;
}

String barberinDateLabel(DateTime value, {bool includeYear = false}) {
  return barberinUsesEnglish
      ? englishDateLabel(value, includeYear: includeYear)
      : greekDateLabel(value, includeYear: includeYear);
}

String barberinDateLabelFromRaw(String raw, {bool includeYear = false}) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw;
  }
  return barberinDateLabel(parsed, includeYear: includeYear);
}

class Text extends StatelessWidget {
  const Text(
    String this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.semanticsIdentifier,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : textSpan = null;

  const Text.rich(
    InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.semanticsIdentifier,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : data = null;

  final String? data;
  final InlineSpan? textSpan;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final String? semanticsIdentifier;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) {
    if (textSpan != null) {
      return material.Text.rich(
        textSpan!,
        style: style,
        strutStyle: strutStyle,
        textAlign: textAlign,
        textDirection: textDirection,
        locale: locale,
        softWrap: softWrap,
        overflow: overflow,
        textScaler: textScaler,
        maxLines: maxLines,
        semanticsLabel: semanticsLabel,
        semanticsIdentifier: semanticsIdentifier,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        selectionColor: selectionColor,
      );
    }
    return material.Text(
      barberinTranslate(data!),
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
      semanticsIdentifier: semanticsIdentifier,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}
