import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/api/account_api.dart';
import '../../data/api/products_api.dart';
import '../../data/models/product.dart';
import '../../state/cart_provider.dart';
import '../../widgets/product_card.dart';

const _orange = Color(0xFFFF7A00);
const _ink = Color(0xFF0F1419);
const _mute = Color(0xFF6B7785);
const _faint = Color(0xFF9AA3AE);
const _line = Color(0xFFECEEF1);
const _green = Color(0xFF0F9D58);
const _danger = Color(0xFFDC2626);
const _bg = Color(0xFFF4F5F7);

String _fmt(num n) => (n).toStringAsFixed(2).replaceAll('.', ',');

class FavorisScreen extends ConsumerStatefulWidget {
  const FavorisScreen({super.key});
  @override
  ConsumerState<FavorisScreen> createState() => _FavorisScreenState();
}

class _FavorisScreenState extends ConsumerState<FavorisScreen> {
  List<Product>? _list; // favoris
  List<Product>? _reco;
  bool _editing = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final account = ref.read(accountApiProvider);
    final products = ref.read(productsApiProvider);
    account.favorites().then((d) { if (mounted) setState(() => _list = d); })
        .catchError((_) { if (mounted) setState(() => _list = <Product>[]); });
    products.recommended().then((d) { if (mounted) setState(() => _reco = d); })
        .catchError((_) { if (mounted) setState(() => _reco = <Product>[]); });
  }

  Future<void> _removeOne(String id) async {
    setState(() {
      _list = (_list ?? const []).where((p) => p.id != id).toList();
      _selected.remove(id);
    });
    try {
      await ref.read(productsApiProvider).removeFavorite(id);
    } catch (_) {/* optimiste : on garde le retrait local */}
  }

  Future<void> _removeSelected() async {
    final ids = _selected.toList();
    for (final id in ids) {
      await _removeOne(id);
    }
    if (mounted) setState(() { _selected.clear(); _editing = false; });
  }

  void _toggleSel(String id) => setState(() {
        _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
      });

  bool get _allSelected => (_list?.isNotEmpty ?? false) && _selected.length == _list!.length;
  void _toggleAll() => setState(() {
        if (_allSelected) {
          _selected.clear();
        } else {
          _selected
            ..clear()
            ..addAll(_list!.map((p) => p.id));
        }
      });
  void _toggleEdit() => setState(() { _editing = !_editing; _selected.clear(); });

  @override
  Widget build(BuildContext context) {
    final loading = _list == null;
    final list = _list ?? const <Product>[];
    final reco = (_reco ?? const <Product>[]).take(10).toList();
    final isEmpty = !loading && list.isEmpty;
    final showList = !loading && list.isNotEmpty;
    final cartCount = ref.watch(cartProvider).count;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── En-tête ──
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: _ink),
                  onPressed: () => context.canPop() ? context.pop() : context.go('/dashboard'),
                ),
                Expanded(child: Text('Favoris', style: AppTheme.body(size: 21, weight: FontWeight.w700, color: _ink))),
                _cartButton(cartCount),
                IconButton(
                  icon: Icon(Icons.checklist, color: _editing ? _orange : _ink),
                  onPressed: () => _toggleEdit(),
                ),
              ]),
            ),

            // ── Onglet ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Align(alignment: Alignment.centerLeft, child: _tab(list.length)),
            ),

            // ── Contenu ──
            Expanded(
              child: loading
                  ? const _Skeleton()
                  : isEmpty
                      ? const _EmptyState()
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          children: [
                            for (final p in list)
                              _FavRow(
                                p: p,
                                editing: _editing,
                                selected: _selected.contains(p.id),
                                onToggleSel: () => _toggleSel(p.id),
                              ),
                            if (reco.isNotEmpty) _RecoSection(items: reco),
                          ],
                        ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: (_editing && showList)
          ? _EditBar(
              allSelected: _allSelected,
              count: _selected.length,
              onToggleAll: _toggleAll,
              onRemove: _removeSelected,
            )
          : null,
    );
  }

  Widget _cartButton(int count) => GestureDetector(
        onTap: () => context.go('/panier'),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Stack(clipBehavior: Clip.none, children: [
            const Icon(Icons.shopping_cart_outlined, color: _ink, size: 22),
            if (count > 0)
              Positioned(top: -6, right: -8, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                constraints: const BoxConstraints(minWidth: 16), height: 16,
                decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(20)),
                alignment: Alignment.center,
                child: Text(count > 99 ? '99+' : '$count',
                    style: AppTheme.body(size: 10, weight: FontWeight.w800, color: Colors.white)),
              )),
          ]),
        ),
      );

  Widget _tab(int count) => IntrinsicWidth(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Tous les articles ($count)',
                style: AppTheme.body(size: 17, weight: FontWeight.w700, color: _ink)),
          ),
          Container(height: 3, decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(2))),
        ]),
      );
}

/// Ligne favori (mobile) : image · nom · prix · Ajouter au panier + recherche visuelle.
class _FavRow extends ConsumerStatefulWidget {
  final Product p;
  final bool editing;
  final bool selected;
  final VoidCallback onToggleSel;
  const _FavRow({
    required this.p,
    required this.editing,
    required this.selected,
    required this.onToggleSel,
  });
  @override
  ConsumerState<_FavRow> createState() => _FavRowState();
}

