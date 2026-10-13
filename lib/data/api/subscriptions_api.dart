import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';

double _d(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

class SubPlan {
  final String id;
  final String name;
  final double priceTnd;
  final double commissionPct;
  final int? maxProducts;
  final int durationDays;
  const SubPlan({
    required this.id,
    required this.name,
    this.priceTnd = 0,
    this.commissionPct = 0,
    this.maxProducts,
    this.durationDays = 30,
  });

  factory SubPlan.fromJson(Map m) => SubPlan(
        id: '${m['id']}',
        name: m['name']?.toString() ?? '',
        priceTnd: _d(m['price_tnd']),
        commissionPct: _d(m['commission_pct']),
        maxProducts: m['max_products'] == null ? null : (m['max_products'] as num?)?.toInt(),
        durationDays: (m['duration_days'] as num?)?.toInt() ?? 30,
      );
}

class SubSubscription {
  final String id;
  final SubPlan? plan;
  final String status;
  final String? startedAt;
  final String? expiresAt;
  const SubSubscription({required this.id, this.plan, this.status = 'active', this.startedAt, this.expiresAt});

  factory SubSubscription.fromJson(Map m) => SubSubscription(
        id: '${m['id']}',
        plan: (m['plan'] is Map) ? SubPlan.fromJson(m['plan'] as Map) : null,
        status: m['status']?.toString() ?? 'active',
        startedAt: m['started_at']?.toString(),
        expiresAt: m['expires_at']?.toString(),
      );
}

final subscriptionsApiProvider =
    Provider<SubscriptionsApi>((ref) => SubscriptionsApi(ref.read(dioProvider)));

class SubscriptionsApi {
  final Dio _dio;
  SubscriptionsApi(this._dio);

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

  // GET /store/subscriptions/plans/
  Future<List<SubPlan>> plans() async {
    final d = _decode((await _dio.get('/store/subscriptions/plans/')).data);
    final list = (d is List) ? d : (d is Map ? (d['results'] ?? const []) : const []);
    return (list as List).whereType<Map>().map(SubPlan.fromJson).toList();
  }

  // GET /store/subscriptions/me/  → abonnement actif ou null
  Future<SubSubscription?> mine() async {
    final d = _decode((await _dio.get('/store/subscriptions/me/')).data);
    return (d is Map) ? SubSubscription.fromJson(d) : null;
  }

  // POST /store/subscriptions/change/  { plan_id }
  Future<SubSubscription?> changePlan(String planId) async {
    final d = _decode((await _dio.post('/store/subscriptions/change/', data: {'plan_id': planId})).data);
    return (d is Map) ? SubSubscription.fromJson(d) : null;
  }
}

final plansProvider = FutureProvider<List<SubPlan>>((ref) => ref.read(subscriptionsApiProvider).plans());
final mySubscriptionProvider = FutureProvider<SubSubscription?>((ref) => ref.read(subscriptionsApiProvider).mine());