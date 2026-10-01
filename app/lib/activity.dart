import 'package:flutter/foundation.dart';

/// The user is at the device: input that reaches the app without a key
/// event or a touch, such as typing on Android's soft keyboard into a
/// terminal, reports here so the vault's idle lock waits.
class UserActivity extends ChangeNotifier {
  void ping() => notifyListeners();
}

final userActivity = UserActivity();
