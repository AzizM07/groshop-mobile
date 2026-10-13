import 'dart:io' show Platform;
import 'dart:math';
import 'dart:ui' show PlatformDispatcher;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';

final analyticsApiProvider = Provider<AnalyticsApi>((ref) => AnalyticsApi(ref.read(dioProvider)));

/// Port mobile de usePageTracking.js — fire-and-forget : n'échoue jamais
/// bruyamment et ne bloque jamais l'UI.
///   1. pageview      → à l'arrivée sur une page (voir PageTracker)
///   2. duration      → à la sortie d'une fiche produit (temps passé)
///   3. productEvent  → clics significatifs (description, panier, variante…)
class AnalyticsApi {
  final Dio _dio;
  AnalyticsApi(this._dio);

  /// Une session = un lancement de l'app (équivalent du sessionStorage web).
  static final String sessionId = _newId('s');

  /// Identifiant d'UNE ouverture de page (pour rattacher le temps passé).
  static String newViewId() => _newId('v');

  static String _newId(String prefix) {
    final r = Random();
    return '$prefix-${DateTime.now().millisecondsSinceEpoch}-'
        '${r.nextInt(1 << 32).toRadixString(36)}${r.nextInt(1 << 32).toRadixString(36)}';
  }

  /// Canal : l'app compte comme app_android / app_ios (valeurs acceptées par le back).
  static String get channel {
    if (kIsWeb) return 'direct';
    if (Platform.isIOS) return 'app_ios';
    if (Platform.isAndroid) return 'app_android';
    return 'unknown';
  }

  /// Appareil : tablette si le plus petit côté logique ≥ 600 px, sinon mobile.
  static String get deviceType {
    final views = PlatformDispatcher.instance.views;
    if (views.isEmpty) return 'mobile';
    final v = views.first;
    final logical = v.physicalSize / v.devicePixelRatio;
    return logical.shortestSide >= 600 ? 'tablet' : 'mobile';
  }

  /// pageType ∈ home, catalogue, search, product_detail, supplier_shop.
  void pageview({
    required String pageType,
    required String clientViewId,
    String? supplierId,
    String? productId,
  }) =>
      _fire('/analytics/pageview/', {
        'page_type': pageType,
        'supplier': supplierId,
        'product': productId,
        'session_id': sessionId,
        'client_view_id': clientViewId,
        'channel': channel,
        'device_type': deviceType,
        'utm_source': '',
        'utm_medium': '',
        'utm_campaign': '',
        'referrer': '',
      });

  void duration(String clientViewId, int ms) => _fire('/analytics/duration/', {
        'client_view_id': clientViewId,
        'duration_ms': ms,
      });

  /// type ∈ view_description, view_image, select_variant, add_to_cart,
  /// contact_supplier (+ open_customize, add_to_cart_customized).
  void productEvent(String productId, String type) => _fire('/analytics/product-event/', {
        'product': productId,
        'event_type': type,
        'session_id': sessionId,
      });

  Future<void> _fire(String path, Map<String, dynamic> data) async {
    try {
      await _dio.post(path, data: data);
    } catch (_) {
      // silencieux : le tracking ne doit jamais gêner l'utilisateur
    }
  }
}