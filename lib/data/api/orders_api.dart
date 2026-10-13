import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';

final ordersApiProvider = Provider<OrdersApi>((ref) => OrdersApi(ref.read(dioProvider)));

typedef Json = Map<String, dynamic>;

class OrdersApi {
  final Dio _dio;
  OrdersApi(this._dio);

  /// Liste brute, ou objet paginé / enveloppé sous l'une des [keys].
  static List<Json> _maps(dynamic data, [List<String> keys = const ['results', 'orders']]) {
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

  static Json _map(dynamic data) => data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};

  // ── Acheteur ────────────────────────────────────────────────────

  /// GET /orders/ — commandes de l'acheteur.
  Future<List<Json>> list() async => _maps((await _dio.get('/orders/')).data);

  /// GET /orders/<id>/
  Future<Json> detail(String id) async => _map((await _dio.get('/orders/$id/')).data);

  /// POST /orders/create/
  Future<Json> create(Json data) async => _map((await _dio.post('/orders/create/', data: data)).data);

  /// POST /orders/<id>/cancel/
  Future<void> cancel(String id) => _dio.post('/orders/$id/cancel/');

  /// GET /orders/to-review/ — lignes d'achat livrées pas encore notées
  /// ({ order_id, order_item_id, product_id, ... }).
  Future<List<Json>> toReview() async => _maps((await _dio.get('/orders/to-review/')).data, const ['results']);

  // ── Fournisseur ─────────────────────────────────────────────────

  /// GET /orders/supplier/?status=...
  Future<List<Json>> supplier([Map<String, dynamic>? params]) async =>
      _maps((await _dio.get('/orders/supplier/', queryParameters: params)).data);

  /// PATCH /orders/supplier/<id>/ { status, ...extra }
  Future<Json> updateSubOrderStatus(String id, String status, [Json extra = const {}]) async =>
      _map((await _dio.patch('/orders/supplier/$id/', data: {'status': status, ...extra})).data);
}