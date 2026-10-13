/// Boutique (fournisseur) suivie par l'acheteur.
class FollowedShop {
  final String id;
  final String slug;
  final String name;
  final String? logo;
  final String? city;
  final bool verified;
  final int productCount;
  /// Produits publiés depuis la dernière visite de la boutique (fourni par Django).
  final int newProductsCount;
  final List<String> previewImages;

  const FollowedShop({
    required this.id,
    required this.slug,
    required this.name,
    this.logo,
    this.city,
    this.verified = false,
    this.productCount = 0,
    this.newProductsCount = 0,
    this.previewImages = const [],
  });

  factory FollowedShop.fromJson(Map<String, dynamic> j) {
    final raw = j['supplier'];
    final s = raw is Map ? Map<String, dynamic>.from(raw) : j;
    String? str(dynamic v) => (v == null || '$v'.isEmpty) ? null : '$v';
    return FollowedShop(
      id: '${s['id']}',
      slug: '${s['slug'] ?? ''}',
      name: '${s['company_name'] ?? s['name'] ?? ''}',
      logo: str(s['logo']),
      city: str(s['city']),
      verified: s['is_verified'] == true,
      productCount: (s['product_count'] as num?)?.toInt() ?? 0,
      newProductsCount: ((s['new_products_count'] ?? j['new_products_count']) as num?)?.toInt() ?? 0,
      previewImages: ((s['preview_images'] ?? j['preview_images']) as List? ?? const [])
          .map((e) => '$e')
          .where((e) => e.isNotEmpty)
          .toList(),
    );
  }
}