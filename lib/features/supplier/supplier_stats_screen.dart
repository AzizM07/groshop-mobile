import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
const _pinkSoft = Color(0xFFFFE8EA);
const _green = Color(0xFF1FB57A);
const _greenSoft = Color(0xFFE2F8EE);
const _violet = Color(0xFF8B5CF6);
const _violetSoft = Color(0xFFF0EAFF);
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

// Rampe orange (carte, canaux)
const _ramp = [Color(0xFFFF8A00), Color(0xFFFF9F2E), Color(0xFFFFB25C), Color(0xFFFFC98A), Color(0xFFFFE1BF)];
const _noData = Color(0xFFEDEDF2);

const _catColors = [
  Color(0xFF8B5CF6), Color(0xFF4F7CFF), Color(0xFF06B6D4), Color(0xFF6366F1), Color(0xFFEC4899),
  Color(0xFFF25C6E), Color(0xFF1FB57A), Color(0xFF84CC16), Color(0xFFF59E0B), Color(0xFFFF8A00),
];

const _statusLabel = {
  'pending': 'En attente',
  'confirmed': 'Confirmées',
  'in_production': 'En production',
  'shipped': 'Expédiées',
  'delivered': 'Livrées',
  'cancelled': 'Annulées',
};
const _statusColor = {
  'pending': _pink,
  'confirmed': _blue,
  'in_production': Color(0xFF7FA0FF),
  'shipped': _violet,
  'delivered': _green,
  'cancelled': Color(0xFFD1D1DB),
};

const _channelLabel = {
  'direct': 'Direct',
  'search': 'Recherche',
  'social': 'Réseaux sociaux',
  'email': 'E-mail',
  'referral': 'Sites référents',
  'app_ios': 'App iOS',
  'app_android': 'App Android',
  'unknown': 'Inconnu',
};

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

String _kShort(num v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}k' : _fmt(v);

double _pctChange(num cur, num prev) => prev == 0 ? (cur != 0 ? 100 : 0) : ((cur - prev) / prev) * 100;

/// Normalise un nom de région : minuscules, sans accents, lettres seulement.
String _norm(String s) {
  const from = 'àâäáãéèêëíìîïóòôöõúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    final c = i >= 0 ? to[i] : ch;
    if (RegExp(r'[a-z]').hasMatch(c)) b.write(c);
  }
  return b.toString();
}

// ═══════ Carte : chargement de l'asset ═══════
class _Region {
  final String name;
  final List<String> keys;
  final List<List<Offset>> rings; // Offset(longitude, latitude)
  const _Region(this.name, this.keys, this.rings);
}

class _MapData {
  final List<_Region> regions;
  final double minLon, maxLon, minLat, maxLat;
  const _MapData(this.regions, this.minLon, this.maxLon, this.minLat, this.maxLat);

  static const _k = 0.829; // cos(34°) — corrige l'étirement est-ouest
  double get projW => (maxLon - minLon) * _k;
  double get projH => maxLat - minLat;
  double get aspect => projH / projW;
}

final _tunisiaMapProvider = FutureProvider<_MapData>((ref) async {
  final raw = jsonDecode(await rootBundle.loadString('assets/tunisia_regions.json')) as List;
  var minLon = 999.0, maxLon = -999.0, minLat = 999.0, maxLat = -999.0;
  final regions = <_Region>[];
  for (final e in raw.whereType<Map>()) {
    final rings = <List<Offset>>[];
    for (final ring in (e['rings'] as List)) {
      final pts = <Offset>[];
      for (final p in (ring as List)) {
        final lon = (p[0] as num).toDouble();
        final lat = (p[1] as num).toDouble();
        minLon = math.min(minLon, lon);
        maxLon = math.max(maxLon, lon);
        minLat = math.min(minLat, lat);
        maxLat = math.max(maxLat, lat);
        pts.add(Offset(lon, lat));
      }
      rings.add(pts);
    }
    regions.add(_Region(
      e['name'].toString(),
      (e['keys'] as List).map((k) => k.toString()).toList(),
      rings,
    ));
  }
  return _MapData(regions, minLon, maxLon, minLat, maxLat);
});

// ═══════ Écran ═══════
class SupplierStatsScreen extends ConsumerStatefulWidget {
  const SupplierStatsScreen({super.key});

  @override
  ConsumerState<SupplierStatsScreen> createState() => _SupplierStatsScreenState();
}

class _SupplierStatsScreenState extends ConsumerState<SupplierStatsScreen> {
  void _invalidateAll() {
    ref.invalidate(supplierOrdersProvider);
    ref.invalidate(supplierStatsProvider);
    ref.invalidate(supplierActiveUsersProvider);
    ref.invalidate(supplierRegionsProvider);
    ref.invalidate(supplierMyProductsProvider);
  }

