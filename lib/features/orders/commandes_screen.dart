import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/api/orders_api.dart';
import '../../widgets/saved_list_kit.dart';

// ─────────────────────────── Helpers ───────────────────────────

const _blue = Color(0xFF1F8EFF);

/// Onglets : (id, libellé). `review` = commandes avec au moins un article à noter.
const _tabs = <(String, String)>[
  ('all', 'Tout'),
  ('pending', 'En attente'),
  ('in_production', 'En production'),
  ('shipped', 'Expédiées'),
  ('delivered', 'Livrées'),
  ('review', 'À évaluer'),
];

const _pendingStatuses = {'pending', 'confirmed', 'call_confirmed'};

String _statusLabel(String s) => switch (s) {
      'pending' => 'En attente',
      'confirmed' || 'call_confirmed' => 'Confirmée',
      'in_production' => 'En production',
      'shipped' => 'En cours de livraison',
      'delivered' => 'Livrée',
      'cancelled' => 'Annulée',
      _ => s,
    };

const _months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

DateTime? _parse(dynamic v) => DateTime.tryParse('${v ?? ''}')?.toLocal();

String _date(dynamic v) {
  final d = _parse(v);
  return d == null ? '' : '${d.day} ${_months[d.month - 1]} ${d.year}';
}

String _dateTime(dynamic v) {
  final d = _parse(v);
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${_date(v)}, ${two(d.hour)}:${two(d.minute)}';
}

double _num(dynamic v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);
int _int(dynamic v) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? 1);

String _ref(Json o) {
  final r = o['reference'];
  if (r != null && '$r'.isNotEmpty) return '$r'.toUpperCase();
  final id = '${o['id'] ?? ''}';
  return (id.length > 8 ? id.substring(0, 8) : id).toUpperCase();
}

List<Json> _items(dynamic v) =>
    v is List ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : const [];

class _Group {
  final String? name, slug, status;
  final List<Json> items;
  const _Group({this.name, this.slug, this.status, required this.items});
}

List<_Group> _groups(Json o) {
  final subs = o['sub_orders'];
  if (subs is List && subs.isNotEmpty) {
    return subs.whereType<Map>().map((s) => _Group(
          name: s['supplier_name'] as String?,
          slug: s['supplier_slug'] as String?,
          status: s['status'] as String?,
          items: _items(s['items']),
        )).toList();
  }
  final sup = o['supplier'];
  return [
    _Group(
      name: (sup is Map ? sup['name'] : o['supplier_name']) as String?,
      slug: (sup is Map ? sup['slug'] : o['supplier_slug']) as String?,
      status: o['status'] as String?,
      items: _items(o['items']),
    ),
  ];
}

// ─────────────────────────── Écran ───────────────────────────

class CommandesScreen extends ConsumerStatefulWidget {
  final String? initialTab;
  const CommandesScreen({super.key, this.initialTab});

  @override
  ConsumerState<CommandesScreen> createState() => _CommandesScreenState();
}

