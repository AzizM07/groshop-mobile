// lib/features/orders/order_confirmation_screen.dart — GROSHOP mobile
// Port Flutter de OrderConfirmationPage.jsx.
// Reçoit la commande via GoRouter `extra` (juste après le POST /orders/create/)
// ou la recharge par id via /commande/:id/confirmation.
//
// Bannière : assets/images/order-confirmation-banner.jpg (même image que le web,
// à déclarer dans pubspec.yaml). Sans fichier → bandeau orange de secours.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/api/api_client.dart' show dioProvider;

const _orange = Color(0xFFFF7A00);
const _orangeSoft = Color(0xFFFFF1E3);
const _orangeText = Color(0xFFC25200);
const _ink = Color(0xFF14171A);
const _mute = Color(0xFF6B7280);
const _faint = Color(0xFF9CA3AF);
const _line = Color(0xFFE5E7EB);
const _bg = Color(0xFFF3F4F6);
const _green = Color(0xFF059669);

const _bannerAsset = 'assets/images/order-confirmation-banner.jpg';

const _paymentLabels = {
  'cod': 'Paiement à la livraison',
  'd17': 'D17',
  'flouci': 'Flouci',
  'sobflous': 'Sobflous',
  'virement': 'Virement bancaire',
};

const _months = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

double _num(Object? v) => double.tryParse('${v ?? 0}') ?? 0;

String _fmt(Object? v) {
  final s = _num(v).toStringAsFixed(2);
  final p = s.split('.');
  final b = StringBuffer();
  for (var i = 0; i < p[0].length; i++) {
    if (i > 0 && (p[0].length - i) % 3 == 0) b.write(' ');
    b.write(p[0][i]);
  }
  return '${b.toString()},${p[1]} TND';
}

String _fmtDate(Object? iso) {
  final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (d == null) return '';
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// Doit rester aligné avec shortRef() côté web (CommandesPage).
String _shortRef(Map<String, dynamic> o) {
  final ref = o['reference'];
  if (ref != null && '$ref'.isNotEmpty) return '$ref'.toUpperCase();
  final id = '${o['id'] ?? ''}';
  return (id.length > 8 ? id.substring(0, 8) : id).toUpperCase();
}

/// Statuts backend : pending, call_confirmed, in_production, shipped, delivered, cancelled
int _stepIndex(String? status) => switch (status) {
      'shipped' => 1,
      'delivered' => 2,
      _ => 0,
    };

const _steps = ['Confirmée', 'En transit', 'Livrée'];

// ═════════════════════════════════════════════════════════════════
class OrderConfirmationScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? order;
  final String? orderId;
  const OrderConfirmationScreen({super.key, this.order, this.orderId});

  @override
  ConsumerState<OrderConfirmationScreen> createState() => _OrderConfirmationScreenState();
}

class _OrderConfirmationScreenState extends ConsumerState<OrderConfirmationScreen> {
  Map<String, dynamic>? _order;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    if (_order == null && widget.orderId != null) _load(widget.orderId!);
    if (_order != null) HapticFeedback.mediumImpact();
  }

  Future<void> _load(String id) async {
    setState(() => _loading = true);
    try {
      final r = await ref.read(dioProvider).get('/orders/$id/');
      final code = r.statusCode ?? 0;
      if (code >= 200 && code < 300 && r.data is Map && mounted) {
        setState(() => _order = Map<String, dynamic>.from(r.data as Map));
      }
    } on DioException catch (_) {
      /* → « Commande introuvable » */
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pas de retour vers le checkout (la commande est déjà créée) : retour = accueil.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/');
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: _bg,
          body: _loading
              ? const Center(child: CircularProgressIndicator(color: _orange))
              : _order == null
                  ? _NotFound(onHome: () => context.go('/'))
                  : _Content(order: _order!),
        ),
      ),
    );
  }
}

// ─── Contenu ─────────────────────────────────────────────────────
class _Content extends StatelessWidget {
  final Map<String, dynamic> order;
  const _Content({required this.order});