  Future<void> _refresh() async {
    _invalidateAll();
    try {
      await ref.read(supplierOrdersProvider.future);
    } catch (_) {}
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/supplier');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(supplierOrdersProvider);
    final statsAsync = ref.watch(supplierStatsProvider);
    final activeAsync = ref.watch(supplierActiveUsersProvider);
    final regionsAsync = ref.watch(supplierRegionsProvider);
    final prodsAsync = ref.watch(supplierMyProductsProvider);

    final orders = ordersAsync.valueOrNull ?? const <SubOrder>[];
    final paid = orders.where((o) => o.status != 'cancelled').toList();
    final stats = statsAsync.valueOrNull;

    bool first(AsyncValue v) => v.isLoading && !v.hasValue;
    final ordersLoading = first(ordersAsync);
    final statsLoading = first(statsAsync);

    final netErr = ordersAsync.hasError && isNetworkError(ordersAsync.error);

    Widget body;
    if (netErr && !ordersAsync.hasValue && !ordersAsync.isLoading) {
      body = NoConnectionView(onRetry: _invalidateAll);
    } else {
      body = RefreshIndicator(
        color: _orange,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (netErr && ordersAsync.hasValue)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: OfflineBanner(onRetry: () => _refresh()),
                ),
              ),
            _KpiGrid(orders: orders, paid: paid, stats: stats, loading: ordersLoading),
            const SizedBox(height: 16),
            _RevenueCard(paid: paid, loading: ordersLoading),
            const SizedBox(height: 16),
            _ActiveUsersCard(active: activeAsync.valueOrNull, loading: first(activeAsync)),
            const SizedBox(height: 16),
            _RegionsCard(regions: regionsAsync.valueOrNull ?? const [], loading: first(regionsAsync)),
            const SizedBox(height: 16),
            _FunnelCard(stats: stats, loading: statsLoading),
            const SizedBox(height: 16),
            _CategoriesCard(paid: paid, loading: ordersLoading),
            const SizedBox(height: 16),
            _ChannelsCard(stats: stats, loading: statsLoading),
            const SizedBox(height: 16),
            _StatusCard(orders: orders, loading: ordersLoading),
            const SizedBox(height: 16),
            _TopProductsCard(products: prodsAsync.valueOrNull ?? const [], loading: first(prodsAsync)),
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
            // En-tête
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
                        Text('Statistiques', style: AppTheme.body(size: 22, weight: FontWeight.w800, color: _ink)),
                        Text('Revenus, trafic et conversions', style: AppTheme.body(size: 12, color: _mute)),
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
}

// ═══════ Primitives UI ═══════
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: _shadow),
        child: child,
      );
}

Widget _head(String title, {String? sub, Widget? right}) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTheme.body(size: 15, weight: FontWeight.w700, color: _ink)),
              if (sub != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(sub, style: AppTheme.body(size: 11.5, color: _mute)),
                ),
            ],
          ),
        ),
        if (right != null) ...[const SizedBox(width: 8), right],
      ],
    );

Widget _empty(IconData icon, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 26, color: _faint),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center, style: AppTheme.body(size: 12, color: _mute)),
          ],
        ),
      ),
    );

Widget _loader([double h = 140]) =>
    SizedBox(height: h, child: const Center(child: CircularProgressIndicator(color: _orange)));

Widget _dot(Color c, [double s = 8]) =>
    Container(width: s, height: s, decoration: BoxDecoration(color: c, shape: BoxShape.circle));

Widget _trendPill(double? v) {
  if (v == null || !v.isFinite) return const SizedBox.shrink();
  final r = (v * 10).round() / 10;
  final up = r > 0, flat = r == 0;
  final bg = flat ? _tile : (up ? _greenSoft : _pinkSoft);
  final fg = flat ? _mute : (up ? _green : _pink);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!flat) Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 12, color: fg),
        if (!flat) const SizedBox(width: 3),
        Text('${up ? '+' : ''}$r%', style: AppTheme.body(size: 10.5, weight: FontWeight.w700, color: fg)),
      ],
    ),
  );
}

/// Bascule à 2-3 options (pilule).
class _Toggle<T> extends StatelessWidget {
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChange;
  const _Toggle({required this.value, required this.options, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((o) {
          final on = o.$1 == value;
          return GestureDetector(
            onTap: () => onChange(o.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: on ? _orange : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(o.$2,
                  style: AppTheme.body(size: 11, weight: FontWeight.w600, color: on ? Colors.white : _mute)),
            ),
          );
        }).toList(),
      ),
    );
  }
}

TextPainter _tp(String s, TextStyle style) =>
    TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();

void _dash(Canvas c, Offset a, Offset z, Paint p, {double dash = 4, double gap = 4}) {
  final d = z - a;
  final len = d.distance;
  if (len == 0) return;
  final dir = d / len;
  var s = 0.0;
  while (s < len) {
    c.drawLine(a + dir * s, a + dir * math.min(s + dash, len), p);
    s += dash + gap;
  }
}

Path _smooth(List<Offset> pts) {
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  final n = pts.length;
  for (var i = 0; i < n - 1; i++) {
    final p0 = pts[i == 0 ? 0 : i - 1];
    final p1 = pts[i];
    final p2 = pts[i + 1];
    final p3 = pts[i + 2 < n ? i + 2 : n - 1];
    path.cubicTo(
      p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6,
      p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6,
      p2.dx, p2.dy,
    );
  }
  return path;
}

// ═══════ KPI 2×2 ═══════
class _KpiGrid extends StatelessWidget {
  final List<SubOrder> orders;
  final List<SubOrder> paid;
  final SupplierStats? stats;
  final bool loading;
  const _KpiGrid({required this.orders, required this.paid, required this.stats, required this.loading});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final mStart = DateTime(now.year, now.month, 1);
    final pStart = DateTime(now.year, now.month - 1, 1);
    bool inR(SubOrder o, DateTime a, DateTime? b) {
      final d = o.createdAt;
      return d != null && !d.isBefore(a) && (b == null || d.isBefore(b));
    }

    double sum(Iterable<SubOrder> a) => a.fold(0.0, (s, o) => s + o.subtotalTnd);
    final curM = paid.where((o) => inR(o, mStart, null));
    final prvM = paid.where((o) => inR(o, pStart, mStart));
    final s = stats;

