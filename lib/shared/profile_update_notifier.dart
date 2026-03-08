import 'package:flutter/foundation.dart';

/// Notifies listeners when the user profile is updated (e.g. after edit profile).
/// Dashboards listen to this so the header name updates without restarting.
class ProfileUpdateNotifier extends ChangeNotifier {
  ProfileUpdateNotifier._();
  static final ProfileUpdateNotifier instance = ProfileUpdateNotifier._();

  void notifyProfileUpdated() {
    notifyListeners();
  }
}
