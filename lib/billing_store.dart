part of 'main.dart';

const String _barberoMonthlyProductId = 'barbero_monthly';
const String _barberoYearlyProductId = 'barbero_yearly';
const String _barberinStorePackageId = 'com.barberin.app';
const String _barberoPendingPurchasesStorageKey =
    'barbero_pending_store_purchases_v1';

bool get _barberoUsesAppleStore =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

bool get _barberoUsesNativeStore =>
    defaultTargetPlatform == TargetPlatform.android || _barberoUsesAppleStore;

class BarberoStoreProductOffer {
  const BarberoStoreProductOffer({required this.plan, required this.product});

  final BarberoBillingPlan plan;
  final ProductDetails product;

  String get id => product.id;
  String get displayPrice => product.price;

  bool get isNativeFreeTrialOffer {
    if (product is GooglePlayProductDetails) {
      final androidProduct = product as GooglePlayProductDetails;
      final subscriptionIndex = androidProduct.subscriptionIndex;
      final subscriptionOffers =
          androidProduct.productDetails.subscriptionOfferDetails;
      if (subscriptionIndex == null ||
          subscriptionOffers == null ||
          subscriptionIndex >= subscriptionOffers.length) {
        return false;
      }
      final pricingPhases = subscriptionOffers[subscriptionIndex].pricingPhases;
      return pricingPhases.isNotEmpty &&
          pricingPhases.first.priceAmountMicros == 0;
    }
    if (product is AppStoreProductDetails) {
      final introductoryPrice =
          (product as AppStoreProductDetails).skProduct.introductoryPrice;
      return introductoryPrice?.paymentMode ==
          SKProductDiscountPaymentMode.freeTrail;
    }
    if (product is AppStoreProduct2Details) {
      final offers =
          (product as AppStoreProduct2Details)
              .sk2Product
              .subscription
              ?.promotionalOffers ??
          const <SK2SubscriptionOffer>[];
      return offers.any(
        (offer) =>
            offer.type == SK2SubscriptionOfferType.introductory &&
            offer.paymentMode == SK2SubscriptionOfferPaymentMode.freeTrial,
      );
    }
    return false;
  }
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
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  bool _isInitialized = false;
  Future<void> _processingLock = Future<void>.value();