    Widget row(Widget a, Widget b) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)],
          ),
        );

    return Column(
      children: [
        row(
          _KpiTile(
            label: 'Ventes totales',
            value: _fmt(sum(paid)),
            unit: 'TND',
            icon: Icons.payments_outlined,
            fg: _orange,
            bg: _orangeSoft,
            footer: _trendPill(_pctChange(sum(curM), sum(prvM))),
            loading: loading,
          ),
          _KpiTile(
            label: 'Commandes',
            value: _fmt(orders.length),
            icon: Icons.shopping_cart_outlined,
            fg: _blue,
            bg: _blueSoft,
            footer: _trendPill(_pctChange(curM.length, prvM.length)),
            loading: loading,
          ),
        ),
        const SizedBox(height: 12),
        row(
          _KpiTile(
            label: 'Visiteurs',
            value: s == null ? '—' : _fmt(s.viewsMonth),
            icon: Icons.people_outline_rounded,
            fg: _violet,
            bg: _violetSoft,
            footer: Text(s == null ? 'ce mois' : '${_fmt(s.uniqueVisitors)} uniques',
                style: AppTheme.body(size: 11, color: _mute)),
            loading: loading && s == null,
          ),
          _KpiTile(
            label: 'Conversion',
            value: s == null ? '—' : '${s.conversionRate}%',
            icon: Icons.track_changes_rounded,
            fg: _green,
            bg: _greenSoft,
            footer: Text('visites → commandes', style: AppTheme.body(size: 11, color: _mute)),
            loading: loading && s == null,
          ),
        ),
      ],
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final IconData icon;
  final Color fg;
  final Color bg;
  final Widget footer;
  final bool loading;
  const _KpiTile({
    required this.label,
    required this.value,
    this.unit,
    required this.icon,
    required this.fg,
    required this.bg,
    required this.footer,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(22)),
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
          const SizedBox(height: 12),
          if (loading)
            Container(
              height: 26,
              width: 70,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.6), borderRadius: BorderRadius.circular(8)),
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
                  Text(value, style: AppTheme.body(size: 24, weight: FontWeight.w800, color: _ink)),
                  if (unit != null) ...[
                    const SizedBox(width: 4),
                    Text(unit!, style: AppTheme.body(size: 11, weight: FontWeight.w500, color: _mute)),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 6),
          if (!loading) footer,
        ],
      ),
    );
  }
}

// ═══════ Analyse des revenus ═══════
class _RevenueCard extends StatefulWidget {
  final List<SubOrder> paid;
  final bool loading;
  const _RevenueCard({required this.paid, required this.loading});

  @override
  State<_RevenueCard> createState() => _RevenueCardState();
}

class _RevenueCardState extends State<_RevenueCard> {
  int _days = 30;
  int? _sel;

  List<({String label, double revenue, double orders})> _buckets() {
    final now = DateTime.now();
    final step = _days <= 7 ? 1 : (_days <= 30 ? 3 : 9);
    final out = <({String label, double revenue, double orders})>[];
    for (var i = _days; i >= 0; i -= step) {
      final end = DateTime(now.year, now.month, now.day - i, 23, 59, 59);
      final start = DateTime(end.year, end.month, end.day - step + 1);
      final inB = widget.paid.where(
          (o) => o.createdAt != null && !o.createdAt!.isBefore(start) && !o.createdAt!.isAfter(end));
      out.add((
        label: '${end.day}/${end.month}',
        revenue: inB.fold(0.0, (s, o) => s + o.subtotalTnd),
        orders: inB.length.toDouble(),
      ));
    }
    return out;
  }

