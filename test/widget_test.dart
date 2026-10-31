import 'package:barbero/main.dart' hide Text;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

void main() {
  test('Apple EUR prices match the configured checkout prices', () {
    expect(
      barberoStoreDisplayPrice(
        productId: 'barbero_monthly',
        storePrice: '24,99 €',
        storeCurrencyCode: 'EUR',
        isAppleStore: true,
      ),
      '29,99 €',
    );
    expect(
      barberoStoreDisplayPrice(
        productId: 'barbero_yearly',
        storePrice: '249,99 €',
        storeCurrencyCode: 'EUR',
        isAppleStore: true,
      ),
      '299,99 €',
    );
    expect(
      barberoStoreDisplayPrice(
        productId: 'barbero_monthly',
        storePrice: '24,99 €',
        storeCurrencyCode: 'EUR',
        isAppleStore: false,
      ),
      '24,99 €',
    );
    expect(
      barberoStoreDisplayPrice(
        productId: 'barbero_monthly',
        storePrice: '\$29.99',
        storeCurrencyCode: 'USD',
        isAppleStore: true,
      ),
      '\$29.99',
    );
  });

  test('product offer uses corrected EUR display only on Apple', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final offer = BarberoStoreProductOffer(
      plan: BarberoBillingPlan.monthly,
      product: ProductDetails(
        id: 'barbero_monthly',
        title: 'Monthly',
        description: 'Subscription',
        price: '24,99 €',
        rawPrice: 24.99,
        currencyCode: 'EUR',
      ),
    );
    expect(offer.displayPrice, '29,99 €');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(offer.displayPrice, '24,99 €');
  });

  testWidgets('menu pages can return to the previous page or home', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                const Text('Home screen'),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(
                        body: Column(
                          children: [AppHamburgerMenu(), Text('Menu page')],
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Open menu page'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open menu page'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Πίσω'), findsOneWidget);
    await tester.tap(find.byTooltip('Πίσω'));
    await tester.pumpAndSettle();
    expect(find.text('Home screen'), findsOneWidget);

    await tester.tap(find.text('Open menu page'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Αρχική'));
    await tester.pumpAndSettle();
    expect(find.text('Home screen'), findsOneWidget);
    expect(find.text('Menu page'), findsNothing);
  });

  test('Apple sandbox subscriptions do not use production management', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    BarberoBillingSnapshot billing(String environment) =>
        BarberoBillingSnapshot(
          status: BarberoBillingStatus.active,
          selectedPlan: BarberoBillingPlan.monthly,
          planConfirmed: true,
          allowsAccess: true,
          requiresOwnerAction: false,
          monthlyPriceEur: 29.99,
          yearlyPriceEur: 299.99,
          yearlySavingsEur: 59.89,
          storeEnvironment: environment,
        );

    expect(barberoIsAppleSandboxSubscription(billing('sandbox')), isTrue);
    expect(barberoIsAppleSandboxSubscription(billing('production')), isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(barberoIsAppleSandboxSubscription(billing('sandbox')), isFalse);
  });

  test('yearly savings use the storefront prices, not a fixed euro amount', () {
    BarberoStoreProductOffer offer(
      BarberoBillingPlan plan,
      double amount,
      String currency,
    ) => BarberoStoreProductOffer(
      plan: plan,
      product: ProductDetails(
        id: plan == BarberoBillingPlan.monthly
            ? 'barbero_monthly'
            : 'barbero_yearly',
        title: 'Test',
        description: 'Test',
        price: '$amount $currency',
        rawPrice: amount,
        currencyCode: currency,
      ),
    );

    final greekMonthly = offer(BarberoBillingPlan.monthly, 29.99, 'EUR');
    final greekYearly = offer(BarberoBillingPlan.yearly, 299.99, 'EUR');
    expect(
      barberoStoreYearlySavingsLabel(
        monthlyOffer: greekMonthly,
        yearlyOffer: greekYearly,
      ),
      'Εξοικονόμηση 17%',
    );
    expect(
      barberoStoreYearlySavingsLabel(
        monthlyOffer: greekMonthly,
        yearlyOffer: offer(BarberoBillingPlan.yearly, 249.99, 'USD'),
      ),
      '',
    );
    expect(
      barberoStoreYearlySavingsLabel(
        monthlyOffer: null,
        yearlyOffer: greekYearly,
      ),
      '',
    );
  });

  test('restored purchase failure does not claim a new purchase', () {
    expect(
      barberoStorePurchaseFailureMessage(PurchaseStatus.restored),
      contains('επαναφορά'),
    );
    expect(
      barberoStorePurchaseFailureMessage(PurchaseStatus.restored),
      isNot(contains('αγορά ολοκληρώθηκε')),
    );
    expect(
      barberoStorePurchaseFailureMessage(PurchaseStatus.purchased),
      contains('αγορά ολοκληρώθηκε'),
    );
  });

  test('unsolicited StoreKit restores cannot attach to another shop', () {
    final pending = <Map<String, dynamic>>[
      <String, dynamic>{
        'shopId': 'shop_a',
        'acknowledged': false,
        'purchase': <String, dynamic>{
          'status': 'purchased',
          'productId': 'barbero_monthly',
          'purchaseId': 'transaction_a',
        },
      },
      <String, dynamic>{
        'shopId': 'shop_b',
        'acknowledged': false,
        'purchase': <String, dynamic>{
          'status': 'restored',
          'productId': 'barbero_monthly',
          'purchaseId': 'transaction_b',
        },
      },
    ];
    bool accepts(String? shopId, String purchaseId, {bool requested = false}) =>
        barberoShouldProcessRestoredPurchase(
          shopId: shopId,
          productId: 'barbero_monthly',
          purchaseId: purchaseId,
          verificationData: '',
          restoreRequested: requested,
          pendingPurchases: pending,
        );

    expect(accepts('shop_b', 'transaction_b'), isFalse);
    expect(accepts('shop_b', 'transaction_a'), isFalse);
    expect(accepts('shop_a', 'transaction_b'), isFalse);
    expect(accepts(null, 'transaction_a', requested: true), isFalse);
    expect(accepts('shop_a', 'transaction_a'), isTrue);
    expect(accepts('shop_b', 'transaction_b', requested: true), isTrue);
  });

  test('legacy restore retries are skipped only on Apple platforms', () {
    final restored = <String, dynamic>{
      'shopId': 'shop_a',
      'purchase': <String, dynamic>{'status': 'restored'},
    };
    final purchased = <String, dynamic>{
      'shopId': 'shop_a',
      'purchase': <String, dynamic>{'status': 'purchased'},
    };
    expect(
      barberoShouldRetryPendingPurchase(
        restored,
        'shop_a',
        usesAppleStore: true,
      ),
      isFalse,
    );
    expect(
      barberoShouldRetryPendingPurchase(
        restored,
        'shop_a',
        usesAppleStore: false,
      ),
      isTrue,
    );
    expect(
      barberoShouldRetryPendingPurchase(
        purchased,
        'shop_a',
        usesAppleStore: true,
      ),
      isTrue,
    );
    expect(
      barberoShouldRetryPendingPurchase(
        purchased,
        'shop_b',
        usesAppleStore: true,
      ),
      isFalse,
    );
  });

  testWidgets('Firebase startup failure shows a recoverable screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      const BarberinApp(firebaseStartupError: 'missing-firebase-options'),
    );

    expect(find.text('Το Barberin δεν μπόρεσε να ξεκινήσει'), findsOneWidget);
    expect(find.text('Δοκίμασε ξανά'), findsOneWidget);
    expect(find.byType(AppFlowPage), findsNothing);
  });

  test(
    'StoreKit 2 JWS is replaced with the app receipt for the backend',
    () async {
      expect(
        await barberoAppleReceiptForBackend(
          'header.payload.signature',
          () async => 'receipt-base64',
        ),
        'receipt-base64',
      );
      expect(
        await barberoAppleReceiptForBackend(
          'receipt-base64',
          () async => throw StateError('should not load'),
        ),
        'receipt-base64',
      );
      await expectLater(
        barberoAppleReceiptForBackend(
          'header.payload.signature',
          () async => '',
        ),
        throwsStateError,
      );
      var loads = 0;
      var refreshes = 0;
      expect(
        await barberoAppleReceiptForBackend(
          'header.payload.signature',
          () async => ++loads == 1 ? '' : 'refreshed-receipt',
          refreshReceipt: () async => refreshes++,
        ),
        'refreshed-receipt',
      );
      expect(loads, 2);
      expect(refreshes, 1);
    },
  );

  test(
    'session resolution exposes a missing shop without leaking other errors',
    () {
      expect(
        barberoSessionFailureReason(
          '{"message":"forbidden","details":"barbero-session-not-found"}',
        ),
        'barbero-session-not-found',
      );
      expect(
        barberoSessionFailureReason(
          '{"message":"forbidden","details":"invalid-auth-token"}',
        ),
        'forbidden',
      );
      expect(barberoSessionFailureReason('not-json'), 'session-resolve-failed');
    },
  );

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
