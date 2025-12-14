import 'dart:io' show Platform;
import 'package:local_auth/local_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AuthService {
  static final AuthService instance = AuthService._init();
  final LocalAuthentication _auth = LocalAuthentication();

  AuthService._init();

  /// Check if biometric authentication is available on the device
  Future<bool> canAuthenticate() async {
    // Linux doesn't support local_auth, so we skip auth there
    if (Platform.isLinux) {
      return true;
    }

    try {
      return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } catch (e) {
      return false;
    }
  }

  /// Get list of available biometric types
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  /// Authenticate user using biometrics or device credentials
  /// Returns true if authenticated successfully, false otherwise
  /// On Linux, always returns true (no auth available)
  Future<bool> authenticate({
    String reason = 'Please authenticate to view hidden notes',
  }) async {
    // Linux doesn't support local_auth, allow access without auth
    if (Platform.isLinux) {
      debugPrint('Linux detected - skipping authentication');
      return true;
    }

    try {
      final canAuth = await canAuthenticate();
      if (!canAuth) {
        debugPrint('Authentication not available on this device');
        return false;
      }

      final availableBiometrics = await getAvailableBiometrics();
      debugPrint('Available biometrics: $availableBiometrics');

      final result = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // Allow PIN/password as fallback
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );

      debugPrint('Authentication result: $result');
      return result;
    } on PlatformException catch (e) {
      // Handle errors like user cancellation, biometric not enrolled, etc.
      debugPrint('PlatformException during authentication: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('Error during authentication: $e');
      return false;
    }
  }

  /// Stop authentication (useful for canceling ongoing auth)
  Future<void> stopAuthentication() async {
    try {
      await _auth.stopAuthentication();
    } catch (_) {
      // Ignore errors
    }
  }
}
