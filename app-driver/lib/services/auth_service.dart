import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/network/api_client.dart';

/// Service d'authentification chauffeur (role driver).
class AuthService {
  AuthService({ApiClient? apiClient})
      : _api = apiClient ?? ApiClient(),
        _storage = _AuthStorage();

  final ApiClient _api;
  final _AuthStorage _storage;

  static const _keyToken = 'bikeride_driver_token';
  static const _keyUser = 'bikeride_driver_user';

  String? get token => _api.token ?? _storage.token;
  ApiClient get apiClient => _api;
  Map<String, dynamic>? get user => _storage.user;

  /// ID du chauffeur (user.id) pour les appels PUT /users/drivers/:id/status
  int? get driverId {
    final u = _storage.user;
    if (u == null) return null;
    final id = u['id'];
    if (id is int) return id;
    if (id is num) return id.toInt();
    return int.tryParse(id?.toString() ?? '');
  }

  Future<void> loadStoredAuth() async {
    await _storage.load();
    final t = _storage.token;
    if (t != null && t.isNotEmpty) {
      _api.setToken(t);
    }
  }

  Future<bool> isLoggedIn() async {
    await _storage.load();
    return _storage.token != null && _storage.token!.isNotEmpty;
  }

  Future<void> logout() async {
    _api.setToken(null);
    await _storage.clear();
  }

  /// Inscription chauffeur (role = driver).
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String? phone,
    String? firstName,
    String? lastName,
    String role = 'driver',
  }) async {
    final body = <String, dynamic>{
      'email': email,
      'password': password,
      'role': role,
    };
    if (phone != null && phone.isNotEmpty) body['phone'] = phone;
    if (firstName != null && firstName.isNotEmpty) body['first_name'] = firstName;
    if (lastName != null && lastName.isNotEmpty) body['last_name'] = lastName;

    final res = await _api.post('/auth/register', data: body);
    final data = res['data'] as Map<String, dynamic>? ?? {};
    final newToken = data['token'] as String?;
    final user = data['user'] as Map<String, dynamic>?;
    if (newToken != null) {
      _api.setToken(newToken);
      await _storage.saveToken(newToken);
      if (user != null) await _storage.saveUser(user);
    }
    return data;
  }

  /// Connexion chauffeur.
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final res = await _api.post('/auth/login', data: {
      'email': email.trim(),
      'password': password,
    });
    final data = res['data'] as Map<String, dynamic>? ?? {};
    final newToken = data['token'] as String?;
    final user = data['user'] as Map<String, dynamic>?;
    if (newToken != null) {
      _api.setToken(newToken);
      await _storage.saveToken(newToken);
      if (user != null) await _storage.saveUser(user);
    }
    return data;
  }
}

class _AuthStorage {
  SharedPreferences? _prefs;
  String? _token;
  Map<String, dynamic>? _user;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    _token = _prefs!.getString(AuthService._keyToken);
    final userStr = _prefs!.getString(AuthService._keyUser);
    if (userStr != null) {
      try {
        _user = jsonDecode(userStr) as Map<String, dynamic>?;
      } catch (_) {
        _user = null;
      }
    } else {
      _user = null;
    }
  }

  Future<void> saveToken(String t) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(AuthService._keyToken, t);
    _token = t;
  }

  Future<void> saveUser(Map<String, dynamic> u) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(AuthService._keyUser, jsonEncode(u));
    _user = u;
  }

  Future<void> clear() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.remove(AuthService._keyToken);
    await _prefs!.remove(AuthService._keyUser);
    _token = null;
    _user = null;
  }
}
