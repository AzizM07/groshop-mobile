import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lottie/lottie.dart';
import '../../../core/theme.dart';
import '../../../data/models/category.dart';
import '../../search/search_screen.dart' show CatalogPrefetch;
import 'mobile_hero_grid.dart' show heroColorProvider;

const _idle = Color(0xFF6B7785);
const _fallback = Color(0xFFFF8A15);

/// Animation Lottie de la loupe dans la barre de recherche (à déclarer dans pubspec.yaml).
const _searchLottie = 'assets/lottie/searchicon.json';

/// Bordure de la barre de recherche — ajuste ces valeurs pour la renforcer ou l'adoucir.
/// • Sur fond blanc (header défilé, écran Catégories) : liseré gris un peu plus marqué.
/// • Sur fond coloré (haut de l'accueil) : liseré sombre très léger + ombre douce,
///   pour détacher la barre blanche du dégradé sans la durcir.
const _barBorderWidth = 1.4;
const _barBorderLight = Color(0xFFD1D5DB);
const _barBorderOnColor = Color(0x1F000000);
const _barShadow = [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 1))];

/// Durée / courbe communes : pilule du header ET glissement du contenu.
const kCategorySwitchDuration = Duration(milliseconds: 300);
const kCategorySwitchCurve = Curves.easeOutCubic;

/// Fond du header après défilement : blanc semi-transparent + léger flou.
/// Augmente l'opacité pour un header plus couvrant, baisse-la pour voir davantage.
const _scrolledOpacity = 0.72;
const _scrolledBlur = 14.0;

const _chipH = 32.0;
const _chipGap = 8.0;

/// Catégorie affichée sur l'accueil (null = « Pour vous »).
/// Les puces la modifient ; l'accueil fait glisser son contenu en conséquence.
final homeCategoryProvider = StateProvider<String?>((ref) => null);

// ── Helpers couleur ──────────────────────────────────────────────

Color _tint(Color base, double lightness) {
  final h = HSLColor.fromColor(base);
  return h.withLightness(lightness).withSaturation(h.saturation.clamp(0.35, 0.85)).toColor();
}

Color _inkFrom(Color base) {
  final h = HSLColor.fromColor(base);
  return h.withLightness(0.20).withSaturation(h.saturation.clamp(0.30, 0.90)).toColor();
}

Color _onColor(Color bg, Color base) => bg.computeLuminance() > 0.45 ? _inkFrom(base) : Colors.white;

// ─────────────────────────────────────────────────────────────────
/// Logo GROSHOP en image (assets/images/groshop_logo.png), teinté en [color].
class BrandWordmark extends StatelessWidget {
  final Color color;
  final double size;
  const BrandWordmark({super.key, required this.color, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/groshop_logo.png',
      height: size,
      fit: BoxFit.contain,
      color: color,
      colorBlendMode: BlendMode.srcIn,
      errorBuilder: (_, __, ___) => Text.rich(TextSpan(
        text: 'GROS',
        style: AppTheme.body(size: size * 0.86, weight: FontWeight.w700, color: color),
        children: const [TextSpan(text: 'HOP')],
      )),
    );
  }
}

