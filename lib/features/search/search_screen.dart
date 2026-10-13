import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart' show DioException;
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import '../../core/config.dart';
import '../../core/links.dart';
import '../../core/theme.dart';
import '../../data/api/api_client.dart' show dioProvider;
import '../../data/api/products_api.dart';
import '../../data/models/product.dart';
import '../../data/models/category.dart';
import '../../widgets/product_card.dart';
import '../home/widgets/home_header.dart';

// ─────────────────────────── Données (alignées sur SearchPage.jsx) ───────────────────────────

/// Recherche : clé (q, cat). Texte prioritaire ; si une catégorie est aussi
/// fournie, elle restreint la recherche (comme le web).
/// Catégories (q vide) : gardées en cache → y revenir est instantané.
/// Une ERREUR n'est jamais gardée : le lien keepAlive est relâché → nouvel essai
/// au prochain affichage.
final searchResultsProvider =
    FutureProvider.autoDispose.family<List<Product>, (String, String?)>((ref, key) async {
  final (q, cat) = key;
  final link = q.isEmpty ? ref.keepAlive() : null;
  final api = ref.read(productsApiProvider);
  try {
    if (q.isNotEmpty) {
      return await api.search(q, categoryId: cat, includeDescendants: cat != null);
    }
    return await api.list(categoryId: cat, includeDescendants: true, pageSize: 60);
  } catch (_) {
    link?.close();
    rethrow;
  }
});

/// Conservé pour compatibilité (d'autres écrans peuvent l'utiliser).
/// Cet écran utilise [_bannerProvider], plus robuste.
final searchBannerProvider = FutureProvider.autoDispose.family<CategoryBanner?, String>((ref, term) async {
  if (term.isEmpty) return null;
  try {
    return await ref.read(productsApiProvider).categoryBanner(term);
  } catch (_) {
    return null;
  }
});

// ─────────────────────────── Bannière (même source que le web) ───────────────────────────

/// Bannière résolue : URL d'image ABSOLUE + lien éventuel.
class _Banner {
  final String imageUrl;
  final String? link;
  const _Banner(this.imageUrl, this.link);
}

/// Le backend stocke les fichiers en chemins relatifs (« /media/… »). Le
/// navigateur les résout tout seul, mais une app mobile a besoin de l'URL
/// complète → on préfixe avec l'origine de l'API (https://api.groshop.tn).
String _absolute(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  final base = Uri.parse(AppConfig.apiBaseUrl);
  final origin = '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}';
  return url.startsWith('/') ? '$origin$url' : '$origin/$url';
}

/// Lit la réponse de /products/category-banner/ : le web fait `d?.banner`,
/// donc forme `{ banner: { image_url, link } }` — on accepte aussi la forme à plat.
_Banner? _parseBanner(Object? data) {
  if (data is! Map) return null;
  final b = data['banner'] is Map ? data['banner'] as Map : data;
  final img = '${b['image_url'] ?? b['banner_url'] ?? b['url'] ?? ''}'.trim();
  if (img.isEmpty || img == 'null') return null;
  final link = '${b['link'] ?? b['banner_link'] ?? ''}'.trim();
  return _Banner(_absolute(img), link.isEmpty || link == 'null' ? null : link);
}

/// Bannière pour (terme principal, terme de repli) : ex. la sous-catégorie
/// active, sinon sa catégorie parente. Gardée en cache une fois chargée.
/// Un « pas de bannière » (réponse du serveur) est gardé ; un échec RÉSEAU
/// ne l'est pas → nouvel essai au prochain affichage.
final _bannerProvider = FutureProvider.autoDispose.family<_Banner?, (String, String?)>((ref, key) async {
  final (primary, fallback) = key;
  final link = ref.keepAlive();
  final dio = ref.read(dioProvider);
  var networkFailure = false;
  for (final term in [primary, if (fallback != null && fallback != primary) fallback]) {
    if (term.isEmpty) continue;
    try {
      final r = await dio.get('/products/category-banner/', queryParameters: {'q': term});
      final code = r.statusCode ?? 0;
      if (code >= 200 && code < 300) {
        final b = _parseBanner(r.data);
        if (b != null) return b;
      } else {
        if (code >= 500) networkFailure = true;
        debugPrint('🖼️ category-banner?q=$term → HTTP $code');
      }
    } catch (e) {
      final code = e is DioException ? e.response?.statusCode : null;
      if (code == null || code >= 500) networkFailure = true;
      debugPrint('🖼️ category-banner?q=$term → $e');
    }
  }
  if (networkFailure) link.close();
  return null;
});

