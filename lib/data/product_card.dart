import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/theme.dart';
import '../data/models/product.dart';

const _ink = Color(0xFF0F1419);
const _mute = Color(0xFF6B7785);
const _faint = Color(0xFF9AA3AE);
const _certBlue = Color(0xFF2E7CF6);
const _promoRed = Color(0xFFFF3B30);
const _green = Color(0xFF0F9D58);

String _price(double n) => n.toStringAsFixed(2).replaceAll('.', ',');
String _count(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

class ProductCard extends StatelessWidget {
  final Product product;
  final bool showTrendingBadge; // pour le carrousel Best Sellers
  const ProductCard({super.key, required this.product, this.showTrendingBadge = false});

  @override
  Widget build(BuildContext context) {
    final p = product;
    final (mn, _) = p.priceRange;

    return GestureDetector(
      onTap: () => context.push('/produit/${p.id}'),
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Image ──
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: const Color(0xFFF4F5F7),
                    child: (p.primaryImage != null && p.primaryImage!.isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: p.primaryImage!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => const ColoredBox(color: Color(0xFFF4F5F7)),
                            errorWidget: (_, __, ___) =>
                                const Icon(Icons.image_outlined, color: Color(0xFFC0C6CC), size: 30),
                          )
                        : const Icon(Icons.inventory_2_outlined, color: Color(0xFFC0C6CC), size: 30),
                  ),
                  if (showTrendingBadge)
                    Positioned(
                      top: 8, left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFFFF6A2E), borderRadius: BorderRadius.circular(4)),
                        child: Text('TENDANCE',
                            style: AppTheme.body(size: 8.5, weight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                  if (!p.inStock)
                    Container(
                      color: Colors.white70,
                      alignment: Alignment.center,
                      child: Text('RUPTURE', style: AppTheme.body(size: 12, weight: FontWeight.w700, color: _ink)),
                    ),
                  if (p.badgeChoice)
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: Container(
                        color: _certBlue,
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        alignment: Alignment.center,
                        child: Text('Certifié Original',
                            style: AppTheme.body(size: 10, weight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 6),

          // ── Badges promo / livraison ──
          if (p.isPromo || p.isFreeShipping)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Wrap(spacing: 3, children: [
                if (p.isPromo) _tag('Promo', _promoRed),
                if (p.isFreeShipping) _tag('Livraison offerte', _green),
              ]),
            ),

          // ── Nom (2 lignes) ──
          Text(p.name,
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: AppTheme.body(size: 12, weight: FontWeight.w500, color: _ink, )),

          // ── Ventes + note ──
          if (p.soldCount != null || p.ratingAvg != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(children: [
                if (p.soldCount != null)
                  Text('${_count(p.soldCount!)}+ vendus', style: AppTheme.body(size: 10.5, color: _mute)),
                if (p.soldCount != null && p.ratingAvg != null)
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text('|', style: TextStyle(color: Color(0xFFDDDDDD), fontSize: 10.5))),
                if (p.ratingAvg != null) ...[
                  const Icon(Icons.star, size: 11, color: Color(0xFFFFB800)),
                  const SizedBox(width: 2),
                  Text(p.ratingAvg!.toStringAsFixed(1), style: AppTheme.body(size: 10.5, color: _mute)),
                ],
              ]),
            ),

          // ── Prix ──
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 5, children: [
              Text('TND ${_price(mn)}${p.isPriceRange ? '+' : ''}',
                  style: AppTheme.body(size: 14, weight: FontWeight.w800, color: _ink)),
              if (p.oldPrice != null && p.oldPrice! > mn)
                Text(_price(p.oldPrice!),
                    style: AppTheme.body(size: 10.5, color: _faint).copyWith(decoration: TextDecoration.lineThrough)),
              if (p.discount != null)
                Text('-${p.discount}%', style: AppTheme.body(size: 10.5, weight: FontWeight.w700, color: _promoRed)),
            ]),
          ),

          // ── MOQ ──
          if (p.moq != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('Min. ${p.moq} ${p.unit}', style: AppTheme.body(size: 10.5, color: _mute)),
            ),
        ],
      ),
    );
  }

  Widget _tag(String label, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(2)),
        child: Text(label, style: AppTheme.body(size: 9, weight: FontWeight.w700, color: Colors.white)),
      );
}