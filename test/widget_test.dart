import 'package:barbero/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders Barberin privacy policy page', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: BarberoPrivacyPolicyPage()),
    );

    expect(find.text('Πολιτική απορρήτου'), findsOneWidget);
    expect(find.textContaining('Barberin'), findsWidgets);
    expect(find.text('1. Πεδίο εφαρμογής'), findsOneWidget);
  });

  testWidgets('renders theme choices in settings', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BarberinSettingsPage()));

    expect(find.text('Ρυθμίσεις'), findsOneWidget);
    expect(find.text('Σκούρα εμφάνιση'), findsOneWidget);
    expect(find.text('Ανοιχτόχρωμη εμφάνιση'), findsOneWidget);
    expect(find.text('Ραντεβού'), findsOneWidget);
  });

  testWidgets('renders settings language controls in English', (tester) async {
    addTearDown(() => barberinLanguage.value = BarberinLanguage.greek);
    barberinLanguage.value = BarberinLanguage.english;
    await tester.pumpWidget(const MaterialApp(home: BarberinSettingsPage()));

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);

    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    expect(find.text('Language selection'), findsOneWidget);
  });

  testWidgets('renders every primary tab in the light theme', (tester) async {
    final pages = <Widget>[
      BarberHomePage(
        onOpenSchedule: () {},
        onOpenProgram: () {},
        onQuickAdd: () {},
        onOpenNotifications: () {},
        selectedDate: DateTime(2026, 8, 9),
        ownerFirstName: 'Dimitrios',
        shopName: 'Barberin',
        appointments: const <Appointment>[],
        customerPhotoUrlForAppointment: (_) => '',
        onOpenCustomer: (_) {},
        onManageAppointment: (_) {},
        onQuickAddForSlot: (_) {},
      ),
      ProgramPage(
        selectedDate: DateTime(2026, 8, 9),
        entries: const <ProgramEntry>[],
        onPreviousDay: () {},
        onNextDay: () {},
        onPickDate: () {},
        onQuickAdd: () {},
        customerPhotoUrlForEntry: (_) => '',
        onOpenCustomer: (_) {},
        onManageAppointment: (_) {},
      ),
      CustomersListPage(
        customers: const <CustomerProfile>[],
        onOpenCustomer: (_) {},
        onManageCustomer: (_) {},
      ),
      RevenueReportsPage(
        selectedDate: DateTime(2026, 8, 9),
        appointments: const <Appointment>[],
        weeklySchedule: const <ScheduleDay>[],
        onOpenCustomerIntelligence: () {},
      ),
      const MoreHubPage(
        onOpenSustainabilityIndex: null,
        onOpenCustomerIntelligence: null,
        onOpenFinancialClarity: null,
        onOpenOperationalAlerts: null,
        onOpenBarberPerformance: null,
        onOpenServiceInsights: null,
        onOpenDemandInsights: null,
        onOpenBusinessSnapshot: null,
      ),
    ];

    final lightTheme = ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF7F4EF),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFFB47A2C),
        surface: Color(0xFFFFFCF8),
        surfaceContainerHighest: Color(0xFFF0EBE4),
        outline: Color(0xFFD8CEC0),
        onSurface: Color(0xFF292621),
        onSurfaceVariant: Color(0xFF6E675F),
      ),
      useMaterial3: true,
    );

    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final surfaceSize in const [Size(390, 844), Size(1024, 1366)]) {
      await tester.binding.setSurfaceSize(surfaceSize);
      for (final page in pages) {
        await tester.pumpWidget(
          MaterialApp(
            theme: lightTheme,
            home: Material(child: page),
          ),
        );
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: '$surfaceSize ${page.runtimeType}',
        );
      }
    }
  });
}
