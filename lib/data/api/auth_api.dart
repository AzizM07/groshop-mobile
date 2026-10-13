import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';
import '../models/supplier.dart';
import '../storage/cookie_store.dart';
import 'api_client.dart';

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.read(dioProvider), ref.read(cookieStoreProvider)),
);

/// Porte les erreurs DRF par champ ({ email:[...], phone:[...] }).
class AuthException implements Exception {
  final String message;
  final Map<String, dynamic> fields;
  final int? statusCode;
  AuthException(this.message, [this.fields = const {}, this.statusCode]);
  @override
  String toString() => message;
}

class AuthApi {
  final Dio _dio;
  final CookieStore _store;
  AuthApi(this._dio, this._store);

  /// Login par cookies : /auth/login/ pose access_token/refresh_token/csrftoken
  /// (gérés par le CookieManager) et renvoie { user } dans le corps.
  Future<User> login(String email, String password) async {
    final r = await _dio.post('/auth/login/', data: {'email': email, 'password': password});
    if (r.statusCode != 200) {
      _throwFrom(r, fallback: 'Identifiants invalides');
    }
    final d = (r.data as Map).cast<String, dynamic>();
    return User.fromJson(d['user'] ?? d);
  }

  /// Connexion Google native (popup système, pas de navigateur) : envoie
  /// l'idToken au même endpoint que le web (/auth/google/), qui vérifie déjà
  /// l'audience contre GOOGLE_CLIENT_ID côté Django.
  Future<User> googleNativeSignIn(String idToken) async {
    final r = await _dio.post('/auth/google/', data: {'credential': idToken});
    if (r.statusCode != 200) {
      _throwFrom(r, fallback: 'Connexion Google impossible');
    }
    final d = (r.data as Map).cast<String, dynamic>();
    return User.fromJson(d['user'] ?? d);
  }

  /// Inscription acheteur : /auth/register/buyer/. Le back connecte
  /// l'utilisateur (pose les cookies) et renvoie { user } — sinon on se logue.
  Future<User> registerBuyer({
    required String fullName,
    required String email,
    required String phone,
    required String password,
  }) async {
    final r = await _dio.post('/auth/register/buyer/', data: {
      'full_name': fullName,
      'email': email,
      'phone': phone,
      'password': password,
    });
    if (r.statusCode == 200 || r.statusCode == 201) {
      final d = (r.data is Map) ? (r.data as Map).cast<String, dynamic>() : <String, dynamic>{};
      if (d['user'] != null) return User.fromJson(d['user']);
      return login(email, password);
    }
    _throwFrom(r, fallback: 'Inscription impossible');
  }

  /// Mot de passe oublié : POST /auth/password-reset/request/ { email }.
  /// Django répond TOUJOURS 200 avec le même message (que l'email existe ou
  /// non). Le lien reçu par mail ouvre la page web /reset-password.
  /// Lève [AuthException] sur 400 (email vide) ou 429 (trop de demandes).
  Future<String> requestPasswordReset(String email) async {
    final r = await _dio.post('/auth/password-reset/request/', data: {'email': email});
    if (r.statusCode != 200) {
      _throwFrom(r, fallback: 'Demande impossible');
    }
    final d = (r.data is Map) ? (r.data as Map).cast<String, dynamic>() : <String, dynamic>{};
    return (d['message'] ??
            'Si un compte existe avec cet email, un lien de réinitialisation vous a été envoyé.')
        .toString();
  }

  /// Connexion sociale mobile : échange le code reçu du deep link
  /// (groshop://auth-callback?code=...) contre une session — le backend pose
  /// les mêmes cookies JWT que login()/registerBuyer(), captés par le CookieJar.
  Future<User> exchangeSocialCode(String code) async {
    final r = await _dio.post('/auth/mobile/exchange/', data: {'code': code});
    if (r.statusCode != 200) {
      _throwFrom(r, fallback: 'Connexion impossible');
    }
    final d = (r.data as Map).cast<String, dynamic>();
    return User.fromJson(d['user'] ?? d);
  }

  Future<User> me() async {
    final r = await _dio.get('/auth/me/');
    return User.fromJson(r.data);
  }

  Future<Supplier> supplierMe() async {
    final r = await _dio.get('/auth/supplier/me/');
    return Supplier.fromJson(r.data);
  }

  Future<void> logout() async {
    try { await _dio.post('/auth/logout/'); } catch (_) {}
    await _store.clear();
  }

  Never _throwFrom(Response r, {required String fallback}) {
    final data = r.data;
    if (data is Map) {
      final map = data.cast<String, dynamic>();
      final fields = <String, dynamic>{};
      map.forEach((k, v) {
        if (v is List && v.isNotEmpty && !['error', 'detail', 'message'].contains(k)) fields[k] = v;
      });
      final msg = (map['error'] ?? map['detail'] ?? map['message'] ?? fallback).toString();
      throw AuthException(msg, fields, r.statusCode);
    }
    throw AuthException(fallback, const {}, r.statusCode);
  }
}