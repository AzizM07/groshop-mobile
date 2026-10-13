import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/api/network_error.dart';
import '../../data/api/supplier_api.dart';
import '../../data/models/supplier_models.dart';
import '../../widgets/no_connection_view.dart';

// ═══════ Palette (identique au dashboard) ═══════
const _orange = Color(0xFFFF8A00);
const _orangeSoft = Color(0xFFFFEEDB);
const _blue = Color(0xFF4F7CFF);
const _blueSoft = Color(0xFFE8EEFF);
const _pink = Color(0xFFF25C6E);
const _green = Color(0xFF1FB57A);
const _greenSoft = Color(0xFFE2F8EE);
const _violet = Color(0xFF8B5CF6);
const _violetSoft = Color(0xFFF0EAFF);
const _red = Color(0xFFE5484D);
const _redSoft = Color(0xFFFFE4E4);
const _star = Color(0xFFFFB800);
const _bg = Color(0xFFFAFAFB);
const _ink = Color(0xFF1E1E2D);
const _mute = Color(0xFF8A8A99);
const _faint = Color(0xFFB5B5C3);
const _tile = Color(0xFFF4F4F6);
const _grid = Color(0xFFE9E9EF);

const _shadow = <BoxShadow>[
  BoxShadow(color: Color(0x0F1B1B3A), blurRadius: 24, offset: Offset(0, 8)),
];

