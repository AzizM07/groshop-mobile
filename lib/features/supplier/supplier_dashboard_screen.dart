import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/api/network_error.dart';
import '../../data/api/supplier_api.dart';
import '../../data/models/supplier_models.dart';
import '../../widgets/no_connection_view.dart';

// ═══════ Palette « My Bazar Seller » ═══════
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

String _kShort(num v) =>
    v >= 1000 ? '${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}k' : _fmt(v);

const _monthNames = ['', 'jan', 'fév', 'mar', 'avr', 'mai', 'juin', 'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'];
const _dayLetters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

class SupplierDashboardScreen extends ConsumerWidget {
  const SupplierDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(supplierOrdersProvider);
    final statsAsync = ref.watch(supplierStatsProvider);
    final prodsAsync = ref.watch(supplierMyProductsProvider);
    final profile = ref.watch(supplierProfileProvider).valueOrNull;

    final orders = ordersAsync.valueOrNull ?? const <SubOrder>[];
    final stats = statsAsync.valueOrNull;
    final prods = prodsAsync.valueOrNull ?? const <MyProduct>[];
    final loading = ordersAsync.isLoading && !ordersAsync.hasValue;

    void invalidateAll() {
      ref.invalidate(supplierOrdersProvider);
      ref.invalidate(supplierStatsProvider);
      ref.invalidate(supplierMyProductsProvider);
    }

    Future<void> refresh() async {
      invalidateAll();
      try {
        await ref.read(supplierOrdersProvider.future);
      } catch (_) {}
    }

    // Pas de réseau et rien de chargé → écran « Pas de connexion ».
    final netErr = ordersAsync.hasError && isNetworkError(ordersAsync.error);
    if (netErr && !ordersAsync.hasValue && !ordersAsync.isLoading) {
      return ColoredBox(color: _bg, child: NoConnectionView(onRetry: invalidateAll));
    }

    return ColoredBox(
      color: _bg,
      child: RefreshIndicator(
        color: _orange,
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (netErr && ordersAsync.hasValue)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: OfflineBanner(onRetry: () => refresh()),
                ),
              ),
            _Header(profile: profile),
            const SizedBox(height: 20),
            _StatusTiles(orders: orders, prods: prods, loading: loading),
            const SizedBox(height: 20),
            _SalesCard(orders: orders, loading: loading),
            const SizedBox(height: 24),
            _TrendingProducts(stats: stats, loading: statsAsync.isLoading && !statsAsync.hasValue),
            const SizedBox(height: 20),
            _VisitorsCard(stats: stats, loading: statsAsync.isLoading && !statsAsync.hasValue),
            const SizedBox(height: 24),
            _RecentOrders(orders: orders, loading: loading),
          ],
        ),
      ),
    );
  }
}

// ═══════ Carte blanche ombrée ═══════
class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: _shadow,
        ),
        child: child,
      );
}

Widget _sectionTitle(String title, {String? trailing}) => Row(
      children: [
        Expanded(
          child: Text(title, style: AppTheme.body(size: 16, weight: FontWeight.w700, color: _ink)),
        ),
        if (trailing != null) Text(trailing, style: AppTheme.body(size: 11, color: _faint)),
      ],
    );

// ═══════ Header : avatar · nom · bouton stats ═══════
class _Header extends StatelessWidget {
  final SupplierProfileInfo? profile;
  const _Header({this.profile});

  @override
  Widget build(BuildContext context) {
    final name = profile?.companyName ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final logo = profile?.logoUrl;
    final fallback = Center(
      child: Text(initial, style: AppTheme.body(size: 18, weight: FontWeight.w800, color: _orange)),
    );

    return Row(
      children: [
                GestureDetector(
          onTap: () => context.push('/supplier/settings'),
          child: Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: _shadow,
            ),
            child: ClipOval(
              child: ColoredBox(
                color: _orangeSoft,
                child: (logo != null && logo.isNotEmpty)
                    ? Image.network(
                        logo,
                        width: 46,
                        height: 46,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => fallback,
                      )
                    : fallback,
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                name.isNotEmpty ? name : 'Espace fournisseur',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTheme.body(size: 17, weight: FontWeight.w700, color: _ink),
              ),
              const SizedBox(height: 2),
              Text('Tableau de bord', style: AppTheme.body(size: 11.5, color: _mute)),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => context.push('/supplier/stats'),
          child: Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: _shadow,
            ),
            child: const Icon(Icons.insights_rounded, size: 21, color: _ink),
          ),
        ),
      ],
    );
  }
}

