import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/api/cart_api.dart';
import '../data/models/cart.dart';
import 'auth_provider.dart';

class CartState {
  final List<CartItem> items;
  final bool loading;
  const CartState({this.items = const [], this.loading = false});

  int get count => items.length;
  int get unitCount => items.fold(0, (n, i) => n + i.quantity);
}

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() {
    // recharge à chaque changement d'auth (login/logout)
    ref.listen(authProvider, (_, next) {
      final logged = next.valueOrNull?.isAuthenticated ?? false;
      if (logged) {
        refresh();
      } else {
        state = const CartState();
      }
    });
    Future.microtask(refresh);
    return const CartState(loading: true);
  }

  CartApi get _api => ref.read(cartApiProvider);

  Future<void> refresh() async {
    final logged = ref.read(authProvider).valueOrNull?.isAuthenticated ?? false;
    if (!logged) { state = const CartState(); return; }
    state = CartState(items: state.items, loading: true);
    try {
      state = CartState(items: await _api.list());
    } catch (_) {
      state = const CartState();
    }
  }

  Future<bool> add(String productId, int quantity, {String? variantId}) async {
    final ok = await _api.add(productId, quantity, variantId: variantId);
    if (ok) await refresh();
    return ok;
  }

  Future<void> setQty(String itemId, int quantity) async {
    // optimiste
    state = CartState(items: [
      for (final i in state.items)
        if (i.id == itemId)
          CartItem(id: i.id, productId: i.productId, name: i.name, imageUrl: i.imageUrl,
              unit: i.unit, variantName: i.variantName, quantity: quantity, moq: i.moq,
              unitPrice: i.unitPrice, oldPrice: i.oldPrice, deliveryDays: i.deliveryDays, supplier: i.supplier)
        else i,
    ]);
    try { await _api.updateQty(itemId, quantity); } catch (_) { await refresh(); }
  }

  Future<void> remove(String itemId) async {
    state = CartState(items: state.items.where((i) => i.id != itemId).toList());
    try { await _api.remove(itemId); } catch (_) { await refresh(); }
  }

  Future<void> clear() async {
    state = const CartState();
    try { await _api.clear(); } catch (_) { await refresh(); }
  }
}

final cartProvider = NotifierProvider<CartNotifier, CartState>(CartNotifier.new);