/// Recherche récursive d'une catégorie dans l'arbre (le web : findCategoryById).
Category? _findCategory(List<Category> cats, String? id) {
  if (id == null || id.isEmpty) return null;
  for (final c in cats) {
    if (c.id == id) return c;
    // ignore: dead_null_aware_expression
    final found = _findCategory(c.children ?? const <Category>[], id);
    if (found != null) return found;
  }
  return null;
}

/// Noms d'une catégorie ET de toute sa descendance : une capsule doit montrer
/// aussi les produits rangés dans ses sous-sous-catégories (ex. « Pneus » dans
/// la capsule « Pneus & Jantes »).
Set<String> _namesWithDescendants(Category c) {
  final names = <String>{c.name};
  // ignore: dead_null_aware_expression
  for (final child in c.children ?? const <Category>[]) {
    names.addAll(_namesWithDescendants(child));
  }
  return names;
}

// ─────────────────────────── Préchargement du catalogue ───────────────────────────

/// Précharge, dès l'ouverture de l'app, tout ce que les catégories affichent :
///  1. produits + bannière (image décodée) de chaque catégorie principale ;
///  2. bannière (image décodée) + icône de chaque sous-catégorie.
/// Remplit les MÊMES providers, avec les MÊMES clés que [SearchResultsView] :
/// toucher une catégorie / capsule affiche donc tout instantanément.
///
/// Appelé par [HomeHeader] dès que la liste des catégories est disponible.
/// Ne tourne qu'une fois par arbre de catégories (relancé s'il change).
class CatalogPrefetch {
  CatalogPrefetch._();

  /// Requêtes en parallèle (pour ne pas saturer le réseau au démarrage).
  static const _concurrency = 3;

  /// Laisse d'abord l'accueil charger son propre contenu.
  static const _startDelay = Duration(milliseconds: 800);

  /// Taille minimale du cache d'images en mémoire (défaut Flutter : 100 Mo).
  /// Baisse-la si tu vises des téléphones très modestes.
  static const _minImageCacheBytes = 160 << 20;

  static String? _signature;

  static void start(BuildContext context, List<Category> categories) {
    if (categories.isEmpty) return;
    final sig = categories.map((c) => '${c.id}:${_children(c).map((s) => s.id).join(',')}').join('|');
    if (sig == _signature) return;
    _signature = sig;

    // Capturés tout de suite : le préchargement survit même si ce widget disparaît.
    final container = ProviderScope.containerOf(context, listen: false);
    final config = createLocalImageConfiguration(context);
    Future.delayed(_startDelay, () => _run(container, config, categories));
  }

  static List<Category> _children(Category c) {
    // ignore: dead_null_aware_expression
    return c.children ?? const <Category>[];
  }

