// data/models/supplier_profile_models.dart — GROSHOP.tn
// Modèles de la vitrine PUBLIQUE fournisseur (GET /auth/suppliers/{slug}/).
// Parsing volontairement tolérant : plusieurs clés possibles, tout optionnel.

double _toD(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

int _toI(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

String _s(dynamic v) => (v ?? '').toString();

String? _sn(dynamic v) {
  final s = _s(v);
  return s.isEmpty ? null : s;
}

String? _firstUrl(List<dynamic> candidates) {
  for (final c in candidates) {
    final s = (c ?? '').toString();
    if (s.isNotEmpty) return s;
  }
  return null;
}

List<String> _strList(dynamic v) {
  if (v is List) {
    return v
        .map((e) => e is Map ? _s(e['url'] ?? e['image'] ?? e['image_url']) : _s(e))
        .where((s) => s.isNotEmpty)
        .toList();
  }
  if (v is String) {
    return v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }
  return const [];
}

class SupplierProfile {
  final String id, companyName, slug, city, wilaya, createdAt;
  final bool verified;
  final double ratingAvg;
  final int ratingCount, followersCount;
  final SupplierStore store;
  final List<SupplierReview> reviews;

  const SupplierProfile({
    required this.id,
    required this.companyName,
    required this.slug,
    required this.city,
    required this.wilaya,
    required this.createdAt,
    required this.verified,
    required this.ratingAvg,
    required this.ratingCount,
    required this.followersCount,
    required this.store,
    required this.reviews,
  });

  factory SupplierProfile.fromJson(Map<String, dynamic> j) {
    final rawStore = j['store'] ?? j['supplier_store'] ?? j;
    final cn = _s(j['company_name']);
    return SupplierProfile(
      id: _s(j['id']),
      companyName: cn.isNotEmpty ? cn : _s(j['name']),
      slug: _s(j['slug']),
      city: _s(j['city']),
      wilaya: _s(j['wilaya']),
      createdAt: _s(j['created_at']),
      verified: _s(j['verification_status']) == 'verified',
      ratingAvg: _toD(j['rating_avg'] ?? j['rating']),
      ratingCount: _toI(j['rating_count']),
      followersCount: _toI(j['followers_count']),
      store: SupplierStore.fromJson(
          (rawStore is Map) ? rawStore.cast<String, dynamic>() : const {}),
      reviews: ((j['reviews'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => SupplierReview.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

class SupplierStore {
  final String? logoUrl, bannerUrl, heroTitle, description, mission;
  final double? responseRate;
  final List<String> certifications, aboutImages;

  const SupplierStore({
    this.logoUrl,
    this.bannerUrl,
    this.heroTitle,
    this.description,
    this.mission,
    this.responseRate,
    this.certifications = const [],
    this.aboutImages = const [],
  });

  factory SupplierStore.fromJson(Map<String, dynamic> j) => SupplierStore(
        logoUrl: _firstUrl([j['brand_logo_url'], j['logo_url'], j['logo']]),
        bannerUrl: _firstUrl([j['banner_url'], j['banner']]),
        heroTitle: _sn(j['hero_title']),
        description: _sn(j['description']),
        mission: _sn(j['mission']),
        responseRate: j['response_rate'] != null ? _toD(j['response_rate']) : null,
        certifications: _strList(j['certifications']),
        aboutImages: _strList(j['about_images']),
      );
}

class SupplierReview {
  final double rating;
  final String text, authorName, city, avatarUrl;
  final List<String> images;

  const SupplierReview({
    required this.rating,
    required this.text,
    required this.authorName,
    required this.city,
    required this.avatarUrl,
    required this.images,
  });

  factory SupplierReview.fromJson(Map<String, dynamic> j) {
    final a = _s(j['author_name']);
    final r = _s(j['reviewer_name']);
    final att = _strList(j['attached_images']);
    return SupplierReview(
      rating: _toD(j['rating']),
      text: _s(j['text']).isNotEmpty ? _s(j['text']) : _s(j['comment']),
      authorName: a.isNotEmpty ? a : (r.isNotEmpty ? r : 'Client'),
      city: _s(j['city']),
      avatarUrl: _s(j['avatar_url']),
      images: att.isNotEmpty ? att : _strList(j['photos']),
    );
  }
}