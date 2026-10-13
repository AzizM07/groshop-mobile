import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cart.dart';
import 'api_client.dart';

final cartApiProvider = Provider<CartApi>((ref) => CartApi(ref.read(dioProvider)));

class CartApi {
  final Dio _dio;
  CartApi(this._dio);

  List<CartItem> _parse(dynamic data) {
    final list = (data is Map) ? (data['items'] ?? data['results'] ?? []) : (data ?? []);
    if (list is! List) return const [];
    return list.whereType<Map>().map((e) => CartItem.fromJson(e.cast<String, dynamic>())).toList();
  }

  Future<List<CartItem>> list() async => _parse((await _dio.get('/cart/')).data);

  Future<bool> add(String productId, int quantity, {String? variantId}) async {
    final r = await _dio.post('/cart/', data: {
      'product_id': productId,
      'quantity': quantity,
      'variant_id': variantId,
    });
    return r.statusCode == 200 || r.statusCode == 201;
  }

  Future<void> updateQty(String itemId, int quantity) =>
      _dio.patch('/cart/$itemId/', data: {'quantity': quantity});
  Future<void> remove(String itemId) => _dio.delete('/cart/$itemId/');
  Future<void> clear() => _dio.delete('/cart/clear/');
}