  @override
  Widget build(BuildContext context) {
    final status = '${order['status'] ?? 'pending'}';
    final cancelled = status == 'cancelled';

    final items = <(Map<String, dynamic>, String)>[];
    for (final so in (order['sub_orders'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(so as Map);
      for (final it in (m['items'] as List? ?? const [])) {
        items.add((Map<String, dynamic>.from(it as Map), '${m['supplier_name'] ?? 'le fournisseur'}'));
      }
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _Banner(onClose: () => context.go('/'))),
        SliverToBoxAdapter(
          child: Transform.translate(
            offset: const Offset(0, -22),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 24, offset: Offset(0, 8))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  cancelled ? const _CancelledPill() : _Stepper(index: _stepIndex(status)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _FadeUp(delay: 50, child: _Header(cancelled: cancelled)),
                        const SizedBox(height: 18),
                        _FadeUp(delay: 120, child: _InfoBox(order: order)),
                        const SizedBox(height: 10),
                        _FadeUp(
                          delay: 200,
                          child: Column(children: [
                            for (var i = 0; i < items.length; i++)
                              _ItemRow(item: items[i].$1, supplier: items[i].$2, isLast: i == items.length - 1),
                          ]),
                        ),
                        _Totals(order: order),
                        const SizedBox(height: 18),
                        Container(height: 1, color: _line),
                        const SizedBox(height: 16),
                        Text(
                          'Merci d’avoir choisi GROSHOP pour vos besoins professionnels. '
                          'Pour toute question, notre équipe reste à un clic.',
                          textAlign: TextAlign.center,
                          style: AppTheme.body(size: 12.5, color: _mute).copyWith(height: 1.55),
                        ),
                        const SizedBox(height: 6),
                        Text('L’équipe GROSHOP',
                            textAlign: TextAlign.center,
                            style: AppTheme.body(size: 13, weight: FontWeight.w800, color: _ink)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 12 + MediaQuery.paddingOf(context).bottom)),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final VoidCallback onClose;
  const _Banner({required this.onClose});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final h = (MediaQuery.sizeOf(context).height * 0.28).clamp(170.0, 280.0);
    return SizedBox(
      height: h,
      child: Stack(fit: StackFit.expand, children: [
        Image.asset(
          _bannerAsset,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFF9A3D), Color(0xFFFF5E00)],
              ),
            ),
            alignment: Alignment.center,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.inventory_2_rounded, size: 46, color: Colors.white),
              const SizedBox(height: 8),
              Text('Merci pour votre commande',
                  style: AppTheme.body(size: 17, weight: FontWeight.w800, color: Colors.white)),
            ]),
          ),
        ),
        // Voile léger en haut pour lisibilité de la barre d'état + bouton fermer
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment(0, -0.2),
              colors: [Color(0x55000000), Color(0x00000000)],
            ),
          ),
        ),
        Positioned(
          top: top + 6,
          right: 8,
          child: Material(
            color: Colors.white.withOpacity(.9),
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded, size: 20, color: _ink),
              tooltip: 'Retour à l’accueil',
            ),
          ),
        ),
      ]),
    );
  }
}

// ─── Stepper animé ───────────────────────────────────────────────
class _Stepper extends StatefulWidget {
  final int index;
  const _Stepper({required this.index});
  @override
  State<_Stepper> createState() => _StepperState();
}

class _StepperState extends State<_Stepper> with TickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat();
  late final AnimationController _fill =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 800));

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _fill.forward();
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final idx = widget.index;
    final children = <Widget>[];
    for (var i = 0; i < _steps.length; i++) {
      final done = i < idx, active = i == idx;
      children.add(SizedBox(
        width: 70,
        child: Column(children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) {
              final t = _pulse.value;
              final wave = t < .5 ? t * 2 : (1 - t) * 2; // 0→1→0
              return Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: active
                      ? [BoxShadow(color: _orange.withOpacity(.35 * (1 - wave)), spreadRadius: 8 * wave)]
                      : null,
                ),
                child: child,
              );
            },
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done || active ? _orange : Colors.white,
                border: Border.all(color: done || active ? _orange : _line, width: 2),
              ),
              alignment: Alignment.center,
              child: done
                  ? const Icon(Icons.check_rounded, size: 17, color: Colors.white)
                  : Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: active ? Colors.white : _line),
                    ),
            ),
          ),
          const SizedBox(height: 7),
          Text(_steps[i],
              maxLines: 1,
              style: AppTheme.body(
                size: 11.5,
                weight: FontWeight.w700,
                color: done || active ? _orange : _faint,
              )),
        ]),
      ));
      if (i < _steps.length - 1) {
        children.add(Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 15),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Stack(children: [
                Container(height: 2, color: _line),
                if (i < idx)
                  AnimatedBuilder(
                    animation: _fill,
                    builder: (_, __) => FractionallySizedBox(
                      widthFactor: Curves.easeOut.transform(_fill.value),
                      child: Container(height: 2, color: _orange),
                    ),
                  ),
              ]),
            ),
          ),
        ));
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

