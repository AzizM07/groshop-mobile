import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/api/network_error.dart';
import '../../data/api/supplier_access_reviews_api.dart';
import '../../data/api/supplier_api.dart';
import '../../widgets/no_connection_view.dart';

// ═══════ Palette (identique au dashboard) ═══════
const _orange = Color(0xFFFF8A00);
const _orangeSoft = Color(0xFFFFEEDB);
const _star = Color(0xFFFFB800);
const _starOff = Color(0xFFE5E5EC);
const _bg = Color(0xFFFAFAFB);
const _ink = Color(0xFF1E1E2D);
const _sub = Color(0xFF4A4A5A);
const _mute = Color(0xFF8A8A99);
const _faint = Color(0xFFB5B5C3);
const _tile = Color(0xFFF4F4F6);
const _grid = Color(0xFFE9E9EF);

const _shadow = <BoxShadow>[
  BoxShadow(color: Color(0x0F1B1B3A), blurRadius: 24, offset: Offset(0, 8)),
];

const _pageSize = 8;
const _months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

String _ago(DateTime? d) {
  if (d == null) return '';
  final s = DateTime.now().difference(d).inSeconds;
  if (s < 3600) return '${(s / 60).round().clamp(1, 59)} min';
  if (s < 86400) return '${(s / 3600).round()} h';
  final j = (s / 86400).round();
  return j < 30 ? '$j j' : '${d.day} ${_months[d.month - 1]}';
}

class SupplierReviewsScreen extends ConsumerStatefulWidget {
  const SupplierReviewsScreen({super.key});

  @override
  ConsumerState<SupplierReviewsScreen> createState() => _SupplierReviewsScreenState();
}

class _SupplierReviewsScreenState extends ConsumerState<SupplierReviewsScreen> {
  int _starFilter = 0; // 0 = tous
  int _visible = _pageSize;

