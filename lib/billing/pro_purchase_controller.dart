import 'package:flutter/foundation.dart';

abstract class ProPurchaseController extends ChangeNotifier {
  bool get isAndroid;
  bool get isPro;
  bool get isAvailable;
  bool get isBusy;
  String? get localizedPrice;
  String? get message;

  Future<void> initialize();
  Future<void> buyPro();
  Future<void> restorePurchases();
}
