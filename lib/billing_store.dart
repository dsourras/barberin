part of 'main.dart';

const String _barberoMonthlyProductId = 'barbero_monthly';
const String _barberoYearlyProductId = 'barbero_yearly';

class BarberoStoreProductOffer {
  const BarberoStoreProductOffer({
    required this.plan,
    required this.product,
  });

  final BarberoBillingPlan plan;
  final ProductDetails product;

  String get id => product.id;
  String get displayPrice => product.price;
}

class BarberoStoreBillingService {
  BarberoStoreBillingService._();

  static final BarberoStoreBillingService instance =
      BarberoStoreBillingService._();

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final ValueNotifier<List<BarberoStoreProductOffer>> offers =
      ValueNotifier<List<BarberoStoreProductOffer>>(
        const <BarberoStoreProductOffer>[],
      );
  final ValueNotifier<bool> isStoreAvailable = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isPurchasePending = ValueNotifier<bool>(false);
  final ValueNotifier<String?> lastStoreError = ValueNotifier<String?>(null);

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) {
      await refreshProducts();
      return;
    }
    _isInitialized = true;
    _purchaseSubscription = _inAppPurchase.purchaseStream.listen(
      _handlePurchaseUpdates,
      onDone: () {
        _purchaseSubscription?.cancel();
        _purchaseSubscription = null;
        _isInitialized = false;
      },
      onError: (_) {
        lastStoreError.value = 'Unable to listen for store purchases.';
        isPurchasePending.value = false;
      },
    );
    await refreshProducts();
  }

  Future<void> dispose() async {
    await _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
    _isInitialized = false;
  }

  Future<void> refreshProducts() async {
    final available = await _inAppPurchase.isAvailable();
    isStoreAvailable.value = available;
    if (!available) {
      offers.value = const <BarberoStoreProductOffer>[];
      lastStoreError.value = 'Store is currently unavailable on this device.';
      return;
    }
    final response = await _inAppPurchase.queryProductDetails(const <String>{
      _barberoMonthlyProductId,
      _barberoYearlyProductId,
    });
    if (response.error != null) {
      offers.value = const <BarberoStoreProductOffer>[];
      lastStoreError.value = response.error!.message;
      return;
    }
    final loadedOffers =
        response.productDetails.map((product) {
          return BarberoStoreProductOffer(
            plan:
                product.id == _barberoYearlyProductId
                    ? BarberoBillingPlan.yearly
                    : BarberoBillingPlan.monthly,
            product: product,
          );
        }).toList(growable: false)
          ..sort((left, right) {
            if (left.plan == right.plan) {
              return 0;
            }
            return left.plan == BarberoBillingPlan.monthly ? -1 : 1;
          });
    offers.value = loadedOffers;
    lastStoreError.value =
        response.notFoundIDs.isNotEmpty
            ? 'Some subscription products are not available in the store setup yet.'
            : null;
  }

  BarberoStoreProductOffer? offerForPlan(BarberoBillingPlan plan) {
    try {
      return offers.value.firstWhere((item) => item.plan == plan);
    } catch (_) {
      return null;
    }
  }

  Future<void> purchasePlan(BarberoBillingPlan plan) async {
    await initialize();
    final offer = offerForPlan(plan);
    if (offer == null) {
      throw Exception('missing-store-product');
    }
    isPurchasePending.value = true;
    lastStoreError.value = null;
    final purchaseParam = PurchaseParam(productDetails: offer.product);
    final launched = await _inAppPurchase.buyNonConsumable(
      purchaseParam: purchaseParam,
    );
    if (!launched) {
      isPurchasePending.value = false;
      throw Exception('purchase-flow-not-started');
    }
  }

  Future<void> restorePurchases() async {
    await initialize();
    await _inAppPurchase.restorePurchases();
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    for (final purchaseDetails in purchaseDetailsList) {
      switch (purchaseDetails.status) {
        case PurchaseStatus.pending:
          isPurchasePending.value = true;
          break;
        case PurchaseStatus.error:
          isPurchasePending.value = false;
          lastStoreError.value =
              purchaseDetails.error?.message ??
              'The store purchase could not be completed.';
          break;
        case PurchaseStatus.canceled:
          isPurchasePending.value = false;
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          try {
            await _submitVerifiedPurchaseToBackend(purchaseDetails);
            lastStoreError.value = null;
          } catch (_) {
            lastStoreError.value =
                'Purchase completed, but the shop entitlement could not be updated yet.';
          } finally {
            isPurchasePending.value = false;
          }
          break;
      }

      if (purchaseDetails.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(purchaseDetails);
      }
    }
  }

  Future<void> _submitVerifiedPurchaseToBackend(
    PurchaseDetails purchaseDetails,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    final session = currentBarberoSession.value;
    if (user == null || session == null || !session.isOwner) {
      throw Exception('missing-owner-billing-context');
    }
    final plan =
        purchaseDetails.productID == _barberoYearlyProductId
            ? BarberoBillingPlan.yearly
            : BarberoBillingPlan.monthly;
    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse(
        'https://europe-west1-barbero-88d00.cloudfunctions.net/barberoProcessStorePurchase',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
          'idToken': idToken,
          'shopId': session.shopId,
          'purchase': {
          'platform':
              defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
          'productId': purchaseDetails.productID,
          'selectedPlan': plan == BarberoBillingPlan.yearly ? 'yearly' : 'monthly',
          'purchaseId': purchaseDetails.purchaseID ?? '',
          'transactionDate': purchaseDetails.transactionDate ?? '',
          'status': purchaseDetails.status.name,
          'verificationData': {
            'source': purchaseDetails.verificationData.source,
            'serverVerificationData':
                purchaseDetails.verificationData.serverVerificationData,
            'localVerificationData':
                purchaseDetails.verificationData.localVerificationData,
          },
        },
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('backend-purchase-processing-failed');
    }
    final decoded = jsonDecode(response.body);
    final billing = decoded is Map<String, dynamic> ? decoded['billing'] : null;
    if (billing is! Map) {
      throw Exception('invalid-billing-response');
    }
    currentBarberoBilling.value = BarberoBillingSnapshot.fromJson(
      billing.cast<String, dynamic>(),
    );
  }
}
