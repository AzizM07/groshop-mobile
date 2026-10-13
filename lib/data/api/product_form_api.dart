import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

final productFormApiProvider = Provider<ProductFormApi>((ref) => ProductFormApi(ref.read(dioProvider)));

/// Catégories brutes (racines + enfants) pour le formulaire produit.
final productFormCategoriesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) => ref.read(productFormApiProvider).categories());

/// Appels du formulaire « Ajouter / Modifier un produit » (équivalent AddProductPage.jsx).
/// Travaille en JSON brut pour coller exactement au payload du web.
class ProductFormApi {
  final Dio _dio;
  ProductFormApi(this._dio);

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

  // GET /products/categories/
  Future<List<Map<String, dynamic>>> categories() async {
    final d = _decode((await _dio.get('/products/categories/')).data);
    final list = (d is Map) ? (d['results'] ?? const []) : (d ?? const []);
    if (list is! List) return const [];
    return list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  // GET /products/{id}/  (édition)
  Future<Map<String, dynamic>> detail(String id) async {
    final d = _decode((await _dio.get('/products/$id/')).data);
    return (d is Map) ? d.cast<String, dynamic>() : <String, dynamic>{};
  }

  // POST /products/create/
  Future<void> create(Map<String, dynamic> payload) => _dio.post('/products/create/', data: payload);

  // PATCH /products/{id}/
  Future<void> update(String id, Map<String, dynamic> payload) => _dio.patch('/products/$id/', data: payload);

  // POST /products/upload-image/  (multipart "file") → { url }
  Future<String> uploadImage(String path) async {
    final form = FormData.fromMap({'file': await MultipartFile.fromFile(path)});
    final res = await _dio.post(
      '/products/upload-image/',
      data: form,
      options: Options(sendTimeout: const Duration(seconds: 60), receiveTimeout: const Duration(seconds: 60)),
    );
    final d = _decode(res.data);
    final url = (d is Map) ? (d['url'] ?? '').toString() : '';
    if (url.isEmpty) throw Exception('Upload échoué');
    return url;
  }

  // POST /products/upload-video/  (multipart "file") → { url, poster }
  Future<({String url, String poster})> uploadVideo(String path) async {
    final form = FormData.fromMap({'file': await MultipartFile.fromFile(path)});
    final res = await _dio.post(
      '/products/upload-video/',
      data: form,
      options: Options(sendTimeout: const Duration(minutes: 5), receiveTimeout: const Duration(minutes: 5)),
    );
    final d = _decode(res.data);
    final url = (d is Map) ? (d['url'] ?? '').toString() : '';
    if (url.isEmpty) throw Exception('Upload vidéo échoué');
    return (url: url, poster: (d is Map ? (d['poster'] ?? '') : '').toString());
  }
}