// ═══════ Tuiles pastel (scroll horizontal) ═══════
class _StatusTiles extends StatelessWidget {
  final List<SubOrder> orders;
  final List<MyProduct> prods;
  final bool loading;
  const _StatusTiles({required this.orders, required this.prods, required this.loading});

  @override
  Widget build(BuildContext context) {
    int count(bool Function(SubOrder o) f) => orders.where(f).length;

    final tiles = [
      (label: 'Commandes', value: orders.length, icon: Icons.shopping_cart_outlined, fg: _orange, bg: _orangeSoft),
      (label: 'En attente', value: count((o) => o.status == 'pending'), icon: Icons.schedule_rounded, fg: _blue, bg: _blueSoft),
      (
        label: 'En cours',
        value: count((o) => o.status == 'confirmed' || o.status == 'in_production'),
        icon: Icons.autorenew_rounded,
        fg: _pink,
        bg: _pinkSoft,
      ),
      (label: 'Expédiées', value: count((o) => o.status == 'shipped'), icon: Icons.local_shipping_outlined, fg: _violet, bg: _violetSoft),
      (label: 'Livrées', value: count((o) => o.status == 'delivered'), icon: Icons.check_rounded, fg: _green, bg: _greenSoft),
      (
        label: 'Produits actifs',
        value: prods.where((p) => p.status == 'approved').length,
        icon: Icons.inventory_2_outlined,
        fg: _orange,
        bg: _orangeSoft,
      ),
    ];

    return SizedBox(
      height: 122,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final t = tiles[i];
          return Container(
            width: 140,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(22)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(color: t.fg, shape: BoxShape.circle),
                      child: Icon(t.icon, size: 16, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(t.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(size: 12.5, weight: FontWeight.w600, color: _ink)),
                    ),
                  ],
                ),
                const Spacer(),
                if (loading)
                  Container(
                    height: 30,
                    width: 54,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  )
                else
                  Text(_fmt(t.value), style: AppTheme.body(size: 32, weight: FontWeight.w800, color: _ink)),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ═══════ Statistiques des ventes — double courbe + tooltip ═══════
class _SalesCard extends StatefulWidget {
  final List<SubOrder> orders;
  final bool loading;
  const _SalesCard({required this.orders, required this.loading});

  @override
  State<_SalesCard> createState() => _SalesCardState();
}

class _SalesCardState extends State<_SalesCard> {
  static const _modes = {'week': 'Cette semaine', 'month': '6 mois', 'day': "Aujourd'hui"};
  String _mode = 'week';
  int? _sel;

  List<({String label, double amount, double count})> _buckets() {
    final now = DateTime.now();
    final paid = widget.orders.where((o) => o.status != 'cancelled' && o.createdAt != null).toList();

    ({double amount, double count}) between(DateTime a, DateTime b) {
      final inB = paid.where((o) => !o.createdAt!.isBefore(a) && o.createdAt!.isBefore(b));
      return (amount: inB.fold(0.0, (s, o) => s + o.subtotalTnd), count: inB.length.toDouble());
    }

    final out = <({String label, double amount, double count})>[];
    if (_mode == 'month') {
      for (var i = 5; i >= 0; i--) {
        final s = DateTime(now.year, now.month - i, 1);
        final e = DateTime(now.year, now.month - i + 1, 1);
        final r = between(s, e);
        out.add((label: _monthNames[s.month], amount: r.amount, count: r.count));
      }
    } else if (_mode == 'week') {
      for (var i = 6; i >= 0; i--) {
        final d = DateTime(now.year, now.month, now.day - i);
        final r = between(d, d.add(const Duration(days: 1)));
        out.add((label: _dayLetters[(d.weekday - 1) % 7], amount: r.amount, count: r.count));
      }
    } else {
      for (var i = 0; i < 6; i++) {
        final s = DateTime(now.year, now.month, now.day, i * 4);
        final r = between(s, s.add(const Duration(hours: 4)));
        out.add((label: '${(i * 4).toString().padLeft(2, '0')}h', amount: r.amount, count: r.count));
      }
    }
    return out;
  }

  Widget _legend(Color c, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: c, width: 3),
            ),
          ),
          const SizedBox(width: 6),
          Text(text, style: AppTheme.body(size: 11.5, color: _mute)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final data = _buckets();
    final amounts = data.map((d) => d.amount).toList();
    final counts = data.map((d) => d.count).toList();
    final totalAmount = amounts.fold(0.0, (s, v) => s + v);
    final totalCount = counts.fold(0.0, (s, v) => s + v);
    final hasData = amounts.any((v) => v > 0) || counts.any((v) => v > 0);
    final sel = math.min(math.max(_sel ?? data.length - 1, 0), data.length - 1);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Statistiques des ventes',
                        style: AppTheme.body(size: 15, weight: FontWeight.w700, color: _ink)),
                    const SizedBox(height: 3),
                    Text('${_fmt(totalAmount)} TND · ${_fmt(totalCount)} commandes',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(size: 11.5, color: _mute)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _ModePill(
                value: _mode,
                options: _modes,
                onChange: (v) => setState(() {
                  _mode = v;
                  _sel = null;
                }),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(children: [
            _legend(_orange, 'Montant'),
            const SizedBox(width: 18),
            _legend(_blue, 'Commandes'),
          ]),
          const SizedBox(height: 6),
          if (widget.loading)
            const SizedBox(height: 200, child: Center(child: CircularProgressIndicator(color: _orange)))
          else if (!hasData)
            const _EmptyMini(icon: Icons.show_chart, text: 'Aucune vente sur cette période.')
          else
            SizedBox(
              height: 210,
              child: LayoutBuilder(builder: (context, box) {
                void pick(double dx) {
                  final w = box.maxWidth - _StatsChartPainter.l - _StatsChartPainter.r;
                  final n = data.length;
                  final i = n == 1
                      ? 0
                      : math.min(math.max(((dx - _StatsChartPainter.l) / w * (n - 1)).round(), 0), n - 1);
                  if (i != _sel) setState(() => _sel = i);
                }

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => pick(d.localPosition.dx),
                  onHorizontalDragUpdate: (d) => pick(d.localPosition.dx),
                  child: CustomPaint(
                    size: Size(box.maxWidth, 210),
                    painter: _StatsChartPainter(
                      amounts: amounts,
                      counts: counts,
                      labels: data.map((d) => d.label).toList(),
                      selected: sel,
                    ),
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChange;
  const _ModePill({required this.value, required this.options, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: value,
      onSelected: onChange,
      color: Colors.white,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (_) => options.entries
          .map((e) => PopupMenuItem<String>(
                value: e.key,
                child: Text(e.value,
                    style: AppTheme.body(
                        size: 13,
                        weight: e.key == value ? FontWeight.w700 : FontWeight.w500,
                        color: e.key == value ? _orange : _ink)),
              ))
          .toList(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        decoration: BoxDecoration(
          color: _orange,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [BoxShadow(color: Color(0x40FF8A00), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(options[value] ?? '',
                style: AppTheme.body(size: 12, weight: FontWeight.w600, color: Colors.white)),
            const SizedBox(width: 4),
            const Icon(Icons.unfold_more_rounded, size: 16, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _StatsChartPainter extends CustomPainter {
  _StatsChartPainter({
    required this.amounts,
    required this.counts,
    required this.labels,
    required this.selected,
  });

  final List<double> amounts;
  final List<double> counts;
  final List<String> labels;
  final int selected;

  static const l = 36.0, r = 8.0, t = 38.0, b = 24.0;

  TextPainter _tp(String s, TextStyle style) =>
      TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();

  void _dash(Canvas c, Offset a, Offset z, Paint p, {double dash = 4, double gap = 4}) {
    final d = z - a;
    final len = d.distance;
    if (len == 0) return;
    final dir = d / len;
    var s = 0.0;
    while (s < len) {
      final e = math.min(s + dash, len);
      c.drawLine(a + dir * s, a + dir * e, p);
      s += dash + gap;
    }
  }

  Path _smooth(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    final n = pts.length;
    if (n == 1) return path..lineTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < n - 1; i++) {
      final p0 = pts[i == 0 ? 0 : i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = pts[i + 2 < n ? i + 2 : n - 1];
      final c1 = Offset(p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6);
      final c2 = Offset(p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6);
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = amounts.length;
    if (n == 0) return;
    final w = size.width - l - r;
    final h = size.height - t - b;

    final maxA = amounts.fold<double>(0, (m, v) => math.max(m, v));
    final maxC = counts.fold<double>(0, (m, v) => math.max(m, v));
    final topA = maxA <= 0 ? 1.0 : maxA * 1.15;
    final topC = maxC <= 0 ? 1.0 : maxC * 1.15;

    // Grille pointillée + axe Y
    final gridPaint = Paint()
      ..color = _grid
      ..strokeWidth = 1;
    final axisStyle = AppTheme.body(size: 9.5, color: _faint);
    for (var i = 0; i <= 4; i++) {
      final y = t + h * i / 4;
      _dash(canvas, Offset(l, y), Offset(l + w, y), gridPaint);
      final tp = _tp(_kShort(topA * (1 - i / 4)), axisStyle);
      tp.paint(canvas, Offset(l - 8 - tp.width, y - tp.height / 2));
    }

    double x(int i) => l + (n == 1 ? w / 2 : w * i / (n - 1));
    final pa = [for (var i = 0; i < n; i++) Offset(x(i), t + h - amounts[i] / topA * h)];
    final pc = [for (var i = 0; i < n; i++) Offset(x(i), t + h - counts[i] / topC * h)];

    // Axe X
    for (var i = 0; i < n; i++) {
      final tp = _tp(labels[i], axisStyle);
      tp.paint(canvas, Offset(x(i) - tp.width / 2, size.height - b + 8));
    }

    final s = math.min(math.max(selected, 0), n - 1);

    // Ligne verticale de sélection
    _dash(
      canvas,
      pa[s],
      Offset(pa[s].dx, t + h),
      Paint()
        ..color = _orange
        ..strokeWidth = 1.3,
      dash: 4,
      gap: 3,
    );

    // Courbes
    canvas.drawPath(
      _smooth(pc),
      Paint()
        ..color = _blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      _smooth(pa),
      Paint()
        ..color = _orange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );

    // Points sélectionnés
    canvas.drawCircle(pc[s], 4, Paint()..color = _blue);
    canvas.drawCircle(
      pc[s],
      4,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(pa[s], 6, Paint()..color = Colors.white);
    canvas.drawCircle(
      pa[s],
      6,
      Paint()
        ..color = _orange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Bulle tooltip
    final tp = _tp('${_fmt(amounts[s])} TND', AppTheme.body(size: 11, weight: FontWeight.w700, color: _ink));
    final rw = tp.width + 18;
    final rh = tp.height + 10;
    final rx = math.min(math.max(pa[s].dx - rw / 2, 0.0), math.max(size.width - rw, 0.0));
    final ry = math.max(pa[s].dy - rh - 12, 0.0);
    final rr = RRect.fromRectAndRadius(Rect.fromLTWH(rx, ry, rw, rh), const Radius.circular(10));
    canvas.drawShadow(Path()..addRRect(rr), const Color(0x33000000), 6, false);
    canvas.drawRRect(rr, Paint()..color = Colors.white);
    tp.paint(canvas, Offset(rx + 9, ry + 5));
  }

  @override
  bool shouldRepaint(covariant _StatsChartPainter old) => true;
}

// ═══════ Produits tendance (carrousel) ═══════
class _TrendingProducts extends StatelessWidget {
  final SupplierStats? stats;
  final bool loading;
  const _TrendingProducts({required this.stats, required this.loading});

  @override
  Widget build(BuildContext context) {
    final rows = (stats?.productViewsRanked ?? const <ProductViewRow>[]).take(10).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Produits tendance', trailing: '7 derniers jours'),
        const SizedBox(height: 12),
        if (loading)
          const SizedBox(height: 160, child: Center(child: CircularProgressIndicator(color: _orange)))
        else if (rows.isEmpty)
          const _Card(child: _EmptyMini(icon: Icons.visibility_outlined, text: 'Aucune vue produit.'))
        else
          SizedBox(
            height: 168,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final r = rows[i];
                return SizedBox(
                  width: 132,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 112,
                        width: double.infinity,
                        decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(18)),
                        child: Stack(
                          children: [
                            const Center(child: Icon(Icons.inventory_2_outlined, size: 34, color: _faint)),
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(999)),
                                child: Text('#${i + 1}',
                                    style: AppTheme.body(size: 10.5, weight: FontWeight.w700, color: Colors.white)),
                              ),
                            ),
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                                child: Text('${r.engagementPct}%',
                                    style: AppTheme.body(size: 10, weight: FontWeight.w700, color: _orange)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(r.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(size: 13, weight: FontWeight.w600, color: _ink)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.visibility_rounded, size: 13, color: _orange),
                          const SizedBox(width: 4),
                          Text(_fmt(r.views), style: AppTheme.body(size: 12, weight: FontWeight.w700, color: _ink)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text('(${_fmt(r.uniques)})',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.body(size: 11, color: _faint)),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

// ═══════ Visiteurs — barres 7 jours ═══════
class _VisitorsCard extends StatelessWidget {
  final SupplierStats? stats;
  final bool loading;
  const _VisitorsCard({required this.stats, required this.loading});

  @override
  Widget build(BuildContext context) {
    final src = stats?.viewsByDay ?? const <ViewsByDay>[];
    final map = {for (final r in src) r.date: r};
    final now = DateTime.now();
    final days = <({String day, int visitors})>[];
    for (var i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      days.add((day: _dayLetters[(d.weekday - 1) % 7], visitors: map[key]?.uniques ?? 0));
    }
    final total = days.fold(0, (s, d) => s + d.visitors);
    final maxV = days.fold(0, (m, d) => d.visitors > m ? d.visitors : m);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text('Visiteurs', style: AppTheme.body(size: 15, weight: FontWeight.w700, color: _ink)),
              ),
              if (!loading && maxV > 0) ...[
                Text(_fmt(total), style: AppTheme.body(size: 20, weight: FontWeight.w800, color: _ink)),
                const SizedBox(width: 5),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('uniques · 7 j', style: AppTheme.body(size: 10.5, color: _faint)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          if (loading)
            const SizedBox(height: 110, child: Center(child: CircularProgressIndicator(color: _orange)))
          else if (maxV == 0)
            const _EmptyMini(icon: Icons.people_outline, text: 'Aucune visite enregistrée.')
          else
            SizedBox(
              height: 110,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: days.asMap().entries.map((e) {
                  final d = e.value;
                  final isToday = e.key == days.length - 1;
                  final hgt = math.max(d.visitors / maxV * 80, 6.0);
                  return Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (isToday)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('${d.visitors}',
                                style: AppTheme.body(size: 10, weight: FontWeight.w700, color: _orange)),
                          ),
                        Container(
                          width: 18,
                          height: hgt,
                          decoration: BoxDecoration(
                            color: d.visitors == 0 ? _grid : (isToday ? _orange : _orangeSoft),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(d.day,
                            style: AppTheme.body(
                                size: 10,
                                weight: isToday ? FontWeight.w700 : FontWeight.w400,
                                color: isToday ? _ink : _faint)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════ Commandes récentes ═══════
const _statusText = {
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

class _RecentOrders extends StatelessWidget {
  final List<SubOrder> orders;
  final bool loading;
  const _RecentOrders({required this.orders, required this.loading});

  String _ago(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d).inSeconds;
    if (diff < 3600) return '${(diff / 60).round().clamp(1, 999)} min';
    if (diff < 86400) return '${(diff / 3600).round()} h';
    final j = (diff / 86400).round();
    return j < 30 ? '$j j' : '${d.day}/${d.month}';
  }

  @override
  Widget build(BuildContext context) {
    final rows = [...orders]
      ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    final top = rows.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Commandes récentes'),
        const SizedBox(height: 12),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: _orange)),
          )
        else if (top.isEmpty)
          const _Card(child: _EmptyMini(icon: Icons.inbox_outlined, text: "Aucune commande pour l'instant."))
        else
          ...top.map((o) {
            final first = o.items.isNotEmpty ? o.items.first.productName : '—';
            final label = o.itemsCount > 1 ? '$first +${o.itemsCount - 1}' : first;
            final st = _statusStyle[o.status] ?? _statusStyle['pending']!;
            const placeholder = Icon(Icons.inventory_2_outlined, size: 26, color: _faint);

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _Card(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(18)),
                      child: (o.primaryImage != null && o.primaryImage!.isNotEmpty)
                          ? Image.network(o.primaryImage!,
                              fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Center(child: placeholder))
                          : const Center(child: placeholder),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.body(size: 14, weight: FontWeight.w700, color: _ink)),
                          const SizedBox(height: 4),
                          Text('Prix : ${o.subtotalTnd.toStringAsFixed(3)} TND',
                              style: AppTheme.body(size: 12, color: _mute)),
                          const SizedBox(height: 2),
                          Text('${o.buyerName ?? 'Client'} · ${_ago(o.createdAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.body(size: 11, color: _faint)),
                          const SizedBox(height: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(color: st.$1, borderRadius: BorderRadius.circular(999)),
                            child: Text(_statusText[o.status] ?? o.status,
                                style: AppTheme.body(size: 10.5, weight: FontWeight.w600, color: st.$2)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _EmptyMini extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyMini({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 26),
        child: Center(
          child: Column(
            children: [
              Icon(icon, size: 26, color: _faint),
              const SizedBox(height: 8),
              Text(text, style: AppTheme.body(size: 12, color: _faint)),
            ],
          ),
        ),
      );
}