  static Future<void> _run(ProviderContainer c, ImageConfiguration cfg, List<Category> cats) async {
    final cache = PaintingBinding.instance.imageCache;
    if (cache.maximumSizeBytes < _minImageCacheBytes) cache.maximumSizeBytes = _minImageCacheBytes;

    // 1. Catégories principales : produits + bannière.
    //    Clé bannière identique à SearchResultsView avec « Tout » actif : (nom, nom).
    await _pool<Category>(cats, (cat) async {
      await Future.wait([
        c.read(searchResultsProvider(('', cat.id.toString())).future).then((_) {}, onError: (_) {}),
        _banner(c, cfg, (cat.name, cat.name)),
      ]);
    });

    // 2. Sous-catégories : bannière (clé = (capsule, parent)) + icône de la capsule.
    final subs = <(Category, Category)>[
      for (final cat in cats)
        for (final s in _children(cat)) (cat, s),
    ];
    await _pool<(Category, Category)>(subs, (pair) async {
      final (parent, sub) = pair;
      await _banner(c, cfg, (sub.name, parent.name));
      final String? img = sub.imageUrl;
      if (img != null && img.isNotEmpty) {
        await _warm(CachedNetworkImageProvider(_absolute(img)), cfg);
      }
    });

    debugPrint('📦 Catalogue préchargé : ${cats.length} catégories, ${subs.length} sous-catégories');
  }

  static Future<void> _banner(ProviderContainer c, ImageConfiguration cfg, (String, String?) key) async {
    try {
      final b = await c.read(_bannerProvider(key).future);
      if (b != null) await _warm(CachedNetworkImageProvider(b.imageUrl), cfg);
    } catch (_) {}
  }

  /// Télécharge (cache disque) ET décode (cache mémoire) une image.
  /// Même provider que le widget CachedNetworkImage → même clé de cache.
  static Future<void> _warm(ImageProvider provider, ImageConfiguration cfg) {
    final done = Completer<void>();
    final stream = provider.resolve(cfg);
    late final ImageStreamListener listener;
    void finish() {
      if (done.isCompleted) return;
      done.complete();
      stream.removeListener(listener);
    }

    listener = ImageStreamListener((_, __) => finish(), onError: (_, __) => finish());
    stream.addListener(listener);
    return done.future.timeout(const Duration(seconds: 20), onTimeout: finish);
  }

  /// Exécute [task] sur chaque élément, [_concurrency] à la fois.
  static Future<void> _pool<T>(List<T> items, Future<void> Function(T) task) async {
    var next = 0;
    Future<void> worker() async {
      while (next < items.length) {
        final item = items[next++];
        try {
          await task(item);
        } catch (_) {}
      }
    }

    await Future.wait([for (var i = 0; i < _concurrency; i++) worker()]);
  }
}

// ─────────────────────────── Facettes (useFacetFilters du web) ───────────────────────────

const _orange = Color(0xFFFF7A00);
const _ink = Color(0xFF0F1419);
const _mute = Color(0xFF6B7785);
const _line = Color(0xFFF1F0EE);

const _moqBuckets = <(String, String, bool Function(int))>[
  ('low', 'MOQ ≤ 20', _moqLow),
  ('mid', 'MOQ 21 à 50', _moqMid),
  ('high', 'MOQ > 50', _moqHigh),
];
bool _moqLow(int m) => m <= 20;
bool _moqMid(int m) => m > 20 && m <= 50;
bool _moqHigh(int m) => m > 50;

bool _isBest(Product p) => (p.soldCount ?? 0) > 1000;
bool _isPromo(Product p) => p.oldPrice != null && p.oldPrice! > p.basePrice;

class _Facets {
  RangeValues? price;
  final Set<String> moq;
  bool best;
  bool promo;
  _Facets({this.price, Set<String>? moq, this.best = false, this.promo = false}) : moq = moq ?? {};

  _Facets copy() => _Facets(price: price, moq: {...moq}, best: best, promo: promo);

  int activeCount(RangeValues bounds) =>
      moq.length +
      (best ? 1 : 0) +
      (promo ? 1 : 0) +
      ((price != null && price != bounds) ? 1 : 0);

  List<Product> apply(List<Product> list) => list.where((p) {
        if (moq.isNotEmpty &&
            !_moqBuckets.any((b) => moq.contains(b.$1) && b.$3(p.moq ?? 1))) {
          return false;
        }
        if (price != null && (p.basePrice < price!.start || p.basePrice > price!.end)) return false;
        if (best && !_isBest(p)) return false;
        if (promo && !_isPromo(p)) return false;
        return true;
      }).toList();
}

