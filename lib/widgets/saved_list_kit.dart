import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/theme.dart';
import '../data/models/product.dart';
import '../state/cart_provider.dart';
import 'product_card.dart';

/// Briques partagées par les pages « listes » du compte :
/// Favoris, Historique, Boutiques suivies.

class SavedColors {
  SavedColors._();
  static const orange = Color(0xFFFF7A00);
  static const ink = Color(0xFF0F1419);
  static const mute = Color(0xFF6B7785);
  static const faint = Color(0xFF9AA3AE);
  static const line = Color(0xFFECEEF1);
  static const green = Color(0xFF0F9D58);
  static const danger = Color(0xFFDC2626);
  static const bg = Color(0xFFF4F5F7);
  static const soft = Color(0xFFFFF0E8);
}

String fmtTnd(num n) => n.toStringAsFixed(2).replaceAll('.', ',');

void showSoon(BuildContext context, String what) => ScaffoldMessenger.of(context)
    .showSnackBar(SnackBar(content: Text('$what — bientôt disponible.')));

// ─────────────────────────── En-tête ───────────────────────────

class SavedHeader extends ConsumerWidget {
  final String title;
  final bool editing;
  final VoidCallback? onToggleEdit;
  const SavedHeader({super.key, required this.title, this.editing = false, this.onToggleEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(cartProvider).count;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: SavedColors.ink),
          onPressed: () => context.canPop() ? context.pop() : context.go('/dashboard'),
        ),
        Expanded(
          child: Text(title, overflow: TextOverflow.ellipsis,
              style: AppTheme.body(size: 21, weight: FontWeight.w700, color: SavedColors.ink)),
        ),
        GestureDetector(
          onTap: () => context.go('/panier'),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Stack(clipBehavior: Clip.none, children: [
              const Icon(Icons.shopping_cart_outlined, color: SavedColors.ink, size: 22),
              if (count > 0)
                Positioned(
                  top: -6, right: -8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    constraints: const BoxConstraints(minWidth: 16), height: 16,
                    decoration: BoxDecoration(color: SavedColors.orange, borderRadius: BorderRadius.circular(20)),
                    alignment: Alignment.center,
                    child: Text(count > 99 ? '99+' : '$count',
                        style: AppTheme.body(size: 10, weight: FontWeight.w800, color: Colors.white)),
                  ),
                ),
            ]),
          ),
        ),
        if (onToggleEdit != null)
          IconButton(
            icon: Icon(Icons.checklist, color: editing ? SavedColors.orange : SavedColors.ink),
            onPressed: onToggleEdit,
          ),
      ]),
    );
  }
}

// ─────────────────────────── Onglet ───────────────────────────

class SavedTab extends StatelessWidget {
  final String label;
  final Widget? trailing;
  const SavedTab({super.key, required this.label, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          IntrinsicWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(label, style: AppTheme.body(size: 17, weight: FontWeight.w700, color: SavedColors.ink)),
              ),
              Container(height: 3,
                  decoration: BoxDecoration(color: SavedColors.ink, borderRadius: BorderRadius.circular(2))),
            ]),
          ),
          const Spacer(),
          if (trailing != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: trailing!),
        ]),
      );
}

// ─────────────────────────── Sélection ───────────────────────────

class SelectCheckbox extends StatelessWidget {
  final bool checked;
  const SelectCheckbox({super.key, required this.checked});

  @override
  Widget build(BuildContext context) => Container(
        width: 22, height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: checked ? SavedColors.orange : Colors.white,
          border: Border.all(color: checked ? SavedColors.orange : const Color(0xFFCBD2D9), width: 2),
        ),
        child: checked ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
      );
}

class SelectionBar extends StatelessWidget {
  final bool allSelected;
  final int count;
  final String actionLabel;
  final VoidCallback onToggleAll;
  final VoidCallback onAction;
  const SelectionBar({
    super.key,
    required this.allSelected,
    required this.count,
    required this.actionLabel,
    required this.onToggleAll,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: SavedColors.line)),
          boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, -4))],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(children: [
              GestureDetector(
                onTap: onToggleAll,
                behavior: HitTestBehavior.opaque,
                child: Row(children: [
                  SelectCheckbox(checked: allSelected),
                  const SizedBox(width: 8),
                  Text('Tout', style: AppTheme.body(size: 14, color: SavedColors.ink)),
                ]),
              ),
              const Spacer(),
              GestureDetector(
                onTap: count > 0 ? onAction : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                  decoration: BoxDecoration(
                    color: count > 0 ? SavedColors.danger : const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(count > 0 ? '$actionLabel ($count)' : actionLabel,
                      style: AppTheme.body(size: 15, weight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ]),
          ),
        ),
      );
}

// ─────────────────────────── Ligne produit ───────────────────────────

/// Ligne produit : image · nom · prix · Ajouter au panier + recherche visuelle.
class ProductSavedRow extends ConsumerStatefulWidget {
  final Product p;
  final bool editing;
  final bool selected;
  final VoidCallback onToggleSel;
  final VoidCallback? onVisual;
  const ProductSavedRow({
    super.key,
    required this.p,
    required this.editing,
    required this.selected,
    required this.onToggleSel,
    this.onVisual,
  });

