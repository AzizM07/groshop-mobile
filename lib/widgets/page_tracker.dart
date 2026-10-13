import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/analytics_api.dart';

/// Équivalent Flutter du hook `usePageTracking` : on enveloppe l'écran,
/// et le suivi se fait tout seul.
///
///   PageTracker(pageType: 'home', child: Scaffold(...))
///
/// 1. Pageview dès que la page est prête. Pour `product_detail`, on attend
///    [productId] ; pour `supplier_shop`, on attend [supplierId] (tant qu'ils
///    valent null, rien n'est envoyé — ils peuvent arriver après chargement).
/// 2. Temps passé, mesuré seulement sur les fiches produit : envoyé quand
///    l'app passe en arrière-plan ou quand on quitte l'écran (une seule fois,
///    ignoré sous 1 s), comme visibilitychange / pagehide / démontage côté web.
class PageTracker extends ConsumerStatefulWidget {
  final String pageType; // home | catalogue | search | product_detail | supplier_shop
  final String? supplierId;
  final String? productId;
  final Widget child;

  const PageTracker({
    super.key,
    required this.pageType,
    this.supplierId,
    this.productId,
    required this.child,
  });

  @override
  ConsumerState<PageTracker> createState() => _PageTrackerState();
}

class _PageTrackerState extends ConsumerState<PageTracker> with WidgetsBindingObserver {
  late final AnalyticsApi _analytics;
  final Stopwatch _watch = Stopwatch();
  String? _viewId;
  bool _sent = false;

  bool get _measuresDuration => widget.pageType == 'product_detail' && widget.productId != null;

  @override
  void initState() {
    super.initState();
    _analytics = ref.read(analyticsApiProvider); // gardé pour dispose()
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void didUpdateWidget(covariant PageTracker old) {
    super.didUpdateWidget(old);
    final changed = old.pageType != widget.pageType ||
        old.productId != widget.productId ||
        old.supplierId != widget.supplierId;
    if (!changed) return;
    // Nouvelle page (ou id enfin chargé) : on clôt l'ancienne vue, on en ouvre une.
    _flush(productId: old.productId, pageType: old.pageType);
    _start();
  }

  void _start() {
    if (widget.pageType == 'product_detail' && widget.productId == null) return;
    if (widget.pageType == 'supplier_shop' && widget.supplierId == null) return;
    final id = AnalyticsApi.newViewId();
    _viewId = id;
    _sent = false;
    _watch
      ..reset()
      ..start();
    _analytics.pageview(
      pageType: widget.pageType,
      clientViewId: id,
      supplierId: widget.supplierId,
      productId: widget.productId,
    );
  }

  /// Envoie le temps passé (une seule fois par vue, ≥ 1 s).
  void _flush({String? productId, String? pageType}) {
    final pt = pageType ?? widget.pageType;
    final pid = productId ?? widget.productId;
    if (pt != 'product_detail' || pid == null) return;
    final vid = _viewId;
    if (_sent || vid == null) return;
    final ms = _watch.elapsedMilliseconds;
    if (ms < 1000) return;
    _sent = true;
    _analytics.duration(vid, ms);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Bascule d'app / verrouillage → moment le plus fiable (comme visibilitychange)
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      if (_measuresDuration) _flush();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flush();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}