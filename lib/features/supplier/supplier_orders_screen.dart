import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
const _pinkSoft = Color(0xFFFFE8EA);
const _green = Color(0xFF1FB57A);
const _greenSoft = Color(0xFFE2F8EE);
const _violet = Color(0xFF8B5CF6);
const _violetSoft = Color(0xFFF0EAFF);
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

const _statusLabel = {
  'pending': 'En attente',
  'confirmed': 'Confirmée',
  'in_production': 'En production',
  'shipped': 'Expédiée',
  'delivered': 'Livrée',
  'cancelled': 'Annulée',
};
const _statusStyle = <String, (Color, Color)>{
  'pending': (_pinkSoft, _pink),
  'confirmed': (_blueSoft, _blue),
  'in_production': (_blueSoft, _blue),
  'shipped': (_violetSoft, _violet),
  'delivered': (_greenSoft, _green),
  'cancelled': (_tile, _mute),
};
const _statusOrder = ['pending', 'confirmed', 'in_production', 'shipped', 'delivered', 'cancelled'];

const _tabs = [
  ('all', 'Toutes'),
  ('pending', 'En attente'),
  ('confirmed', 'Confirmées'),
  ('in_production', 'Production'),
  ('shipped', 'Expédiées'),
  ('delivered', 'Livrées'),
  ('cancelled', 'Annulées'),
];

class SupplierOrdersScreen extends ConsumerStatefulWidget {
  const SupplierOrdersScreen({super.key});

  @override
  ConsumerState<SupplierOrdersScreen> createState() => _SupplierOrdersScreenState();
}

class _SupplierOrdersScreenState extends ConsumerState<SupplierOrdersScreen> {
  String _tab = 'all';

  String _ago(DateTime? d) {
    if (d == null) return '';
    final s = DateTime.now().difference(d).inSeconds;
    if (s < 3600) return '${(s / 60).round().clamp(1, 999)} min';
    if (s < 86400) return '${(s / 3600).round()} h';
    final j = (s / 86400).round();
    return j < 30 ? '$j j' : '${d.day}/${d.month}';
  }

  String _shortId(SubOrder o) =>
      '#${o.id.length > 8 ? o.id.substring(0, 8).toUpperCase() : o.id.toUpperCase()}';

  Future<void> _refresh() async {
    ref.invalidate(supplierOrdersProvider);
    try {
      await ref.read(supplierOrdersProvider.future);
    } catch (_) {}
  }