  Future<void> _refresh() async {
    ref.invalidate(supplierMyProductsProvider);
    ref.invalidate(supplierReviewsProvider);
    try {
      await ref.read(supplierReviewsProvider.future);
    } catch (_) {}
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/supplier/settings');
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(supplierReviewsProvider);
    final reviews = async.valueOrNull ?? const <SupplierReviewItem>[];
    final netErr = async.hasError && isNetworkError(async.error);
    final loading = async.isLoading && !async.hasValue;

    int roundOf(SupplierReviewItem r) => r.rating.round().clamp(1, 5);
    final counts = {for (var s = 1; s <= 5; s++) s: reviews.where((r) => roundOf(r) == s).length};
    final n = reviews.length;
    final avg = n == 0 ? 0.0 : reviews.fold(0.0, (s, r) => s + r.rating) / n;
    final filtered = _starFilter == 0 ? reviews : reviews.where((r) => roundOf(r) == _starFilter).toList();
    final rows = filtered.take(_visible).toList();

    Widget body;
    if (netErr && !async.hasValue && !async.isLoading) {
      body = NoConnectionView(onRetry: () {
        ref.invalidate(supplierMyProductsProvider);
        ref.invalidate(supplierReviewsProvider);
      });
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
            _summary(avg, n, counts, loading),
            const SizedBox(height: 16),
            _filters(n, counts),
            const SizedBox(height: 14),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator(color: _orange)),
              )
            else if (async.hasError && !async.hasValue)
              _state(Icons.error_outline_rounded, 'Une erreur est survenue', 'Tire vers le bas pour réessayer.')
            else if (reviews.isEmpty)
              _state(Icons.chat_bubble_outline_rounded, 'Aucun avis pour le moment',
                  'Les retours de vos clients apparaîtront ici.')
            else if (filtered.isEmpty)
              _state(Icons.star_outline_rounded, 'Aucun avis ici', 'Aucun avis avec cette note.')
            else ...[
              ...rows.map(_card),
              if (_visible < filtered.length)
                GestureDetector(
                  onTap: () => setState(() => _visible += _pageSize),
                  child: Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(color: _orangeSoft, borderRadius: BorderRadius.circular(16)),
                    child: Center(
                      child: Text('Voir plus (${filtered.length - _visible} restants)',
                          style: AppTheme.body(size: 13, weight: FontWeight.w700, color: _orange)),
                    ),
                  ),
                ),
            ],
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
                        Text('Avis clients', style: AppTheme.body(size: 21, weight: FontWeight.w800, color: _ink)),
                        Text(
                          loading ? 'Chargement…' : '$n avis sur l’ensemble de vos produits',
                          style: AppTheme.body(size: 12, color: _mute),
                        ),
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

  Widget _stars(double v, double size) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          5,
          (i) => Icon(Icons.star_rounded, size: size, color: i < v.round() ? _star : _starOff),
        ),
      );

  // ═══════ Résumé ═══════
  Widget _summary(double avg, int n, Map<int, int> counts, bool loading) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: _shadow),
        child: Row(
          children: [
            SizedBox(
              width: 104,
              child: Column(
                children: [
                  Text(loading ? '—' : avg.toStringAsFixed(1),
                      style: AppTheme.body(size: 44, weight: FontWeight.w800, color: _ink)),
                  const SizedBox(height: 2),
                  _stars(avg, 16),
                  const SizedBox(height: 6),
                  Text('$n avis', style: AppTheme.body(size: 11.5, color: _mute)),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                children: [
                  for (var s = 5; s >= 1; s--)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3.5),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            child: Text('$s', style: AppTheme.body(size: 11.5, color: _mute)),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: n == 0 ? 0 : (counts[s] ?? 0) / n,
                                minHeight: 8,
                                backgroundColor: _tile,
                                valueColor: const AlwaysStoppedAnimation(_star),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 26,
                            child: Text('${counts[s] ?? 0}',
                                textAlign: TextAlign.right, style: AppTheme.body(size: 11, color: _faint)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );

  // ═══════ Filtres par note ═══════
  Widget _filters(int total, Map<int, int> counts) {
    final opts = <(int, String, int)>[
      (0, 'Tous', total),
      for (var s = 5; s >= 1; s--) (s, '$s ★', counts[s] ?? 0),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: opts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (key, label, count) = opts[i];
          final on = key == _starFilter;
          return GestureDetector(
            onTap: () => setState(() {
              _starFilter = key;
              _visible = _pageSize;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? _orange : Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: on ? _orange : _grid),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: AppTheme.body(
                          size: 12.5, weight: on ? FontWeight.w700 : FontWeight.w500, color: on ? Colors.white : _sub)),
                  const SizedBox(width: 6),
                  Text('$count',
                      style: AppTheme.body(
                          size: 11, weight: FontWeight.w700, color: on ? Colors.white : _faint)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════ Carte d'avis ═══════
  Widget _card(SupplierReviewItem r) {
    final name = r.reviewerName.isEmpty ? 'Client' : r.reviewerName;
    const ph = Icon(Icons.inventory_2_outlined, size: 16, color: _faint);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: _shadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Produit (touchable → fiche produit)
          GestureDetector(
            onTap: () => context.push('/produit/${r.productId}'),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                    child: (r.productImage != null && r.productImage!.isNotEmpty)
                        ? Image.network(r.productImage!,
                            width: 34, height: 34, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Center(child: ph))
                        : const Center(child: ph),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(r.productName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(size: 12.5, weight: FontWeight.w600, color: _ink)),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 18, color: _faint),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Auteur + note
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(color: _orange, shape: BoxShape.circle),
                child: Center(
                  child: Text(name[0].toUpperCase(),
                      style: AppTheme.body(size: 15, weight: FontWeight.w800, color: Colors.white)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(size: 13.5, weight: FontWeight.w700, color: _ink)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        _stars(r.rating, 13),
                        const SizedBox(width: 6),
                        Text('· ${_ago(r.createdAt)}', style: AppTheme.body(size: 11, color: _faint)),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: _orangeSoft, borderRadius: BorderRadius.circular(999)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, size: 13, color: _star),
                    const SizedBox(width: 3),
                    Text(r.rating.toStringAsFixed(1),
                        style: AppTheme.body(size: 12, weight: FontWeight.w700, color: _orange)),
                  ],
                ),
              ),
            ],
          ),

          // Commentaire
          if (r.comment.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(r.comment, style: AppTheme.body(size: 13, color: _sub).copyWith(height: 1.5)),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('Pas de commentaire.',
                  style: AppTheme.body(size: 12.5, color: _faint).copyWith(fontStyle: FontStyle.italic)),
            ),

          // Photos
          if (r.photos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: SizedBox(
                height: 62,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: r.photos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => _openPhoto(r.photos[i]),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(r.photos[i],
                          width: 62,
                          height: 62,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(width: 62, height: 62, color: _tile)),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openPhoto(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: InteractiveViewer(
          child: Center(child: Image.network(url, fit: BoxFit.contain)),
        ),
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