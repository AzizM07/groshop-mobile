import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/api/products_api.dart';
import '../../data/models/category.dart';
import '../../data/models/product.dart';
import '../../widgets/page_tracker.dart';
import '../../widgets/product_card.dart';
import '../../widgets/native_ad_tile.dart'; // ⚠️ adapte le chemin si NativeAdTile est ailleurs
import '../home/widgets/home_header.dart' show HomeSearchBar;

const _orange = Color(0xFFFF7A00);
const _ink = Color(0xFF0F1419);

/// Grille des sous-catégories : 3 colonnes × 4 lignes au maximum avant « Découvrir plus ».
const _cols = 3;
const _maxRows = 4;
const _maxCells = _cols * _maxRows; // 12

/// Native ad dans « Trouvez de l'inspiration » : insérée après N produits,
/// comme une carte parmi les autres (même colonne, même largeur).
const _adAfter = 3;

/// Largeur minimale d'une colonne pour y mettre la pub : AdMob exige une image
/// d'au moins 120 × 120 dp. Téléphone large (≈ 411 dp) → colonne ≈ 135 dp : OK.
/// Petit téléphone (≈ 360 dp) → colonne ≈ 110 dp : la pub passe en pleine largeur.
const _adMinWidth = 120.0;

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});
  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  String? _activeId; // null = "Pour vous"
  bool _expanded = false; // grille dépliée via « Découvrir plus »

  void _select(String? id) {
    if (id == _activeId) return;
    setState(() {
      _activeId = id;
      _expanded = false; // chaque catégorie repart repliée sur 4 lignes
    });
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final products = ref.watch(categoryProductsProvider(_activeId));

    Category? activeCat;
    if (_activeId != null) {
      for (final c in cats) {
        if (c.id == _activeId) { activeCat = c; break; }
      }
    }
    final allSubs = cats.expand((c) => c.children).toList();
    final rightSubs = _activeId == null ? allSubs : (activeCat?.children ?? const <Category>[]);
    final rightTitle = _activeId == null ? null : (activeCat?.name ?? '');
    final isInspiration = _activeId == null;
    final sectionTitle = isInspiration
        ? "Trouvez de l'inspiration"
        : "Produits populaires${activeCat != null ? ' — ${activeCat.name}' : ''}";

    // 4 lignes max : 11 sous-catégories + la case « Découvrir plus » (12e).
    final overflow = rightSubs.length > _maxCells;
    final visibleSubs = (!overflow || _expanded) ? rightSubs : rightSubs.take(_maxCells - 1).toList();

    // Suivi de page « catalogue » (pageview à l'ouverture de l'écran)
    return PageTracker(
      pageType: 'catalogue',
      child: Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _searchHeader(),
            _promoBanner(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Sidebar catégories ──
                  Container(
                    width: 110,
                    color: const Color(0xFFF5F5F5),
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        _sideItem(null, 'Pour vous'),
                        ...cats.map((c) => _sideItem(c.id, c.name)),
                      ],
                    ),
                  ),
                  // ── Panneau droit ──
                  Expanded(
                    child: ListView(
                      key: ValueKey(_activeId), // remonte en haut à chaque changement de catégorie
                      padding: const EdgeInsets.fromLTRB(10, 12, 10, 24),
                      children: [
                        if (rightTitle != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(rightTitle, style: AppTheme.body(size: 16, weight: FontWeight.w600, color: _ink)),
                          ),

                        // Grille sous-catégories
                        if (rightSubs.isEmpty)
                          Text('Aucune sous-catégorie', style: AppTheme.body(size: 13, color: const Color(0xFF9AA3AE)))
                        else
                          // Hauteur de cellule calculée = image carrée + 6 + 2 lignes de texte.
                          LayoutBuilder(
                            builder: (context, c) {
                              const gap = 12.0;
                              const textBlock = 34.0; // 6 (marge) + 2 lignes @12px
                              final cellW = (c.maxWidth - gap * (_cols - 1)) / _cols;
                              final cellH = cellW + textBlock;
                              final count = visibleSubs.length + (overflow ? 1 : 0);
                              return AnimatedSize(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.topCenter,
                                child: GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  padding: EdgeInsets.zero,
                                  itemCount: count,
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: _cols,
                                    mainAxisSpacing: gap,
                                    crossAxisSpacing: gap,
                                    mainAxisExtent: cellH,
                                  ),
                                  itemBuilder: (_, i) => i < visibleSubs.length
                                      ? _subTile(visibleSubs[i])
                                      : _moreTile(),
                                ),
                              );
                            },
                          ),

                        // Produits
                        products.when(
                          loading: () => const Padding(
                            padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator(color: _orange))),
                          error: (_, __) => const SizedBox.shrink(),
                          data: (all) {
                            final items = all.take(12).toList();
                            if (items.isEmpty) return const SizedBox.shrink();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(height: 1, color: const Color(0xFFF0F0F0), margin: const EdgeInsets.fromLTRB(0, 20, 0, 16)),
                                Text(sectionTitle, style: AppTheme.body(size: 14, weight: FontWeight.w700, color: _ink)),
                                const SizedBox(height: 12),
                                // Native ad uniquement dans « Trouvez de l'inspiration ».
                                _productsMasonry(items, withAd: isInspiration),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }

  // ── Produits en 2 colonnes (masonry) + native ad ──
  Widget _productsMasonry(List<Product> items, {bool withAd = false}) {
    final cards = <Widget>[for (final p in items) _card(p)];
    if (!withAd || items.length < _adAfter) return _masonry(cards);

    return LayoutBuilder(builder: (context, c) {
      const colGap = 10.0;
      final colW = (c.maxWidth - colGap) / 2;

      // Cas normal : la pub est une carte dans la colonne (4e tuile → colonne
      // de droite, sous le produit 2), à la largeur des produits.
      if (colW >= _adMinWidth) {
        final tiles = [...cards]..insert(_adAfter, _adTile());
        return _masonry(tiles);
      }

      // Petit écran : colonne trop étroite pour AdMob → pleine largeur,
      // après des rangées complètes (pas de trou au-dessus).
      final at = _adAfter.isOdd ? _adAfter + 1 : _adAfter;
      if (items.length <= at) return _masonry(cards);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _masonry(cards.take(at).toList()),
          _adTile(),
          _masonry(cards.skip(at).toList()),
        ],
      );
    });
  }

  Widget _card(Product p) => ProductCard(product: p, showTrendingBadge: false, promoTab: true);

  /// Pub : hauteur calculée par la tuile (image carrée + texte), marge du bas
  /// comprise ; se referme entièrement si aucune pub n'est dispo.
  Widget _adTile() => const NativeAdTile(
        key: ValueKey('categories-native-ad'),
        autoHeight: true,
        margin: EdgeInsets.only(bottom: 14),
      );

  /// 2 colonnes en alternance, chaque tuile à sa hauteur naturelle.
  Widget _masonry(List<Widget> tiles) {
    final left = <Widget>[];
    final right = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      final t = tiles[i];
      // La pub porte déjà sa marge (disparaît avec elle si pas de pub).
      final cell = t is NativeAdTile ? t : Padding(padding: const EdgeInsets.only(bottom: 14), child: t);
      (i.isEven ? left : right).add(cell);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: left)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: right)),
      ],
    );
  }

  // ── Item de la sidebar ──
  Widget _sideItem(String? id, String name) {
    final on = _activeId == id;
    return InkWell(
      onTap: () => _select(id),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        decoration: BoxDecoration(
          color: on ? Colors.white : Colors.transparent,
          border: Border(left: BorderSide(color: on ? _orange : Colors.transparent, width: 3)),
        ),
        child: Text(name,
            style: AppTheme.body(size: on ? 13.5 : 13, weight: on ? FontWeight.w600 : FontWeight.w400,
                color: on ? _orange : const Color(0xFF3D4853))),
      ),
    );
  }

  // ── Tuile sous-catégorie → ouvre ses produits ──
  Widget _subTile(Category sub) {
    return GestureDetector(
      onTap: () => context.push('/search?cat=${sub.id}'),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                color: const Color(0xFFF4F5F7),
                child: (sub.imageUrl != null && sub.imageUrl!.isNotEmpty)
                    ? CachedNetworkImage(imageUrl: sub.imageUrl!, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _subFallback(sub))
                    : _subFallback(sub),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Bloc texte de hauteur fixe (2 lignes) → toutes les cellules identiques.
          SizedBox(
            height: 28,
            child: Text(sub.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                style: AppTheme.body(size: 12, color: const Color(0xFF1F2937)).copyWith(height: 1.15)),
          ),
        ],
      ),
    );
  }

  // ── 12e case : bloc noir avec un grand « + » / flèche « Voir moins » une fois dépliée ──
  Widget _moreTile() {
    final open = _expanded;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _expanded = !_expanded);
      },
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: _ink,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  open ? Icons.keyboard_arrow_up_rounded : Icons.add_rounded,
                  size: 38,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 28,
            child: Text(open ? 'Voir moins' : 'Découvrir plus',
                maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                style: AppTheme.body(size: 12, weight: FontWeight.w700, color: _ink).copyWith(height: 1.15)),
          ),
        ],
      ),
    );
  }

  Widget _subFallback(Category sub) => Center(
        child: Text(sub.name.isNotEmpty ? sub.name[0].toUpperCase() : '?',
            style: AppTheme.body(size: 24, weight: FontWeight.w500, color: const Color(0xFF9AA3AE))),
      );

  // ── En-tête : même barre de recherche que l'accueil (loupe animée + photo), sans notifications ──
  Widget _searchHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: const HomeSearchBar(dark: false),
    );
  }

  // ── Bandeau orange avec texte défilant ──
  Widget _promoBanner() {
    return Container(
      width: double.infinity,
      color: _orange,
      // Hauteur de la bande = 2 × padding vertical + hauteur d'une ligne de texte.
      // Baisse `vertical` (ou `height`) pour l'affiner encore.
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: _MarqueeText(
        text: 'Bienvenue dans Groshop',
        style: AppTheme.body(size: 13, weight: FontWeight.w600, color: Colors.white)
            .copyWith(height: 1.2),
      ),
    );
  }
}

