double _d(v) => v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;
double? _dn(v) => v == null ? null : double.tryParse(v.toString());
int _i(v) => v == null ? 0 : int.tryParse(v.toString().split('.').first) ?? 0;
/// Chaîne optionnelle : null si absente ou vide.
String? _sn(v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

class PriceTier {
  final int minQty;
  final int? maxQty;
  final double price;
  final double oldPrice;
  const PriceTier({required this.minQty, this.maxQty, required this.price, this.oldPrice = 0});
  factory PriceTier.fromJson(Map j) => PriceTier(
        minQty: _i(j['min_qty']),
        maxQty: j['max_qty'] == null ? null : _i(j['max_qty']),
        price: _d(j['price_tnd']),
        oldPrice: _d(j['old_price_tnd']),
      );
}

class Variant {
  final String id, name;
  final String? imageUrl;
  const Variant({required this.id, required this.name, this.imageUrl});
  factory Variant.fromJson(Map j) =>
      Variant(id: '${j['id']}', name: j['name'] ?? '', imageUrl: j['image_url']);
}

class ChoiceGroup {
  final String id, name;
  final List<Variant> variants;
  const ChoiceGroup({required this.id, required this.name, this.variants = const []});
  factory ChoiceGroup.fromJson(Map j) => ChoiceGroup(
        id: '${j['id']}',
        name: j['name'] ?? '',
        variants: (j['variants'] as List? ?? [])
            .whereType<Map>().map(Variant.fromJson).toList(),
      );
}

class VariantCombo {
  final List<String> variantIds;
  final List<PriceTier> priceTiers;
  const VariantCombo({this.variantIds = const [], this.priceTiers = const []});
  factory VariantCombo.fromJson(Map j) => VariantCombo(
        variantIds: (j['variant_ids'] as List? ?? []).map((e) => '$e').toList(),
        priceTiers: (j['price_tiers'] as List? ?? []).whereType<Map>().map(PriceTier.fromJson).toList(),
      );
  String get key => (List<String>.from(variantIds)..sort()).join('|');
}

class Spec {
  final String k, v;
  const Spec(this.k, this.v);
}

class Review {
  final String id, reviewerName;
  final double rating;
  final String comment;
  /// URLs des photos jointes à l'avis (affichées en vignettes + lightbox).
  final List<String> photos;
  const Review({
    required this.id, required this.reviewerName, required this.rating,
    this.comment = '', this.photos = const [],
  });
  factory Review.fromJson(Map j) {
    final photos = <String>[];
    if (j['photos'] is List) {
      for (final ph in j['photos']) {
        final u = (ph is Map) ? (ph['url'] ?? ph['image']) : ph;
        if (u != null && '$u'.isNotEmpty) photos.add('$u');
      }
    }
    return Review(
      id: '${j['id']}',
      reviewerName: j['reviewer_name'] ?? 'Client',
      rating: _d(j['rating']),
      comment: j['comment'] ?? '',
      photos: photos,
    );
  }
}

/// Champ de personnalisation défini par le fournisseur.
/// field_type ∈ {text, number, color, image, file}.
class CustomizationField {
  final String id, label, fieldType;
  final bool required;
  final int? maxChars;
  const CustomizationField({
    required this.id, required this.label, required this.fieldType,
    this.required = false, this.maxChars,
  });

  bool get isUpload => fieldType == 'image' || fieldType == 'file';

  factory CustomizationField.fromJson(Map j) {
    final c = (j['constraints'] is Map) ? j['constraints'] as Map : const {};
    final max = _i(c['max_chars']);
    return CustomizationField(
      id: '${j['id']}',
      label: '${j['label'] ?? ''}',
      fieldType: '${j['field_type'] ?? 'text'}',
      required: j['required'] == true,
      maxChars: max > 0 ? max : null,
    );
  }
}

class ProductDetail {
  final String id, name, description;
  final List<String> images;
  final List<PriceTier> priceTiers;
  final double basePrice, oldPrice;
  final int moq;
  final String unit;
  final double ratingAvg;
  final int ratingCount, soldCount, deliveryDays;
  final double shippingPrice;
  final bool inStock, isFavorited, badgeChoice, priceLocked;
  final String? reference, categoryName, categorySlug;

  // Vidéo produit (affichée en premier dans la galerie)
  final String? videoUrl, videoPoster;

  // Fournisseur
  final String? supplierName, supplierSlug, supplierCity, supplierWilaya, supplierLogo, supplierBanner;
  final bool supplierVerified;
  final double? supplierRating;
  final int? supplierRatingCount;

  // Variantes / perso
  final List<ChoiceGroup> choiceGroups;
  final List<VariantCombo> variantCombos;
  final List<Spec> specs;
  final bool allowCustomization, customizationRequired;
  final String customizationMode;
  final double customizationExtra;
  final String? customizationInstructions;
  final List<CustomizationField> customizationFields;

  const ProductDetail({
    required this.id, required this.name, this.description = '',
    this.images = const [], this.priceTiers = const [], this.basePrice = 0, this.oldPrice = 0,
    this.moq = 1, this.unit = 'pièce', this.ratingAvg = 0, this.ratingCount = 0, this.soldCount = 0,
    this.deliveryDays = 3, this.shippingPrice = 0, this.inStock = true, this.isFavorited = false,
    this.badgeChoice = false, this.priceLocked = false, this.reference, this.categoryName, this.categorySlug,
    this.videoUrl, this.videoPoster,
    this.supplierName, this.supplierSlug, this.supplierCity, this.supplierWilaya, this.supplierLogo,
    this.supplierBanner, this.supplierVerified = false, this.supplierRating, this.supplierRatingCount,
    this.choiceGroups = const [], this.variantCombos = const [], this.specs = const [],
    this.allowCustomization = false, this.customizationRequired = false,
    this.customizationMode = 'fixed', this.customizationExtra = 0,
    this.customizationInstructions, this.customizationFields = const [],
  });

  factory ProductDetail.fromJson(Map<String, dynamic> j) {
    final imgs = <String>[];
    if (j['images'] is List) {
      for (final im in j['images']) {
        final u = (im is Map) ? im['url'] : im;
        if (u != null && '$u'.isNotEmpty) imgs.add('$u');
      }
    }
    if (imgs.isEmpty && j['primary_image'] != null) imgs.add('${j['primary_image']}');

    final specs = <Spec>[];
    if (j['specs'] is List) {
      for (final s in j['specs']) {
        if (s is Map) {
          final k = '${s['k'] ?? s['label'] ?? ''}';
          final v = '${s['v'] ?? s['value'] ?? ''}';
          if (k.isNotEmpty && v.isNotEmpty) specs.add(Spec(k, v));
        }
      }
    }

    return ProductDetail(
      id: '${j['id']}',
      name: j['name'] ?? '',
      description: j['description'] ?? '',
      images: imgs,
      priceTiers: (j['price_tiers'] as List? ?? []).whereType<Map>().map(PriceTier.fromJson).toList(),
      basePrice: _d(j['base_price_tnd']),
      oldPrice: _d(j['old_price_tnd']),
      moq: _i(j['moq']) == 0 ? 1 : _i(j['moq']),
      unit: j['unit'] ?? 'pièce',
      ratingAvg: _d(j['rating_avg']),
      ratingCount: _i(j['rating_count']),
      soldCount: _i(j['sold_count']),
      deliveryDays: _i(j['delivery_days']) == 0 ? 3 : _i(j['delivery_days']),
      shippingPrice: _d(j['shipping_price_tnd']),
      inStock: j['in_stock'] != false,
      isFavorited: j['is_favorited'] == true,
      badgeChoice: j['badge_choice'] == true,
      priceLocked: j['price_locked'] == true,
      reference: j['reference'],
      categoryName: j['category_name'],
      categorySlug: j['category_slug'] ?? '${j['category_id'] ?? ''}',
      videoUrl: _sn(j['video_url']),
      videoPoster: _sn(j['video_poster_url']),
      supplierName: j['supplier_name'],
      supplierSlug: j['supplier_slug'],
      supplierCity: j['supplier_city'],
      supplierWilaya: j['supplier_wilaya'],
      supplierLogo: j['supplier_logo'] ?? j['brand_logo_url'],
      supplierBanner: j['supplier_banner'] ?? j['banner_url'],
      supplierVerified: j['supplier_verified'] == 'approved',
      supplierRating: _dn(j['supplier_rating']),
      supplierRatingCount: j['supplier_rating_count'] == null ? null : _i(j['supplier_rating_count']),
      choiceGroups: (j['choice_groups'] as List? ?? []).whereType<Map>().map(ChoiceGroup.fromJson).toList(),
      variantCombos: (j['variant_combos'] as List? ?? []).whereType<Map>().map(VariantCombo.fromJson).toList(),
      specs: specs,
      allowCustomization: j['allow_customization'] == true,
      customizationRequired: j['customization_required'] == true,
      customizationMode: j['customization_mode'] ?? 'fixed',
      customizationExtra: _d(j['customization_extra_price_tnd']),
      customizationInstructions: _sn(j['customization_instructions']),
      customizationFields: (j['customization_fields'] as List? ?? [])
          .whereType<Map>().map(CustomizationField.fromJson).toList(),
    );
  }
}