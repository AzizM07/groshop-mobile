import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../../data/api/products_api.dart';
import '../../data/models/category.dart';
import '../../data/models/product.dart';
import '../../widgets/async_view.dart';
import '../../widgets/product_card.dart';
import '../../widgets/native_ad_tile.dart';
import '../search/search_screen.dart' show SearchResultsView;
import 'widgets/home_header.dart';
import 'widgets/mobile_hero_grid.dart';
import 'widgets/best_sellers.dart';

/// Accueil : header FIXE + contenu qui glisse d'une catégorie à l'autre.
///
/// • Toucher une puce → le contenu part d'un côté et le nouveau arrive de
///   l'autre (vers la droite si la catégorie est à droite, et inversement).
///   Le header ne bouge pas ; seule la pilule / le trait glisse.
/// • Balayer le contenu à gauche / à droite → catégorie suivante / précédente.
/// • Les contenus déjà visités restent en mémoire (données, position de
///   défilement) : y revenir est instantané, sans rechargement.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const _homeKey = '__home__';
  int _dir = 1; // sens du dernier changement : 1 = vers la droite, -1 = vers la gauche

  /// État « défilé » de chaque contenu (le header prend celui du contenu affiché).
  final _scrolledBy = <String, bool>{};

  /// Hauteur du header superposé (les contenus démarrent dessous).
  final _inset = ValueNotifier<double>(0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Estimation avant la 1re mesure : évite un saut du contenu au démarrage.
    if (_inset.value == 0) _inset.value = MediaQuery.paddingOf(context).top + 102;
  }

  @override
  void dispose() {
    _inset.dispose();
    super.dispose();
  }

  void _onScrolled(String key, bool s) {
    if (_scrolledBy[key] == s) return;
    _scrolledBy[key] = s;
    if (mounted && key == (ref.read(homeCategoryProvider) ?? _homeKey)) setState(() {});
  }

  List<String?> _ids(List<Category> cats) => [null, ...cats.map((c) => c.id.toString())];

  void _swipe(DragEndDetails d, List<String?> ids, String? current) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() < 350) return; // geste trop lent : on ignore
    final i = ids.indexOf(current);
    if (i < 0) return;
    final j = v < 0 ? i + 1 : i - 1;
    if (j < 0 || j >= ids.length) return;
    HapticFeedback.selectionClick();
    ref.read(homeCategoryProvider.notifier).state = ids[j];
  }

  Widget _buildPage(String key) => key == _homeKey
      ? _ForYouFeed(onScrolled: (s) => _onScrolled(key, s))
      : SearchResultsView(categoryId: key, onScrolled: (s) => _onScrolled(key, s));

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final ids = _ids(categories);
    final current = ref.watch(homeCategoryProvider);
    final currentKey = current ?? _homeKey;

    // Sens du glissement, calculé avant la reconstruction.
    ref.listen<String?>(homeCategoryProvider, (prev, next) {
      final a = ids.indexOf(prev);
      final b = ids.indexOf(next);
      _dir = b >= a ? 1 : -1;
    });

    // Header SUPERPOSÉ : le contenu défile derrière lui (fond translucide au scroll).
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned.fill(
            child: HeaderInset(
              inset: _inset,
              child: ClipRect(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragEnd: (d) => _swipe(d, ids, current),
                  child: _CategoryPager(current: currentKey, dir: _dir, builder: _buildPage),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: MeasureSize(
              onChange: (size) => _inset.value = size.height,
              child: HomeHeader(
                scrolled: _scrolledBy[currentKey] ?? false,
                categories: categories,
                isHome: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════ Pager : glisse entre contenus gardés en mémoire ═══════
/// Chaque contenu est construit UNE fois puis conservé (hors écran quand il
/// n'est pas affiché). Un changement ne fait que déplacer deux contenus déjà
/// prêts : aucune reconstruction pendant l'animation → fluide.
class _CategoryPager extends StatefulWidget {
  final String current;
  final int dir;
  final Widget Function(String key) builder;
  const _CategoryPager({required this.current, required this.dir, required this.builder});

  @override
  State<_CategoryPager> createState() => _CategoryPagerState();
}

class _CategoryPagerState extends State<_CategoryPager> with SingleTickerProviderStateMixin {
  static const _maxAlive = 6; // contenus gardés en mémoire (les plus récents)

  late final AnimationController _c =
      AnimationController(vsync: this, duration: kCategorySwitchDuration, value: 1);
  late final CurvedAnimation _t = CurvedAnimation(parent: _c, curve: kCategorySwitchCurve);

  final _order = <String>[]; // du plus ancien au plus récent (le dernier est dessiné au-dessus)
  final _pages = <String, Widget>{};
  String? _prev;

  @override
  void initState() {
    super.initState();
    _ensure(widget.current);
  }

  @override
  void didUpdateWidget(covariant _CategoryPager old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) {
      _prev = old.current;
      _ensure(widget.current);
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _t.dispose();
    _c.dispose();
    super.dispose();
  }

  void _ensure(String k) {
    _pages.putIfAbsent(
      k,
      () => KeyedSubtree(key: ValueKey('page-$k'), child: RepaintBoundary(child: widget.builder(k))),
    );
    _order
      ..remove(k)
      ..add(k);
    // Libère les plus anciens (jamais l'actuel ni celui qui sort).
    while (_order.length > _maxAlive) {
      final victim = _order.firstWhere((x) => x != widget.current && x != _prev, orElse: () => '');
      if (victim.isEmpty) break;
      _order.remove(victim);
      _pages.remove(victim);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _t.value;
        final animating = _c.isAnimating;
        final d = widget.dir.toDouble();
        return Stack(
          fit: StackFit.expand,
          children: [
            for (final k in _order)
              _slot(
                k,
                visible: k == widget.current || (animating && k == _prev),
                dx: k == widget.current ? d * (1 - t) : (k == _prev ? -d * t : 0),
              ),
          ],
        );
      },
    );
  }

  Widget _slot(String k, {required bool visible, required double dx}) => Offstage(
        key: ValueKey('slot-$k'),
        offstage: !visible,
        child: TickerMode(
          enabled: visible,
          child: FractionalTranslation(translation: Offset(dx, 0), child: _pages[k]),
        ),
      );
}

// ═══════ Contenu « Pour vous » ═══════
/// Branché sur AsyncView :
/// • pas de réseau au 1er chargement → page « Pas de connexion Internet » ;
/// • réseau coupé après chargement   → on garde le fil + bandeau hors-ligne ;
/// • réseau qui revient              → rechargement automatique.
class _ForYouFeed extends ConsumerStatefulWidget {
  final ValueChanged<bool> onScrolled;
  const _ForYouFeed({required this.onScrolled});

  @override
  ConsumerState<_ForYouFeed> createState() => _ForYouFeedState();
}

class _ForYouFeedState extends ConsumerState<_ForYouFeed> {
  // Contrôleur propre à cette instance : jamais partagé pendant une transition.
  final _scroll = ScrollController();
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final s = _scroll.offset > 30;
      if (s != _scrolled) {
        _scrolled = s;
        widget.onScrolled(s);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Rafraîchit tout l'accueil (tirer vers le bas, bouton Réessayer, retour du réseau).
  Future<void> _refresh() async {
    ref.invalidate(recommendedProvider);
    ref.invalidate(trendingProvider);
    ref.invalidate(categoriesProvider);
    await Future.wait([
      ref.read(recommendedProvider.future),
      ref.read(trendingProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final recommended = ref.watch(recommendedProvider);
    final inset = HeaderInset.of(context);

    Widget view(double top) => AsyncView<List<Product>>(
          value: recommended,
          onRetry: _refresh,
          topInset: top, // header superposé : erreurs et bandeau restent visibles
          data: (items) => _feed(items, top),
        );

    return ColoredBox(
      color: Colors.white,
      child: inset == null
          ? view(0)
          : ValueListenableBuilder<double>(valueListenable: inset, builder: (_, h, __) => view(h)),
    );
  }

  Widget _feed(List<Product> items, double top) {
    // Feed mixte : 2 produits puis 1 annonce (jamais en dernière position).
    final feed = <Product?>[];
    for (var i = 0; i < items.length; i++) {
      feed.add(items[i]);
      final isPairEnd = (i + 1) % 2 == 0;
      if (isPairEnd && i != items.length - 1) feed.add(null);
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: const Color(0xFFFF7A00),
      edgeOffset: top, // la roue apparaît sous le header
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const HeaderInsetSliver(),
          const SliverToBoxAdapter(child: MobileHeroGrid()),
          const SliverToBoxAdapter(child: BestSellers()),
          const SliverToBoxAdapter(
            child: SizedBox(height: 10, child: ColoredBox(color: Color(0xFFF5F6F7))),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
            sliver: SliverMasonryGrid.count(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 12,
              childCount: feed.length,
              itemBuilder: (context, i) {
                final p = feed[i];
                if (p == null) {
                  return LayoutBuilder(
                    builder: (context, c) => SizedBox(
                      width: c.maxWidth,
                      height: c.maxWidth / 0.62,
                      child: const NativeAdTile(),
                    ),
                  );
                }
                return ProductCard(product: p);
              },
            ),
          ),
        ],
      ),
    );
  }
}