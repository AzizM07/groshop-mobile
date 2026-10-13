import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';

// ── Modèles légers pour l'autocomplétion ──
class AutoProduct {
  final String id;
  final String name;
  final double? price;
  final String? image;
  const AutoProduct({required this.id, required this.name, this.price, this.image});
}

class AutoCategory {
  final String id;
  final String name;
  const AutoCategory({required this.id, required this.name});
}

class AutoResult {
  final List<String> completions;
  final List<AutoProduct> products;
  final List<AutoCategory> categories;
  const AutoResult({
    this.completions = const [],
    this.products = const [],
    this.categories = const [],
  });
  bool get isEmpty =>
      completions.isEmpty && products.isEmpty && categories.isEmpty;
  static const empty = AutoResult();
}

final searchApiProvider = Provider<SearchApi>((ref) => SearchApi(ref.read(dioProvider)));

class SearchApi {
  final Dio _dio;
  SearchApi(this._dio);

  // Défensif : selon la config dio, res.data peut arriver en String (JSON non
  // décodé) — on décode ici si besoin (même leçon que pour les bannières).
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

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  // GET /products/autocomplete/?q=  → { completions, products, categories }
  Future<AutoResult> autocomplete(String query) async {
    try {
      final data = _decode(
          (await _dio.get('/products/autocomplete/', queryParameters: {'q': query})).data);
      if (data is! Map) return AutoResult.empty;

      final comps = (data['completions'] is List)
          ? (data['completions'] as List).whereType<String>().toList()
          : <String>[];

      final prods = (data['products'] is List)
          ? (data['products'] as List).whereType<Map>().map((m) {
              return AutoProduct(
                id: '${m['id']}',
                name: m['name']?.toString() ?? '',
                price: _toDouble(m['price']),
                image: m['image']?.toString(),
              );
            }).toList()
          : <AutoProduct>[];

      final cats = (data['categories'] is List)
          ? (data['categories'] as List).whereType<Map>().map((m) {
              return AutoCategory(id: '${m['id']}', name: m['name']?.toString() ?? '');
            }).toList()
          : <AutoCategory>[];

      return AutoResult(completions: comps, products: prods, categories: cats);
    } catch (_) {
      return AutoResult.empty;
    }
  }

  // GET /store/recent-searches/  → { searches: [...] }  (nécessite d'être connecté)
  Future<List<String>> recentSearches() async {
    try {
      final data = _decode((await _dio.get('/store/recent-searches/')).data);
      final list = (data is Map) ? (data['searches'] ?? const []) : const [];
      return (list is List) ? list.whereType<String>().toList() : const [];
    } catch (_) {
      return const [];
    }
  }

  // POST /store/recent-searches/clear/
  Future<void> clearRecentSearches() async {
    try {
      await _dio.post('/store/recent-searches/clear/');
    } catch (_) {
      // silencieux
    }
  }
}