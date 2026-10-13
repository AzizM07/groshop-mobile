import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import '../../../core/theme.dart';
import '../../../data/api/products_api.dart';
import '../../../data/models/product.dart';

const _orange = Color(0xFFFF8009);
const _orangeDark = Color(0xFFFF6A00);
const _pillBg = Color(0xFFFFF1E0);
const _priceColor = Color(0xFF0F1419);
const _titleColor = Color(0xFF0F1419);
const _subtitleColor = Color(0xFF8A94A0);
const _pillInactiveText = Color(0xFF5B6470);
const _pillInactiveBg = Color(0xFFF1F2F4);
const _nameColor = Color(0xFF5B6470);
const _imgBg = Color(0xFFFAFAFB);

const _initialCount = 6;

/// Chemin de l'animation Lottie du trophée (à déclarer dans pubspec.yaml).
const _trophyLottie = 'assets/lottie/trophy.json';

String _fmtNum(num? n) {
  final v = n ?? 0;
  final fixed = v.toStringAsFixed(2);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (int i = 0; i < intPart.length; i++) {
    if (i != 0 && (intPart.length - i) % 3 == 0) buf.write(' ');
    buf.write(intPart[i]);
  }
  return '${buf.toString()},${parts[1]}';
}

class DisplayPrice {
  final double single;
  final double? rangeMax;
  const DisplayPrice.single(this.single) : rangeMax = null;
  const DisplayPrice.range(this.single, double max) : rangeMax = max;
  bool get isRange => rangeMax != null;
  double get min => single;
}

DisplayPrice _computePrice(Product p) {
  final (mn, mx) = p.priceRange;
  return mn == mx ? DisplayPrice.single(mn) : DisplayPrice.range(mn, mx);
}

class BestSellers extends ConsumerStatefulWidget {
  const BestSellers({super.key});
  @override
  ConsumerState<BestSellers> createState() => _BestSellersState();
}

class _BestSellersState extends ConsumerState<BestSellers> {
  String _active = 'Tout';
  bool _expanded = false;

  @override
  Widget build(BuildContext context, [WidgetRef? _]) {
    final trending = ref.watch(trendingProvider);
    final items = trending.valueOrNull ?? const <Product>[];
    if (items.isEmpty) return const SizedBox.shrink();

    final categories = <String>[
      'Tout',
      ...{for (final p in items) if (p.categoryName != null) p.categoryName!},
    ];

    final filtered = _active == 'Tout'
        ? items
        : items.where((p) => p.categoryName == _active).toList();
    final list = _expanded ? filtered : filtered.take(_initialCount).toList();

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.only(top: 14, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => context.push('/tendances'),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(
                children: [
                  const _TrophyLottie(size: 34),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Best Sellers',
                            style: AppTheme.body(size: 17, weight: FontWeight.w800, color: _titleColor)),
                        const SizedBox(height: 2),
                        Text("Tendances du moment jusqu'à -90%",
                            style: AppTheme.body(size: 11, weight: FontWeight.w500, color: _subtitleColor)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 20, color: _titleColor),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 33,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemBuilder: (_, i) {
                final cat = categories[i];
                final on = _active == cat;
                return GestureDetector(
                  onTap: () => setState(() { _active = cat; _expanded = false; }),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: on ? _orange : _pillInactiveBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(cat,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(size: 10.5, weight: FontWeight.w600,
                            color: on ? Colors.white : _pillInactiveText)),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: _MasonryGrid(items: list, columns: 3, gap: 10),
          ),
          if (!_expanded && filtered.length > _initialCount)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
              child: Center(
                child: GestureDetector(
                  onTap: () => setState(() => _expanded = true),
                  child: Text('Voir plus',
                      style: AppTheme.body(size: 13, weight: FontWeight.w600, color: _titleColor)
                          .copyWith(decoration: TextDecoration.underline)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MasonryGrid extends StatelessWidget {
  final List<Product> items;
  final int columns;
  final double gap;
  const _MasonryGrid({required this.items, this.columns = 3, this.gap = 10});

  @override
  Widget build(BuildContext context) {
    final cols = List.generate(columns, (_) => <Product>[]);
    for (var i = 0; i < items.length; i++) {
      cols[i % columns].add(items[i]);
    }
    final children = <Widget>[];
    for (var c = 0; c < columns; c++) {
      if (c > 0) children.add(SizedBox(width: gap));
      children.add(
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var j = 0; j < cols[c].length; j++) ...[
                if (j > 0) SizedBox(height: gap),
                _TrendingCard(product: cols[c][j]),
              ],
            ],
          ),
        ),
      );
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

/// Animation Lottie du trophée à côté du titre « Best Sellers ».
/// Si le fichier est introuvable ou invalide, on retombe sur une icône trophée.
class _TrophyLottie extends StatelessWidget {
  final double size;
  const _TrophyLottie({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Lottie.asset(
        _trophyLottie,
        width: size,
        height: size,
        fit: BoxFit.contain,
        repeat: true,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.emoji_events, size: size * 0.7, color: _orangeDark),
      ),
    );
  }
}

class _TrendingCard extends StatelessWidget {
  final Product product;
  const _TrendingCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final price = _computePrice(product);
    final showSold = (product.soldCount ?? 0) > 0;

    return GestureDetector(
      onTap: () => context.push('/produit/${product.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      color: _imgBg,
                      child: product.primaryImage != null
                          ? Image.network(product.primaryImage!, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.image_not_supported_outlined, color: Color(0xFF9AA3AE))))
                          : const Center(child: Icon(Icons.image_not_supported_outlined, color: Color(0xFF9AA3AE))),
                    ),
                  ),
                ),
                Positioned(right: 6, bottom: 6, child: _HeartButton(productId: product.id)),
              ],
            ),
          ),
          _RollingSoldRating(showSold: showSold, soldCount: product.soldCount, rating: product.ratingAvg),
          Text.rich(
            TextSpan(
              text: price.isRange ? '${_fmtNum(price.min)} - ${_fmtNum(price.rangeMax)}' : _fmtNum(price.single),
              style: TextStyle(fontSize: price.isRange ? 15 : 18, fontWeight: FontWeight.w900,
                  color: _priceColor, letterSpacing: -0.2, height: 1.2),
              children: const [TextSpan(text: ' TND', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700))],
            ),
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }
}

