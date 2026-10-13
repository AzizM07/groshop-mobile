import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/theme.dart';
import '../data/models/product.dart';

const _orange = Color(0xFFFF5E20);
const _ink = Color(0xFF0F1419);
const _mute = Color(0xFF6B7785);
const _faint = Color(0xFF9AA3AE);
const _blue = Color(0xFF1A6DD2);
const _green = Color(0xFF0F9D58);
const _certBlue = Color(0xFF2E7CF6);
const _star = Color(0xFFFFCE00);
const _starOff = Color(0xFFE3E6EA);

/// Espacement vertical entre les lignes d'infos (avant : 3).
const _gap = 2.0;

/// Hauteur de ligne des textes d'infos (resserre l'interligne).
const _lh = 1.2;

String _price(double n) => n.toStringAsFixed(2).replaceAll('.', ',');
String _count(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

class ProductCard extends StatelessWidget {
  final Product product;
  final bool showTrendingBadge;

  /// Affiche l'onglet « Nos Promos » sous l'image (produits en promo).
  /// Réservé aux cartes de la page Catégories.
  final bool promoTab;

  const ProductCard({
    super.key,
    required this.product,
    this.showTrendingBadge = false,
    this.promoTab = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = product;
    final (mn, _) = p.priceRange;
    final showTab = promoTab && p.isPromo;

    return GestureDetector(
      onTap: () => context.push('/produit/${p.id}'),
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Image (+ onglet promo en extension sous l'image) ──
          LayoutBuilder(builder: (ctx, c) {
            final w = c.maxWidth;
            final tabH = (w * 0.10).clamp(15.0, 20.0); // ~1/10 de la hauteur d'image
            final dip = tabH * 0.32;                   // profondeur du creux concave
            return Column(mainAxisSize: MainAxisSize.min, children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: showTab
                      ? const BorderRadius.vertical(top: Radius.circular(8))
                      : BorderRadius.circular(8),
                  child: Stack(fit: StackFit.expand, children: [
                    Container(
                      color: const Color(0xFFF7F8FA),
                      child: (p.primaryImage != null && p.primaryImage!.isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: p.primaryImage!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => const ColoredBox(color: Color(0xFFF7F8FA)),
                              errorWidget: (_, __, ___) => const Icon(Icons.image_outlined, color: Color(0xFFC0C6CC), size: 30),
                            )
                          : const Icon(Icons.inventory_2_outlined, color: Color(0xFFC0C6CC), size: 30),
                    ),
                    if (showTrendingBadge)
                      Positioned(top: 8, left: 8, child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFFFF6A2E), borderRadius: BorderRadius.circular(4)),
                        child: Text('TENDANCE', style: AppTheme.body(size: 8.5, weight: FontWeight.w700, color: Colors.white)))),
                    if (!p.inStock)
                      Container(color: Colors.white70, alignment: Alignment.center,
                        child: Text('RUPTURE', style: AppTheme.body(size: 12, weight: FontWeight.w700, color: _ink))),
                  ]),
                ),
              ),
              // Onglet « Nos Promos » : remonte de 3px pour se coller à l'image.
              if (showTab)
                Transform.translate(offset: const Offset(0, -3), child: _promoTab(tabH, dip)),
            ]);
          }),
          SizedBox(height: showTab ? 2 : 5),

          // ── Badges sous l'image (Certifié / Livraison offerte) — rétrécis ──
          if (p.supplierVerified || p.isFreeShipping)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Wrap(spacing: 3, runSpacing: 3, children: [
                if (p.supplierVerified) _badge('Certifié', _certBlue, Colors.white),
                if (p.isFreeShipping) _badge('Livraison offerte', _green, Colors.white),
              ]),
            ),

          // ── Nom (2 lignes) ──
          Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: AppTheme.body(size: 12.5, weight: FontWeight.w400, color: _ink).copyWith(height: 1.2)),
          const SizedBox(height: _gap),

          // ── Prix (16,00 TND) ──
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 5, children: [
            Text.rich(TextSpan(
              text: '${_price(mn)}${p.isPriceRange ? '+' : ''} ',
              style: AppTheme.body(size: 16, weight: FontWeight.w700, color: _ink).copyWith(height: 1.1),
              children: [TextSpan(text: 'TND', style: AppTheme.body(size: 10.5, weight: FontWeight.w600, color: _ink))],
            )),
            if (p.oldPrice != null && p.oldPrice! > mn)
              Text('${_price(p.oldPrice!)} TND',
                  style: AppTheme.body(size: 11, color: _faint).copyWith(decoration: TextDecoration.lineThrough, height: _lh)),
          ]),

          // ── Étoiles + note + (avis) ──
          if (p.ratingAvg != null)
            Padding(
              padding: const EdgeInsets.only(top: _gap),
              child: Row(children: [
                ...List.generate(5, (i) => Icon(Icons.star, size: 12,
                    color: i < p.ratingAvg!.round() ? _star : _starOff)),
                const SizedBox(width: 4),
                Text(p.ratingAvg!.toStringAsFixed(1),
                    style: AppTheme.body(size: 11, weight: FontWeight.w600, color: _ink).copyWith(height: _lh)),
                if (p.reviewCount != null && p.reviewCount! > 0)
                  Text(' (${p.reviewCount})', style: AppTheme.body(size: 10.5, color: _mute).copyWith(height: _lh)),
              ]),
            ),

          // ── MOQ + vendus ──
          if (p.moq != null)
            Padding(
              padding: const EdgeInsets.only(top: _gap),
              child: Text.rich(TextSpan(
                text: 'Quantité min. : ${p.moq} ${p.unit}',
                style: AppTheme.body(size: 11.5, color: _ink).copyWith(height: _lh),
                children: [
                  if (p.soldCount != null)
                    TextSpan(text: ' · ${_count(p.soldCount!)} vendus', style: AppTheme.body(size: 11.5, color: _mute)),
                ],
              )),
            )
          else if (p.soldCount != null)
            Padding(padding: const EdgeInsets.only(top: _gap),
                child: Text('${_count(p.soldCount!)} vendus',
                    style: AppTheme.body(size: 11.5, color: _mute).copyWith(height: _lh))),

          // ── Fournisseur + Verified + médailles + années ──
          if (p.supplierName != null || p.supplierVerified || p.supplierMedals > 0 || p.yearsActive != null)
            Padding(
              padding: const EdgeInsets.only(top: _gap),
              child: Row(children: [
                if (p.supplierName != null)
                  Flexible(child: Text(p.supplierName!, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(size: 11.5, color: _mute).copyWith(height: _lh))),
                if (p.supplierVerified) Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.verified, size: 11, color: _blue),
                    const SizedBox(width: 2),
                    Text('Verified', style: AppTheme.body(size: 11, weight: FontWeight.w700, color: _blue).copyWith(height: _lh)),
                  ])),
                if (p.supplierMedals > 0) Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Row(mainAxisSize: MainAxisSize.min,
                    children: List.generate(p.supplierMedals, (_) => const Padding(
                      padding: EdgeInsets.only(left: 1),
                      child: Icon(Icons.workspace_premium, size: 10, color: _orange))))),
                if (p.yearsActive != null) Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text('${p.yearsActive} ans', style: AppTheme.body(size: 11, color: _mute).copyWith(height: _lh))),
              ]),
            ),
        ],
      ),
    );
  }

  // Onglet « Nos Promos » : petite extension sous l'image, bord haut concave.
  Widget _promoTab(double h, double dip) => ClipPath(
        clipper: _PromoTabClipper(dip),
        child: Container(
          height: h,
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFFFF3D7F), Color(0xFFFF2E4D)],
            ),
          ),
          alignment: const Alignment(0, 0.4),
          child: Text('Nos Promos', style: AppTheme.body(size: 10, weight: FontWeight.w600, color: Colors.white)),
        ),
      );

  // Badge compact façon AliExpress (~15px de haut au lieu de ~22px).
  Widget _badge(String t, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(2)),
        child: Text(t, style: AppTheme.body(size: 9.5, weight: FontWeight.w700, color: fg).copyWith(height: 1.15)),
      );
}

// Découpe : bord haut concave (creux au centre) + coins bas arrondis.
class _PromoTabClipper extends CustomClipper<Path> {
  final double dip;
  const _PromoTabClipper(this.dip);

  @override
  Path getClip(Size s) {
    const r = 3.0;
    return Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(s.width / 2, dip, s.width, 0)
      ..lineTo(s.width, s.height - r)
      ..quadraticBezierTo(s.width, s.height, s.width - r, s.height)
      ..lineTo(r, s.height)
      ..quadraticBezierTo(0, s.height, 0, s.height - r)
      ..close();
  }

  @override
  bool shouldReclip(covariant _PromoTabClipper old) => old.dip != dip;
}