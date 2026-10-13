import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/followed_shop.dart';
import '../models/history_entry.dart';
import '../models/product.dart';
import 'api_client.dart';

final accountApiProvider = Provider<AccountApi>((ref) => AccountApi(ref.read(dioProvider)));

class AccountApi {
  final Dio _dio;
  AccountApi(this._dio);

  /// Le client Dio accepte les 4xx sans lever d'exception (validateStatus < 500).
  /// On vérifie donc le statut ici : tout ce qui n'est pas 2xx devient une
  /// DioException, que les écrans attrapent comme n'importe quelle erreur réseau.
  static Response<T> _ok<T>(Response<T> r) {
    final code = r.statusCode ?? 0;
    if (code >= 200 && code < 300) return r;
    throw DioException(
      requestOptions: r.requestOptions,
      response: r,
      type: DioExceptionType.badResponse,
      message: messageOf(r.data) ?? 'Erreur $code',
    );
  }

  /// Message lisible depuis une erreur DRF ({error}, {detail} ou {champ: [msg]}).
  /// Utilisable dans les écrans : `AccountApi.messageOf(e.response?.data)`.
  static String? messageOf(Object? data) {
    if (data is! Map) return null;
    for (final k in ['error', 'detail', 'message', 'non_field_errors']) {
      final v = data[k];
      if (v is String && v.isNotEmpty) return v;
      if (v is List && v.isNotEmpty) return '${v.first}';
    }
    for (final v in data.values) {
      if (v is List && v.isNotEmpty) return '${v.first}';
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  /// Extrait une liste d'objets JSON d'une réponse : liste brute,
  /// ou objet paginé / enveloppé sous l'une des [keys].
  static List<Map<String, dynamic>> _maps(dynamic data, List<String> keys) {
    dynamic list = data;
    if (data is Map) {
      list = const [];
      for (final k in keys) {
        if (data[k] is List) {
          list = data[k];
          break;
        }
      }
    }
    if (list is! List) return const [];
    return list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  // ── Favoris ─────────────────────────────────────────────────────

  Future<List<Product>> favorites() async {
    final data = _ok(await _dio.get('/products/favorites/')).data;
    return _maps(data, const ['products', 'results']).map(Product.fromJson).toList();
  }

  // ── Historique de recherche ─────────────────────────────────────

  Future<List<String>> recentSearches() async {
    final data = _ok(await _dio.get('/store/recent-searches/')).data;
    final raw = (data is Map) ? (data['searches'] ?? data['results'] ?? []) : (data ?? []);
    if (raw is! List) return const [];
    return raw.map((s) {
      if (s is String) return s;
      if (s is Map) return '${s['content'] ?? s['text'] ?? s['name'] ?? ''}';
      return '$s';
    }).where((s) => s.isNotEmpty).toList();
  }

  Future<void> clearRecentSearches() async {
    _ok(await _dio.post('/store/recent-searches/clear/'));
  }

  // ── Paramètres du compte ────────────────────────────────────────

  /// POST /auth/change-password/
  /// ⚠️ Lève une DioException si l'ancien mot de passe est faux (400) :
  /// l'écran doit l'attraper et afficher `AccountApi.messageOf(e.response?.data)`.
  Future<void> changePassword(String oldPassword, String newPassword) async {
    _ok(await _dio.post(
      '/auth/change-password/',
      data: {'old_password': oldPassword, 'new_password': newPassword},
    ));
  }

  /// PATCH /auth/language/ — 'fr' | 'en' | 'ar'
  Future<void> setLanguage(String lang) async {
    _ok(await _dio.patch('/auth/language/', data: {'language': lang}));
  }

  // ── Historique de consultation (produits vus) ───────────────────
  // ⚠️ Endpoints à créer côté Django : tant qu'ils n'existent pas, ces
  // méthodes lèvent une erreur 404 (au lieu de renvoyer une liste vide).

  /// GET /products/history/ → [{ product: {...}, viewed_at: "..." }, ...]
  /// trié du plus récent au plus ancien.
  Future<List<HistoryEntry>> history() async {
    final data = _ok(await _dio.get('/products/history/')).data;
    return _maps(data, const ['history', 'results']).map(HistoryEntry.fromJson).toList();
  }

  /// DELETE /products/history/ { product_ids: [...] } → retire ces produits.
  Future<void> removeHistory(List<String> productIds) async {
    _ok(await _dio.delete('/products/history/', data: {'product_ids': productIds}));
  }

  /// DELETE /products/history/ sans corps → vide tout l'historique.
  Future<void> clearHistory() async {
    _ok(await _dio.delete('/products/history/'));
  }

  // ── Boutiques suivies ───────────────────────────────────────────
  // ⚠️ Endpoints à créer côté Django (même remarque : 404 → erreur).

  /// GET /auth/suppliers/following/ → [{ id, slug, company_name, logo, city,
  /// is_verified, product_count, preview_images: [url, ...] }, ...]
  Future<List<FollowedShop>> followedShops() async {
    final data = _ok(await _dio.get('/auth/suppliers/following/')).data;
    return _maps(data, const ['suppliers', 'results']).map(FollowedShop.fromJson).toList();
  }

  /// POST /auth/suppliers/following/ { supplier_id } → suivre une boutique.
  Future<void> followShop(String supplierId) async {
    _ok(await _dio.post('/auth/suppliers/following/', data: {'supplier_id': supplierId}));
  }

  /// DELETE /auth/suppliers/following/<id>/ → ne plus suivre.
  Future<void> unfollowShop(String supplierId) async {
    _ok(await _dio.delete('/auth/suppliers/following/$supplierId/'));
  }
}