/// Bouton cœur : persiste réellement le favori. Un tap pendant un appel en
/// cours est ignoré (plus de désync UI/serveur), et l'UI revient en arrière si
/// l'appel API échoue.
class _HeartButton extends ConsumerStatefulWidget {
  final String productId;
  const _HeartButton({required this.productId});
  @override
  ConsumerState<_HeartButton> createState() => _HeartButtonState();
}

class _HeartButtonState extends ConsumerState<_HeartButton> with SingleTickerProviderStateMixin {
  bool _fav = false;
  bool _busy = false;

  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  late final Animation<double> _pop = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35).chain(CurveTween(curve: Curves.easeOut)), weight: 45),
    TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 55),
  ]).animate(_c);

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  Future<void> _toggle() async {
    if (_busy) return; // ⭐ ignore les taps tant qu'un appel n'est pas terminé
    final next = !_fav;
    setState(() => _fav = next);
    _c.forward(from: 0); // petit « pop »
    _busy = true;
    try {
      final api = ref.read(productsApiProvider);
      if (next) {
        await api.addFavorite(widget.productId);
      } else {
        await api.removeFavorite(widget.productId);
      }
    } catch (_) {
      if (mounted) setState(() => _fav = !next); // ⭐ revert si l'API échoue
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggle,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: _pop,
        child: Container(
          width: 27, height: 27,
          decoration: const BoxDecoration(
            color: Colors.white, shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x2E000000), blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: Icon(_fav ? Icons.favorite : Icons.favorite_border,
              size: 15, color: _fav ? _orange : _priceColor),
        ),
      ),
    );
  }
}

class _RollingSoldRating extends StatefulWidget {
  final bool showSold;
  final int? soldCount;
  final double? rating;
  const _RollingSoldRating({required this.showSold, required this.soldCount, required this.rating});
  @override
  State<_RollingSoldRating> createState() => _RollingSoldRatingState();
}

class _RollingSoldRatingState extends State<_RollingSoldRating> {
  Timer? _timer;
  int _tick = 0;
  bool get _hasSold => widget.showSold;
  bool get _hasRating => widget.rating != null;

  @override
  void initState() {
    super.initState();
    if (_hasSold && _hasRating) {
      _timer = Timer.periodic(const Duration(seconds: 3), (_) { if (mounted) setState(() => _tick++); });
    }
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (!_hasSold && !_hasRating) return const SizedBox(height: 22);
    final showingSold = (_hasSold && _hasRating) ? _tick % 2 == 0 : _hasSold;

    Widget pill;
    if (showingSold) {
      final sold = widget.soldCount ?? 0;
      final label = sold >= 1000 ? '${(sold / 1000).toStringAsFixed(1)}k vendus' : '$sold vendus';
      pill = _Pill(icon: Icons.local_fire_department, label: label);
    } else {
      pill = _Pill(icon: Icons.star, label: widget.rating!.toStringAsFixed(1));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero).animate(anim),
            child: child,
          ),
        ),
        child: Align(key: ValueKey(showingSold), alignment: Alignment.centerLeft, child: pill),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Pill({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: _orangeDark),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _orangeDark)),
      ],
    );
  }
}