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

  /// Called on app start to restore a previously "remembered" session.
  Future<void> restoreSession() async {
    final token = await TokenStorage.instance.readToken();
    final userJson = await TokenStorage.instance.readUserJson();

    if (token == null || userJson == null) {
      status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    try {
      currentUser = AppUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
      status = AuthStatus.authenticated;
      notifyListeners();

      // Validate the token is still good in the background; log out if not.
      final freshUser = await _authService.getMe();
      currentUser = freshUser;
      await TokenStorage.instance.saveUserJson(jsonEncode(freshUser.toJson()));
      notifyListeners();
    } catch (_) {
      await logout();
    }
  }

  Future<bool> login(String identifier, String password) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final (token, user) = await _authService.login(identifier, password);
      await TokenStorage.instance.saveToken(token);
      await TokenStorage.instance.saveUserJson(jsonEncode(user.toJson()));
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
    } catch (e) {
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

  /// Invoked by the Dio 401 interceptor when the session becomes invalid.
  void forceLogout() {
    TokenStorage.instance.clear();
    currentUser = null;
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
