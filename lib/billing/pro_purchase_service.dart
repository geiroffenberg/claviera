import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pro_purchase_controller.dart';

class ProPurchaseService extends ProPurchaseController {
  ProPurchaseService({
    InAppPurchase? store,
    Future<SharedPreferences> Function()? preferences,
    this.reviewAccessCode = const String.fromEnvironment(
      'CLAVIERA_REVIEW_CODE',
    ),
  }) : _storeOverride = store,
       _preferences = preferences ?? SharedPreferences.getInstance;

  static const productId = 'claviera_pro_unlock';
  static const _entitlementKey = 'claviera.pro.unlocked';
  static const _reviewAccessKey = 'claviera.pro.reviewAccess';

  final String reviewAccessCode;
  final InAppPurchase? _storeOverride;
  final Future<SharedPreferences> Function() _preferences;
  final bool _isAndroid = defaultTargetPlatform == TargetPlatform.android;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  Future<void>? _initializeFuture;
  ProductDetails? _product;
  bool _isPro = false;
  bool _hasReviewAccess = false;
  bool _isRedeeming = false;
  bool _isAvailable = false;
  bool _isLoading = false;
  bool _purchasePending = false;
  bool _isRestoring = false;
  bool _disposed = false;
  String? _message;
  InAppPurchase get _store => _storeOverride ?? InAppPurchase.instance;

  @override
  bool get isAndroid => _isAndroid;

  @override
  bool get isPro => _isPro || _hasReviewAccess || !_isAndroid;

  @override
  bool get isAvailable => _isAvailable;

  @override
  bool get isBusy =>
      _isLoading || _purchasePending || _isRestoring || _isRedeeming;

  @override
  String? get localizedPrice => _product?.price;

  @override
  String? get message => _message;

  @override
  Future<void> initialize() {
    if (!_isAndroid) return Future.value();
    return _initializeFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    _purchaseSubscription ??= _store.purchaseStream.listen(
      _handlePurchases,
      onError: (Object error) {
        _purchasePending = false;
        _message = 'Google Play purchase update failed: $error';
        _notifyListeners();
      },
    );

    _isLoading = true;
    _message = null;
    _notifyListeners();

    try {
      final preferences = await _preferences();
      _isPro = preferences.getBool(_entitlementKey) ?? false;
      _hasReviewAccess = preferences.getBool(_reviewAccessKey) ?? false;
      _notifyListeners();
    } on PlatformException catch (error) {
      _message =
          'Saved Pro status could not be read: ${error.message ?? error.code}';
    } on MissingPluginException {
      _message = 'Saved Pro status is unavailable on this device.';
    }

    try {
      _isAvailable = await _store.isAvailable();
      if (!_isAvailable) {
        _message ??= 'Google Play billing is currently unavailable.';
        return;
      }

      final response = await _store.queryProductDetails({productId});
      if (response.error != null) {
        _message = 'Could not load the Pro price: ${response.error!.message}';
      } else {
        for (final product in response.productDetails) {
          if (product.id == productId) {
            _product = product;
            break;
          }
        }
        if (_product == null) {
          _message =
              'The Pro product is not configured in Google Play Console yet.';
        }
      }

      await _syncOwnedPurchase();
    } on PlatformException catch (error) {
      _message = 'Google Play billing error: ${error.message ?? error.code}';
    } on MissingPluginException {
      _message = 'Google Play billing is unavailable in this build.';
    } on InAppPurchaseException catch (error) {
      _message = 'Google Play billing error: ${error.message ?? error.code}';
    } finally {
      _isLoading = false;
      _notifyListeners();
    }
  }