  Widget _legend(Color c, String t) => Row(
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
          Text(t, style: AppTheme.body(size: 11.5, color: _mute)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final data = _buckets();
    final revenues = data.map((d) => d.revenue).toList();
    final counts = data.map((d) => d.orders).toList();
    final total = revenues.fold(0.0, (s, v) => s + v);
    final hasData = revenues.any((v) => v > 0);
    final sel = math.min(math.max(_sel ?? data.length - 1, 0), data.length - 1);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _head(
            'Analyse des revenus',
            sub: widget.loading ? null : '${_fmt(total)} TND sur la période',
            right: _Toggle<int>(
              value: _days,
              options: const [(7, '7 j'), (30, '30 j'), (90, '90 j')],
              onChange: (v) => setState(() {
                _days = v;
                _sel = null;
              }),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [_legend(_orange, 'Revenus'), const SizedBox(width: 16), _legend(_blue, 'Commandes')]),
          const SizedBox(height: 6),
          if (widget.loading)
            _loader(200)
          else if (!hasData)
            _empty(Icons.show_chart_rounded, 'Aucune vente sur cette période.')
          else
            SizedBox(
              height: 220,
              child: LayoutBuilder(builder: (context, box) {
                void pick(double dx) {
                  final w = box.maxWidth - _LineChartPainter.l - _LineChartPainter.r;
                  final n = data.length;
                  final i = n == 1 ? 0 : ((dx - _LineChartPainter.l) / w * (n - 1)).round().clamp(0, n - 1);
                  if (i != _sel) setState(() => _sel = i);
                }

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => pick(d.localPosition.dx),
                  onHorizontalDragUpdate: (d) => pick(d.localPosition.dx),
                  child: CustomPaint(
                    size: Size(box.maxWidth, 220),
                    painter: _LineChartPainter(
                      a: revenues,
                      b: counts,
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

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({required this.a, required this.b, required this.labels, required this.selected});
  final List<double> a; // revenus
  final List<double> b; // commandes
  final List<String> labels;
  final int selected;

  static const l = 36.0, r = 8.0, t = 62.0, bt = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    final n = a.length;
    if (n == 0) return;
    final w = size.width - l - r;
    final h = size.height - t - bt;
    final maxA = a.fold<double>(0, (m, v) => math.max(m, v));
    final maxB = b.fold<double>(0, (m, v) => math.max(m, v));
    final topA = maxA <= 0 ? 1.0 : maxA * 1.12;
    final topB = maxB <= 0 ? 1.0 : maxB * 1.12;

    final axis = AppTheme.body(size: 9.5, color: _faint);
    final gridP = Paint()
      ..color = _grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = t + h * i / 4;
      _dash(canvas, Offset(l, y), Offset(l + w, y), gridP);
      final tp = _tp(_kShort(topA * (1 - i / 4)), axis);
      tp.paint(canvas, Offset(l - 8 - tp.width, y - tp.height / 2));
    }

    double x(int i) => l + (n == 1 ? w / 2 : w * i / (n - 1));
    final pa = [for (var i = 0; i < n; i++) Offset(x(i), t + h - a[i] / topA * h)];
    final pb = [for (var i = 0; i < n; i++) Offset(x(i), t + h - b[i] / topB * h)];

    for (var i = 0; i < n; i++) {
      if (n > 8 && i.isOdd && i != n - 1) continue;
      final tp = _tp(labels[i], axis);
      tp.paint(canvas, Offset(x(i) - tp.width / 2, size.height - bt + 8));
    }

    // Aire sous la courbe revenus
    final area = Path.from(_smooth(pa))
      ..lineTo(pa.last.dx, t + h)
      ..lineTo(pa.first.dx, t + h)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_orange.withOpacity(0.18), _orange.withOpacity(0)],
        ).createShader(Rect.fromLTWH(0, t, size.width, h)),
    );

    final s = selected.clamp(0, n - 1);
    _dash(canvas, Offset(pa[s].dx, t), Offset(pa[s].dx, t + h),
        Paint()
          ..color = _orange.withOpacity(0.6)
          ..strokeWidth = 1.2,
        dash: 3,
        gap: 3);

    canvas.drawPath(
        _smooth(pb),
        Paint()
          ..color = _blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round);
    canvas.drawPath(
        _smooth(pa),
        Paint()
          ..color = _orange
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round);

    canvas.drawCircle(pb[s], 4, Paint()..color = _blue);
    canvas.drawCircle(pa[s], 6, Paint()..color = Colors.white);
    canvas.drawCircle(
        pa[s],
        6,
        Paint()
          ..color = _orange
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);

    // Bulle : date · montant · commandes
    final t1 = _tp(labels[s], AppTheme.body(size: 9.5, color: _mute));
    final t2 = _tp('${_fmt(a[s])} TND', AppTheme.body(size: 12, weight: FontWeight.w800, color: _ink));
    final t3 = _tp('${b[s].round()} commande${b[s] > 1 ? 's' : ''}',
        AppTheme.body(size: 9.5, weight: FontWeight.w600, color: _blue));
    final bw = math.max(t1.width, math.max(t2.width, t3.width)) + 20;
    final bh = t1.height + t2.height + t3.height + 12;
    final bx = math.min(math.max(pa[s].dx - bw / 2, 0.0), math.max(size.width - bw, 0.0));
    const by = 0.0;
    final rr = RRect.fromRectAndRadius(Rect.fromLTWH(bx, by, bw, bh), const Radius.circular(12));
    canvas.drawShadow(Path()..addRRect(rr), const Color(0x33000000), 6, false);
    canvas.drawRRect(rr, Paint()..color = Colors.white);
    var yy = by + 6;
    for (final tp in [t1, t2, t3]) {
      tp.paint(canvas, Offset(bx + (bw - tp.width) / 2, yy));
      yy += tp.height;
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) => true;
}

// ═══════ Utilisateurs actifs ═══════
class _ActiveUsersCard extends StatefulWidget {
  final ActiveUsers? active;
  final bool loading;
  const _ActiveUsersCard({required this.active, required this.loading});

  @override
  State<_ActiveUsersCard> createState() => _ActiveUsersCardState();
}

class _ActiveUsersCardState extends State<_ActiveUsersCard> {
  String _mode = 'visitors';

  @override
  Widget build(BuildContext context) {
    final a = widget.active;
    final src = a == null ? const DauWauMau() : (_mode == 'visitors' ? a.uniqueVisitors : a.authenticatedUsers);
    final rows = [
      ('dau', "Aujourd'hui", '24 dernières heures', Icons.bolt_rounded, src.dau),
      ('wau', 'Cette semaine', '7 derniers jours', Icons.calendar_view_week_rounded, src.wau),
      ('mau', 'Ce mois', '30 derniers jours', Icons.calendar_month_rounded, src.mau),
    ];
    final maxV = [src.dau, src.wau, src.mau, 1].reduce(math.max);
    final stick = a?.stickinessRatio ?? 0;
    final good = stick >= 20;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _head(
            'Utilisateurs actifs',
            sub: 'Fenêtres glissantes',
            right: _Toggle<String>(
              value: _mode,
              options: const [('visitors', 'Visiteurs'), ('users', 'Connectés')],
              onChange: (v) => setState(() => _mode = v),
            ),
          ),
          const SizedBox(height: 14),
          if (widget.loading)
            _loader(150)
          else if (a == null)
            _empty(Icons.people_outline_rounded, 'Suivi non disponible.')
          else ...[
            for (final r in rows)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: r.$1 == 'dau' ? _orangeSoft : _tile,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: r.$1 == 'dau' ? _orange : Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(r.$4, size: 15, color: r.$1 == 'dau' ? Colors.white : _mute),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.$2, style: AppTheme.body(size: 12.5, weight: FontWeight.w600, color: _ink)),
                              Text(r.$3, style: AppTheme.body(size: 10.5, color: _mute)),
                            ],
                          ),
                        ),
                        Text(_fmt(r.$5),
                            style: AppTheme.body(
                                size: 18, weight: FontWeight.w800, color: r.$1 == 'dau' ? _orange : _ink)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: (r.$5 / maxV).clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: Colors.white,
                        valueColor: AlwaysStoppedAnimation(r.$1 == 'dau' ? _orange : _faint),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Fidélité (DAU/MAU)', style: AppTheme.body(size: 12, weight: FontWeight.w600, color: _ink)),
                      Text(good ? 'Bon retour des visiteurs' : 'Peu de visiteurs récurrents',
                          style: AppTheme.body(size: 11, color: _mute)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: good ? _greenSoft : _orangeSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('$stick%',
                      style: AppTheme.body(size: 15, weight: FontWeight.w800, color: good ? _green : _orange)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════ Ventes par région (carte Tunisie) ═══════
class _RegionsCard extends ConsumerStatefulWidget {
  final List<RegionStat> regions;
  final bool loading;
  const _RegionsCard({required this.regions, required this.loading});

  @override
  ConsumerState<_RegionsCard> createState() => _RegionsCardState();
}

class _RegionsCardState extends ConsumerState<_RegionsCard> {
  String _metric = 'revenue';
  String? _selected; // nom de région sur la carte

  num _val(RegionStat r) => _metric == 'revenue' ? r.revenue : r.ordersCount;

  @override
  Widget build(BuildContext context) {
    final mapAsync = ref.watch(_tunisiaMapProvider);
    final regions = widget.regions;

    // Index des stats par clé normalisée (label et code gouvernorat)
    final byKey = <String, RegionStat>{};
    for (final r in regions) {
      byKey[_norm(r.label)] = r;
      byKey[_norm(r.gouvernorat)] = r;
    }
    RegionStat? statFor(_Region g) {
      for (final k in g.keys) {
        final s = byKey[k];
        if (s != null) return s;
      }
      return null;
    }

    final sorted = [...regions]..sort((x, y) => _val(y).compareTo(_val(x)));
    final top = sorted.take(8).toList();
    final maxVal = top.isEmpty ? 1 : math.max(_val(top.first), 1);
    final total = regions.fold<num>(0, (s, r) => s + _val(r));

    Color fillForStat(RegionStat? r) {
      if (r == null) return _noData;
      final t = _val(r) / maxVal;
      if (t <= 0) return _noData;
      if (t >= 0.80) return _ramp[0];
      if (t >= 0.60) return _ramp[1];
      if (t >= 0.45) return _ramp[2];
      if (t >= 0.30) return _ramp[3];
      return _ramp[4];
    }

    String valText(num v) => _metric == 'revenue' ? '${_fmt(v)} TND' : _fmt(v);

    // Région sélectionnée
    _Region? selRegion;
    RegionStat? selStat;
    final md = mapAsync.valueOrNull;
    if (_selected != null && md != null) {
      for (final g in md.regions) {
        if (g.name == _selected) {
          selRegion = g;
          selStat = statFor(g);
        }
      }
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _head(
            'Ventes par région',
            sub: widget.loading ? null : '${regions.length} gouvernorat${regions.length > 1 ? 's' : ''}',
            right: _Toggle<String>(
              value: _metric,
              options: const [('revenue', 'Revenus'), ('orders', 'Commandes')],
              onChange: (v) => setState(() => _metric = v),
            ),
          ),
          const SizedBox(height: 14),
          if (widget.loading)
            _loader(220)
          else if (regions.isEmpty)
            _empty(Icons.location_on_outlined, 'Aucune vente géolocalisée pour le moment.')
          else ...[
            // Info région touchée
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              child: selRegion == null
                  ? const SizedBox(width: double.infinity)
                  : Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: _orangeSoft, borderRadius: BorderRadius.circular(14)),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on_rounded, size: 16, color: _orange),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(selRegion.name,
                                style: AppTheme.body(size: 13, weight: FontWeight.w700, color: _ink)),
                          ),
                          Text(
                            selStat == null
                                ? 'Aucune vente'
                                : '${_fmt(selStat.revenue)} TND · ${selStat.ordersCount} cmd',
                            style: AppTheme.body(size: 12, weight: FontWeight.w600, color: _orange),
                          ),
                        ],
                      ),
                    ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Carte
                Expanded(
                  flex: 5,
                  child: mapAsync.when(
                    loading: () => _loader(220),
                    error: (_, __) => _empty(Icons.map_outlined, 'Carte indisponible.'),
                    data: (m) => _TunisiaMap(
                      data: m,
                      fill: (g) => fillForStat(statFor(g)),
                      selected: _selected,
                      onTap: (g) => setState(() => _selected = (g == null || g.name == _selected) ? null : g.name),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Classement
                Expanded(
                  flex: 6,
                  child: Column(
                    children: top.map((r) {
                      final v = _val(r);
                      final share = total == 0 ? 0 : (v / total * 100).round();
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            _dot(fillForStat(r)),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(r.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.body(size: 12, weight: FontWeight.w500, color: _ink)),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(valText(v), style: AppTheme.body(size: 11.5, weight: FontWeight.w700, color: _ink)),
                                Text('$share%', style: AppTheme.body(size: 10, color: _faint)),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Touchez une région pour voir le détail.', style: AppTheme.body(size: 10.5, color: _faint)),
          ],
        ],
      ),
    );
  }
}

class _TunisiaMap extends StatelessWidget {
  final _MapData data;
  final Color Function(_Region) fill;
  final String? selected;
  final ValueChanged<_Region?> onTap;
  const _TunisiaMap({required this.data, required this.fill, required this.selected, required this.onTap});

  Map<String, Path> _paths(Size size) {
    final sx = size.width / data.projW;
    final sy = size.height / data.projH;
    final s = math.min(sx, sy);
    final ox = (size.width - data.projW * s) / 2;
    final oy = (size.height - data.projH * s) / 2;
    Offset proj(Offset p) => Offset(
          ox + (p.dx - data.minLon) * _MapData._k * s,
          oy + (data.maxLat - p.dy) * s,
        );
    final out = <String, Path>{};
    for (final g in data.regions) {
      final path = Path();
      for (final ring in g.rings) {
        path.addPolygon(ring.map(proj).toList(), true);
      }
      out[g.name] = path;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final size = Size(w, w * data.aspect);
      final paths = _paths(size);
      return GestureDetector(
        onTapUp: (d) {
          _Region? hit;
          for (final g in data.regions) {
            if (paths[g.name]!.contains(d.localPosition)) hit = g;
          }
          onTap(hit);
        },
        child: CustomPaint(
          size: size,
          painter: _MapPainter(data: data, paths: paths, fill: fill, selected: selected),
        ),
      );
    });
  }
}

class _MapPainter extends CustomPainter {
  final _MapData data;
  final Map<String, Path> paths;
  final Color Function(_Region) fill;
  final String? selected;
  _MapPainter({required this.data, required this.paths, required this.fill, required this.selected});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeJoin = StrokeJoin.round;
    for (final g in data.regions) {
      final p = paths[g.name]!;
      canvas.drawPath(p, Paint()..color = fill(g));
      canvas.drawPath(p, stroke);
    }
    if (selected != null && paths[selected] != null) {
      canvas.drawPath(
        paths[selected]!,
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => true;
}

// ═══════ Entonnoir de conversion ═══════
class _FunnelCard extends StatelessWidget {
  final SupplierStats? stats;
  final bool loading;
  const _FunnelCard({required this.stats, required this.loading});

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final base = math.max(s?.viewsMonth ?? 0, 1);
    final steps = s == null
        ? const <({String label, int value, IconData icon})>[]
        : [
            (label: 'Pages vues', value: s.viewsMonth, icon: Icons.visibility_outlined),
            (label: 'Visiteurs uniques', value: s.uniqueVisitors, icon: Icons.people_outline_rounded),
            (label: 'Sessions', value: s.sessionsCount, icon: Icons.ads_click_rounded),
            (label: 'Commandes', value: s.convertedCount, icon: Icons.shopping_bag_outlined),
          ];

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _head(
            'Entonnoir de conversion',
            sub: 'Des visites aux commandes · 30 j',
            right: (loading || s == null)
                ? null
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: _orangeSoft, borderRadius: BorderRadius.circular(999)),
                    child: Text('${s.conversionRate}%',
                        style: AppTheme.body(size: 14, weight: FontWeight.w800, color: _orange)),
                  ),
          ),
          const SizedBox(height: 14),
          if (loading)
            _loader(150)
          else if (s == null || steps.every((e) => e.value == 0))
            _empty(Icons.filter_alt_outlined, 'Pas encore assez de données.')
          else ...[
            for (var i = 0; i < steps.length; i++) ...[
              _funnelRow(steps, i, base),
              if (i < steps.length - 1) const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }

  Widget _funnelRow(List<({String label, int value, IconData icon})> steps, int i, int base) {
    final st = steps[i];
    final pct = (st.value / base).clamp(0.0, 1.0);
    final last = i == steps.length - 1;
    final prev = i > 0 ? steps[i - 1].value : 0;
    final dropRaw = (i > 0 && prev > 0) ? ((1 - st.value / prev) * 100).round() : null;
    final drop = (dropRaw != null && dropRaw > 0) ? dropRaw : null;
    final color = last ? _orange : (i == 0 ? const Color(0xFFFFB25C) : const Color(0xFFFFD2A3));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(st.icon, size: 15, color: last ? _orange : _mute),
            const SizedBox(width: 6),
            Expanded(child: Text(st.label, style: AppTheme.body(size: 12, weight: FontWeight.w500, color: _ink))),
            if (drop != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('−$drop%', style: AppTheme.body(size: 10.5, color: _faint)),
              ),
            Text(_fmt(st.value),
                style: AppTheme.body(size: 14, weight: FontWeight.w800, color: last ? _orange : _ink)),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (_, box) => Container(
            height: 12,
            width: box.maxWidth,
            decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(999)),
            alignment: Alignment.centerLeft,
            child: Container(
              width: math.max(box.maxWidth * pct, 10),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════ Top catégories (donut) ═══════
class _CategoriesCard extends StatelessWidget {
  final List<SubOrder> paid;
  final bool loading;
  const _CategoriesCard({required this.paid, required this.loading});

  @override
  Widget build(BuildContext context) {
    final map = <String, double>{};
    for (final o in paid) {
      for (final it in o.items) {
        final name = (it.productCategory?.isNotEmpty ?? false) ? it.productCategory! : 'Autre';
        map[name] = (map[name] ?? 0) + it.totalTnd;
      }
    }
    final total = map.values.fold(0.0, (s, v) => s + v);
    final cats = map.entries
        .where((e) => e.value > 0)
        .map((e) => (name: e.key, rev: e.value, pct: total == 0 ? 0.0 : e.value / total * 100))
        .toList()
      ..sort((a, b) => b.rev.compareTo(a.rev));
    final top = cats.take(10).toList();

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _head('Top catégories',
              sub: loading ? null : '${top.length} catégorie${top.length > 1 ? 's' : ''} · par revenus'),
          const SizedBox(height: 14),
          if (loading)
            _loader(180)
          else if (top.isEmpty)
            _empty(Icons.pie_chart_outline_rounded, 'Aucune vente par catégorie.')
          else ...[
            Center(
              child: SizedBox(
                width: 180,
                height: 180,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(180, 180),
                      painter: _DonutPainter(
                        values: top.map((c) => c.pct).toList(),
                        colors: [for (var i = 0; i < top.length; i++) _catColors[i % _catColors.length]],
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Total', style: AppTheme.body(size: 11, color: _mute)),
                        Text(_kShort(total), style: AppTheme.body(size: 20, weight: FontWeight.w800, color: _ink)),
                        Text('TND', style: AppTheme.body(size: 10.5, color: _mute)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < top.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _catColors[i % _catColors.length].withOpacity(0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _dot(_catColors[i % _catColors.length]),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: Text(top[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.body(size: 11.5, weight: FontWeight.w500, color: _ink)),
                        ),
                        const SizedBox(width: 5),
                        Text('${top[i].pct.round()}%',
                            style: AppTheme.body(
                                size: 11.5, weight: FontWeight.w700, color: _catColors[i % _catColors.length])),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<double> values; // pourcentages
  final List<Color> colors;
  _DonutPainter({required this.values, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 24.0;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - stroke / 2);
    const gap = 0.035;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / 100 * math.pi * 2;
      if (sweep <= gap) {
        start += sweep;
        continue;
      }
      canvas.drawArc(
        rect,
        start + gap / 2,
        sweep - gap,
        false,
        Paint()
          ..color = colors[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => true;
}

// ═══════ Performance par canal (demi-donut) ═══════
class _ChannelsCard extends StatelessWidget {
  final SupplierStats? stats;
  final bool loading;
  const _ChannelsCard({required this.stats, required this.loading});

  @override
  Widget build(BuildContext context) {
    final conv = {for (final c in stats?.conversionByChannel ?? const <ChannelConv>[]) c.channel: c.rate};
    final channels = (stats?.byChannel ?? const <ChannelCount>[]).take(5).toList();
    final total = channels.fold(0, (s, c) => s + c.count);
    String label(String k) => _channelLabel[k] ?? k;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _head('Performance par canal', sub: "D'où viennent vos visiteurs"),
          const SizedBox(height: 12),
          if (loading)
            _loader(180)
          else if (channels.isEmpty || total == 0)
            _empty(Icons.podcasts_rounded, 'Aucune donnée de canal.')
          else ...[
            Text('Pages vues', style: AppTheme.body(size: 11.5, color: _mute)),
            Text(_fmt(total), style: AppTheme.body(size: 24, weight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 8),
            Center(
              child: SizedBox(
                width: 240,
                height: 132,
                child: Stack(
                  children: [
                    CustomPaint(
                      size: const Size(240, 132),
                      painter: _HalfDonutPainter(
                        values: channels.map((c) => c.count.toDouble()).toList(),
                        colors: [for (var i = 0; i < channels.length; i++) _ramp[i % _ramp.length]],
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 4,
                      child: Column(
                        children: [
                          Text('Canal principal', style: AppTheme.body(size: 10.5, color: _mute)),
                          Text(label(channels.first.channel),
                              style: AppTheme.body(size: 15, weight: FontWeight.w800, color: _ink)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < channels.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    _dot(_ramp[i % _ramp.length], 10),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(label(channels[i].channel),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(size: 12.5, weight: FontWeight.w500, color: _ink)),
                    ),
                    Text(_fmt(channels[i].count), style: AppTheme.body(size: 12, color: _mute)),
                    if (conv[channels[i].channel] != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: _orangeSoft, borderRadius: BorderRadius.circular(999)),
                        child: Text('${conv[channels[i].channel]}%',
                            style: AppTheme.body(size: 10.5, weight: FontWeight.w700, color: _orange)),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _HalfDonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  _HalfDonutPainter({required this.values, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 22.0;
    final r = math.min(size.width / 2, size.height) - stroke / 2;
    final center = Offset(size.width / 2, size.height - 2);
    final rect = Rect.fromCircle(center: center, radius: r);
    final total = values.fold(0.0, (s, v) => s + v);
    if (total <= 0) return;
    const gap = 0.07;
    final span = math.pi - gap * math.max(values.length - 1, 0);
    var start = math.pi;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * span;
      if (sweep > 0.01) {
        canvas.drawArc(
          rect,
          start,
          sweep,
          false,
          Paint()
            ..color = colors[i]
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.butt,
        );
      }
      start += sweep + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _HalfDonutPainter old) => true;
}

// ═══════ Ventes & commandes par statut ═══════
class _StatusCard extends StatefulWidget {
  final List<SubOrder> orders;
  final bool loading;
  const _StatusCard({required this.orders, required this.loading});

  @override
  State<_StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends State<_StatusCard> {
  String? _open;

  @override
  Widget build(BuildContext context) {
    final map = <String, ({int count, double revenue})>{};
    for (final o in widget.orders) {
      final cur = map[o.status] ?? (count: 0, revenue: 0.0);
      map[o.status] = (count: cur.count + 1, revenue: cur.revenue + o.subtotalTnd);
    }
    final total = widget.orders.length;
    final rows = map.entries.toList()..sort((a, b) => b.value.count.compareTo(a.value.count));
    final maxV = rows.isEmpty ? 1 : rows.first.value.count;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _head('Ventes & commandes', sub: 'Par statut · touchez une ligne'),
          const SizedBox(height: 12),
          if (widget.loading)
            _loader(140)
          else if (rows.isEmpty)
            _empty(Icons.assignment_outlined, 'Aucune commande.')
          else ...[
            Text('Total commandes', style: AppTheme.body(size: 11.5, color: _mute)),
            Text(_fmt(total), style: AppTheme.body(size: 24, weight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 12),
            for (final e in rows) ...[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _open = _open == e.key ? null : e.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(_statusLabel[e.key] ?? e.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.body(
                                size: 12,
                                weight: _open == e.key ? FontWeight.w700 : FontWeight.w500,
                                color: _open == e.key ? _ink : _mute)),
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (_, box) => Container(
                            height: 16,
                            decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(999)),
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: math.max(box.maxWidth * e.value.count / maxV, 14),
                              decoration: BoxDecoration(
                                color: _statusColor[e.key] ?? _faint,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 34,
                        child: Text(_fmt(e.value.count),
                            textAlign: TextAlign.right,
                            style: AppTheme.body(size: 12.5, weight: FontWeight.w700, color: _ink)),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                child: _open != e.key
                    ? const SizedBox(width: double.infinity)
                    : Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            Text('${total == 0 ? 0 : (e.value.count / total * 100).toStringAsFixed(1)}% des commandes',
                                style: AppTheme.body(size: 11.5, color: _mute)),
                            const Spacer(),
                            Text('${_fmt(e.value.revenue)} TND',
                                style: AppTheme.body(size: 12, weight: FontWeight.w700, color: _ink)),
                          ],
                        ),
                      ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ═══════ Top produits ═══════
class _TopProductsCard extends StatefulWidget {
  final List<MyProduct> products;
  final bool loading;
  const _TopProductsCard({required this.products, required this.loading});

  @override
  State<_TopProductsCard> createState() => _TopProductsCardState();
}

class _TopProductsCardState extends State<_TopProductsCard> {
  String _sort = 'sold';

  @override
  Widget build(BuildContext context) {
    num key(MyProduct p) => switch (_sort) {
          'stock' => p.stockQty,
          'price' => p.basePriceTnd,
          'rating' => p.ratingAvg,
          _ => p.soldCount,
        };
    final rows = [...widget.products]..sort((a, b) => key(b).compareTo(key(a)));
    final top = rows.take(8).toList();

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _head('Top produits',
              sub: widget.loading ? null : '${widget.products.length} produit${widget.products.length > 1 ? 's' : ''}'),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _Toggle<String>(
              value: _sort,
              options: const [('sold', 'Ventes'), ('stock', 'Stock'), ('price', 'Prix'), ('rating', 'Note')],
              onChange: (v) => setState(() => _sort = v),
            ),
          ),
          const SizedBox(height: 12),
          if (widget.loading)
            _loader(160)
          else if (top.isEmpty)
            _empty(Icons.inventory_2_outlined, 'Aucun produit.')
          else
            for (var i = 0; i < top.length; i++) _productRow(top[i], i, i == top.length - 1),
        ],
      ),
    );
  }

  Widget _productRow(MyProduct p, int rank, bool last) {
    const ph = Icon(Icons.inventory_2_outlined, size: 20, color: _faint);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: _tile))),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text('${rank + 1}',
                style: AppTheme.body(size: 12, weight: FontWeight.w800, color: rank < 3 ? _orange : _faint)),
          ),
          Container(
            width: 48,
            height: 48,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(14)),
            child: (p.primaryImage != null && p.primaryImage!.isNotEmpty)
                ? Image.network(p.primaryImage!,
                    width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Center(child: ph))
                : const Center(child: ph),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(size: 13, weight: FontWeight.w700, color: _ink)),
                const SizedBox(height: 2),
                Text(p.categoryName ?? '—',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.body(size: 11, color: _mute)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 13, color: _star),
                    const SizedBox(width: 2),
                    Text(p.ratingAvg.toStringAsFixed(1),
                        style: AppTheme.body(size: 11, weight: FontWeight.w600, color: _ink)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        p.stockQty > 0 ? '${_fmt(p.stockQty)} en stock' : 'Épuisé',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                            size: 11,
                            weight: p.stockQty > 0 ? FontWeight.w400 : FontWeight.w700,
                            color: p.stockQty > 0 ? _faint : _pink),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_fmt(p.soldCount), style: AppTheme.body(size: 15, weight: FontWeight.w800, color: _orange)),
              Text('vendus', style: AppTheme.body(size: 10, color: _mute)),
              const SizedBox(height: 2),
              Text('${p.basePriceTnd.toStringAsFixed(3)} TND',
                  style: AppTheme.body(size: 10.5, weight: FontWeight.w600, color: _ink)),
            ],
          ),
        ],
      ),
    );
  }
}