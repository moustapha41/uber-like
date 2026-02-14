import 'package:dio/dio.dart';
import 'dart:developer' as developer;

import 'api_config.dart';

/// Client HTTP pour l'API BikeRide Pro.
/// Gère le token JWT et les erreurs 401.
class ApiClient {
  ApiClient({String? token}) {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
    ));
    
    // Ajout d'un intercepteur pour le logging
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        developer.log('🚀 Requête envoyée à: ${options.uri}');
        developer.log('📝 Headers: ${options.headers}');
        if (options.data != null) {
          developer.log('📦 Body: ${options.data}');
        }
        if (_token != null && _token!.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $_token';
        }
        return handler.next(options);
      },
      onResponse: (response, handler) {
        developer.log('✅ Réponse reçue: ${response.statusCode}');
        developer.log('📥 Données: ${response.data}');
        return handler.next(response);
      },
      onError: (error, handler) {
        developer.log('❌ Erreur: ${error.message}');
        if (error.response != null) {
          developer.log('📡 Statut: ${error.response?.statusCode}');
          developer.log('📤 Données d\'erreur: ${error.response?.data}');
        }
        if (error.response?.statusCode == 401) {
          onUnauthorized?.call();
        }
        return handler.next(error);
      },
    ));
    _token = token;
  }

  late final Dio _dio;
  String? _token;

  /// Appelé en cas de 401 (token expiré ou invalide).
  void Function()? onUnauthorized;

  void setToken(String? token) {
    _token = token;
    if (token != null) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    } else {
      _dio.options.headers.remove('Authorization');
    }
  }

  String? get token => _token;

  Dio get dio => _dio;

  /// Réponse standard backend : { success, message?, data? }
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      developer.log('📡 Envoi de la requête $method à $path');
      
      final response = await _dio.request<Map<String, dynamic>>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          headers: options?.headers,
        ),
      );
      
      final body = response.data;
      if (body is! Map<String, dynamic>) {
        throw ApiException(
          message: 'Réponse invalide du serveur',
          statusCode: response.statusCode,
          responseData: body,
        );
      }
      
      if (body['success'] == true || response.statusCode == 200) {
        return body;
      }
      
      throw ApiException(
        message: body['message'] as String? ?? 'Erreur inconnue',
        statusCode: response.statusCode,
        responseData: body,
      );
    } on DioException catch (e) {
      // Gestion des erreurs spécifiques à Dio
      if (e.type == DioExceptionType.connectionTimeout) {
        throw ApiException(
          message: 'Délai de connexion dépassé. Vérifiez votre connexion internet.',
          statusCode: 408,
        );
      } else if (e.type == DioExceptionType.receiveTimeout) {
        throw ApiException(
          message: 'Délai d\'attente de la réponse du serveur dépassé.',
          statusCode: 504,
        );
      } else if (e.type == DioExceptionType.sendTimeout) {
        throw ApiException(
          message: 'Délai d\'envoi de la requête dépassé.',
          statusCode: 408,
        );
      } else if (e.type == DioExceptionType.badResponse) {
        // Erreur HTTP (4xx, 5xx)
        final response = e.response;
        final data = response?.data;
        
        if (data is Map<String, dynamic>) {
          throw ApiException(
            message: data['message'] as String? ?? 'Erreur serveur',
            statusCode: response?.statusCode,
            responseData: data,
          );
        }
        
        throw ApiException(
          message: 'Erreur serveur: ${response?.statusCode} ${response?.statusMessage}' ?? 'Erreur inconnue',
          statusCode: response?.statusCode,
          responseData: data,
        );
      } else if (e.type == DioExceptionType.cancel) {
        throw ApiException(message: 'Requête annulée');
      } else if (e.type == DioExceptionType.unknown) {
        // Erreur de connexion (serveur injoignable, DNS, etc.)
        throw ApiException(
          message: 'Impossible de joindre le serveur. Vérifiez que le backend tourne et que l\'app utilise la bonne adresse (${ApiConfig.baseUrl}). Même réseau WiFi que ce PC ?',
          statusCode: 0,
        );
      } else {
        // Autres erreurs
        throw ApiException(
          message: e.message ?? 'Erreur réseau inconnue',
          statusCode: e.response?.statusCode,
          responseData: e.response?.data,
        );
      }
    } catch (e) {
      // Erreurs non gérées
      throw ApiException(
        message: e.toString(),
        statusCode: 0,
      );
    }
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? queryParameters}) =>
      request(path, queryParameters: queryParameters);

  Future<Map<String, dynamic>> post(String path, {dynamic data}) =>
      request(path, method: 'POST', data: data);

  Future<Map<String, dynamic>> put(String path, {dynamic data}) =>
      request(path, method: 'PUT', data: data);
}

class ApiException implements Exception {
  ApiException({
    this.message,
    this.statusCode,
    this.responseData,
  });
  
  final String? message;
  final int? statusCode;
  final dynamic responseData;
  
  @override
  String toString() => 'ApiException: $message (Status: $statusCode)';
}