  Future<void> initialize() async {
    if (!_barberoUsesNativeStore) {
      await refreshProducts();
      return;
    }
    if (_isInitialized) {
      await refreshProducts();
      await _retryPendingPurchases();
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
        lastStoreError.value =
            'Δεν ήταν δυνατή η παρακολούθηση των αγορών του καταστήματος.';
        isPurchasePending.value = false;
      },
    );
    await refreshProducts();
    await _retryPendingPurchases();
  }

  Future<void> dispose() async {
    await _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
    _isInitialized = false;
  }

  Future<void> refreshProducts() async {
    if (!_barberoUsesNativeStore) {
      offers.value = const <BarberoStoreProductOffer>[];
      isStoreAvailable.value = false;
      lastStoreError.value =
          'Οι αγορές συνδρομών γίνονται από Android, iPhone ή Mac.';
      return;
    }
    final available = await _inAppPurchase.isAvailable();
    isStoreAvailable.value = available;
    if (!available) {
      offers.value = const <BarberoStoreProductOffer>[];
      lastStoreError.value =
          'Το κατάστημα δεν είναι διαθέσιμο αυτή τη στιγμή σε αυτή τη συσκευή.';
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
        response.productDetails
            .map((product) {
              return BarberoStoreProductOffer(
                plan: product.id == _barberoYearlyProductId
                    ? BarberoBillingPlan.yearly
                    : BarberoBillingPlan.monthly,
                product: product,
              );
            })
            .toList(growable: false)
          ..sort((left, right) {
            if (left.plan == right.plan) {
              return 0;
            }
            return left.plan == BarberoBillingPlan.monthly ? -1 : 1;
          });
    offers.value = loadedOffers;
    lastStoreError.value = response.notFoundIDs.isNotEmpty
        ? 'Ορισμένα προϊόντα συνδρομής δεν είναι ακόμη διαθέσιμα στη ρύθμιση του καταστήματος.'
        : null;
  }

  BarberoStoreProductOffer? offerForPlan(BarberoBillingPlan plan) {
    final matchingOffers = offers.value
        .where((item) => item.plan == plan)
        .toList(growable: false);
    if (matchingOffers.isEmpty) {
      return null;
    }
    try {
      return matchingOffers.firstWhere((item) => !item.isNativeFreeTrialOffer);
    } catch (_) {
      return matchingOffers.first;
    }
  }

  BarberoStoreProductOffer? nativeTrialOfferForPlan(BarberoBillingPlan plan) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      // StoreKit applies an eligible introductory offer configured in App Store
      // Connect when the base subscription product is purchased.
      return offerForPlan(plan);
    }
    try {
      return offers.value.firstWhere(
        (item) => item.plan == plan && item.isNativeFreeTrialOffer,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> purchasePlan(
    BarberoBillingPlan plan, {
    bool requireFreeTrial = false,
  }) async {
    if (!_barberoUsesNativeStore) {
      throw Exception('native-store-required');
    }
    await initialize();
    final offer = requireFreeTrial
        ? nativeTrialOfferForPlan(plan)
        : offerForPlan(plan);
    if (offer == null) {
      throw Exception(
        requireFreeTrial
            ? 'missing-native-free-trial-offer'
            : 'missing-store-product',
      );
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
    if (!_barberoUsesNativeStore) {
      throw Exception('native-store-required');
    }
    await initialize();
    await _inAppPurchase.restorePurchases();
  }

  Future<void> openManageSubscription(BarberoBillingPlan plan) async {
    if (!_barberoUsesNativeStore) {
      throw Exception('subscription-management-on-native-device-required');
    }
    final productId = plan == BarberoBillingPlan.yearly
        ? _barberoYearlyProductId
        : _barberoMonthlyProductId;
    final uri = _barberoUsesAppleStore
        ? Uri.parse('https://apps.apple.com/account/subscriptions')
        : Uri.parse(
            'https://play.google.com/store/account/subscriptions'
            '?sku=$productId&package=$_barberinStorePackageId',
          );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      throw Exception('manage-subscription-unavailable');
    }
  }

  Future<Map<String, dynamic>> _handlePurchaseWithOutbox(
    PurchaseDetails purchaseDetails,
  ) async {
    final pending = await _upsertPendingPurchase(purchaseDetails);
    if (pending['acknowledged'] != true) {
      await _submitPendingPurchaseToBackend(pending);
      await _markPendingPurchaseAcknowledged(pending['key'] as String);
    }
    return pending;
  }

  Future<List<Map<String, dynamic>>> _loadPendingPurchases() async {
    final raw = await _secureStorage.read(
      key: _barberoPendingPurchasesStorageKey,
    );
    if (raw == null || raw.trim().isEmpty) {
      return <Map<String, dynamic>>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <Map<String, dynamic>>[];
      }
      return decoded
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList(growable: true);
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _savePendingPurchases(
    List<Map<String, dynamic>> purchases,
  ) async {
    if (purchases.isEmpty) {
      await _secureStorage.delete(key: _barberoPendingPurchasesStorageKey);
      return;
    }
    await _secureStorage.write(
      key: _barberoPendingPurchasesStorageKey,
      value: jsonEncode(purchases),
    );
  }

  Map<String, dynamic> _purchasePayloadFromDetails(
    PurchaseDetails purchaseDetails,
  ) {
    final session = currentBarberoSession.value;
    if (session == null || !session.isOwner) {
      throw Exception('missing-owner-billing-context');
    }
    final plan = purchaseDetails.productID == _barberoYearlyProductId
        ? BarberoBillingPlan.yearly
        : BarberoBillingPlan.monthly;
    return <String, dynamic>{
      'shopId': session.shopId,
      'purchase': <String, dynamic>{
        'platform': defaultTargetPlatform == TargetPlatform.macOS
            ? 'macos'
            : _barberoUsesAppleStore
            ? 'ios'
            : 'android',
        'productId': purchaseDetails.productID,
        'selectedPlan': plan == BarberoBillingPlan.yearly
            ? 'yearly'
            : 'monthly',
        'purchaseId': purchaseDetails.purchaseID ?? '',
        'transactionDate': purchaseDetails.transactionDate ?? '',
        'status': purchaseDetails.status.name,
        'verificationData': <String, dynamic>{
          'source': purchaseDetails.verificationData.source,
          'serverVerificationData':
              purchaseDetails.verificationData.serverVerificationData,
        },
      },
    };
  }

  String _pendingPurchaseKey(Map<String, dynamic> payload) {
    final purchase = Map<String, dynamic>.from(
      (payload['purchase'] as Map?) ?? <String, dynamic>{},
    );
    final verificationData = Map<String, dynamic>.from(
      (purchase['verificationData'] as Map?) ?? <String, dynamic>{},
    );
    final purchaseId = '${purchase['purchaseId'] ?? ''}'.trim();
    final token = '${verificationData['serverVerificationData'] ?? ''}'.trim();
    final identity = purchaseId.isNotEmpty ? purchaseId : token;
    return '${purchase['platform'] ?? ''}|${purchase['productId'] ?? ''}|$identity';
  }

  Future<Map<String, dynamic>> _upsertPendingPurchase(
    PurchaseDetails purchaseDetails,
  ) async {
    final payload = _purchasePayloadFromDetails(purchaseDetails);
    final key = _pendingPurchaseKey(payload);
    final entries = await _loadPendingPurchases();
    final existingIndex = entries.indexWhere((entry) => entry['key'] == key);
    final existing = existingIndex >= 0 ? entries[existingIndex] : null;
    final entry = <String, dynamic>{
      'key': key,
      'shopId': payload['shopId'],
      'purchase': payload['purchase'],
      'acknowledged': existing?['acknowledged'] == true,
      'storeCompleted': existing?['storeCompleted'] == true,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    if (existingIndex >= 0) {
      entries[existingIndex] = entry;
    } else {
      entries.add(entry);
    }
    await _savePendingPurchases(entries);
    return entry;
  }

  Future<void> _markPendingPurchaseAcknowledged(String key) async {
    final entries = await _loadPendingPurchases();
    final index = entries.indexWhere((entry) => entry['key'] == key);
    if (index < 0) {
      return;
    }
    entries[index] = <String, dynamic>{
      ...entries[index],
      'acknowledged': true,
      'acknowledgedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await _savePendingPurchases(entries);
  }

  Future<void> _markPendingPurchaseStoreCompleted(String key) async {
    final entries = await _loadPendingPurchases();
    final index = entries.indexWhere((entry) => entry['key'] == key);
    if (index < 0) {
      return;
    }
    entries[index] = <String, dynamic>{
      ...entries[index],
      'storeCompleted': true,
      'storeCompletedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await _savePendingPurchases(entries);
  }

  Future<void> _removePendingPurchase(String key) async {
    final entries = await _loadPendingPurchases();
    entries.removeWhere((entry) => entry['key'] == key);
    await _savePendingPurchases(entries);
  }

  Future<void> _retryPendingPurchases() async {
    final entries = await _loadPendingPurchases();
    if (entries.isEmpty) {
      return;
    }
    await _runSerialized(() async {
      for (final entry in entries) {
        if (entry['acknowledged'] == true && entry['storeCompleted'] == true) {
          continue;
        }
        try {
          if (entry['acknowledged'] != true) {
            await _submitPendingPurchaseToBackend(entry);
            await _markPendingPurchaseAcknowledged(entry['key'] as String);
          }
          lastStoreError.value = null;
        } catch (_) {
          lastStoreError.value =
              'Η αγορά θα επαναληφθεί αυτόματα όταν αποκατασταθεί η σύνδεση.';
        }
      }
    });
    // The store owns completion. Asking it to restore causes unfinished
    // purchases to be emitted again so they can be completed safely.
    await _inAppPurchase.restorePurchases();
  }

  Future<void> _runSerialized(Future<void> Function() action) async {
    final previous = _processingLock;
    final release = Completer<void>();
    _processingLock = release.future;
    await previous;
    try {
      await action();
    } finally {
      release.complete();
    }
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    for (final purchaseDetails in purchaseDetailsList) {
      await _runSerialized(() async {
        var shouldCompletePurchase = true;
        Map<String, dynamic>? pendingEntry;
        switch (purchaseDetails.status) {
          case PurchaseStatus.pending:
            isPurchasePending.value = true;
            break;
          case PurchaseStatus.error:
            isPurchasePending.value = false;
            lastStoreError.value =
                purchaseDetails.error?.message ??
                'Η αγορά από το κατάστημα δεν ολοκληρώθηκε.';
            break;
          case PurchaseStatus.canceled:
            isPurchasePending.value = false;
            break;
          case PurchaseStatus.purchased:
          case PurchaseStatus.restored:
            try {
              pendingEntry = await _handlePurchaseWithOutbox(purchaseDetails);
              lastStoreError.value = null;
            } catch (_) {
              shouldCompletePurchase = false;
              lastStoreError.value =
                  'Η αγορά ολοκληρώθηκε, αλλά η πρόσβαση του καταστήματος δεν ενημερώθηκε ακόμη. Χρησιμοποίησε την επαναφορά αγορών όταν αποκατασταθεί η σύνδεση.';
            } finally {
              isPurchasePending.value = false;
            }
            break;
        }

        if (shouldCompletePurchase && purchaseDetails.pendingCompletePurchase) {
          try {
            await _inAppPurchase.completePurchase(purchaseDetails);
            if (pendingEntry != null) {
              await _markPendingPurchaseStoreCompleted(
                pendingEntry['key'] as String,
              );
            }
          } catch (_) {
            shouldCompletePurchase = false;
          }
        } else if (shouldCompletePurchase && pendingEntry != null) {
          await _markPendingPurchaseStoreCompleted(
            pendingEntry['key'] as String,
          );
        }

        if (shouldCompletePurchase &&
            (purchaseDetails.status == PurchaseStatus.purchased ||
                purchaseDetails.status == PurchaseStatus.restored)) {
          try {
            final payload = _purchasePayloadFromDetails(purchaseDetails);
            final key = _pendingPurchaseKey(payload);
            final matchingPending = (await _loadPendingPurchases())
                .where((entry) => entry['key'] == key)
                .toList(growable: false);
            final pending = matchingPending.isEmpty
                ? null
                : matchingPending.first;
            if (pending == null || pending['storeCompleted'] == true) {
              await _removePendingPurchase(key);
            }
          } catch (_) {
            // The acknowledged purchase remains safely deduplicated server-side.
          }
        }
      });
    }
  }

  Future<void> _submitPendingPurchaseToBackend(
    Map<String, dynamic> pending,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('missing-billing-context');
    }
    final idToken = await user.getIdToken();
    final purchase = Map<String, dynamic>.from(
      (pending['purchase'] as Map?) ?? <String, dynamic>{},
    );
    final response = await http.post(
      Uri.parse(
        'https://europe-west1-barbero-88d00.cloudfunctions.net/barberoProcessStorePurchase',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
        'shopId': pending['shopId'],
        'purchase': purchase,
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