class _FavRowState extends ConsumerState<_FavRow> {
  bool _busy = false;
  bool _done = false;
  bool _searching = false;

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _add() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await ref.read(cartProvider.notifier).add(widget.p.id, widget.p.moq ?? 1);
      if (ok && mounted) {
        setState(() => _done = true);
        Future.delayed(const Duration(milliseconds: 1500), () { if (mounted) setState(() => _done = false); });
      }
    } catch (_) {
      if (mounted) _snack("Impossible d'ajouter au panier.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Recherche visuelle à partir de la photo du produit : on récupère le
  /// fichier depuis le cache de CachedNetworkImage (déjà téléchargé puisque
  /// l'image est affichée) et on ouvre /visual-search comme la barre de recherche.
  Future<void> _visualSearch() async {
    if (_searching) return;
    final url = widget.p.primaryImage;
    if (url == null || url.isEmpty) {
      _snack("Ce produit n'a pas d'image.");
      return;
    }
    setState(() => _searching = true);
    try {
      final file = await DefaultCacheManager().getSingleFile(url);
      if (!mounted) return;
      context.push('/visual-search', extra: file.path);
    } catch (_) {
      if (mounted) _snack("Impossible de charger l'image.");
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final old = (p.oldPrice != null && p.oldPrice! > p.basePrice) ? _fmt(p.oldPrice!) : null;

    return GestureDetector(
      onTap: widget.editing ? widget.onToggleSel : () => context.push('/produit/${p.id}'),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.editing) Padding(
            padding: const EdgeInsets.only(right: 12, top: 50),
            child: _Checkbox(checked: widget.selected),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(width: 116, height: 116,
              child: (p.primaryImage != null && p.primaryImage!.isNotEmpty)
                  ? CachedNetworkImage(imageUrl: p.primaryImage!, fit: BoxFit.cover,
                      placeholder: (_, __) => const ColoredBox(color: _bg),
                      errorWidget: (_, __, ___) => const ColoredBox(color: _bg,
                          child: Icon(Icons.inventory_2_outlined, color: _faint)))
                  : const ColoredBox(color: _bg,
                      child: Icon(Icons.inventory_2_outlined, color: _faint))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: AppTheme.body(size: 15, color: _ink).copyWith(height: 1.35)),
            const SizedBox(height: 10),
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 7, children: [
              Text('TND ${_fmt(p.basePrice)}', style: AppTheme.body(size: 17, weight: FontWeight.w800, color: _ink)),
              if (old != null) Text('TND $old',
                  style: AppTheme.body(size: 12.5, color: _faint).copyWith(decoration: TextDecoration.lineThrough)),
            ]),
            if (!widget.editing) Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(children: [
                Expanded(child: GestureDetector(
                  onTap: _add,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 40, alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _done ? _green : _orange, borderRadius: BorderRadius.circular(999)),
                    child: Opacity(opacity: _busy ? 0.7 : 1, child: Text(
                      _busy ? 'Ajout…' : (_done ? '✓ Ajouté' : 'Ajouter au panier'),
                      style: AppTheme.body(size: 13, weight: FontWeight.w700, color: Colors.white))),
                  ),
                )),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _visualSearch,
                  child: Container(
                    width: 40, height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
                        border: Border.all(color: _line)),
                    child: _searching
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _orange))
                        : const Icon(Icons.image_search, size: 18, color: _ink),
                  ),
                ),
              ]),
            ),
          ])),
        ]),
      ),
    );
  }
}

class _Checkbox extends StatelessWidget {
  final bool checked;
  const _Checkbox({required this.checked});
  @override
  Widget build(BuildContext context) => Container(
        width: 22, height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: checked ? _orange : Colors.white,
          border: Border.all(color: checked ? _orange : const Color(0xFFCBD2D9), width: 2),
        ),
        child: checked ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
      );
}

class _EditBar extends StatelessWidget {
  final bool allSelected;
  final int count;
  final VoidCallback onToggleAll;
  final VoidCallback onRemove;
  const _EditBar({required this.allSelected, required this.count, required this.onToggleAll, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white,
          border: Border(top: BorderSide(color: _line)),
          boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, -4))]),
      child: SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(children: [
          GestureDetector(
            onTap: onToggleAll,
            behavior: HitTestBehavior.opaque,
            child: Row(children: [
              _Checkbox(checked: allSelected),
              const SizedBox(width: 8),
              Text('Tout', style: AppTheme.body(size: 14, color: _ink)),
            ]),
          ),
          const Spacer(),
          GestureDetector(
            onTap: count > 0 ? onRemove : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
              decoration: BoxDecoration(
                color: count > 0 ? _danger : const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(999)),
              child: Text(count > 0 ? 'Retirer ($count)' : 'Retirer',
                  style: AppTheme.body(size: 15, weight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ]),
      )),
    );
  }
}

class _RecoSection extends StatelessWidget {
  final List<Product> items;
  const _RecoSection({required this.items});

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
        Text('Recommandés pour vous', style: AppTheme.body(size: 17, weight: FontWeight.w700, color: _ink)),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 22),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _line)),
            child: Column(children: [
              const Icon(Icons.inventory_2_outlined, size: 40, color: _faint),
              const SizedBox(height: 12),
              Text('Aucun produit en favori.', style: AppTheme.body(size: 15, color: _mute)),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => context.go('/'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 11),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: _ink)),
                  child: Text('Explorer des produits',
                      style: AppTheme.body(size: 13.5, weight: FontWeight.w700, color: _ink)),
                ),
              ),
            ]),
          ),
        ],
      );
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) {
    Widget box(double w, double h, [double r = 4]) => Container(
          width: w, height: h,
          decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(r)),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: List.generate(4, (_) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          box(116, 116, 10),
          const SizedBox(width: 12),
          Expanded(child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              box(double.infinity, 12),
              const SizedBox(height: 10),
              box(160, 12),
              const SizedBox(height: 18),
              box(120, 18),
            ]),
          )),
        ]),
      )),
    );
  }
}