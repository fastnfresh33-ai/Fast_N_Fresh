import 'package:dio/dio.dart';
import '../core/network/dio_client.dart';
import '../models/user.dart';

class AuthService {
  final Dio _dio = DioClient.instance.dio;

  Future<(String token, AppUser user)> login(String identifier, String password) async {
    try {
      final res = await _dio.post('/auth/login', data: {'identifier': identifier, 'password': password});
      final data = res.data['data'] as Map<String, dynamic>;
      final token = data['token'] as String;
      final user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
      return (token, user);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<AppUser> getMe() async {
    try {
      final res = await _dio.get('/auth/me');
      return AppUser.fromJson(res.data['data'] as Map<String, dynamic>);
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<void> changePassword(String currentPassword, String newPassword) async {
    try {
      await _dio.post('/auth/change-password', data: {'currentPassword': currentPassword, 'newPassword': newPassword});
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }

  Future<void> logoutAllDevices() async {
    try {
      await _dio.post('/auth/logout-all');
    } catch (e) {
      throw DioClient.instance.mapError(e);
    }
  }
}