RangeValues _boundsOf(List<Product> list) {
  if (list.isEmpty) return const RangeValues(0, 100);
  var lo = list.first.basePrice.toDouble(), hi = lo;
  for (final p in list) {
    final v = p.basePrice.toDouble();
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  lo = lo.floorToDouble();
  hi = hi.ceilToDouble();
  if (hi <= lo) hi = lo + 1;
  return RangeValues(lo, hi);
}

const _sorts = <(String, String)>[
  ('relevance', 'Meilleures correspondances'),
  ('sold', 'Top ventes'),
  ('price_asc', 'Prix croissant'),
  ('price_desc', 'Prix décroissant'),
];

List<Product> _sorted(List<Product> list, String sort) {
  final r = [...list];
  switch (sort) {
    case 'sold':
      r.sort((a, b) => (b.soldCount ?? 0).compareTo(a.soldCount ?? 0));
    case 'price_asc':
      r.sort((a, b) => a.basePrice.compareTo(b.basePrice));
    case 'price_desc':
      r.sort((a, b) => b.basePrice.compareTo(a.basePrice));
  }
  return r;
}

// ─────────────────────────── Écran (route /search) ───────────────────────────

/// Page de résultats autonome : recherche texte (?q=) ou lien direct vers une
/// catégorie (?cat=). Depuis l'accueil, les catégories ne passent plus par ici :
/// elles s'affichent DANS l'accueil via [SearchResultsView].
class SearchScreen extends ConsumerStatefulWidget {
  final String? categoryId;
  final String? query;
  const SearchScreen({super.key, this.categoryId, this.query});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  bool _scrolled = false;

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final hasQuery = (widget.query?.trim() ?? '').isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(children: [
        HomeHeader(
          scrolled: _scrolled,
          categories: categories,
          initialQuery: widget.query,
          activeCategoryId: hasQuery ? null : widget.categoryId,
        ),
        Expanded(
          child: SearchResultsView(
            categoryId: widget.categoryId,
            query: widget.query,
            onScrolled: (s) {
              if (s != _scrolled && mounted) setState(() => _scrolled = s);
            },
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────── Contenu réutilisable ───────────────────────────

/// Résultats (bannière, sous-catégories, filtres, grille) SANS header.
/// Utilisé par la page /search et directement dans l'accueil pour une catégorie.
class SearchResultsView extends ConsumerStatefulWidget {
  final String? categoryId;
  final String? query;
  /// Appelé quand le contenu passe au-dessus / en dessous de 30 px de défilement
  /// (le header change alors de style).
  final ValueChanged<bool>? onScrolled;
  const SearchResultsView({super.key, this.categoryId, this.query, this.onScrolled});

  @override
  ConsumerState<SearchResultsView> createState() => _SearchResultsViewState();
}

class _SearchResultsViewState extends ConsumerState<SearchResultsView> {
  final _scroll = ScrollController();
  bool _scrolled = false;
  String _activeSub = 'all';
  bool _sortBySold = false;     // catégorie de 1er niveau (barre simple)
  String _sort = 'relevance';   // recherche / sous-catégorie (barre filtres)
  _Facets _facets = _Facets();
  List<Product>? _facetSource;  // pour réinitialiser les facettes si les résultats changent

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final s = _scroll.offset > 30;
      if (s != _scrolled) {
        _scrolled = s;
        widget.onScrolled?.call(s);
      }
    });
  }

  @override
  void didUpdateWidget(covariant SearchResultsView old) {
    super.didUpdateWidget(old);
    if (old.categoryId != widget.categoryId || old.query != widget.query) {
      _activeSub = 'all';
      _sortBySold = false;
      _sort = 'relevance';
      _facets = _Facets();
      _facetSource = null;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _goBanner(_Banner b) {
    final l = b.link;
    if (l == null) return;
    if (l.startsWith('http')) {
      openExternal(context, l);
    } else {
      context.push(l);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final q = widget.query?.trim() ?? '';
    final cat = (widget.categoryId?.isNotEmpty ?? false) ? widget.categoryId : null;
    final hasQuery = q.isNotEmpty;

    final catObj = _findCategory(categories, cat);
    final isTopLevel = cat != null && categories.any((c) => c.id == cat);
    // ignore: dead_null_aware_expression
    final subs = catObj?.children ?? const <Category>[];
    // Comme le web : barre Filtres + Trier en recherche texte et en sous-catégorie.
    final showFilterBar = hasQuery || (cat != null && !isTopLevel);

    Category? activeSubObj;
    for (final s in subs) {
      if (s.id == _activeSub) activeSubObj = s;
    }

    // Bannière : la capsule active d'abord, sinon la catégorie ouverte (comme le web).
    // ⚠️ Ces clés doivent rester identiques à celles de [CatalogPrefetch].
    final (String, String?) bannerKey = hasQuery
        ? (q, null)
        : (activeSubObj?.name ?? catObj?.name ?? '', catObj?.name);
    final bannerAsync = ref.watch(_bannerProvider(bannerKey));

    List<Widget> slivers;
    if (!hasQuery && cat == null) {
      slivers = const [
        SliverToBoxAdapter(
          child: _EmptyState(
            icon: '🔍',
            title: 'Que cherchez-vous ?',
            text: 'Saisissez un produit, une catégorie ou un fournisseur.',
          ),
        ),
      ];
    } else {
      final key = (q, cat);
      slivers = ref.watch(searchResultsProvider(key)).when(
            loading: () => const [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator(color: _orange)),
                ),
              ),
            ],
            error: (_, __) => [
              SliverToBoxAdapter(
                child: _EmptyState(
                  icon: '⚠️',
                  title: 'Erreur',
                  text: hasQuery ? 'Erreur lors de la recherche.' : 'Impossible de charger les produits.',
                  action: ('Réessayer', () => ref.invalidate(searchResultsProvider(key))),
                ),
              ),
            ],
            data: (raw) => _results(raw, q, catObj, subs, activeSubObj, showFilterBar, bannerAsync),
          );
    }

    // Fond opaque + grille paresseuse (seules les cartes visibles sont construites).
    return ColoredBox(
      color: const Color(0xFFF5F5F5),
      // HeaderInsetSliver : dans l'accueil, le contenu démarre sous le header superposé.
      child: CustomScrollView(controller: _scroll, slivers: [const HeaderInsetSliver(), ...slivers]),
    );
  }

  List<Widget> _results(
    List<Product> raw,
    String q,
    Category? catObj,
    List<Category> subs,
    Category? activeSubObj,
    bool showFilterBar,
    AsyncValue<_Banner?> bannerAsync,
  ) {
    if (!identical(_facetSource, raw)) {
      _facetSource = raw;
      _facets = _Facets();
    }
    final bounds = _boundsOf(raw);

    // Capsule active : ses produits ET ceux de toute sa descendance.
    final names = activeSubObj == null ? null : _namesWithDescendants(activeSubObj);
    var list = names == null ? raw : raw.where((p) => names.contains(p.categoryName)).toList();
    if (showFilterBar) {
      list = _sorted(_facets.apply(list), _sort);
    } else if (_sortBySold) {
      list = _sorted(list, 'sold');
    }

    final banner = bannerAsync.valueOrNull;
    // Repli dégradé seulement pour une catégorie (pas en recherche texte),
    // et seulement une fois qu'on SAIT qu'il n'y a pas de bannière (pas de flash).
    final showFallback = q.isEmpty && catObj != null && !bannerAsync.isLoading && banner == null;

    return [
      if (banner != null)
        SliverToBoxAdapter(
          child: GestureDetector(
            onTap: () => _goBanner(banner),
            child: AspectRatio(
              aspectRatio: 1600 / 480,
              child: CachedNetworkImage(
                key: ValueKey(banner.imageUrl),
                imageUrl: banner.imageUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                fadeInDuration: const Duration(milliseconds: 200),
                placeholder: (_, __) => const ColoredBox(color: Color(0xFFEDEEF0)),
                errorWidget: (_, url, err) {
                  debugPrint('🖼️ bannière illisible : $url ($err)');
                  return _BannerFallback(title: activeSubObj?.name ?? catObj?.name ?? '');
                },
              ),
            ),
          ),
        )
      else if (showFallback)
        SliverToBoxAdapter(child: _BannerFallback(title: activeSubObj?.name ?? catObj?.name ?? '')),

      if (subs.isNotEmpty)
        SliverToBoxAdapter(
          child: _SubChips(subs: subs, activeSub: _activeSub, onSelect: (id) => setState(() => _activeSub = id)),
        ),

      if (showFilterBar)
        SliverToBoxAdapter(child: _FilterBar(
          activeCount: _facets.activeCount(bounds),
          sortLabel: _sorts.firstWhere((s) => s.$1 == _sort).$2,
          sortActive: _sort != 'relevance',
          onFilters: () => _openFilters(raw, bounds),
          onSort: _openSort,
        ))
      else if (list.isNotEmpty)
        SliverToBoxAdapter(
          child: _SortBar(
            label: activeSubObj?.name ?? 'Meilleures ventes',
            active: _sortBySold,
            onTap: () => setState(() => _sortBySold = !_sortBySold),
          ),
        ),

      if (q.isNotEmpty) SliverToBoxAdapter(child: _ResultsHeader(count: list.length, query: q)),

      if (list.isEmpty)
        SliverToBoxAdapter(child: _EmptyState(
          icon: q.isNotEmpty ? '🔍' : '📦',
          title: 'Aucun résultat',
          text: (raw.isNotEmpty && showFilterBar && _facets.activeCount(bounds) > 0)
              ? "Aucun produit ne correspond à ces filtres. Essayez d'en retirer quelques-uns."
              : activeSubObj != null
                  ? 'Aucun produit dans « ${activeSubObj.name} ».'
                  : q.isNotEmpty
                      ? 'Aucun produit ne correspond à « $q ».'
                      : 'Aucun produit dans cette catégorie pour le moment.',
        ))
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
          sliver: SliverMasonryGrid.count(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childCount: list.length,
            itemBuilder: (_, i) => ProductCard(product: list[i]),
          ),
        ),
    ];
  }

  Future<void> _openSort() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final s in _sorts)
            ListTile(
              title: Text(s.$2,
                  style: AppTheme.body(
                    size: 14.5,
                    weight: s.$1 == _sort ? FontWeight.w700 : FontWeight.w500,
                    color: s.$1 == _sort ? _orange : _ink,
                  )),
              trailing: s.$1 == _sort ? const Icon(Icons.check, color: _orange) : null,
              onTap: () => Navigator.pop(c, s.$1),
            ),
        ]),
      ),
    );
    if (picked != null) setState(() => _sort = picked);
  }

  Future<void> _openFilters(List<Product> raw, RangeValues bounds) async {
    final draft = _facets.copy()..price ??= bounds;
    final bestCount = raw.where(_isBest).length;
    final promoCount = raw.where(_isPromo).length;

    final result = await showModalBottomSheet<_Facets>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) {
          Widget check(String label, bool on, VoidCallback tap, {int? count}) => InkWell(
                onTap: () => setSheet(tap),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    Container(
                      width: 18, height: 18,
                      decoration: BoxDecoration(
                        color: on ? _orange : Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: on ? _orange : const Color(0xFFD6D4D0)),
                      ),
                      child: on ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(label,
                          style: AppTheme.body(
                              size: 13.5,
                              weight: on ? FontWeight.w600 : FontWeight.w500,
                              color: on ? _ink : const Color(0xFF555555))),
                    ),
                    if (count != null) Text('$count', style: AppTheme.body(size: 12, color: const Color(0xFF9A9A9A))),
                  ]),
                ),
              );

          Widget section(String title, List<Widget> children, {bool last = false}) => Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: _line))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: AppTheme.body(size: 13.5, weight: FontWeight.w700, color: _ink)),
                  const SizedBox(height: 6),
                  ...children,
                ]),
              );

          final pr = draft.price!;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.85),
            child: SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(children: [
                    Expanded(child: Text('Filtres', style: AppTheme.body(size: 16, weight: FontWeight.w700, color: _ink))),
                    IconButton(icon: const Icon(Icons.close, color: _mute), onPressed: () => Navigator.pop(c)),
                  ]),
                ),
                const Divider(height: 1, color: _line),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      section('Prix', [
                        Text('${pr.start.round()} TND – ${pr.end.round()} TND',
                            style: AppTheme.body(size: 13, weight: FontWeight.w600, color: const Color(0xFF555555))),
                        RangeSlider(
                          values: pr,
                          min: bounds.start,
                          max: bounds.end,
                          activeColor: _orange,
                          inactiveColor: const Color(0xFFECEAE7),
                          onChanged: (v) => setSheet(() => draft.price = v),
                        ),
                      ]),
                      section('Quantité minimum', [
                        for (final b in _moqBuckets)
                          check(b.$2, draft.moq.contains(b.$1),
                              () => draft.moq.contains(b.$1) ? draft.moq.remove(b.$1) : draft.moq.add(b.$1)),
                      ], last: bestCount == 0 && promoCount == 0),
                      if (bestCount > 0 || promoCount > 0)
                        section('Promotions', [
                          if (bestCount > 0)
                            check('Meilleures ventes', draft.best, () => draft.best = !draft.best, count: bestCount),
                          if (promoCount > 0)
                            check('En promotion', draft.promo, () => draft.promo = !draft.promo, count: promoCount),
                        ], last: true),
                    ],
                  ),
                ),
                const Divider(height: 1, color: _line),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(c, _Facets(price: bounds)),
                        style: OutlinedButton.styleFrom(
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        child: Text('Réinitialiser',
                            style: AppTheme.body(size: 14, weight: FontWeight.w600, color: const Color(0xFF3D4853))),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(c, draft),
                        style: FilledButton.styleFrom(
                          backgroundColor: _orange,
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: Text('Voir les résultats',
                            style: AppTheme.body(size: 14, weight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
    if (result != null) setState(() => _facets = result);
  }
}

// ─────────────────────────── Widgets ───────────────────────────

/// Bannière de secours (catégorie sans image) : dégradé orange + nom,
/// comme le repli de MobileCategory côté web.
class _BannerFallback extends StatelessWidget {
  final String title;
  const _BannerFallback({required this.title});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1600 / 480,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF9A3D), Color(0xFFFF5E00)],
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerLeft,
        child: Stack(children: [
          Positioned(
            right: -30,
            top: -40,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(.12)),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.body(size: 20, weight: FontWeight.w800, color: Colors.white).copyWith(height: 1.15),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Barre « Filtres (n) » + « Trier ▼ » (recherche texte / sous-catégorie).
class _FilterBar extends StatelessWidget {
  final int activeCount;
  final String sortLabel;
  final bool sortActive;
  final VoidCallback onFilters;
  final VoidCallback onSort;
  const _FilterBar({
    required this.activeCount,
    required this.sortLabel,
    required this.sortActive,
    required this.onFilters,
    required this.onSort,
  });

  Widget _pill({required Widget child, required VoidCallback onTap}) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: const Color(0xFFF1F3F5), borderRadius: BorderRadius.circular(999)),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Row(children: [
          _pill(
            onTap: onFilters,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.tune, size: 16, color: Color(0xFF141414)),
              const SizedBox(width: 6),
              Text('Filtres', style: AppTheme.body(size: 13.5, weight: FontWeight.w600, color: const Color(0xFF141414))),
              if (activeCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  constraints: const BoxConstraints(minWidth: 16),
                  height: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(999)),
                  child: Text('$activeCount',
                      style: AppTheme.body(size: 10, weight: FontWeight.w700, color: Colors.white)),
                ),
              ],
            ]),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: _pill(
              onTap: onSort,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(sortActive ? sortLabel : 'Trier par',
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                          size: 13.5, weight: FontWeight.w600, color: sortActive ? _orange : const Color(0xFF141414))),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_drop_down, size: 18, color: sortActive ? _orange : const Color(0xFF141414)),
              ]),
            ),
          ),
        ]),
      );
}

