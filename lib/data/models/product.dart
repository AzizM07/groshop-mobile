double? _toD(dynamic v) => v == null ? null : double.tryParse(v.toString());
int? _toI(dynamic v) =>
    v == null ? null : int.tryParse(v.toString().split('.').first);
DateTime? _toDate(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString());

/// Fallback string : traite aussi une chaîne vide comme "absente"
/// (Django `unit = CharField(blank=True)` peut renvoyer '').
String _toS(dynamic v, String fallback) {
  final s = v?.toString();
  return (s == null || s.isEmpty) ? fallback : s;
}

class Product {
  final String id;
  final String slug;
  final String name;
  final double basePrice;
  final double? oldPrice;
  final String? primaryImage;
  final List<String> images;
  final List<double> priceTiers;
  final int? soldCount;
  final double? ratingAvg;
  final int? reviewCount;
  final int? moq;
  final String unit;
  final bool badgeChoice; // → bandeau bleu "Certifié Original"
  final bool badgeFlash; // → badge "Promo"
  final DateTime? badgeFlashEnd;
  final bool isFreeShipping;
  final bool inStock;
  final String? supplierName;
  final String? supplierSlug;
  final String? categoryName;
  final bool supplierVerified;
  final int supplierMedals;
  final int? yearsActive;

  /// 'public' | 'verified_only'
  final String priceVisibility;

  /// Si true, le backend a déjà masqué basePrice/oldPrice/moq/priceTiers
  /// (ils valent 0/null/[] dans ce cas, PAS le vrai prix) — vérifier ce flag
  /// avant d'afficher basePrice dans l'UI.
  final bool priceLocked;

  final bool allowCustomization;
  final String customizationMode; // 'fixed' | 'quote'

  const Product({
    required this.id,
    required this.slug,
    required this.name,
    required this.basePrice,
    this.oldPrice,
    this.primaryImage,
    this.images = const [],
    this.priceTiers = const [],
    this.soldCount,
    this.ratingAvg,
    this.reviewCount,
    this.moq,
    this.unit = 'pcs',
    this.badgeChoice = false,
    this.badgeFlash = false,
    this.badgeFlashEnd,
    this.isFreeShipping = false,
    this.inStock = true,
    this.supplierName,
    this.supplierSlug,
    this.categoryName,
    this.supplierVerified = false,
    this.supplierMedals = 0,
    this.yearsActive,
    this.priceVisibility = 'public',
    this.priceLocked = false,
    this.allowCustomization = false,
    this.customizationMode = 'fixed',
  });

  /// Réplique computePrice() du web : min/max des paliers, sinon prix de base.
  (double, double) get priceRange {
    if (priceTiers.isEmpty) return (basePrice, basePrice);
    final mn = priceTiers.reduce((a, b) => a < b ? a : b);
    final mx = priceTiers.reduce((a, b) => a > b ? a : b);
    return (mn, mx);
  }

  bool get isPriceRange {
    final (mn, mx) = priceRange;
    return mn != mx;
  }

  int? get discount {
    if (priceLocked) return null;
    if (oldPrice != null && oldPrice! > basePrice && basePrice > 0) {
      return ((1 - basePrice / oldPrice!) * 100).round();
    }
    return null;
  }

  bool get isPromo =>
      badgeFlash || (oldPrice != null && oldPrice! > basePrice);

  factory Product.fromJson(Map<String, dynamic> j) {
    final tiers = <double>[];
    final rawTiers = j['price_tiers'];
    if (rawTiers is List) {
      for (final t in rawTiers) {
        final p = (t is Map) ? _toD(t['price_tnd']) : _toD(t);
        if (p != null) tiers.add(p);
      }
    }

    final imgs = <String>[];
    final rawImgs = j['images'];
    if (rawImgs is List) {
      for (final im in rawImgs) {
        final u = (im is Map) ? (im['url'] ?? im['image_url']) : im;
        if (u != null && u.toString().isNotEmpty) imgs.add(u.toString());
      }
    }

    return Product(
      id: '${j['id']}',
      slug: j['slug'] ?? '',
      name: j['name'] ?? '',
      basePrice: _toD(j['base_price_tnd']) ?? 0,
      oldPrice: _toD(j['old_price_tnd']),
      primaryImage: j['primary_image'] ?? j['image'],
      images: imgs,
      priceTiers: tiers,
      soldCount: _toI(j['sold_count']),
      ratingAvg: _toD(j['rating_avg']),
      reviewCount: _toI(j['rating_count'] ?? j['review_count']),
      moq: _toI(j['moq']),
      unit: _toS(j['unit'], 'pcs'),
      badgeChoice: j['badge_choice'] == true,
      badgeFlash: j['badge_flash'] == true,
      badgeFlashEnd: _toDate(j['badge_flash_end']),
      isFreeShipping: j['is_free_shipping'] == true,
      inStock: j['in_stock'] != false, // absent → considéré en stock
      supplierName: j['supplier_name'],
      supplierSlug: j['supplier_slug'],
      categoryName: j['category_name'],
      // supplier_verified côté backend = verification_status (string), pas un bool brut
      supplierVerified: j['supplier_verified'] == 'approved',
      supplierMedals: _toI(j['supplier_medals']) ?? 0,
      yearsActive: _toI(j['years_active']),
      priceVisibility: _toS(j['price_visibility'], 'public'),
      priceLocked: j['price_locked'] == true,
      allowCustomization: j['allow_customization'] == true,
      customizationMode: _toS(j['customization_mode'], 'fixed'),
    );
  }
}