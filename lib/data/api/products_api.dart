import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';
import '../models/product_detail.dart';
import '../models/category.dart';
import 'api_client.dart';

final productsApiProvider = Provider<ProductsApi>((ref) => ProductsApi(ref.read(dioProvider)));

/// Bannière de catégorie/recherche — GET /products/category-banner/?q=
class CategoryBanner {
  final String imageUrl;
  final String? link;
  const CategoryBanner({required this.imageUrl, this.link});
}

class ProductsApi {
  final Dio _dio;
  ProductsApi(this._dio);

  List<Product> _parseList(dynamic data) {
    final list = (data is Map) ? (data['results'] ?? []) : (data ?? []);
    if (list is! List) return const [];
    return list.whereType<Map>().map((e) => Product.fromJson(e.cast<String, dynamic>())).toList();
  }

  Future<List<Product>> recommended() async => _parseList((await _dio.get('/products/recommended/')).data);
  Future<List<Product>> trending() async => _parseList((await _dio.get('/products/trending/')).data);

  Future<List<Product>> list({String? categoryId, bool includeDescendants = false, int? pageSize}) async {
    final qp = <String, dynamic>{};
    if (categoryId != null) qp['category_id'] = categoryId;
    if (includeDescendants) qp['include_descendants'] = 1;
    if (pageSize != null) qp['page_size'] = pageSize;
    return _parseList((await _dio.get('/products/', queryParameters: qp)).data);
  }

  // Recherche texte — équivalent web productsApi.search(query, { category_id, include_descendants }).
  // NB : chemin SANS /api (la base dio inclut déjà /api).
  Future<List<Product>> search(String query, {String? categoryId, bool includeDescendants = false}) async {
    final qp = <String, dynamic>{'q': query};
    if (categoryId != null) qp['category_id'] = categoryId;
    if (includeDescendants) qp['include_descendants'] = 1;
    return _parseList((await _dio.get('/products/search/', queryParameters: qp)).data);
  }

  /// Bannière associée à un terme (nom de catégorie ou requête), ou null.
  Future<CategoryBanner?> categoryBanner(String term) async {
    final d = (await _dio.get('/products/category-banner/', queryParameters: {'q': term})).data;
    final b = d is Map ? d['banner'] : null;
    if (b is! Map || (b['image_url'] ?? '').toString().isEmpty) return null;
    final link = b['link']?.toString();
    return CategoryBanner(imageUrl: '${b['image_url']}', link: (link == null || link.isEmpty) ? null : link);
  }

  // ⭐ Recherche par image — équivalent web productsApi.visualSearch(file, topK).
  //    Upload multipart vers le proxy Django (CLIP+FAISS) : { results, count }.
  //    _parseList lit data['results'] (Product.fromJson ignore le visual_score).
  Future<List<Product>> visualSearch(String imagePath, {int topK = 20}) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(imagePath),
    });
    final res = await _dio.post(
      '/products/visual-search/',
      queryParameters: {'top_k': topK},
      data: form,
      options: Options(sendTimeout: const Duration(seconds: 30), receiveTimeout: const Duration(seconds: 30)),
    );
    return _parseList(res.data);
  }

  // ⭐ Recherche par URL d'image publique — équivalent web productsApi.visualSearchByUrl.
  //    Sert au bouton « recherche visuelle » des Favoris / Historique (image produit).
  Future<List<Product>> visualSearchByUrl(String imageUrl, {int topK = 20}) async {
    final res = await _dio.post(
      '/products/visual-search-url/',
      data: {'image_url': imageUrl, 'top_k': topK},
      options: Options(receiveTimeout: const Duration(seconds: 30)),
    );
    return _parseList(res.data);
  }

  Future<List<Category>> categories() async {
    final data = (await _dio.get('/products/categories/')).data;
    final list = (data is Map) ? (data['results'] ?? []) : (data ?? []);
    if (list is! List) return const [];
    return list.whereType<Map>().map((e) => Category.fromJson(e.cast<String, dynamic>())).toList();
  }

  Future<ProductDetail> detail(String id) async {
    final r = await _dio.get('/products/$id/');
    return ProductDetail.fromJson((r.data as Map).cast<String, dynamic>());
  }

  Future<List<Product>> similar(String id) async => _parseList((await _dio.get('/products/$id/similar/')).data);
  Future<List<Product>> recommendations(String id) async => _parseList((await _dio.get('/products/$id/recommendations/')).data);

  Future<List<Review>> reviews(String id) async {
    final data = (await _dio.get('/products/$id/reviews/')).data;
    final list = (data is Map) ? (data['results'] ?? []) : (data ?? []);
    if (list is! List) return const [];
    return list.whereType<Map>().map(Review.fromJson).toList();
  }

  Future<void> addFavorite(String id) => _dio.post('/products/favorites/', data: {'product_id': id});
  Future<void> removeFavorite(String id) => _dio.delete('/products/favorites/$id/');
}

// ── Providers "cache" ──
final recommendedProvider = FutureProvider<List<Product>>((ref) => ref.read(productsApiProvider).recommended());
final trendingProvider = FutureProvider<List<Product>>((ref) => ref.read(productsApiProvider).trending());
final categoriesProvider = FutureProvider<List<Category>>((ref) => ref.read(productsApiProvider).categories());
final categoryProductsProvider = FutureProvider.family<List<Product>, String?>((ref, catId) {
  final api = ref.read(productsApiProvider);
  return catId == null ? api.recommended() : api.list(categoryId: catId, includeDescendants: true, pageSize: 20);
});