/// Bande horizontale de chips sous-catégories : "Tout" + enfants.
class _SubChips extends StatelessWidget {
  final List<Category> subs;
  final String activeSub;
  final ValueChanged<String> onSelect;
  const _SubChips({required this.subs, required this.activeSub, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: SizedBox(
        height: 26,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: subs.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            if (i == 0) {
              return _Chip(label: 'Tout', heart: true, active: activeSub == 'all', onTap: () => onSelect('all'));
            }
            final s = subs[i - 1];
            return _Chip(label: s.name, img: s.imageUrl, active: activeSub == s.id, onTap: () => onSelect(s.id));
          },
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String? img;
  final bool active;
  final bool heart;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.active, required this.onTap, this.img, this.heart = false});

  Widget _fallback() => Center(
        child: Text(label.isNotEmpty ? label[0].toUpperCase() : '?',
            style: const TextStyle(fontSize: 11, color: Color(0xFF6B7785))),
      );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(2, 2, 12, 2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? _ink : const Color(0xFFE5E7EB), width: 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 22, height: 22,
            clipBehavior: Clip.antiAlias,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFF4F5F7)),
            child: heart
                ? const Icon(Icons.favorite, size: 12, color: Color(0xFFE53935))
                : (img != null && img!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: _absolute(img!),
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _fallback(),
                      )
                    : _fallback()),
          ),
          const SizedBox(width: 6),
          Text(label, style: AppTheme.body(size: 13, weight: FontWeight.w500, color: _ink)),
        ]),
      ),
    );
  }
}