String _fmt(num n) {
  final v = n.round();
  final s = v.abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

class _St {
  final String label;
  final Color color;
  final Color bg;
  final IconData icon;
  const _St(this.label, this.color, this.bg, this.icon);
}

const _statusStyles = {
  'draft': _St('Brouillon', _mute, _tile, Icons.edit_note_rounded),
  'pending_review': _St('En attente', _orange, _orangeSoft, Icons.schedule_rounded),
  'approved': _St('Approuvé', _green, _greenSoft, Icons.check_circle_rounded),
  'rejected': _St('Rejeté', _red, _redSoft, Icons.cancel_rounded),
};

const _filters = [
  ('all', 'Tous'),
  ('approved', 'Approuvés'),
  ('pending_review', 'En attente'),
  ('draft', 'Brouillons'),
  ('rejected', 'Rejetés'),
];

class SupplierProductsScreen extends ConsumerStatefulWidget {
  const SupplierProductsScreen({super.key});

  @override
  ConsumerState<SupplierProductsScreen> createState() => _SupplierProductsScreenState();
}

class _SupplierProductsScreenState extends ConsumerState<SupplierProductsScreen> {
  String _filter = 'all';

  Future<void> _refresh() async {
    ref.invalidate(supplierMyProductsProvider);
    try {
      await ref.read(supplierMyProductsProvider.future);
    } catch (_) {}
  }

  // Ajout / édition : l'écran formulaire invalide la liste après enregistrement.
  void _addProduct() => context.push('/supplier/products/new');

  void _openProduct(MyProduct p) {
    if (p.id.isEmpty) return;
    context.push('/supplier/products/${p.id}/edit');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(supplierMyProductsProvider);
    final items = async.valueOrNull ?? const <MyProduct>[];
    final netErr = async.hasError && isNetworkError(async.error);

    // Pas de réseau et rien de chargé → écran « Pas de connexion ».
    if (netErr && !async.hasValue && !async.isLoading) {
      return ColoredBox(
        color: _bg,
        child: NoConnectionView(onRetry: () => ref.invalidate(supplierMyProductsProvider)),
      );
    }

    final counts = <String, int>{'all': items.length};
    for (final p in items) {
      counts[p.status] = (counts[p.status] ?? 0) + 1;
    }

    final filtered = items.where((p) => _filter == 'all' || p.status == _filter).toList();

    final inStock = items.fold(0, (s, p) => s + p.stockQty);
    final sold = items.fold(0, (s, p) => s + p.soldCount);
    final loading = async.isLoading && !async.hasValue;

    return ColoredBox(
      color: _bg,
      child: Stack(
        children: [
          RefreshIndicator(
        color: _orange,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            if (netErr && async.hasValue)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: OfflineBanner(onRetry: () => _refresh()),
                ),
              ),

            // Titre
            Text('Produits', style: AppTheme.body(size: 26, weight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 3),
            Text(
              '${_fmt(items.length)} produit${items.length > 1 ? 's' : ''} dans votre catalogue',
              style: AppTheme.body(size: 12, color: _mute),
            ),
            const SizedBox(height: 16),

            // KPI 2×2
            _KpiRow(
              left: _KpiTile(
                label: 'Produits',
                value: _fmt(items.length),
                sub: 'au total',
                icon: Icons.inventory_2_outlined,
                fg: _orange,
                bg: _orangeSoft,
                loading: loading,
                selected: _filter == 'all',
                onTap: () => setState(() => _filter = 'all'),
              ),
              right: _KpiTile(
                label: 'Approuvés',
                value: _fmt(counts['approved'] ?? 0),
                sub: 'en ligne',
                icon: Icons.check_rounded,
                fg: _green,
                bg: _greenSoft,
                loading: loading,
                selected: _filter == 'approved',
                onTap: () => setState(() => _filter = 'approved'),
              ),
            ),
            const SizedBox(height: 12),
            _KpiRow(
              left: _KpiTile(
                label: 'Stock',
                value: _fmt(inStock),
                sub: 'unités',
                icon: Icons.warehouse_outlined,
                fg: _blue,
                bg: _blueSoft,
                loading: loading,
              ),
              right: _KpiTile(
                label: 'Ventes',
                value: _fmt(sold),
                sub: 'vendues',
                icon: Icons.sell_outlined,
                fg: _violet,
                bg: _violetSoft,
                loading: loading,
              ),
            ),
            const SizedBox(height: 18),

            // Onglets soulignés
            _UnderlineTabs(
              active: _filter,
              counts: counts,
              onChange: (key) => setState(() => _filter = key),
            ),
            const SizedBox(height: 16),

            // Grille produits
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator(color: _orange)),
              )
            else if (async.hasError && !async.hasValue)
              _stateBox(Icons.error_outline_rounded, 'Une erreur est survenue', 'Tire vers le bas pour réessayer.')
            else if (filtered.isEmpty)
              _stateBox(
                Icons.inventory_2_outlined,
                items.isEmpty ? 'Aucun produit' : 'Aucun produit ici',
                items.isEmpty ? 'Ajoute ton premier produit.' : 'Aucun produit avec ce statut.',
                action: items.isEmpty ? _addProduct : null,
              )
            else
              ..._gridRows(filtered),
          ],
        ),
      ),

          // Bouton flottant « Ajouter »
          Positioned(
            right: 16,
            bottom: 16,
            child: _AddFab(onTap: _addProduct),
          ),
        ],
      ),
    );
  }

  /// Grille 2 colonnes sans GridView (hauteur libre → pas d'overflow).
  List<Widget> _gridRows(List<MyProduct> list) {
    final rows = <Widget>[];
    for (var i = 0; i < list.length; i += 2) {
      final a = list[i];
      final b = i + 1 < list.length ? list[i + 1] : null;
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _ProductCard(product: a, onTap: () => _openProduct(a))),
              const SizedBox(width: 12),
              Expanded(
                child: b == null ? const SizedBox.shrink() : _ProductCard(product: b, onTap: () => _openProduct(b)),
              ),
            ],
          ),
        ),
      ));
    }
    return rows;
  }

  Widget _stateBox(IconData icon, String title, String sub, {VoidCallback? action}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(color: _orangeSoft, shape: BoxShape.circle),
              child: Icon(icon, size: 26, color: _orange),
            ),
            const SizedBox(height: 12),
            Text(title, style: AppTheme.body(size: 15, weight: FontWeight.w700, color: _ink)),
            const SizedBox(height: 4),
            Text(sub, textAlign: TextAlign.center, style: AppTheme.body(size: 12.5, color: _mute)),
            if (action != null) ...[
              const SizedBox(height: 18),
              GestureDetector(
                onTap: action,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                  decoration: BoxDecoration(
                    color: _orange,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [BoxShadow(color: Color(0x40FF8A00), blurRadius: 14, offset: Offset(0, 5))],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_rounded, size: 19, color: Colors.white),
                      const SizedBox(width: 6),
                      Text('Ajouter un produit',
                          style: AppTheme.body(size: 14, weight: FontWeight.w700, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      );
}

// ═══════ Bouton flottant « Ajouter » ═══════
class _AddFab extends StatelessWidget {
  final VoidCallback onTap;
  const _AddFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _orange,
      borderRadius: BorderRadius.circular(999),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [BoxShadow(color: Color(0x59FF8A00), blurRadius: 18, offset: Offset(0, 6))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, size: 21, color: Colors.white),
              const SizedBox(width: 6),
              Text('Ajouter', style: AppTheme.body(size: 14.5, weight: FontWeight.w700, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════ Carte produit (grille) ═══════
class _ProductCard extends StatelessWidget {
  final MyProduct product;
  final VoidCallback onTap;
  const _ProductCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = product;
    final st = _statusStyles[p.status] ?? _statusStyles['draft']!;
    const placeholder = Icon(Icons.inventory_2_outlined, size: 34, color: _faint);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: _shadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(16)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      (p.primaryImage != null && p.primaryImage!.isNotEmpty)
                          ? Image.network(
                              p.primaryImage!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(child: placeholder),
                            )
                          : const Center(child: placeholder),
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: st.bg, borderRadius: BorderRadius.circular(999)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(st.icon, size: 10, color: st.color),
                              const SizedBox(width: 4),
                              Text(st.label,
                                  style: AppTheme.body(size: 9.5, weight: FontWeight.w700, color: st.color)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(size: 13, weight: FontWeight.w700, color: _ink)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 13, color: _star),
                        const SizedBox(width: 3),
                        Text(p.ratingAvg.toStringAsFixed(1),
                            style: AppTheme.body(size: 11, weight: FontWeight.w600, color: _ink)),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text('(${p.ratingCount})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.body(size: 11, color: _faint)),
                        ),
                      ],
                    ),
                    if (p.categoryName != null) ...[
                      const SizedBox(height: 2),
                      Text(p.categoryName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(size: 10.5, color: _faint)),
                    ],
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text.rich(TextSpan(
                        text: p.basePriceTnd.toStringAsFixed(3),
                        style: AppTheme.body(size: 15, weight: FontWeight.w800, color: _orange),
                        children: [
                          TextSpan(
                            text: ' TND',
                            style: AppTheme.body(size: 10, weight: FontWeight.w500, color: _mute),
                          ),
                        ],
                      )),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      p.stockQty > 0 ? '${_fmt(p.stockQty)} en stock' : 'Épuisé',
                      style: AppTheme.body(
                        size: 10.5,
                        weight: p.stockQty > 0 ? FontWeight.w500 : FontWeight.w700,
                        color: p.stockQty > 0 ? _faint : _pink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════ Ligne de 2 KPI (hauteur égale, sans overflow) ═══════
class _KpiRow extends StatelessWidget {
  final Widget left;
  final Widget right;
  const _KpiRow({required this.left, required this.right});

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        ),
      );
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final IconData icon;
  final Color fg;
  final Color bg;
  final bool loading;
  final bool selected;
  final VoidCallback? onTap;
  const _KpiTile({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
    required this.fg,
    required this.bg,
    required this.loading,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: selected ? fg : Colors.transparent, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
                  child: Icon(icon, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(size: 12.5, weight: FontWeight.w600, color: _ink)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (loading)
              Container(
                height: 28,
                width: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
              )
            else
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(value, style: AppTheme.body(size: 26, weight: FontWeight.w800, color: _ink)),
                    const SizedBox(width: 5),
                    Text(sub, style: AppTheme.body(size: 11, weight: FontWeight.w500, color: _mute)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════ Onglets soulignés orange ═══════
class _UnderlineTabs extends StatelessWidget {
  final String active;
  final Map<String, int> counts;
  final ValueChanged<String> onChange;
  const _UnderlineTabs({required this.active, required this.counts, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _grid)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 20),
        itemBuilder: (_, i) {
          final (key, label) = _filters[i];
          final on = key == active;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChange(key),
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label,
                          style: AppTheme.body(
                              size: 13,
                              weight: on ? FontWeight.w700 : FontWeight.w500,
                              color: on ? _orange : _faint)),
                      const SizedBox(width: 5),
                      Text('${counts[key] ?? 0}',
                          style: AppTheme.body(
                              size: 11, weight: FontWeight.w700, color: on ? _orange : _faint)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 3,
                    decoration: BoxDecoration(
                      color: on ? _orange : Colors.transparent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}