/// Header partagé (accueil + résultats de recherche).
///
/// • Sur l'accueil ([isHome] = true) : les puces changent [homeCategoryProvider]
///   et SEUL le contenu sous le header glisse — le header ne bouge pas.
/// • Ailleurs : toucher une puce ramène à l'accueil sur cette catégorie.
///   [activeCategoryId] permet d'y surligner une catégorie (lien direct).
/// • Dès que les catégories sont connues, lance [CatalogPrefetch] (une seule fois) :
///   produits, bannières et icônes de toutes les catégories / sous-catégories.
class HomeHeader extends ConsumerWidget {
  final bool scrolled;
  final List<Category> categories;
  final String? initialQuery;
  final bool isHome;
  final String? activeCategoryId;
  const HomeHeader({
    super.key,
    required this.scrolled,
    required this.categories,
    this.initialQuery,
    this.isHome = false,
    this.activeCategoryId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Préchargement de tout le catalogue (ne fait rien si déjà lancé).
    if (categories.isNotEmpty) CatalogPrefetch.start(context, categories);

    final dark = !scrolled;
    final topPad = MediaQuery.paddingOf(context).top;
    final base = ref.watch(heroColorProvider) ?? _fallback;

    final bgTop = dark ? _tint(base, 0.60) : Colors.white;
    final bgBottom = dark ? _tint(base, 0.72) : Colors.white;
    final onColor = dark ? _onColor(bgTop, base) : const Color(0xFF1A1A1A);
    final onDark = onColor == Colors.white;

    final tabs = <(String?, String)>[
      (null, 'Pour vous'),
      ...categories.map((c) => (c.id.toString(), c.name)),
    ];
    final int active;
    if (isHome) {
      final selected = ref.watch(homeCategoryProvider);
      active = tabs.indexWhere((t) => t.$1 == selected);
    } else {
      active = activeCategoryId == null ? -1 : tabs.indexWhere((t) => t.$1 == activeCategoryId);
    }

    void select(int i) {
      ref.read(homeCategoryProvider.notifier).state = tabs[i].$1;
      if (!isHome) context.go('/');
    }

    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(child: _HeaderBackground(dark: dark, top: bgTop, bottom: bgBottom)),
          Padding(
            padding: EdgeInsets.only(top: topPad),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(12, scrolled ? 8 : 6, 12, 8),
                    child: HomeSearchBar(dark: dark, query: initialQuery),
                  ),
                  _CategoryChips(
                    dark: dark,
                    onColor: onColor,
                    onDark: onDark,
                    tabs: tabs,
                    activeIndex: active,
                    onSelect: select,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderBackground extends StatelessWidget {
  final bool dark;
  final Color top;
  final Color bottom;
  const _HeaderBackground({required this.dark, required this.top, required this.bottom});

  @override
  Widget build(BuildContext context) {
    if (!dark) {
      // Défilé : verre dépoli — les produits restent visibles sous le header.
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: _scrolledBlur, sigmaY: _scrolledBlur),
        child: ColoredBox(color: Colors.white.withOpacity(_scrolledOpacity)),
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom]),
      ),
    );
  }
}

// ═══════ Header en superposition ═══════
/// Hauteur actuelle du header superposé, transmise aux contenus pour qu'ils
/// commencent juste en dessous (tout en pouvant défiler DERRIÈRE lui).
class HeaderInset extends InheritedWidget {
  final ValueListenable<double> inset;
  const HeaderInset({super.key, required this.inset, required super.child});

  static ValueListenable<double>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HeaderInset>()?.inset;

  @override
  bool updateShouldNotify(HeaderInset old) => old.inset != inset;
}

/// Espace en haut d'un CustomScrollView = hauteur du header superposé
/// (0 hors de l'accueil).
class HeaderInsetSliver extends StatelessWidget {
  const HeaderInsetSliver({super.key});

  @override
  Widget build(BuildContext context) {
    final inset = HeaderInset.of(context);
    if (inset == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: ValueListenableBuilder<double>(
        valueListenable: inset,
        builder: (_, h, __) => SizedBox(height: h),
      ),
    );
  }
}

/// Rapporte la taille de son enfant après chaque mise en page où elle change.
class MeasureSize extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onChange;
  const MeasureSize({super.key, required this.onChange, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasureSize renderObject) {
    renderObject.onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  ValueChanged<Size> onChange;
  Size? _old;
  _RenderMeasureSize(this.onChange);

  @override
  void performLayout() {
    super.performLayout();
    final s = size;
    if (s == _old) return;
    _old = s;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(s));
  }
}

/// Loupe animée (Lottie) de la barre de recherche.
/// [size]  = place occupée dans la barre (layout).
/// [scale] = zoom visuel du dessin : utile car beaucoup de fichiers Lottie ont
///           une grosse marge vide autour du dessin. Le zoom ne décale rien.
/// Si le fichier est introuvable ou invalide, on retombe sur l'icône classique.
class _SearchLottie extends StatelessWidget {
  final double size;
  final double scale;
  const _SearchLottie({this.size = 24, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Transform.scale(
        scale: scale,
        child: Lottie.asset(
          _searchLottie,
          width: size,
          height: size,
          fit: BoxFit.contain,
          repeat: true,
          errorBuilder: (_, __, ___) => Icon(Icons.search, size: size * 0.85, color: _idle),
        ),
      ),
    );
  }
}