class _CommandesScreenState extends ConsumerState<CommandesScreen> {
  List<Json>? _orders;
  Map<String, Json> _reviewable = {}; // order_item_id → ligne to-review
  late String _tab;
  String _q = '';
  String? _busy;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tab = _tabs.any((t) => t.$1 == widget.initialTab) ? widget.initialTab! : 'all';
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(ordersApiProvider);
    try {
      final res = await Future.wait([
        api.list(),
        api.toReview().catchError((_) => <Json>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _orders = res[0];
        _reviewable = {for (final r in res[1]) '${r['order_item_id']}': r};
      });
    } catch (_) {
      if (mounted) setState(() => _orders = <Json>[]);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  bool _matches(Json o) {
    final s = '${o['status'] ?? ''}';
    final okTab = switch (_tab) {
      'all' => true,
      'pending' => _pendingStatuses.contains(s),
      'review' => _groups(o).any((g) => g.items.any((it) => _reviewable.containsKey('${it['id']}'))),
      _ => s == _tab,
    };
    if (!okTab) return false;
    if (_q.isEmpty) return true;
    final q = _q.toLowerCase();
    if (_ref(o).toLowerCase().contains(q)) return true;
    return _groups(o).any((g) =>
        (g.name ?? '').toLowerCase().contains(q) ||
        g.items.any((it) => '${it['product_name'] ?? ''}'.toLowerCase().contains(q)));
  }

  Future<void> _cancel(Json o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Annuler la commande ?'),
        content: Text('La commande ${_ref(o)} sera annulée.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Retour')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Annuler la commande', style: TextStyle(color: SavedColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final id = '${o['id']}';
    setState(() => _busy = id);
    try {
      await ref.read(ordersApiProvider).cancel(id);
      await _load();
      _snack('Commande annulée.');
    } catch (_) {
      _snack("Impossible d'annuler la commande.");
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _openTracker(Json o) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
        builder: (_) => _TrackerSheet(order: o),
      );

  // ─────────────── Build ───────────────

  @override
  Widget build(BuildContext context) {
    final loading = _orders == null;
    final list = (_orders ?? const <Json>[]).where(_matches).toList();

    return Scaffold(
      backgroundColor: SavedColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: Colors.white,
            child: Column(children: [
              _searchBar(),
              _tabBar(),
            ]),
          ),
          Expanded(
            child: RefreshIndicator(
              color: SavedColors.orange,
              onRefresh: _load,
              child: loading
                  ? const RowSkeleton(imageSize: 88)
                  : list.isEmpty
                      ? SavedEmpty(
                          icon: Icons.receipt_long_outlined,
                          message: _q.isNotEmpty ? 'Aucune commande ne correspond à « $_q ».' : 'Aucune commande dans cet onglet.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: list.length,
                          itemBuilder: (_, i) => _orderCard(list[i]),
                        ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _searchBar() => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 14, 4),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: SavedColors.ink),
            onPressed: () => context.canPop() ? context.pop() : context.go('/dashboard'),
          ),
          Expanded(
            child: Container(
              height: 42,
              padding: const EdgeInsets.only(left: 14, right: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: SavedColors.ink, width: 1.5),
              ),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: (v) => setState(() => _q = v.trim()),
                    textInputAction: TextInputAction.search,
                    style: AppTheme.body(size: 14, color: SavedColors.ink),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'N° de commande, produit…',
                      hintStyle: AppTheme.body(size: 14, color: SavedColors.faint),
                    ),
                  ),
                ),
                if (_q.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(() {
                      _search.clear();
                      _q = '';
                    }),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.close, size: 18, color: SavedColors.mute),
                    ),
                  ),
                Container(
                  width: 44, height: 32,
                  decoration: BoxDecoration(color: SavedColors.ink, borderRadius: BorderRadius.circular(999)),
                  child: const Icon(Icons.search, size: 19, color: Colors.white),
                ),
              ]),
            ),
          ),
        ]),
      );

  Widget _tabBar() => SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (final t in _tabs)
              GestureDetector(
                onTap: () => setState(() => _tab = t.$1),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(right: 22, top: 12),
                  child: IntrinsicWidth(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(t.$2,
                          style: AppTheme.body(
                            size: 15,
                            weight: _tab == t.$1 ? FontWeight.w700 : FontWeight.w400,
                            color: _tab == t.$1 ? SavedColors.ink : SavedColors.mute,
                          )),
                      const SizedBox(height: 8),
                      Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: _tab == t.$1 ? SavedColors.ink : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _orderCard(Json o) {
    final status = '${o['status'] ?? ''}';
    final groups = _groups(o);
    final ref = _ref(o);
    final count = groups.fold<int>(0, (a, g) => a + g.items.fold<int>(0, (b, it) => b + _int(it['quantity'])));
    final cancelled = status == 'cancelled';
    final canCancel = _pendingStatuses.contains(status) || status == 'in_production';
    final showTrackBox = !cancelled && status != 'delivered';
    final busy = _busy == '${o['id']}';

    return Container(
      margin: const EdgeInsets.only(top: 8),
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // En-tête : statut · date · réf.
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Expanded(
            child: Text(_statusLabel(status),
                style: AppTheme.body(size: 17, weight: FontWeight.w700,
                    color: cancelled ? SavedColors.faint : SavedColors.ink)),
          ),
          Text(_date(o['created_at']), style: AppTheme.body(size: 13, color: SavedColors.mute)),
        ]),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: ref));
            _snack('N° $ref copié.');
          },
          child: Text.rich(TextSpan(children: [
            TextSpan(text: 'N° $ref · ', style: AppTheme.body(size: 12, color: SavedColors.faint)),
            TextSpan(text: 'Copier', style: AppTheme.body(size: 12, color: _blue)),
          ])),
        ),
        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: SavedColors.line)),

        // Produits groupés par fournisseur
        if (groups.every((g) => g.items.isEmpty))
          Text('Commande $ref', style: AppTheme.body(size: 14, color: SavedColors.mute))
        else
          for (final g in groups) _groupBlock(g, status),

        if (showTrackBox) _trackBox(o, status),

        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: SavedColors.line)),

        // Total + actions
        Align(
          alignment: Alignment.centerRight,
          child: Text.rich(TextSpan(children: [
            TextSpan(
              text: 'Total pour $count article${count > 1 ? 's' : ''} : ',
              style: AppTheme.body(size: 14, weight: FontWeight.w600, color: SavedColors.ink),
            ),
            TextSpan(
              text: '${fmtTnd(_num(o['total_tnd']))} TND',
              style: AppTheme.body(size: 15, weight: FontWeight.w800, color: SavedColors.ink),
            ),
          ])),
        ),
        if (!cancelled) ...[
          const SizedBox(height: 12),
          Opacity(
            opacity: busy ? 0.5 : 1,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!cancelled) _btn('Suivre', onTap: () => _openTracker(o)),
                if (status == 'shipped')
                  _btn('Confirmer la réception',
                      fg: SavedColors.orange, border: SavedColors.orange,
                      onTap: () => showSoon(context, 'Confirmation de réception')),
                if (canCancel)
                  _btn('Annuler', fg: SavedColors.danger, border: SavedColors.danger,
                      onTap: busy ? null : () => _cancel(o)),
              ],
            ),
          ),
        ],
      ]),
    );
  }

  Widget _groupBlock(_Group g, String orderStatus) {
    final delivered = (g.status ?? orderStatus) == 'delivered';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (g.name != null && g.name!.isNotEmpty)
        GestureDetector(
          onTap: (g.slug ?? '').isNotEmpty ? () => context.push('/fournisseur/${g.slug}') : null,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              const Icon(Icons.storefront_outlined, size: 18, color: SavedColors.ink),
              const SizedBox(width: 6),
              Flexible(
                child: Text(g.name!, overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(size: 15.5, weight: FontWeight.w700, color: SavedColors.ink)),
              ),
              if ((g.slug ?? '').isNotEmpty) const Icon(Icons.chevron_right, size: 20, color: SavedColors.ink),
            ]),
          ),
        ),
      for (final it in g.items) _itemRow(it, delivered),
    ]);
  }

  Widget _itemRow(Json it, bool delivered) {
    final pid = it['product_id'];
    final removed = pid == null || '$pid'.isEmpty;
    final review = _reviewable['${it['id']}'];
    final qty = _int(it['quantity']);
    final unit = _num(it['unit_price_tnd']);
    final img = it['product_image'] as String?;
    final variant = it['variant'];
    const noImage = ColoredBox(color: SavedColors.bg, child: Icon(Icons.inventory_2_outlined, color: SavedColors.faint));

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GestureDetector(
          onTap: removed ? null : () => context.push('/produit/$pid'),
          behavior: HitTestBehavior.opaque,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 88, height: 88,
                child: (img != null && img.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: img, fit: BoxFit.cover,
                        placeholder: (_, __) => const ColoredBox(color: SavedColors.bg),
                        errorWidget: (_, __, ___) => noImage)
                    : noImage,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text('${it['product_name'] ?? 'Article'}', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(size: 14.5, color: removed ? SavedColors.faint : SavedColors.ink)),
                  ),
                  if (!removed) const Icon(Icons.chevron_right, size: 18, color: SavedColors.mute),
                ]),
                if (variant != null && '$variant'.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('$variant', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(size: 13, color: SavedColors.faint)),
                  ),
                if (removed)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Article supprimé', style: AppTheme.body(size: 12.5, color: SavedColors.danger)),
                  ),
                const SizedBox(height: 10),
                Row(children: [
                  Text('${fmtTnd(unit)} TND',
                      style: AppTheme.body(size: 15.5, weight: FontWeight.w800, color: SavedColors.ink)),
                  const Spacer(),
                  Text('x$qty', style: AppTheme.body(size: 14, weight: FontWeight.w600, color: SavedColors.ink)),
                ]),
              ]),
            ),
          ]),
        ),
        if (delivered && !removed)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
              if (review != null)
                _btn('Laisser un avis',
                    bg: SavedColors.orange, fg: Colors.white, border: SavedColors.orange,
                    onTap: () => showSoon(context, 'Avis')),
              if (review == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Text('✓ Avis laissé', style: AppTheme.body(size: 13, color: SavedColors.green)),
                ),
              _btn('Racheter', onTap: () => context.push('/produit/$pid')),
            ]),
          ),
      ]),
    );
  }

  Widget _trackBox(Json o, String status) {
    final carrier = o['carrier_name'];
    final tracking = o['tracking_number'];
    final sub = [
      if (carrier != null && '$carrier'.isNotEmpty) '$carrier',
      if (tracking != null && '$tracking'.isNotEmpty) '$tracking',
    ].join(' · ');
    final fallback = switch (status) {
      'shipped' => 'Votre colis est en route.',
      'in_production' => 'Le fournisseur prépare votre commande.',
      _ => 'En attente de confirmation du fournisseur.',
    };
    return GestureDetector(
      onTap: () => _openTracker(o),
      child: Container(
        margin: const EdgeInsets.only(top: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Icon(Icons.local_shipping_outlined, size: 22, color: SavedColors.ink),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Suivre la livraison', style: AppTheme.body(size: 14.5, color: SavedColors.ink)),
              const SizedBox(height: 3),
              Text(sub.isNotEmpty ? sub : fallback, style: AppTheme.body(size: 12.5, color: SavedColors.mute)),
            ]),
          ),
          const Icon(Icons.chevron_right, size: 20, color: SavedColors.ink),
        ]),
      ),
    );
  }

  Widget _btn(String label, {VoidCallback? onTap, Color fg = SavedColors.ink, Color border = SavedColors.ink, Color? bg}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            color: bg ?? Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border, width: 1.3),
          ),
          child: Text(label, style: AppTheme.body(size: 13.5, weight: FontWeight.w600, color: fg)),
        ),
      );
}