  Future<void> _changeStatus(SubOrder o, String status) async {
    try {
      await ref.read(supplierApiProvider).updateOrderStatus(o.id, status);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isNetworkError(e)
                ? 'Pas de connexion Internet. Statut non modifié.'
                : 'Échec du changement de statut.'),
          ),
        );
      }
    }
    ref.invalidate(supplierOrdersProvider);
  }

  void _openStatusSheet(SubOrder o) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: _grid, borderRadius: BorderRadius.circular(3)),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Changer le statut',
                        style: AppTheme.body(size: 17, weight: FontWeight.w700, color: _ink)),
                    const SizedBox(height: 3),
                    Text('${o.buyerName ?? 'Client'} · ${_shortId(o)}',
                        style: AppTheme.body(size: 12, color: _mute)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              for (final st in _statusOrder)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _StatusOption(
                    label: _statusLabel[st] ?? st,
                    style: _statusStyle[st]!,
                    selected: st == o.status,
                    onTap: () {
                      Navigator.pop(ctx);
                      if (st != o.status) _changeStatus(o, st);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(supplierOrdersProvider);
    final all = async.valueOrNull ?? const <SubOrder>[];
    final netErr = async.hasError && isNetworkError(async.error);

    // Pas de réseau et rien de chargé → écran « Pas de connexion ».
    if (netErr && !async.hasValue && !async.isLoading) {
      return ColoredBox(
        color: _bg,
        child: NoConnectionView(onRetry: () => ref.invalidate(supplierOrdersProvider)),
      );
    }

    final counts = <String, int>{'all': all.length};
    for (final o in all) {
      counts[o.status] = (counts[o.status] ?? 0) + 1;
    }

    final filtered = all.where((o) => _tab == 'all' || o.status == _tab).toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));

    final ca = all.where((o) => o.status != 'cancelled').fold(0.0, (s, o) => s + o.subtotalTnd);

    return ColoredBox(
      color: _bg,
      child: RefreshIndicator(
        color: _orange,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
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
            Text('Commandes', style: AppTheme.body(size: 26, weight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 3),
            Text(
              '${_fmt(all.length)} commande${all.length > 1 ? 's' : ''} · suivi en temps réel',
              style: AppTheme.body(size: 12, color: _mute),
            ),
            const SizedBox(height: 16),

            // KPI 2×2
            _KpiGrid(
              total: all.length,
              ca: ca,
              pending: counts['pending'] ?? 0,
              shipped: counts['shipped'] ?? 0,
              loading: async.isLoading && !async.hasValue,
              active: _tab,
              onTap: (key) => setState(() => _tab = key),
            ),
            const SizedBox(height: 18),

            // Onglets soulignés
            _UnderlineTabs(
              active: _tab,
              counts: counts,
              onChange: (key) => setState(() => _tab = key),
            ),
            const SizedBox(height: 16),

            // Liste
            if (async.isLoading && all.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator(color: _orange)),
              )
            else if (async.hasError && !async.hasValue)
              _stateBox(Icons.error_outline_rounded, 'Une erreur est survenue',
                  'Tire vers le bas pour réessayer.')
            else if (filtered.isEmpty)
              _stateBox(
                Icons.search_off_rounded,
                all.isEmpty ? 'Aucune commande' : 'Aucune commande ici',
                all.isEmpty ? 'Tes commandes clients apparaîtront ici.' : 'Aucune commande avec ce statut.',
              )
            else
              ...filtered.map(_orderCard),
          ],
        ),
      ),
    );
  }

  Widget _orderCard(SubOrder o) {
    final first = o.items.isNotEmpty ? o.items.first.productName : '—';
    final label = o.itemsCount > 1 ? '$first +${o.itemsCount - 1}' : first;
    final st = _statusStyle[o.status] ?? _statusStyle['pending']!;
    const placeholder = Icon(Icons.inventory_2_outlined, size: 26, color: _faint);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => _openStatusSheet(o),
          child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: _shadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(18)),
                  child: (o.primaryImage != null && o.primaryImage!.isNotEmpty)
                      ? Image.network(
                          o.primaryImage!,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(child: placeholder),
                        )
                      : const Center(child: placeholder),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.body(size: 14, weight: FontWeight.w700, color: _ink)),
                          ),
                          const Icon(Icons.more_vert_rounded, size: 18, color: _faint),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Prix : ${o.subtotalTnd.toStringAsFixed(3)} TND · ${o.itemsCount} article${o.itemsCount > 1 ? 's' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(size: 12, color: _mute),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_shortId(o)} · ${o.buyerName ?? 'Client'} · ${_ago(o.createdAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(size: 11, color: _faint),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(color: st.$1, borderRadius: BorderRadius.circular(999)),
                            child: Text(_statusLabel[o.status] ?? o.status,
                                style: AppTheme.body(size: 10.5, weight: FontWeight.w600, color: st.$2)),
                          ),
                          if (o.paymentMethod != null) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.credit_card_rounded, size: 12, color: _faint),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(o.paymentMethod!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.body(size: 10.5, color: _faint)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stateBox(IconData icon, String title, String sub) => Padding(
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
          ],
        ),
      );
}

// ═══════ KPI 2×2 pastel (sans overflow) ═══════
class _KpiGrid extends StatelessWidget {
  final int total;
  final double ca;
  final int pending;
  final int shipped;
  final bool loading;
  final String active;
  final ValueChanged<String> onTap;
  const _KpiGrid({
    required this.total,
    required this.ca,
    required this.pending,
    required this.shipped,
    required this.loading,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _KpiTile(
                  label: 'Commandes',
                  value: _fmt(total),
                  sub: 'reçues',
                  icon: Icons.shopping_cart_outlined,
                  fg: _orange,
                  bg: _orangeSoft,
                  loading: loading,
                  selected: active == 'all',
                  onTap: () => onTap('all'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiTile(
                  label: 'CA total',
                  value: _fmt(ca),
                  sub: 'TND',
                  icon: Icons.payments_outlined,
                  fg: _green,
                  bg: _greenSoft,
                  loading: loading,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _KpiTile(
                  label: 'En attente',
                  value: _fmt(pending),
                  sub: 'à traiter',
                  icon: Icons.schedule_rounded,
                  fg: _blue,
                  bg: _blueSoft,
                  loading: loading,
                  selected: active == 'pending',
                  onTap: () => onTap('pending'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiTile(
                  label: 'Expédiées',
                  value: _fmt(shipped),
                  sub: 'en route',
                  icon: Icons.local_shipping_outlined,
                  fg: _violet,
                  bg: _violetSoft,
                  loading: loading,
                  selected: active == 'shipped',
                  onTap: () => onTap('shipped'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
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
              // FittedBox : un grand chiffre (ex. CA) rétrécit au lieu de déborder.
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
        itemCount: _tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 20),
        itemBuilder: (_, i) {
          final (key, label) = _tabs[i];
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

// ═══════ Option du bottom sheet de statut ═══════
class _StatusOption extends StatelessWidget {
  final String label;
  final (Color, Color) style;
  final bool selected;
  final VoidCallback onTap;
  const _StatusOption({
    required this.label,
    required this.style,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? style.$1 : _bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: style.$2, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: AppTheme.body(
                      size: 14,
                      weight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? style.$2 : _ink)),
            ),
            if (selected) Icon(Icons.check_rounded, size: 18, color: style.$2),
          ],
        ),
      ),
    );
  }
}