/// Texte qui défile en boucle continue de droite à gauche (sans package).
/// Le texte est répété avec un séparateur « • » pour une boucle sans coupure.
class _MarqueeText extends StatefulWidget {
  const _MarqueeText({
    required this.text,
    required this.style,
    this.speed = 40, // pixels par seconde
    this.separator = '   •   ',
  });

  final String text;
  final TextStyle style;
  final double speed;
  final String separator;

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> with SingleTickerProviderStateMixin {
  late final String _segment = '${widget.text}${widget.separator}';
  late final TextPainter _tp = TextPainter(
    text: TextSpan(text: _segment, style: widget.style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  // Largeur d'un segment (texte + séparateur) = distance parcourue par cycle.
  late final double _segW = _tp.width.ceilToDouble();

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_segW / widget.speed * 1000).round()),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    _tp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, cons) {
        // Assez de copies pour couvrir la largeur + 1 qui entre par la droite.
        final copies = (cons.maxWidth / _segW).ceil() + 1;
        return ClipRect(
          child: SizedBox(
            height: _tp.height,
            width: cons.maxWidth,
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, child) => Transform.translate(
                offset: Offset(-_segW * _c.value, 0),
                child: child,
              ),
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: 0,
                maxWidth: double.infinity,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    copies,
                    (_) => SizedBox(
                      width: _segW,
                      child: Text(
                        _segment,
                        style: widget.style,
                        maxLines: 1,
                        softWrap: false,
                        // Même mesure que le TextPainter → boucle parfaitement jointive.
                        textScaler: TextScaler.noScaling,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}