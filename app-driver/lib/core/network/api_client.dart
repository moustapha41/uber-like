import 'package:dio/dio.dart';

import 'api_config.dart';

/// Client HTTP pour l'API BikeRide Pro (app chauffeur).
/// Gère le token JWT et les erreurs 401.
class ApiClient {
  ApiClient({String? token}) {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_token != null && _token!.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $_token';
        }
        return handler.next(options);
      },
      onError: (error, handler) {
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

  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.request<Map<String, dynamic>>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(method: method, headers: options?.headers),
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
      if (e.type == DioExceptionType.badResponse) {
        final data = e.response?.data;
        if (data is Map<String, dynamic>) {
          throw ApiException(
            message: data['message'] as String? ?? 'Erreur serveur',
            statusCode: e.response?.statusCode,
            responseData: data,
          );
        }
      }
      throw ApiException(
        message: e.message ?? 'Erreur réseau',
        statusCode: e.response?.statusCode,
        responseData: e.response?.data,
      );
    }
  }

  Future<Map<String, dynamic>> get(String path,
          {Map<String, dynamic>? queryParameters}) =>
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
