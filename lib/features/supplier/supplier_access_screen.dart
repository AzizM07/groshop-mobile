import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/api/network_error.dart';
import '../../data/api/supplier_access_reviews_api.dart';
import '../../widgets/no_connection_view.dart';

// ═══════ Palette (identique au dashboard) ═══════
const _orange = Color(0xFFFF8A00);
const _orangeSoft = Color(0xFFFFEEDB);
const _blue = Color(0xFF4F7CFF);
const _blueSoft = Color(0xFFE8EEFF);
const _pink = Color(0xFFF25C6E);
const _pinkSoft = Color(0xFFFFE8EA);
const _green = Color(0xFF1FB57A);
const _violet = Color(0xFF8B5CF6);
const _violetSoft = Color(0xFFF0EAFF);
const _amber = Color(0xFFD97706);
const _bg = Color(0xFFFAFAFB);
const _ink = Color(0xFF1E1E2D);
const _mute = Color(0xFF8A8A99);
const _faint = Color(0xFFB5B5C3);
const _grid = Color(0xFFE9E9EF);

const _shadow = <BoxShadow>[
  BoxShadow(color: Color(0x0F1B1B3A), blurRadius: 24, offset: Offset(0, 8)),
];

const _months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
String _date(DateTime? d) => d == null ? '—' : '${d.day} ${_months[d.month - 1]} ${d.year}';

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2);
  final s = parts.map((w) => w[0].toUpperCase()).join();
  return s.isEmpty ? '?' : s;
}

({String label, Color color, bool urgent}) _expiry(DateTime? exp) {
  if (exp == null) return (label: 'Permanent', color: _green, urgent: false);
  final diff = exp.difference(DateTime.now());
  if (diff.isNegative) return (label: 'Expiré', color: _pink, urgent: true);
  final days = (diff.inHours / 24).ceil();
  if (days <= 7) return (label: 'Expire dans $days j', color: _amber, urgent: true);
  return (label: 'Expire le ${_date(exp)}', color: _mute, urgent: false);
}

class SupplierAccessScreen extends ConsumerStatefulWidget {
  const SupplierAccessScreen({super.key});

  @override
  ConsumerState<SupplierAccessScreen> createState() => _SupplierAccessScreenState();
}

class _SupplierAccessScreenState extends ConsumerState<SupplierAccessScreen> {
  String _filter = 'all'; // all | supplier | product
  String? _revoking;