class _CancelledPill extends StatelessWidget {
  const _CancelledPill();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 24, 0, 6),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(999)),
            child: Text('Commande annulée',
                style: AppTheme.body(size: 12.5, weight: FontWeight.w700, color: const Color(0xFF991B1B))),
          ),
        ),
      );
}

// ─── Titre + actions ─────────────────────────────────────────────
class _Header extends StatelessWidget {
  final bool cancelled;
  const _Header({required this.cancelled});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        cancelled ? 'Commande annulée' : 'Votre commande est confirmée !',
        textAlign: TextAlign.center,
        style: AppTheme.body(size: 20, weight: FontWeight.w800, color: _ink).copyWith(letterSpacing: -0.3),
      ),
      const SizedBox(height: 8),
      Text(
        cancelled
            ? 'Cette commande a été annulée. Contactez-nous si vous avez besoin d’aide.'
            : 'Nous vous tiendrons informé dès qu’elle sera prête à prendre la route.',
        textAlign: TextAlign.center,
        style: AppTheme.body(size: 13.5, color: _mute).copyWith(height: 1.5),
      ),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(
          child: SizedBox(
            height: 46,
            child: OutlinedButton(
              onPressed: () => context.go('/commandes'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _orange,
                side: const BorderSide(color: _orange, width: 1.6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Voir ma commande', style: AppTheme.body(size: 13.5, weight: FontWeight.w800, color: _orange)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 46,
            child: FilledButton(
              onPressed: () => context.go('/'),
              style: FilledButton.styleFrom(
                backgroundColor: _orange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Continuer', style: AppTheme.body(size: 13.5, weight: FontWeight.w800, color: Colors.white)),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      Text('Vos articles peuvent arriver en plusieurs colis selon le fournisseur.',
          textAlign: TextAlign.center, style: AppTheme.body(size: 11.5, color: _faint)),
    ]);
  }
}

// ─── Encart infos ────────────────────────────────────────────────
class _InfoBox extends StatelessWidget {
  final Map<String, dynamic> order;
  const _InfoBox({required this.order});

  @override
  Widget build(BuildContext context) {
    final pm = '${order['payment_method'] ?? ''}';
    Widget cell(String title, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(),
              style: AppTheme.body(size: 11, weight: FontWeight.w700, color: _ink).copyWith(letterSpacing: .3)),
          const SizedBox(height: 4),
          Text(value, style: AppTheme.body(size: 12.5, color: _mute).copyWith(height: 1.45)),
        ]);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Numéro de commande', style: AppTheme.body(size: 11.5, weight: FontWeight.w500, color: _mute)),
        const SizedBox(height: 3),
        Row(children: [
          Text('#${_shortRef(order)}',
              style: AppTheme.body(size: 16, weight: FontWeight.w800, color: _ink).copyWith(letterSpacing: .4)),
          const SizedBox(width: 6),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              Clipboard.setData(ClipboardData(text: _shortRef(order)));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Numéro copié')));
            },
            child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.copy_rounded, size: 15, color: _faint)),
          ),
        ]),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: cell('Date', _fmtDate(order['created_at']))),
          const SizedBox(width: 12),
          Expanded(child: cell('Paiement', _paymentLabels[pm] ?? pm)),
        ]),
        const SizedBox(height: 12),
        cell('Livraison', '${order['shipping_address'] ?? ''}'),
      ]),
    );
  }
}