/// Barre de recherche GROSHOP (loupe animée + texte + recherche par photo).
/// Publique : réutilisée par l'accueil (dans [HomeHeader]) ET l'écran Catégories.
/// [dark] = true sur fond coloré, false sur fond blanc (bordure grise plus marquée).
class HomeSearchBar extends StatefulWidget {
  final bool dark;
  final String? query;
  const HomeSearchBar({super.key, this.dark = false, this.query});

  @override
  State<HomeSearchBar> createState() => _HomeSearchBarState();
}

class _HomeSearchBarState extends State<HomeSearchBar> {
  final _picker = ImagePicker();

  void _openEntry() => context.push('/recherche', extra: widget.query);

  Future<void> _visualSearch() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final x = await _picker.pickImage(source: source, imageQuality: 85);
      if (x == null || !mounted) return;
      context.push('/visual-search', extra: x.path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d’ouvrir l’image.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = (widget.query ?? '').trim().isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 42,
      padding: const EdgeInsets.only(left: 10, right: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: widget.dark ? _barBorderOnColor : _barBorderLight,
          width: _barBorderWidth,
        ),
        boxShadow: _barShadow,
      ),
      child: Row(children: [
        GestureDetector(
          onTap: _openEntry,
          behavior: HitTestBehavior.opaque,
          child: const _SearchLottie(size: 30, scale: 2.4), // ⭐ taille + zoom de la loupe
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: _openEntry,
            behavior: HitTestBehavior.opaque,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                hasQuery ? widget.query!.trim() : 'Rechercher sur Groshop.tn',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(
                  size: 14,
                  color: hasQuery ? const Color(0xFF0F1419) : const Color(0xFF9AA3AE),
                ),
              ),
            ),
          ),
        ),
        GestureDetector(
          onTap: _visualSearch,
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.photo_camera_outlined, size: 22, color: Color(0xFF0F1419)),
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
/// Onglets catégories, deux styles selon le défilement :
///  • en haut (fond coloré) : pilules, avec UNE pilule blanche qui glisse ;
///  • après défilement (fond blanc) : onglets soulignés — actif en gras noir,
///    trait noir qui glisse sous le texte, fine ligne grise en bas.
/// L'onglet actif est recentré automatiquement.
class _CategoryChips extends StatefulWidget {
  final bool dark; // true = en haut (pilules), false = défilé (soulignés)
  final Color onColor;
  final bool onDark;
  final List<(String?, String)> tabs;
  final int activeIndex; // -1 = aucune
  final ValueChanged<int> onSelect;
  const _CategoryChips({
    required this.dark,
    required this.onColor,
    required this.onDark,
    required this.tabs,
    required this.activeIndex,
    required this.onSelect,
  });

  @override
  State<_CategoryChips> createState() => _CategoryChipsState();
}

class _CategoryChipsState extends State<_CategoryChips> {
  static const _tabPad = 14.0; // marge interne des onglets soulignés
  static const _ink = Color(0xFF1A1A1A);
  static const _grey = Color(0xFF7A7A7A);

  final _scroll = ScrollController();
  final _stackKey = GlobalKey();
  List<GlobalKey> _keys = const [];
  List<Rect> _rects = const [];
  bool _animate = false; // pas d'animation au placement initial / changement de style
  bool _measureScheduled = false;

  String _signature(List<(String?, String)> t) => t.map((e) => '${e.$1}:${e.$2}').join('|');