  @override
  ConsumerState<ProductSavedRow> createState() => _ProductSavedRowState();
}

class _ProductSavedRowState extends ConsumerState<ProductSavedRow> {
  bool _busy = false;
  bool _done = false;

  Future<void> _add() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await ref.read(cartProvider.notifier).add(widget.p.id, widget.p.moq ?? 1);
      if (ok && mounted) {
        setState(() => _done = true);
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) setState(() => _done = false);
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Impossible d'ajouter au panier.")));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Produits similaires à partir de l'image du produit (POST /products/visual-search-url/).
  void _visualSearch() {
    final img = widget.p.primaryImage;
    if (img == null || img.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Ce produit n'a pas d'image à rechercher.")));
      return;
    }
    context.push('/visual-search?url=${Uri.encodeComponent(img)}');
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final old = (p.oldPrice != null && p.oldPrice! > p.basePrice) ? fmtTnd(p.oldPrice!) : null;
    const placeholder = ColoredBox(color: SavedColors.bg);
    const noImage = ColoredBox(color: SavedColors.bg, child: Icon(Icons.inventory_2_outlined, color: SavedColors.faint));

    return GestureDetector(
      onTap: widget.editing ? widget.onToggleSel : () => context.push('/produit/${p.id}'),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SavedColors.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.editing)
            Padding(
              padding: const EdgeInsets.only(right: 12, top: 50),
              child: SelectCheckbox(checked: widget.selected),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 116, height: 116,
              child: (p.primaryImage != null && p.primaryImage!.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: p.primaryImage!, fit: BoxFit.cover,
                      placeholder: (_, __) => placeholder,
                      errorWidget: (_, __, ___) => noImage)
                  : noImage,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(size: 15, color: SavedColors.ink).copyWith(height: 1.35)),
              const SizedBox(height: 10),
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 7, children: [
                Text('TND ${fmtTnd(p.basePrice)}',
                    style: AppTheme.body(size: 17, weight: FontWeight.w800, color: SavedColors.ink)),
                if (old != null)
                  Text('TND $old',
                      style: AppTheme.body(size: 12.5, color: SavedColors.faint)
                          .copyWith(decoration: TextDecoration.lineThrough)),
              ]),
              if (!widget.editing)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _add,
                        child: Container(
                          height: 40, alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _done ? SavedColors.green : SavedColors.ink,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Opacity(
                            opacity: _busy ? 0.7 : 1,
                            child: Text(_busy ? 'Ajout…' : (_done ? '✓ Ajouté' : 'Ajouter au panier'),
                                style: AppTheme.body(size: 13, weight: FontWeight.w600, color: Colors.white)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: widget.onVisual ?? _visualSearch,
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle,
                          border: Border.all(color: SavedColors.line),
                        ),
                        child: const Icon(Icons.image_search, size: 18, color: SavedColors.ink),
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────── Recommandations ───────────────────────────

class RecoSection extends StatelessWidget {
  final List<Product> items;
  const RecoSection({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final left = <Widget>[], right = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final card = Padding(padding: const EdgeInsets.only(bottom: 12), child: ProductCard(product: items[i]));
      (i.isEven ? left : right).add(card);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Recommandés pour vous',
            style: AppTheme.body(size: 17, weight: FontWeight.w700, color: SavedColors.ink)),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: left)),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: right)),
        ]),
      ]),
    );
  }
}

// ─────────────────────────── États vide / chargement ───────────────────────────

class SavedEmpty extends StatelessWidget {
  final IconData icon;
  final String message;
  final String ctaLabel;
  final VoidCallback? onCta;
  const SavedEmpty({
    super.key,
    required this.icon,
    required this.message,
    this.ctaLabel = 'Explorer des produits',
    this.onCta,
  });

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SavedColors.line),
            ),
            child: Column(children: [
              Icon(icon, size: 40, color: SavedColors.faint),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center,
                  style: AppTheme.body(size: 15, color: SavedColors.mute)),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: onCta ?? () => context.go('/'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 11),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: SavedColors.ink),
                  ),
                  child: Text(ctaLabel,
                      style: AppTheme.body(size: 13.5, weight: FontWeight.w700, color: SavedColors.ink)),
                ),
              ),
            ]),
          ),
        ],
      );
}

class RowSkeleton extends StatelessWidget {
  final double imageSize;
  final bool circle;
  const RowSkeleton({super.key, this.imageSize = 116, this.circle = false});

  @override
  Widget build(BuildContext context) {
    Widget box(double w, double h, [double r = 4]) => Container(
          width: w, height: h,
          decoration: BoxDecoration(color: SavedColors.bg, borderRadius: BorderRadius.circular(r)),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: List.generate(
        4,
        (_) => Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SavedColors.line))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            box(imageSize, imageSize, circle ? imageSize / 2 : 10),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  box(double.infinity, 12),
                  const SizedBox(height: 10),
                  box(160, 12),
                  if (!circle) ...[const SizedBox(height: 18), box(120, 18)],
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}