// ─── Article ─────────────────────────────────────────────────────
class _ItemRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final String supplier;
  final bool isLast;
  const _ItemRow({required this.item, required this.supplier, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final img = '${item['product_image'] ?? ''}';
    final cat = '${item['product_category'] ?? ''}';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(border: isLast ? null : const Border(bottom: BorderSide(color: _line))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 68,
            height: 68,
            child: img.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: img,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const _ImgFallback(),
                  )
                : const _ImgFallback(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${item['product_name'] ?? ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(size: 13.5, weight: FontWeight.w700, color: _ink).copyWith(height: 1.3)),
            if (cat.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(cat, style: AppTheme.body(size: 11.5, color: _mute)),
            ],
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                text: 'Qté : ',
                style: AppTheme.body(size: 12, color: _mute),
                children: [
                  TextSpan(
                      text: '${item['quantity'] ?? ''}',
                      style: AppTheme.body(size: 12, weight: FontWeight.w700, color: _ink)),
                  TextSpan(text: '  ·  ${_fmt(item['unit_price_tnd'])} / unité'),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: _orangeSoft, borderRadius: BorderRadius.circular(999)),
              child: Text('Expédié par $supplier',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(size: 11, weight: FontWeight.w700, color: _orangeText)),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Text(_fmt(item['total_tnd']), style: AppTheme.body(size: 13.5, weight: FontWeight.w800, color: _ink)),
      ]),
    );
  }
}

class _ImgFallback extends StatelessWidget {
  const _ImgFallback();
  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Color(0xFFF4F5F7),
        child: Center(child: Icon(Icons.inventory_2_outlined, color: _faint)),
      );
}

// ─── Totaux ──────────────────────────────────────────────────────
class _Totals extends StatelessWidget {
  final Map<String, dynamic> order;
  const _Totals({required this.order});

  @override
  Widget build(BuildContext context) {
    final total = _num(order['total_tnd']);
    final discount = _num(order['discount_tnd']);
    Widget row(String l, String v, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(l, style: AppTheme.body(size: 13, color: _mute))),
            Text(v,
                style: AppTheme.body(
                    size: 13, weight: color == null ? FontWeight.w500 : FontWeight.w700, color: color ?? _mute)),
          ]),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(children: [
        row('Sous-total', _fmt(total + discount)),
        if (discount > 0) row('Remise', '− ${_fmt(discount)}', color: _orange),
        row('Livraison', 'Gratuite', color: _green),
        Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: _ink, width: 2))),
          child: Row(children: [
            Expanded(child: Text('Total', style: AppTheme.body(size: 17, weight: FontWeight.w800, color: _ink))),
            Text(_fmt(total), style: AppTheme.body(size: 17, weight: FontWeight.w800, color: _ink)),
          ]),
        ),
      ]),
    );
  }
}

// ─── Introuvable ─────────────────────────────────────────────────
class _NotFound extends StatelessWidget {
  final VoidCallback onHome;
  const _NotFound({required this.onHome});
  @override
  Widget build(BuildContext context) => SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(color: _orangeSoft, borderRadius: BorderRadius.circular(24)),
                child: const Icon(Icons.receipt_long_outlined, size: 40, color: _orange),
              ),
              const SizedBox(height: 16),
              Text('Commande introuvable', style: AppTheme.body(size: 17, weight: FontWeight.w800, color: _ink)),
              const SizedBox(height: 6),
              Text('Retrouvez vos commandes dans « Mes commandes ».',
                  textAlign: TextAlign.center, style: AppTheme.body(size: 13, color: _mute)),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onHome,
                style: FilledButton.styleFrom(
                  backgroundColor: _orange,
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Retour à l’accueil',
                    style: AppTheme.body(size: 13.5, weight: FontWeight.w700, color: Colors.white)),
              ),
            ]),
          ),
        ),
      );
}

// ─── Animation d'entrée (fade + slide) ───────────────────────────
class _FadeUp extends StatelessWidget {
  final int delay;
  final Widget child;
  const _FadeUp({required this.delay, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 450 + delay),
      curve: Interval(delay / (450 + delay), 1, curve: Curves.easeOut),
      builder: (_, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 6 * (1 - t)), child: c),
      ),
      child: child,
    );
  }
}