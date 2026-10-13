import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';

final customizationApiProvider =
    Provider<CustomizationApi>((ref) => CustomizationApi(ref.read(dioProvider)));

/// Port de l'objet `customization` de lib/api.js (+ l'ajout panier personnalisé
/// de cart.add avec opts.isCustomized).
class CustomizationApi {
  final Dio _dio;
  CustomizationApi(this._dio);

  /// POST /products/upload-customization-file/ (multipart) → URL du fichier.
  /// Envoi depuis les octets : fonctionne même sans chemin fichier (URI Android).
  Future<String> uploadBytes(Uint8List bytes, {required String filename}) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final r = await _dio.post(
      '/products/upload-customization-file/',
      data: form,
      options: Options(
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    final url = (r.data is Map) ? r.data['url'] : null;
    if (url == null || '$url'.isEmpty) throw Exception('Upload échoué');
    return '$url';
  }

  /// Mode « fixed » : ajoute directement au panier une ligne personnalisée.
  Future<void> addToCart({
    required String productId,
    required int quantity,
    String? variantId,
    required List<Map<String, dynamic>> values,
  }) async {
    await _dio.post('/cart/', data: {
      'product_id': productId,
      'quantity': quantity,
      'variant_id': variantId,
      'is_customized': true,
      'customization_values': values,
      'customization_request_id': null,
    });
  }

  /// Mode « quote » : crée la demande de devis → id de la conversation créée.
  Future<String?> createRequest({
    required String productId,
    required int quantity,
    String? variantId,
    required List<Map<String, dynamic>> values,
  }) async {
    final r = await _dio.post('/orders/customization-requests/', data: {
      'product_id': productId,
      'variant_id': variantId,
      'quantity': quantity,
      'values': values,
    });
    final c = (r.data is Map) ? r.data['conversation'] : null;
    return (c == null || '$c'.isEmpty) ? null : '$c';
  }
}

/// Message lisible depuis une erreur Dio (mêmes clés que request() côté web).
String apiErrorMessage(Object e, String fallback) {
  if (e is DioException) {
    final d = e.response?.data;
    if (d is Map) {
      for (final k in ['error', 'detail', 'message']) {
        if (d[k] != null && '${d[k]}'.isNotEmpty) return '${d[k]}';
      }
      for (final v in d.values) {
        if (v is List && v.isNotEmpty) return '${v.first}';
      }
    }
    if (e.type == DioExceptionType.sendTimeout || e.type == DioExceptionType.receiveTimeout) {
      return 'Le téléversement a expiré. Vérifiez votre connexion ou essayez un fichier plus léger.';
    }
  }
  return fallback;
}