  Future<void> _refresh() async {
    ref.invalidate(supplierUnlocksProvider);
    try {
      await ref.read(supplierUnlocksProvider.future);
    } catch (_) {}
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/supplier/settings');
    }
  }

  Future<void> _confirmRevoke(PriceUnlock u) async {
    final name = u.userName.isEmpty ? 'ce client' : u.userName;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(color: _grid, borderRadius: BorderRadius.circular(3)),
              ),
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(color: _pinkSoft, shape: BoxShape.circle),
                child: const Icon(Icons.lock_outline_rounded, size: 26, color: _pink),
              ),
              const SizedBox(height: 14),
              Text("Révoquer l'accès ?", style: AppTheme.body(size: 17, weight: FontWeight.w800, color: _ink)),
              const SizedBox(height: 6),
              Text(
                u.scope == 'supplier'
                    ? '$name ne verra plus les prix masqués de votre catalogue.'
                    : '$name ne verra plus le prix de « ${u.productName.isEmpty ? 'ce produit' : u.productName} ».',
                textAlign: TextAlign.center,
                style: AppTheme.body(size: 13, color: _mute).copyWith(height: 1.45),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _sheetBtn('Annuler', _orangeSoft, _orange, () => Navigator.pop(ctx, false)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _sheetBtn('Révoquer', _pink, Colors.white, () => Navigator.pop(ctx, true)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _revoking = u.id);
    try {
      await ref.read(supplierAccessReviewsApiProvider).revoke(u);
      ref.invalidate(supplierUnlocksProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Accès révoqué.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isNetworkError(e) ? 'Pas de connexion Internet. Réessayez.' : 'Échec de la révocation.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _revoking = null);
    }
  }

  Widget _sheetBtn(String t, Color bg, Color fg, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 50,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
          child: Center(child: Text(t, style: AppTheme.body(size: 14.5, weight: FontWeight.w700, color: fg))),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(supplierUnlocksProvider);
    final rows = async.valueOrNull ?? const <PriceUnlock>[];
    final netErr = async.hasError && isNetworkError(async.error);
    final loading = async.isLoading && !async.hasValue;

    final nSupplier = rows.where((r) => r.scope == 'supplier').length;
    final nProduct = rows.where((r) => r.scope == 'product').length;
    final nExpiring = rows.where((r) {
      final e = r.expiresAt;
      if (e == null) return false;
      final h = e.difference(DateTime.now()).inHours;
      return h > 0 && h <= 7 * 24;
    }).length;
    final filtered = rows.where((r) => _filter == 'all' || r.scope == _filter).toList();

    Widget body;
    if (netErr && !async.hasValue && !async.isLoading) {
      body = NoConnectionView(onRetry: () => ref.invalidate(supplierUnlocksProvider));
    } else {
      body = RefreshIndicator(
        color: _orange,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (netErr && async.hasValue)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: OfflineBanner(onRetry: () => _refresh()),
                ),
              ),
            _kpiRow(
              _Kpi('Accès actifs', rows.length, Icons.lock_open_rounded, _orange, _orangeSoft, loading,
                  selected: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
              _Kpi('Catalogues', nSupplier, Icons.storefront_outlined, _violet, _violetSoft, loading,
                  selected: _filter == 'supplier', onTap: () => setState(() => _filter = 'supplier')),
            ),
            const SizedBox(height: 12),
            _kpiRow(
              _Kpi('Produits', nProduct, Icons.inventory_2_outlined, _blue, _blueSoft, loading,
                  selected: _filter == 'product', onTap: () => setState(() => _filter = 'product')),
              _Kpi('Expirent sous 7 j', nExpiring, Icons.schedule_rounded, _pink, _pinkSoft, loading),
            ),
            const SizedBox(height: 18),
            _tabs({'all': rows.length, 'supplier': nSupplier, 'product': nProduct}),
            const SizedBox(height: 14),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator(color: _orange)),
              )
            else if (async.hasError && !async.hasValue)
              _state(Icons.error_outline_rounded, 'Une erreur est survenue', 'Tire vers le bas pour réessayer.')
            else if (rows.isEmpty)
              _state(
                Icons.lock_open_rounded,
                "Aucun accès accordé pour l'instant",
                'Quand un client vous contacte pour un produit à prix masqué, vous pouvez lui débloquer les prix depuis la conversation. Les accès accordés apparaîtront ici.',
              )
            else if (filtered.isEmpty)
              _state(Icons.filter_alt_outlined, 'Aucun accès ici', 'Aucun accès dans cette catégorie.')
            else
              ...filtered.map(_card),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _back,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: _shadow),
                      child: const Icon(Icons.arrow_back_rounded, size: 20, color: _ink),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Accès accordés', style: AppTheme.body(size: 21, weight: FontWeight.w800, color: _ink)),
                        Text('Clients qui voient vos prix masqués',
                            style: AppTheme.body(size: 12, color: _mute)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  // ═══════ KPI ═══════
  Widget _kpiRow(_Kpi a, _Kpi b) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [Expanded(child: _kpi(a)), const SizedBox(width: 12), Expanded(child: _kpi(b))],
        ),
      );

  Widget _kpi(_Kpi k) => GestureDetector(
        onTap: k.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: k.bg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: k.selected ? k.fg : Colors.transparent, width: 1.5),
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
                    decoration: BoxDecoration(color: k.fg, shape: BoxShape.circle),
                    child: Icon(k.icon, size: 16, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(k.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(size: 12.5, weight: FontWeight.w600, color: _ink)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (k.loading)
                Container(
                  height: 28,
                  width: 50,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                )
              else
                Text('${k.value}', style: AppTheme.body(size: 26, weight: FontWeight.w800, color: _ink)),
            ],
          ),
        ),
      );

  // ═══════ Onglets soulignés ═══════
  Widget _tabs(Map<String, int> counts) {
    const tabs = [('all', 'Tous'), ('supplier', 'Catalogue'), ('product', 'Produit')];
    return Container(
      height: 38,
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _grid))),
      child: Row(
        children: [
          for (final (key, label) in tabs) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _filter = key),
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
                                weight: _filter == key ? FontWeight.w700 : FontWeight.w500,
                                color: _filter == key ? _orange : _faint)),
                        const SizedBox(width: 5),
                        Text('${counts[key] ?? 0}',
                            style: AppTheme.body(
                                size: 11, weight: FontWeight.w700, color: _filter == key ? _orange : _faint)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 3,
                      decoration: BoxDecoration(
                        color: _filter == key ? _orange : Colors.transparent,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 22),
          ],
        ],
      ),
    );
  }

  // ═══════ Carte d'accès ═══════
  Widget _card(PriceUnlock u) {
    final name = u.userName.isEmpty ? 'Client' : u.userName;
    final sub = [u.email, u.city].where((x) => x.isNotEmpty).join(' · ');
    final exp = _expiry(u.expiresAt);
    final busy = _revoking == u.id;
    final isCatalog = u.scope == 'supplier';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: _shadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(color: _orangeSoft, shape: BoxShape.circle),
                child: Center(
                  child: Text(_initials(name),
                      style: AppTheme.body(size: 13.5, weight: FontWeight.w800, color: _orange)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(size: 14, weight: FontWeight.w700, color: _ink)),
                    if (sub.isNotEmpty)
                      Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(size: 11.5, color: _mute)),
                  ],
                ),
              ),
            ],
          ),
          if (u.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 54),
              child: Text('« ${u.note} »',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(size: 11.5, color: _faint).copyWith(fontStyle: FontStyle.italic)),
            ),
          const SizedBox(height: 12),

          // Portée
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isCatalog ? _violetSoft : _orangeSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isCatalog ? Icons.storefront_outlined : Icons.inventory_2_outlined,
                        size: 13, color: isCatalog ? _violet : _orange),
                    const SizedBox(width: 5),
                    Text(isCatalog ? 'Catalogue entier' : 'Produit',
                        style: AppTheme.body(
                            size: 11.5, weight: FontWeight.w700, color: isCatalog ? _violet : _orange)),
                  ],
                ),
              ),
              if (!isCatalog && u.productName.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(u.productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(size: 11.5, color: _mute)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: _grid),
          const SizedBox(height: 10),

          // Dates + action
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Accordé le ${_date(u.createdAt)}', style: AppTheme.body(size: 11.5, color: _mute)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (exp.urgent) ...[
                          Icon(Icons.error_outline_rounded, size: 13, color: exp.color),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(exp.label,
                              style: AppTheme.body(
                                  size: 12,
                                  weight: exp.urgent ? FontWeight.w700 : FontWeight.w500,
                                  color: exp.color)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: busy ? null : () => _confirmRevoke(u),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(color: _pinkSoft, borderRadius: BorderRadius.circular(12)),
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: _pink),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lock_outline_rounded, size: 14, color: _pink),
                            const SizedBox(width: 5),
                            Text('Révoquer',
                                style: AppTheme.body(size: 12.5, weight: FontWeight.w700, color: _pink)),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _state(IconData icon, String title, String sub) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(color: _orangeSoft, shape: BoxShape.circle),
              child: Icon(icon, size: 26, color: _orange),
            ),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: AppTheme.body(size: 15, weight: FontWeight.w700, color: _ink)),
            const SizedBox(height: 6),
            Text(sub,
                textAlign: TextAlign.center,
                style: AppTheme.body(size: 12.5, color: _mute).copyWith(height: 1.5)),
          ],
        ),
      );
}

class _Kpi {
  final String label;
  final int value;
  final IconData icon;
  final Color fg;
  final Color bg;
  final bool loading;
  final bool selected;
  final VoidCallback? onTap;
  const _Kpi(this.label, this.value, this.icon, this.fg, this.bg, this.loading, {this.selected = false, this.onTap});
}