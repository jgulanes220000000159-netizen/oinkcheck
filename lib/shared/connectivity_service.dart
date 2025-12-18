import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  Timer? _periodicCheckTimer;

  bool _isConnected = true;
  bool _isInitialized = false;

  bool get isConnected => _isConnected;
  bool get isInitialized => _isInitialized;

  void initialize() {
    try {
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
        _updateConnectionStatus,
        onError: (error) {
          print('🌐 Connectivity stream error: $error');
          _isConnected = false;
          notifyListeners();
        },
      );
      // Check initial connectivity status
      _checkInitialConnectivity();

      // Periodically check internet access every 30 seconds
      // This catches cases where WiFi/mobile is on but no actual internet
      _periodicCheckTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _performPeriodicCheck(),
      );

      _isInitialized = true;
    } catch (e) {
      print('🌐 Error initializing connectivity service: $e');
      _isConnected = false;
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> _performPeriodicCheck() async {
    try {
      final result = await _connectivity.checkConnectivity();
      final hasNetworkConnection =
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.ethernet;

      if (!hasNetworkConnection) {
        if (_isConnected) {
          _isConnected = false;
          print('🌐 Periodic check: Network disconnected');
          notifyListeners();
        }
        return;
      }

      // Check actual internet access
      final hasInternetAccess = await _checkInternetAccess();
      if (_isConnected != hasInternetAccess) {
        _isConnected = hasInternetAccess;
        print(
          '🌐 Periodic check: Internet ${hasInternetAccess ? "restored" : "lost"}',
        );
        notifyListeners();
      }
    } catch (e) {
      print('🌐 Error in periodic check: $e');
    }
  }

  Future<void> _checkInitialConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      print('🌐 Initial connectivity check: $result');
      _updateConnectionStatus(result);
    } catch (e) {
      print('🌐 Error checking initial connectivity: $e');
      _isConnected = false;
      notifyListeners();
    }
  }

  void _updateConnectionStatus(ConnectivityResult result) async {
    final wasConnected = _isConnected;

    // First check if we have a network connection (WiFi/Mobile/Ethernet enabled)
    final hasNetworkConnection =
        result == ConnectivityResult.wifi ||
        result == ConnectivityResult.mobile ||
        result == ConnectivityResult.ethernet;

    // Debug print to see connectivity changes
    print(
      '🌐 Connectivity changed: $result, hasNetwork: $hasNetworkConnection',
    );

    // If no network connection, we're definitely offline
    if (!hasNetworkConnection) {
      _isConnected = false;
      if (wasConnected != _isConnected) {
        print('🌐 No network connection available');
        notifyListeners();
      }
      return;
    }

    // If we have network connection, verify actual internet access
    final hasInternetAccess = await _checkInternetAccess();
    _isConnected = hasInternetAccess;

    // Only notify if status changed
    if (wasConnected != _isConnected) {
      print(
        '🌐 Connection status changed: ${wasConnected ? "Connected" : "Disconnected"} -> ${_isConnected ? "Connected" : "Disconnected"}',
      );
      notifyListeners();
    }
  }

  // Check if we actually have internet access by trying to reach a reliable server
  Future<bool> _checkInternetAccess() async {
    try {
      // Try to lookup Google's DNS server (very reliable and fast)
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 5));

      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        print('🌐 Internet access verified');
        return true;
      }
      print('🌐 No internet access');
      return false;
    } on SocketException catch (_) {
      print('🌐 No internet access (Socket exception)');
      return false;
    } on TimeoutException catch (_) {
      print('🌐 No internet access (Timeout)');
      return false;
    } catch (e) {
      print('🌐 Error checking internet access: $e');
      return false;
    }
  }

  // Method to manually set connectivity status for testing
  void setConnectivityStatus(bool isConnected) {
    if (_isConnected != isConnected) {
      _isConnected = isConnected;
      print(
        '🌐 Manual connectivity change: ${isConnected ? "Connected" : "Disconnected"}',
      );
      notifyListeners();
    }
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _periodicCheckTimer?.cancel();
    super.dispose();
  }
}

// Global connectivity service instance
final connectivityService = ConnectivityService();