/// Bandeau "X résultat(s) pour « q »" (mode recherche texte).
class _ResultsHeader extends StatelessWidget {
  final int count;
  final String query;
  const _ResultsHeader({required this.count, required this.query});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: Text.rich(TextSpan(
          text: '$count résultat${count > 1 ? 's' : ''} ',
          style: AppTheme.body(size: 13.5, weight: FontWeight.w700, color: _ink),
          children: [TextSpan(text: 'pour « $query »', style: AppTheme.body(size: 13, color: _mute))],
        )),
      );
}

/// Barre "<label> ▼" (toggle tri par ventes) — catégorie de premier niveau.
class _SortBar extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SortBar({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      width: double.infinity,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          shape: const RoundedRectangleBorder(),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(size: 13, weight: FontWeight.w600, color: active ? _ink : const Color(0xFF3D4853))),
          ),
          const SizedBox(width: 4),
          Icon(active ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              size: 18, color: active ? _ink : const Color(0xFF8A94A0)),
        ]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String icon;
  final String title;
  final String text;
  final (String, VoidCallback)? action;
  const _EmptyState({required this.icon, required this.title, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(vertical: 70, horizontal: 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Text(icon, style: const TextStyle(fontSize: 40)),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center, style: AppTheme.body(size: 17, weight: FontWeight.w700, color: _ink)),
        const SizedBox(height: 6),
        Text(text, textAlign: TextAlign.center, style: AppTheme.body(size: 13.5, color: const Color(0xFF9AA3AE))),
        if (action != null) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: action!.$2,
            style: OutlinedButton.styleFrom(shape: const StadiumBorder(), side: const BorderSide(color: _ink)),
            child: Text(action!.$1, style: AppTheme.body(size: 13.5, weight: FontWeight.w700, color: _ink)),
          ),
        ],
      ]),
    );
  }
}