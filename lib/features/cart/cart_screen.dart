import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/models/cart.dart';
import '../../state/auth_provider.dart';
import '../../state/cart_provider.dart';
import '../checkout/checkout_screen.dart' show CheckoutLine;

const _orange = Color(0xFFFF7A00);
const _ink = Color(0xFF1A1A1A);
const _mute = Color(0xFF7A7A7A);
const _faint = Color(0xFFA0A0A0);
const _line = Color(0xFFEDEDED);
const _soft = Color(0xFFFFF0E8);
const _green = Color(0xFF05C46B);
const _red = Color(0xFFDC2626);

String _fmt(num n) {
  final s = n.toStringAsFixed(2);
  final p = s.split('.');
  final b = StringBuffer();
  for (var i = 0; i < p[0].length; i++) {
    if (i > 0 && (p[0].length - i) % 3 == 0) b.write(' ');
    b.write(p[0][i]);
  }
  return '${b.toString()},${p[1]}';
}

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});
  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final Set<String> _selected = {};
  final Set<String> _known = {};

  void _syncSelection(List<CartItem> items) {
    // Les nouveaux articles sont sélectionnés par défaut ; ceux que
    // l'utilisateur a décochés restent décochés (« Tout » décoche vraiment tout).
    final ids = items.map((i) => i.id).toSet();
    _selected.removeWhere((id) => !ids.contains(id));
    _known.removeWhere((id) => !ids.contains(id));
    for (final id in ids) {
      if (_known.add(id)) _selected.add(id);
    }
  }

  /// Envoie SEULEMENT les articles cochés vers l'écran de commande.
  /// cart_item_id est transmis pour garder devis / perso / prix négocié.
  void _goToCheckout(List<CartItem> items) {
    final lines = items
        .where((it) => _selected.contains(it.id))
        .map((it) => CheckoutLine(
              cartItemId: it.id,
              productId: it.productId.toString(),
              quantity: it.quantity,
            ))
        .toList();
    if (lines.isEmpty) return;
    context.push('/checkout', extra: lines);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider).valueOrNull;
    final cart = ref.watch(cartProvider);

    if (auth == null || !auth.isAuthenticated) {
      return _prompt(Icons.lock_outline, 'Connectez-vous', 'pour voir votre panier', 'Se connecter', () => context.go('/login'));
    }
    if (cart.loading && cart.items.isEmpty) {
      return const Scaffold(backgroundColor: Color(0xFFF4F5F7), body: Center(child: CircularProgressIndicator(color: _orange)));
    }
    if (cart.items.isEmpty) {
      return _prompt(Icons.shopping_cart_outlined, 'Panier vide', 'Ajoutez des produits pour commander', 'Découvrir les produits', () => context.go('/'));
    }

    _syncSelection(cart.items);

    // groupe par fournisseur
    final groups = <String, List<CartItem>>{};
    for (final it in cart.items) {
      groups.putIfAbsent(it.supplier?.id ?? 'unknown', () => []).add(it);
    }

    double total = 0, savings = 0;
    int selCount = 0;
    for (final it in cart.items) {
      if (!_selected.contains(it.id)) continue;
      total += it.lineTotal;
      savings += it.lineSavings;
      selCount++;
    }
    final allSelected = _selected.length == cart.items.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _titleBar(cart.items.length),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
              children: [
                _selectAll(allSelected, cart.items),
                ...groups.entries.map((e) => _supplierGroup(e.value)),
              ],
            ),
          ),
          _actionBar(total, savings, selCount, allSelected, cart.items),
        ]),
      ),
    );
  }

  Widget _titleBar(int n) => Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Flexible(
            child: Text('Panier ($n)', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTheme.body(size: 20, weight: FontWeight.w600, color: _ink)),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.location_on_outlined, size: 12, color: _orange),
              const SizedBox(width: 3),
              Text('Tunisie', maxLines: 1, style: AppTheme.body(size: 11.5, weight: FontWeight.w500, color: _orange)),
            ]),
          ),
          const Spacer(),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _confirmClear(),
            behavior: HitTestBehavior.opaque,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.delete_outline, size: 16, color: _mute),
              const SizedBox(width: 4),
              Text('Vider', maxLines: 1, style: AppTheme.body(size: 12.5, color: _mute)),
            ]),
          ),
        ]),
      );

  Widget _selectAll(bool all, List<CartItem> items) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
        child: GestureDetector(
          onTap: () => setState(() => all ? _selected.clear() : _selected.addAll(items.map((i) => i.id))),
          behavior: HitTestBehavior.opaque,
          child: Row(children: [
            _check(all, 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text('Tout sélectionner', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(size: 13, weight: FontWeight.w500, color: _ink)),
            ),
          ]),
        ),
      );

  Widget _supplierGroup(List<CartItem> items) {
    final sup = items.first.supplier;
    final ids = items.map((i) => i.id).toList();
    final all = ids.every(_selected.contains);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            GestureDetector(
              onTap: () => setState(() => all ? ids.forEach(_selected.remove) : _selected.addAll(ids)),
              child: _check(all, 22)),
            const SizedBox(width: 10),
            Container(width: 24, height: 24,
              decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(6)),
              clipBehavior: Clip.antiAlias,
              child: (sup?.logoUrl != null && sup!.logoUrl!.isNotEmpty)
                  ? CachedNetworkImage(imageUrl: sup.logoUrl!, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(Icons.storefront, size: 13, color: _orange))
                  : const Icon(Icons.storefront, size: 13, color: _orange)),
            const SizedBox(width: 8),
            Flexible(child: Text(sup?.name ?? 'Fournisseur', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTheme.body(size: 14, weight: FontWeight.w600, color: _ink))),
            const Icon(Icons.chevron_right, size: 15, color: _faint),
          ]),
        ),
        ...items.map((it) => Column(children: [
          Container(height: 1, color: const Color(0xFFF2F2F2), margin: const EdgeInsets.symmetric(horizontal: 14)),
          _row(it),
        ])),
      ]),
    );
  }

  Widget _row(CartItem it) {
    final sel = _selected.contains(it.id);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 28),
            child: GestureDetector(onTap: () => setState(() => sel ? _selected.remove(it.id) : _selected.add(it.id)), child: _check(sel, 20))),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => context.push('/produit/${it.productId}'),
          child: ClipRRect(borderRadius: BorderRadius.circular(10),
            child: SizedBox(width: 84, height: 84,
              child: (it.imageUrl != null && it.imageUrl!.isNotEmpty)
                  ? CachedNetworkImage(imageUrl: it.imageUrl!, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFFF6F6F6)))
                  : const ColoredBox(color: Color(0xFFF6F6F6), child: Icon(Icons.inventory_2_outlined, color: _faint)))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: AppTheme.body(size: 13.5, weight: FontWeight.w500, color: _ink).copyWith(height: 1.3)),
          if (it.variantName != null) Padding(padding: const EdgeInsets.only(top: 3),
              child: Text(it.variantName!, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(size: 12, color: _faint))),
          const SizedBox(height: 7),

          // ── Prix : pleine largeur, rétrécit au lieu de déborder ──
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${_fmt(it.lineTotal)} TND', maxLines: 1,
                  style: AppTheme.body(size: 16, weight: FontWeight.w700, color: _ink)),
              if (it.oldPrice > it.unitPrice) Padding(padding: const EdgeInsets.only(left: 5, bottom: 1),
                  child: Text(_fmt(it.oldPrice), maxLines: 1,
                      style: AppTheme.body(size: 11, color: const Color(0xFFBBBBBB)).copyWith(decoration: TextDecoration.lineThrough))),
            ]),
          ),
          Text('${_fmt(it.unitPrice)} / ${it.unit}${it.quantity <= it.moq ? ' · MOQ ${it.moq}' : ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppTheme.body(size: 11, color: _faint)),
          const SizedBox(height: 8),

          // ── Livraison (se replie) + quantité + supprimer ──
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.local_shipping_outlined, size: 12, color: _green)),
                const SizedBox(width: 5),
                Flexible(
                  child: Text('Livraison sous ${it.deliveryDays ?? '2–5'} jours',
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(size: 11, color: _green).copyWith(height: 1.2)),
                ),
              ]),
            ),
            const SizedBox(width: 6),
            Container(
              decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(22)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _stepBtn(Icons.remove, it.quantity > it.moq, () => ref.read(cartProvider.notifier).setQty(it.id, it.quantity - 1)),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 26, maxWidth: 48),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('${it.quantity}', maxLines: 1, textAlign: TextAlign.center,
                        style: AppTheme.body(size: 13, weight: FontWeight.w600, color: _ink)),
                  ),
                ),
                _stepBtn(Icons.add, true, () => ref.read(cartProvider.notifier).setQty(it.id, it.quantity + 1)),
              ]),
            ),
            const SizedBox(width: 2),
            GestureDetector(onTap: () => ref.read(cartProvider.notifier).remove(it.id),
                child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.delete_outline, size: 16, color: Color(0xFFC4C4C4)))),
          ]),
        ])),
      ]),
    );
  }

  Widget _actionBar(double total, double savings, int selCount, bool all, List<CartItem> items) => Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: _line))),
        child: SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            GestureDetector(
              onTap: () => setState(() => all ? _selected.clear() : _selected.addAll(items.map((i) => i.id))),
              behavior: HitTestBehavior.opaque,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _check(all, 20),
                const SizedBox(width: 7),
                Text('Tout', maxLines: 1, style: AppTheme.body(size: 12.5, color: _ink)),
              ])),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              if (savings > 0)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text('Économie ${_fmt(savings)} TND', maxLines: 1,
                      style: AppTheme.body(size: 10.5, weight: FontWeight.w600, color: _orange)),
                ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text.rich(TextSpan(text: _fmt(total), style: AppTheme.body(size: 17, weight: FontWeight.w700, color: _ink),
                    children: [TextSpan(text: ' TND', style: AppTheme.body(size: 12, color: _mute))]), maxLines: 1),
              ),
            ])),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.5),
              child: GestureDetector(
                onTap: selCount == 0 ? null : () => _goToCheckout(items), // ⭐ vers le récapitulatif
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(color: selCount == 0 ? const Color(0xFFDDDDDD) : _orange, borderRadius: BorderRadius.circular(26)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                      child: Text('Commander ($selCount)', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(size: 14, weight: FontWeight.w600, color: Colors.white)),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward, size: 16, color: Colors.white),
                  ]),
                ),
              ),
            ),
          ]),
        )),
      );

  Widget _check(bool on, double size) => Container(
        width: size, height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: on ? _orange : Colors.transparent,
            border: Border.all(color: on ? _orange : const Color(0xFFCCCCCC), width: 2)),
        child: on ? Icon(Icons.check, size: size * 0.6, color: Colors.white) : null,
      );

  Widget _stepBtn(IconData i, bool on, VoidCallback tap) => InkWell(
        onTap: on ? tap : null,
        customBorder: const CircleBorder(),
        child: SizedBox(width: 30, height: 30, child: Icon(i, size: 14, color: on ? _ink : const Color(0xFFDDDDDD))),
      );

  void _confirmClear() => showDialog(context: context, builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Vider le panier ?', style: AppTheme.body(size: 16, weight: FontWeight.w700, color: _ink)),
        content: Text('Tous les articles seront supprimés.', style: AppTheme.body(size: 13.5, color: _mute)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Annuler', style: AppTheme.body(color: _mute))),
          TextButton(onPressed: () { ref.read(cartProvider.notifier).clear(); Navigator.pop(ctx); },
              child: Text('Vider', style: AppTheme.body(weight: FontWeight.w600, color: _red))),
        ],
      ));

  Widget _prompt(IconData icon, String title, String sub, String cta, VoidCallback onTap) => Scaffold(
        backgroundColor: const Color(0xFFF4F5F7),
        body: Center(
          // Scroll si l'écran est trop bas (paysage, clavier, grande police).
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 96, height: 96,
                decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(26)),
                child: Icon(icon, size: 42, color: _orange)),
              const SizedBox(height: 18),
              Text(title, textAlign: TextAlign.center,
                  style: AppTheme.body(size: 18, weight: FontWeight.w700, color: _ink)),
              const SizedBox(height: 6),
              Text(sub, textAlign: TextAlign.center, style: AppTheme.body(size: 13, color: _faint)),
              const SizedBox(height: 22),
              GestureDetector(onTap: onTap, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(28)),
                child: Text(cta, textAlign: TextAlign.center,
                    style: AppTheme.body(size: 13.5, weight: FontWeight.w700, color: Colors.white)))),
            ]),
          ),
        ),
      );
}