  Future<void> _syncOwnedPurchase({bool showNotFound = false}) async {
    final addition = _store
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final response = await addition.queryPastPurchases();
    if (response.error != null) {
      _message =
          'Could not verify the Pro purchase: ${response.error!.message}';
      return;
    }

    final owned = response.pastPurchases.any(
      (purchase) =>
          purchase.productID == productId &&
          (purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored),
    );
    await _setPro(owned);
    if (owned) {
      _message = 'Claviera Pro is unlocked.';
    } else if (showNotFound) {
      _message = 'No Pro purchase was found for this Google account.';
    }
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      final isProPurchase = purchase.productID == productId;
      switch (purchase.status) {
        case PurchaseStatus.pending:
          if (isProPurchase) {
            _purchasePending = true;
            _message =
                'Purchase pending. Pro unlocks when Google Play completes it.';
          }
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (isProPurchase) {
            _purchasePending = false;
            _message = 'Claviera Pro is unlocked.';
            await _setPro(true);
          }
        case PurchaseStatus.error:
          if (isProPurchase) {
            _purchasePending = false;
            _message =
                'Purchase failed: ${purchase.error?.message ?? 'Google Play reported an error.'}';
          }
        case PurchaseStatus.canceled:
          if (isProPurchase) {
            _purchasePending = false;
            _message = 'Purchase canceled.';
          }
      }
      _notifyListeners();

      if (purchase.pendingCompletePurchase) {
        try {
          await _store.completePurchase(purchase);
        } on PlatformException catch (error) {
          _message =
              'Purchase could not be completed: ${error.message ?? error.code}';
        } on MissingPluginException {
          _message = 'Purchase completion is unavailable in this build.';
        } on InAppPurchaseException catch (error) {
          _message =
              'Purchase could not be completed: ${error.message ?? error.code}';
        }
        _notifyListeners();
      }
    }
  }

  Future<void> _setPro(bool value) async {
    _isPro = value;
    _notifyListeners();
    try {
      final preferences = await _preferences();
      await preferences.setBool(_entitlementKey, value);
    } on PlatformException catch (error) {
      _message =
          'Pro status could not be saved: ${error.message ?? error.code}';
    } on MissingPluginException {
      _message = 'Pro status could not be saved on this device.';
    }
  }

  @override
  Future<void> buyPro() async {
    if (!_isAndroid || !_isAvailable || _product == null || isBusy) return;
    _purchasePending = true;
    _message = null;
    _notifyListeners();
    try {
      final started = await _store.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: _product!),
      );
      if (!started) {
        _purchasePending = false;
        _message = 'Google Play could not start the purchase.';
        _notifyListeners();
      }
    } on PlatformException catch (error) {
      _purchasePending = false;
      _message = 'Purchase could not start: ${error.message ?? error.code}';
      _notifyListeners();
    } on MissingPluginException {
      _purchasePending = false;
      _message = 'Purchases are unavailable in this build.';
      _notifyListeners();
    } on InAppPurchaseException catch (error) {
      _purchasePending = false;
      _message = 'Purchase could not start: ${error.message ?? error.code}';
      _notifyListeners();
    }
  }

  @override
  Future<void> restorePurchases() async {
    if (!_isAndroid || !_isAvailable || isBusy) return;
    _isRestoring = true;
    _message = null;
    _notifyListeners();
    try {
      await _store.restorePurchases();
      await _syncOwnedPurchase(showNotFound: true);
    } on PlatformException catch (error) {
      _message = 'Restore failed: ${error.message ?? error.code}';
    } on MissingPluginException {
      _message = 'Restore is unavailable in this build.';
    } on InAppPurchaseException catch (error) {
      _message = 'Restore failed: ${error.message ?? error.code}';
    } finally {
      _isRestoring = false;
      _notifyListeners();
    }
  }

  @override
  Future<void> redeemReviewCode(String code) async {
    if (isBusy) return;
    if (reviewAccessCode.isEmpty) {
      _message = 'Review access is not configured in this build.';
      _notifyListeners();
      return;
    }
    if (code.trim().isEmpty || code.trim() != reviewAccessCode) {
      _message = 'Invalid review access code.';
      _notifyListeners();
      return;
    }
    _isRedeeming = true;
    _message = null;
    _notifyListeners();
    try {
      final preferences = await _preferences();
      final saved = await preferences.setBool(_reviewAccessKey, true);
      if (saved) {
        _hasReviewAccess = true;
        _message = 'Claviera Pro is unlocked for review on this device.';
      } else {
        _message = 'Review access could not be saved. Please try again.';
      }
    } on PlatformException catch (error) {
      _message =
          'Review access could not be saved: ${error.message ?? error.code}';
    } on MissingPluginException {
      _message = 'Review access could not be saved on this device.';
    } finally {
      _isRedeeming = false;
      _notifyListeners();
    }
  }

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _purchaseSubscription?.cancel();
    super.dispose();
  }
}
