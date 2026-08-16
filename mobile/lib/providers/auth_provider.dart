import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/network/token_storage.dart';
import '../core/network/api_exception.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  AuthStatus status = AuthStatus.unknown;
  AppUser? currentUser;
  String? errorMessage;
  bool isLoading = false;

  bool get isAdmin => currentUser?.isAdmin ?? false;

  /// Restores the locally saved session when the app starts.
  Future<void> restoreSession() async {
    final token = await TokenStorage.instance.readToken();
    final userJson = await TokenStorage.instance.readUserJson();

    if (token == null || userJson == null) {
      status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    try {
      currentUser =
          AppUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);

      status = AuthStatus.authenticated;
      notifyListeners();

      // Validate the session in the background.
      final freshUser = await _authService.getMe();

      currentUser = freshUser;

      await TokenStorage.instance.saveUserJson(
        jsonEncode(freshUser.toJson()),
      );

      notifyListeners();
    } on ApiException catch (e) {
      // Only clear the session when the server explicitly rejects the token.
      if (e.statusCode == 401) {
        await logout();
        return;
      }

      // Keep the local session when the problem is network, timeout,
      // server startup, or another temporary error.
    } catch (_) {
      // Keep the local session for unexpected temporary failures.
    }
  }

  Future<bool> login(String identifier, String password) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final (token, user) =
          await _authService.login(identifier, password);

      await TokenStorage.instance.saveToken(token);
      await TokenStorage.instance.saveUserJson(
        jsonEncode(user.toJson()),
      );

      currentUser = user;
      status = AuthStatus.authenticated;
      isLoading = false;

      notifyListeners();
      return true;
    } on ApiException catch (e) {
      errorMessage = e.message;
      isLoading = false;

      notifyListeners();
      return false;
    } catch (_) {
      errorMessage = 'Unable to log in. Please try again.';
      isLoading = false;

      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await TokenStorage.instance.clear();

    currentUser = null;
    status = AuthStatus.unauthenticated;

    notifyListeners();
  }

  /// Clears the session when authentication is confirmed to be invalid.
  Future<void> forceLogout() async {
    await TokenStorage.instance.clear();

    currentUser = null;
    status = AuthStatus.unauthenticated;

    notifyListeners();
  }
}