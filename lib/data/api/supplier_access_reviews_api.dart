import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'supplier_api.dart';

final supplierAccessReviewsApiProvider =
    Provider<SupplierAccessReviewsApi>((ref) => SupplierAccessReviewsApi(ref.read(dioProvider)));

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

String _s(dynamic v) => v == null ? '' : v.toString();
double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse(_s(v)) ?? 0;

// ═══════ Accès accordés ═══════
class PriceUnlock {
  final String id;
  final String scope; // 'supplier' (catalogue entier) | 'product'
  final String userName;
  final String email;
  final String city;
  final String note;
  final String productName;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  const PriceUnlock({
    required this.id,
    required this.scope,
    this.userName = '',
    this.email = '',
    this.city = '',
    this.note = '',
    this.productName = '',
    this.createdAt,
    this.expiresAt,
  });

  factory PriceUnlock.fromJson(Map m, {String? scope}) {
    final user = m['user'] is Map ? m['user'] as Map : const {};
    return PriceUnlock(
      id: _s(m['unlock_id'] ?? m['id']),
      scope: scope ?? (_s(m['scope']).isEmpty ? 'product' : _s(m['scope'])),
      userName: _s(user['full_name'] ?? m['user_name']),
      email: _s(user['email'] ?? m['user_email']),
      city: _s(user['city']),
      note: _s(m['note']),
      productName: _s(m['product_name']),
      createdAt: DateTime.tryParse(_s(m['created_at'])),
      expiresAt: DateTime.tryParse(_s(m['expires_at'])),
    );
  }
}

// ═══════ Avis ═══════
class SupplierReviewItem {
  final String key;
  final String productId;
  final String productName;
  final String? productImage;
  final String reviewerName;
  final double rating;
  final String comment;
  final List<String> photos;
  final DateTime? createdAt;

  const SupplierReviewItem({
    required this.key,
    required this.productId,
    required this.productName,
    this.productImage,
    this.reviewerName = '',
    this.rating = 0,
    this.comment = '',
    this.photos = const [],
    this.createdAt,
  });
}

class SupplierAccessReviewsApi {
  final Dio _dio;
  SupplierAccessReviewsApi(this._dio);

  // GET /products/access/my-unlocks/
  // Accepte { supplier_unlocks, product_unlocks }, { results: [...] } ou un tableau plat avec `scope`.
  Future<List<PriceUnlock>> myUnlocks() async {
    var d = _decode((await _dio.get('/products/access/my-unlocks/')).data);
    if (d is Map && d['results'] != null) d = d['results'];
    final out = <PriceUnlock>[];
    if (d is List) {
      out.addAll(d.whereType<Map>().map((m) => PriceUnlock.fromJson(m)));
    } else if (d is Map) {
      out.addAll((d['supplier_unlocks'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => PriceUnlock.fromJson(m, scope: 'supplier')));
      out.addAll((d['product_unlocks'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => PriceUnlock.fromJson(m, scope: 'product')));
    }
    out.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    return out;
  }

  // POST /products/access/revoke-supplier/<id>/  ou  revoke-product/<id>/
  Future<void> revoke(PriceUnlock u) => _dio.post(
        u.scope == 'supplier'
            ? '/products/access/revoke-supplier/${u.id}/'
            : '/products/access/revoke-product/${u.id}/',
      );

  // GET /products/<id>/reviews/  (JSON brut)
  Future<List<Map>> productReviews(String productId) async {
    final d = _decode((await _dio.get('/products/$productId/reviews/')).data);
    final list = (d is Map) ? (d['results'] ?? const []) : (d ?? const []);
    return list is List ? list.whereType<Map>().toList() : const [];
  }
}

final supplierUnlocksProvider =
    FutureProvider<List<PriceUnlock>>((ref) => ref.read(supplierAccessReviewsApiProvider).myUnlocks());

const _maxProducts = 40; // garde-fou : évite trop d'appels sur un gros catalogue

/// Avis agrégés côté app, comme le web : produits du fournisseur ayant des avis → avis de chacun.
final supplierReviewsProvider = FutureProvider<List<SupplierReviewItem>>((ref) async {
  final api = ref.read(supplierAccessReviewsApiProvider);
  final prods = await ref.watch(supplierMyProductsProvider.future);
  final rated = prods.where((p) => p.ratingCount > 0).take(_maxProducts).toList();

  final lists = await Future.wait(rated.map((p) async {
    try {
      final rs = await api.productReviews(p.id);
      return rs.map((r) {
        final photos = (r['photos'] as List? ?? const [])
            .map((ph) => ph is Map ? _s(ph['url']) : _s(ph))
            .where((u) => u.isNotEmpty)
            .toList();
        return SupplierReviewItem(
          key: '${p.id}-${_s(r['id'])}',
          productId: p.id,
          productName: p.name,
          productImage: p.primaryImage,
          reviewerName: _s(r['reviewer_name']),
          rating: _d(r['rating']),
          comment: _s(r['comment']),
          photos: photos,
          createdAt: DateTime.tryParse(_s(r['created_at'])),
        );
      }).toList();
    } catch (_) {
      return <SupplierReviewItem>[];
    }
  }));

  final flat = lists.expand((x) => x).toList()
    ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
  return flat;
});