  @override
  void didUpdateWidget(covariant _CategoryChips old) {
    super.didUpdateWidget(old);
    if (_signature(old.tabs) != _signature(widget.tabs) || old.dark != widget.dark) {
      // Liste ou style changé : tailles différentes → nouvelle mesure, sans glisse.
      _rects = const [];
      _animate = false;
    }
    if (old.activeIndex != widget.activeIndex) {
      _animate = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _centerOn(widget.activeIndex);
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scheduleMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final rects = <Rect>[];
      for (final k in _keys) {
        final rb = k.currentContext?.findRenderObject() as RenderBox?;
        if (rb == null || !rb.hasSize) return;
        rects.add(rb.localToGlobal(Offset.zero, ancestor: box) & rb.size);
      }
      final first = _rects.isEmpty;
      setState(() => _rects = rects);
      if (first) _centerOn(widget.activeIndex, animate: false);
    });
  }

  void _centerOn(int i, {bool animate = true}) {
    if (!_scroll.hasClients || i < 0 || i >= _rects.length) return;
    final pos = _scroll.position;
    final target = (12 + _rects[i].center.dx - pos.viewportDimension / 2).clamp(0.0, pos.maxScrollExtent);
    if (animate) {
      _scroll.animateTo(target, duration: kCategorySwitchDuration, curve: kCategorySwitchCurve);
    } else {
      _scroll.jumpTo(target);
    }
  }

  void _tap(int i) {
    if (i == widget.activeIndex) {
      _centerOn(i);
      return;
    }
    HapticFeedback.selectionClick();
    widget.onSelect(i);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabs;
    if (_keys.length != tabs.length) {
      _keys = List.generate(tabs.length, (_) => GlobalKey());
      _rects = const [];
    }
    if (_rects.length != tabs.length) _scheduleMeasure();

    return widget.dark ? _pills(tabs) : _underlined(tabs);
  }

  // ── Style « en haut » : pilules ──
  Widget _pills(List<(String?, String)> tabs) {
    final pillColor = Colors.white;
    final activeFg = AppColors.primary;
    final idleBg = Colors.white.withOpacity(widget.onDark ? 0.20 : 0.45);
    final idleFg = widget.onColor;
    final active = widget.activeIndex;
    final showPill = active >= 0 && active < _rects.length;

    return SizedBox(
      height: 44,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
        child: Stack(
          key: _stackKey,
          children: [
            if (showPill)
              AnimatedPositioned(
                duration: _animate ? kCategorySwitchDuration : Duration.zero,
                curve: kCategorySwitchCurve,
                left: _rects[active].left,
                width: _rects[active].width,
                top: 0,
                height: _chipH,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: pillColor,
                    borderRadius: BorderRadius.circular(_chipH / 2),
                    boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, 3))],
                  ),
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Padding(
                    padding: EdgeInsets.only(right: i == tabs.length - 1 ? 0 : _chipGap),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _tap(i),
                      child: AnimatedContainer(
                        key: _keys[i],
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        height: _chipH,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        decoration: BoxDecoration(
                          color: (showPill && i == active) ? Colors.transparent : idleBg,
                          borderRadius: BorderRadius.circular(_chipH / 2),
                        ),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 250),
                          style: AppTheme.body(
                            size: 13,
                            weight: FontWeight.w600,
                            color: (showPill && i == active) ? activeFg : idleFg,
                          ),
                          child: Text(tabs[i].$2, maxLines: 1),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Style « défilé » : onglets soulignés (comme la maquette) ──
  Widget _underlined(List<(String?, String)> tabs) {
    final active = widget.activeIndex;
    final showBar = active >= 0 && active < _rects.length;

    return DecoratedBox(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE5E5E5)))),
      child: SizedBox(
        height: 42,
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Stack(
            key: _stackKey,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _tap(i),
                      child: Container(
                        key: _keys[i],
                        height: 42,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: _tabPad),
                        // Astuce : une copie invisible en gras réserve la largeur,
                        // donc passer en gras ne décale jamais les autres onglets.
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Opacity(
                              opacity: 0,
                              child: Text(tabs[i].$2,
                                  maxLines: 1,
                                  style: AppTheme.body(size: 14.5, weight: FontWeight.w800, color: _ink)),
                            ),
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                              style: AppTheme.body(
                                size: 14.5,
                                weight: i == active ? FontWeight.w800 : FontWeight.w400,
                                color: i == active ? AppColors.primary : _grey,
                              ),
                              child: Text(tabs[i].$2, maxLines: 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              // Trait noir qui glisse sous l'onglet actif (largeur du texte).
              if (showBar)
                AnimatedPositioned(
                  duration: _animate ? kCategorySwitchDuration : Duration.zero,
                  curve: kCategorySwitchCurve,
                  left: _rects[active].left + _tabPad,
                  width: (_rects[active].width - _tabPad * 2).clamp(12.0, double.infinity),
                  bottom: 0,
                  height: 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}