// ─────────────────────────── Suivi (bottom sheet) ───────────────────────────

class _TrackerSheet extends StatelessWidget {
  final Json order;
  const _TrackerSheet({required this.order});

  static const _steps = <(String, String, String)>[
    ('pending', 'Commande passée', 'created_at'),
    ('confirmed', 'Confirmée', 'confirmed_at'),
    ('in_production', 'En production', 'production_at'),
    ('shipped', 'Expédiée', 'shipped_at'),
    ('delivered', 'Livrée', 'delivered_at'),
  ];

  @override
  Widget build(BuildContext context) {
    var status = '${order['status'] ?? 'pending'}';
    if (status == 'call_confirmed') status = 'confirmed';
    final idx = _steps.indexWhere((s) => s.$1 == status).clamp(0, _steps.length - 1);
    final carrier = order['carrier_name'];
    final tracking = order['tracking_number'];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: SavedColors.line, borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 16),
          Text('Suivi de la commande', style: AppTheme.body(size: 17, weight: FontWeight.w700, color: SavedColors.ink)),
          const SizedBox(height: 4),
          Text('N° ${_ref(order)}', style: AppTheme.body(size: 12.5, color: SavedColors.faint)),
          const SizedBox(height: 18),
          for (var i = 0; i < _steps.length; i++)
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Column(children: [
                  _dot(done: i < idx, current: i == idx),
                  if (i < _steps.length - 1)
                    Expanded(child: Container(width: 2, color: i < idx ? _blue : SavedColors.line)),
                ]),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_steps[i].$2,
                          style: AppTheme.body(
                            size: 14.5,
                            weight: i <= idx ? FontWeight.w600 : FontWeight.w400,
                            color: i <= idx ? SavedColors.ink : SavedColors.faint,
                          )),
                      const SizedBox(height: 2),
                      Text(
                        _dateTime(order[_steps[i].$3]).isNotEmpty
                            ? _dateTime(order[_steps[i].$3])
                            : (i == idx ? 'En cours' : '—'),
                        style: AppTheme.body(size: 12, color: SavedColors.faint),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          if ((carrier != null && '$carrier'.isNotEmpty) || (tracking != null && '$tracking'.isNotEmpty))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(10)),
              child: Text.rich(TextSpan(style: AppTheme.body(size: 12.5, color: SavedColors.mute), children: [
                if (carrier != null && '$carrier'.isNotEmpty) ...[
                  const TextSpan(text: 'Transporteur '),
                  TextSpan(text: '$carrier', style: AppTheme.body(size: 12.5, weight: FontWeight.w600, color: SavedColors.ink)),
                ],
                if (tracking != null && '$tracking'.isNotEmpty) ...[
                  const TextSpan(text: '   ·   Suivi '),
                  TextSpan(text: '$tracking', style: AppTheme.body(size: 12.5, weight: FontWeight.w600, color: SavedColors.ink)),
                ],
              ])),
            ),
        ]),
      ),
    );
  }

  Widget _dot({required bool done, required bool current}) => Container(
        width: 20, height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? _blue : Colors.white,
          border: Border.all(color: (done || current) ? _blue : SavedColors.line, width: current ? 3 : 2),
        ),
        child: done ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
      );
}