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
  });
  final bool isAuthenticated;
  final String? email;
  final String? error;
  final bool isLoading;

  AuthState copyWith({
    bool? isAuthenticated,
    String? email,
    String? error,
    bool? isLoading,
  }) =>
      AuthState(
        isAuthenticated: isAuthenticated ?? this.isAuthenticated,
        email: email ?? this.email,
        error: error,
        isLoading: isLoading ?? this.isLoading,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState()) {
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('user_email');
      if (email != null) {
        state = state.copyWith(
          isAuthenticated: true,
          email: email,
        );
      }
    } catch (e) {
      // Ignore errors during initialization
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
      state = AuthState();
    } on Exception catch (e) {
      state = state.copyWith(error: 'Logout failed: ${e.toString()}');
    }
  }
}
