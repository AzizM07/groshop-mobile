import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config.dart';
import '../storage/cookie_store.dart';

final cookieStoreProvider = Provider<CookieStore>((ref) => CookieStore());

final dioProvider = Provider<Dio>((ref) {
  throw StateError('dioProvider doit être surchargé au démarrage (voir main.dart).');
});

Future<Dio> buildDio(CookieStore store) async {
  final jar = await store.jar();
  final options = BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 20),
    headers: {'Accept': 'application/json'},
    contentType: 'application/json',
    // Les 4xx NE lèvent PAS d'exception : les API (AccountApi._ok,
    // AuthApi._throwFrom…) lisent le statut elles-mêmes.
    // ⚠️ Conséquence : un 401 arrive dans onResponse, JAMAIS dans onError.
    validateStatus: (s) => s != null && s < 500,
  );

  // Client « brut » : mêmes cookies, SANS l'intercepteur de refresh.
  // Il sert au refresh et au rejeu de la requête. Passer par `dio` lui-même
  // depuis l'intercepteur ferait repasser la réponse dans la file du
  // QueuedInterceptor déjà occupée → blocage.
  final raw = Dio(options)..interceptors.add(CookieManager(jar));

  final dio = Dio(options);
  dio.interceptors.add(CookieManager(jar)); // en premier : enregistre les cookies reçus
  dio.interceptors.add(_CsrfRefreshInterceptor(raw, store));
  return dio;
}

class _CsrfRefreshInterceptor extends QueuedInterceptor {
  final Dio _raw;
  final CookieStore _store;
  _CsrfRefreshInterceptor(this._raw, this._store);

  Uri get _base => Uri.parse(AppConfig.apiBaseUrl);
  static const _authFree = ['/auth/login/', '/auth/refresh/', '/auth/register/'];
  bool _isAuthFree(String path) => _authFree.any(path.contains);

  /// Dernier refresh réussi : si plusieurs requêtes reçoivent un 401 en même
  /// temps, seule la première rafraîchit, les suivantes rejouent directement.
  DateTime? _lastRefresh;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final csrf = await _store.read('csrftoken', _base);
    if (csrf != null) options.headers['X-CSRFToken'] = csrf;
    options.headers['X-Lang'] = 'fr';
    handler.next(options);
  }

  /// Access token expiré → refresh une seule fois, puis rejeu de la requête.
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    final req = response.requestOptions;
    final eligible = response.statusCode == 401 &&
        !_isAuthFree(req.path) &&
        req.extra['retried'] != true;

    if (!eligible) return handler.next(response);

    final recentlyRefreshed = _lastRefresh != null &&
        DateTime.now().difference(_lastRefresh!) < const Duration(seconds: 10);

    final ok = recentlyRefreshed || await _refresh();
    if (!ok) {
      // Refresh refusé (refresh token expiré ou révoqué, ex. après un
      // changement de mot de passe sur un autre appareil) → session morte.
      await _store.clear();
      return handler.next(response);
    }

    try {
      final retry = await _raw.fetch(await _retryOptions(req));
      return handler.next(retry);
    } catch (_) {
      return handler.next(response); // on renvoie la 401 d'origine
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Réseau / timeout / 5xx : rien à rafraîchir.
    handler.next(err);
  }

  Future<bool> _refresh() async {
    try {
      final csrf = await _store.read('csrftoken', _base);
      final r = await _raw.post('/auth/refresh/',
          options: Options(headers: csrf != null ? {'X-CSRFToken': csrf} : null));
      final ok = r.statusCode == 200;
      if (ok) _lastRefresh = DateTime.now();
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Copie de la requête pour le rejeu : on retire l'ancien en-tête Cookie
  /// (qui contient l'access token expiré) pour que le CookieManager y mette
  /// les cookies frais du jar, et on relit le CSRF.
  Future<RequestOptions> _retryOptions(RequestOptions req) async {
    final headers = Map<String, dynamic>.of(req.headers)
      ..remove('cookie')
      ..remove('Cookie');
    final csrf = await _store.read('csrftoken', _base);
    if (csrf != null) headers['X-CSRFToken'] = csrf;
    return req.copyWith(
      headers: headers,
      extra: {...req.extra, 'retried': true},
    );
  }
}