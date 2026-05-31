import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/constants.dart';

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);

class AuthState {

  AuthState({
    this.isAuthenticated = false,
    this.email,
    this.error,
    this.isLoading = false,
    this.seenOnboarding = false,
  });
  final bool isAuthenticated;
  final String? email;
  final String? error;
  final bool isLoading;

  /// Whether the user has finished (or skipped) the intro screens.
  /// Cleared on logout so onboarding replays for the next session.
  final bool seenOnboarding;

  AuthState copyWith({
    bool? isAuthenticated,
    String? email,
    String? error,
    bool? isLoading,
    bool? seenOnboarding,
  }) =>
      AuthState(
        isAuthenticated: isAuthenticated ?? this.isAuthenticated,
        email: email ?? this.email,
        error: error,
        isLoading: isLoading ?? this.isLoading,
        seenOnboarding: seenOnboarding ?? this.seenOnboarding,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState()) {
    _checkAuthStatus();
  }

  static const String _kSeenOnboarding = 'seen_onboarding';

  Future<void> _checkAuthStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('user_email');
      // In debug builds always replay onboarding on a cold start so it can be
      // reviewed on every `flutter run`. Release keeps the persisted "seen once"
      // behaviour (and the logout reset).
      final seen = kDebugMode ? false : (prefs.getBool(_kSeenOnboarding) ?? false);
      state = state.copyWith(
        isAuthenticated: email != null,
        email: email,
        seenOnboarding: seen,
      );
    } catch (e) {
      // Ignore errors during initialization
    }
  }

  /// Mark the intro screens as completed (persisted + reflected in state so the
  /// router redirect can act on it synchronously).
  Future<void> completeOnboarding() async {
    state = state.copyWith(seenOnboarding: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSeenOnboarding, true);
    } catch (_) {
      // Non-fatal.
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // Validate demo credentials
      final isValid = (email == AppConstants.demoEmail1 &&
              password == AppConstants.demoPassword1) ||
          (email == AppConstants.demoEmail2 &&
              password == AppConstants.demoPassword2);

      if (!isValid) {
        state = state.copyWith(
          isLoading: false,
          error: 'Invalid email or password',
        );
        return false;
      }

      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_email', email);

      state = state.copyWith(
        isAuthenticated: true,
        email: email,
        isLoading: false,
      );
      return true;
    } on Exception catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Login failed: ${e.toString()}',
      );
      return false;
    }
  }

  Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_email');
      // Replay the intro screens after logout.
      await prefs.remove(_kSeenOnboarding);
      // Fresh state → isAuthenticated=false, seenOnboarding=false.
      state = AuthState();
    } on Exception catch (e) {
      state = state.copyWith(error: 'Logout failed: ${e.toString()}');
    }
  }
}
