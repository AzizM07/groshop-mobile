import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/supplier_models.dart';
import '../models/supplier_profile_models.dart';
import '../models/product.dart';
import 'api_client.dart';

final supplierApiProvider = Provider<SupplierApi>((ref) => SupplierApi(ref.read(dioProvider)));

class SupplierApi {
  final Dio _dio;
  SupplierApi(this._dio);

  // dio peut renvoyer une String (JSON non décodé) — on décode défensivement.
  dynamic _decode(dynamic data) {
    if (data is String) {
      try {
        return jsonDecode(data);
      } catch (_) {
        return null;
      }
    }
    return data;
  }

  List _asList(dynamic data) {
    final d = _decode(data);
    if (d is List) return d;
    if (d is Map) {
      final r = d['results'];
      if (r is List) return r;
    }
    return const [];
  }

  List<Product> _parseProducts(dynamic data) => _asList(data)
      .whereType<Map>()
      .map((e) => Product.fromJson(e.cast<String, dynamic>()))
      .toList();

  // GET /orders/supplier/  → liste des sous-commandes du fournisseur
  Future<List<SubOrder>> orders() async {
    final list = _asList((await _dio.get('/orders/supplier/')).data);
    return list.whereType<Map>().map(SubOrder.fromJson).toList();
  }

  // GET /analytics/supplier/stats/
  Future<SupplierStats> stats() async {
    final d = _decode((await _dio.get('/analytics/supplier/stats/')).data);
    return (d is Map) ? SupplierStats.fromJson(d) : const SupplierStats();
  }

  // GET /analytics/supplier/active-users/
  Future<ActiveUsers> activeUsers() async {
    final d = _decode((await _dio.get('/analytics/supplier/active-users/')).data);
    return (d is Map) ? ActiveUsers.fromJson(d) : const ActiveUsers();
  }

  // GET /analytics/supplier/regions/  → { by_region: [...] }
  Future<List<RegionStat>> regions() async {
    final d = _decode((await _dio.get('/analytics/supplier/regions/')).data);
    final list = (d is Map) ? (d['by_region'] ?? const []) : const [];
    return (list is List) ? list.whereType<Map>().map(RegionStat.fromJson).toList() : const [];
  }

  // GET /products/mine/  → produits du fournisseur (statut uniquement ici)
  Future<List<MyProduct>> myProducts() async {
    final list = _asList((await _dio.get('/products/mine/')).data);
    return list.whereType<Map>().map(MyProduct.fromJson).toList();
  }

  // GET /auth/supplier/me/  → profil fournisseur (Réglages)
  Future<SupplierProfileInfo?> profile() async {
    final d = _decode((await _dio.get('/auth/supplier/me/')).data);
    return (d is Map) ? SupplierProfileInfo.fromJson(d) : null;
  }

  // PATCH /orders/supplier/{id}/  { status } — changement de statut
  Future<void> updateOrderStatus(String id, String status) =>
      _dio.patch('/orders/supplier/$id/', data: {'status': status});

  // ══════════════════ Vitrine PUBLIQUE (par slug) ══════════════════

  // GET /auth/suppliers/{slug}/  → profil public + store + reviews
  Future<SupplierProfile?> publicProfile(String slug) async {
    final d = _decode((await _dio.get('/auth/suppliers/$slug/')).data);
    return (d is Map) ? SupplierProfile.fromJson(d.cast<String, dynamic>()) : null;
  }

  // GET /auth/suppliers/{slug}/products/?page_size=..  → produits publics
  Future<List<Product>> publicProducts(String slug, {int pageSize = 12}) async {
    final r = await _dio.get('/auth/suppliers/$slug/products/',
        queryParameters: {'page_size': pageSize});
    return _parseProducts(r.data);
  }

  // POST /messaging/start/{slug}/  → démarre/rejoint la conversation, renvoie son id
  Future<String?> startConversation(String slug, {String? productId}) async {
    final d = _decode((await _dio.post('/messaging/start/$slug/',
            data: {'product_id': productId}))
        .data);
    if (d is Map) return _s(d['id'] ?? d['conversation_id']);
    return null;
  }

  String _s(dynamic v) => (v == null) ? '' : v.toString();
}

// ── Providers (cache) — dashboard ──
final supplierOrdersProvider =
    FutureProvider<List<SubOrder>>((ref) => ref.read(supplierApiProvider).orders());
final supplierStatsProvider =
    FutureProvider<SupplierStats>((ref) => ref.read(supplierApiProvider).stats());
final supplierMyProductsProvider =
    FutureProvider<List<MyProduct>>((ref) => ref.read(supplierApiProvider).myProducts());
final supplierProfileProvider =
    FutureProvider<SupplierProfileInfo?>((ref) => ref.read(supplierApiProvider).profile());
final supplierActiveUsersProvider =
    FutureProvider<ActiveUsers>((ref) => ref.read(supplierApiProvider).activeUsers());
final supplierRegionsProvider =
    FutureProvider<List<RegionStat>>((ref) => ref.read(supplierApiProvider).regions());

// ── Providers (cache) — vitrine publique ──
final supplierPublicProfileProvider =
    FutureProvider.family<SupplierProfile?, String>((ref, slug) =>
        ref.read(supplierApiProvider).publicProfile(slug));
final supplierPublicProductsProvider =
    FutureProvider.family<List<Product>, String>((ref, slug) =>
        ref.read(supplierApiProvider).publicProducts(slug, pageSize: 12));