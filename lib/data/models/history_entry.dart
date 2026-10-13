import 'product.dart';

/// Un produit consulté + la date de consultation.
/// Accepte `{product: {...}, viewed_at: "..."}` ou un produit « à plat »
/// avec un champ `viewed_at`.
class HistoryEntry {
  final Product product;
  final DateTime? viewedAt;
  const HistoryEntry({required this.product, this.viewedAt});

  factory HistoryEntry.fromJson(Map<String, dynamic> j) {
    final raw = j['product'];
    final productJson = raw is Map ? Map<String, dynamic>.from(raw) : j;
    return HistoryEntry(
      product: Product.fromJson(productJson),
      viewedAt: DateTime.tryParse('${j['viewed_at'] ?? ''}')?.toLocal(),
    );
  }
}