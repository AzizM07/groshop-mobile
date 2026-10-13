import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme.dart';
import '../../data/api/analytics_api.dart';
import '../../data/api/products_api.dart';
import '../../data/api/supplier_api.dart';
import '../../state/auth_provider.dart';
import '../../state/cart_provider.dart';
import '../../data/models/product.dart';
import '../../data/models/product_detail.dart';
import '../../widgets/page_tracker.dart';
import '../../widgets/product_card.dart';
import '../../widgets/native_ad_tile.dart'; // ⚠️ adapte le chemin si NativeAdTile est ailleurs
import '../messages/draft_chat_screen.dart';
import 'widgets/customization_sheet.dart';
import 'widgets/questions_section.dart';

// ── Palette lumineuse (orange GROSHOP + accents vifs) ──
const _orange = Color(0xFFFF7A00);
const _track = Color(0xFFF2F2EF);
const _orangeTint = Color(0xFFFFF6EE);
const _ink = Color(0xFF17171A);
const _sub = Color(0xFF3A3A40);
const _mute = Color(0xFF5C5C62);
const _faint = Color(0xFF8A8A90);
const _line = Color(0xFFEFEFEC);
const _border = Color(0xFFDEDEDA);
const _chipBg = Color(0xFFF5F6F8);
const _specsBg = Color(0xFFF7F7F5);
const _green = Color(0xFF12B84F);
const _greenDot = Color(0xFF22D05F);
const _blue = Color(0xFF1E88FF);
const _red = Color(0xFFFF3B30);
const _star = Color(0xFFFFB800);
const _pageBg = Color(0xFFF2F2EF);
/// Violet réservé à la personnalisation (comme le web).
const _purple = Color(0xFF6D3EF5);
const _purpleTint = Color(0xFFF3EEFF);
/// Espace gris entre deux sections blanches (bord à bord).
const _gap = 8.0;
/// Animation affichée à côté du nombre de ventes (carte boutique).
const _soldLottie = 'assets/lottie/sold.json';

/// Nombre de suggestions visé dans « Vous aimerez aussi » avant de passer à la source suivante.
const _moreTarget = 12;
const _moreMax = 20;

/// Rangées horizontales : largeur d'une carte produit.
const _cardW = 150.0;
/// Native ad insérée après chaque groupe de N produits dans les rangées.
const _adEvery = 3;
/// Ratio largeur / hauteur de la cellule pub (≈ hauteur d'une ProductCard).
const _adAspect = 0.62;

String _fmt(num n) {
  final s = n.toStringAsFixed(2);
  final p = s.split('.');
  final b = StringBuffer();
  for (var i = 0; i < p[0].length; i++) {
    if (i > 0 && (p[0].length - i) % 3 == 0) b.write(' ');
    b.write(p[0][i]);
  }
  return '${b.toString()},${p[1]}';
}

/// 5234 → « 5 000+ », 870 → « 870 » (comme AliExpress).
String _soldLabel(int n) {
  if (n >= 10000) return '${(n ~/ 10000) * 10} 000+';
  if (n >= 1000) return '${n ~/ 1000} 000+';
  return '$n';
}

class _InfoRow {
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;
  const _InfoRow(this.icon, this.title, this.detail, this.onTap);
}

class ProductScreen extends ConsumerStatefulWidget {
  final String id;
  const ProductScreen({super.key, required this.id});
  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  ProductDetail? _p;
  List<Product> _reco = const [];
  List<Product> _similar = const [];
  List<Review> _reviews = const [];
  bool _loading = true;
  String? _error;

  // Bannière de la boutique (lue depuis le profil public du fournisseur)
  String? _supplierBanner;

  // Vidéo produit (champs video_url / video_poster_url du détail)
  String? _videoUrl;
  String? _videoPoster;

  // « Vous aimerez aussi » : similaires → même boutique → tendances → recommandés
  List<Product> _more = const [];
  bool _moreLoading = true;

  int _qty = 1;
  final _page = PageController();
  int _imgIndex = 0; // index dans la galerie (vidéo comprise)
  String? _imgOverride;
  final Map<String, Variant> _selected = {};
  bool _wishlisted = false, _added = false, _busy = false;
  bool _contacting = false; // ouverture de la conversation en cours

  // Tracking des clics (la vue + le temps passé sont gérés par PageTracker)
  late final AnalyticsApi _analytics;

  // Sections dépliables
  bool _descOpen = false;
  bool _allReviews = false;
  final GlobalKey _reviewsKey = GlobalKey();

  // Défilement : bascule status bar claire/sombre au scroll.
  final ScrollController _scroll = ScrollController();
  bool _collapsed = false;
  double _collapseAt = 300;

  bool get _hasVideo => _videoUrl != null && _videoUrl!.isNotEmpty;

  // Personnalisation (mêmes règles que le web)
  bool get _canCustomize => _p!.allowCustomization && !_p!.priceLocked;
  bool get _isQuote => _canCustomize && _p!.customizationMode == 'quote';
  bool get _mustCustomize =>
      _canCustomize && (_isQuote || (_p!.customizationMode == 'fixed' && _p!.customizationRequired));
  int get _galleryCount => (_hasVideo ? 1 : 0) + (_p?.images.length ?? 0);

  @override
  void initState() {
    super.initState();
    _analytics = ref.read(analyticsApiProvider);
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _page.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final c = _scroll.offset > _collapseAt;
    if (c != _collapsed && mounted) setState(() => _collapsed = c);
  }

  Future<void> _load() async {
    final api = ref.read(productsApiProvider);
    try {
      final p = await api.detail(widget.id);
      final results = await Future.wait<Object>([
        api.similar(widget.id).catchError((_) => <Product>[]),
        api.recommendations(widget.id).catchError((_) => <Product>[]),
        api.reviews(widget.id).catchError((_) => <Review>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _p = p;
        _similar = results[0] as List<Product>;
        _reco = results[1] as List<Product>;
        _reviews = results[2] as List<Review>;
        _videoUrl = p.videoUrl;
        _videoPoster = p.videoPoster;
        _wishlisted = p.isFavorited;
        _qty = _moqOf(p);
        _selected.clear();
        for (final g in p.choiceGroups) {
          if (g.variants.isNotEmpty) _selected[g.id] = g.variants.first;
        }
        _loading = false;
      });
      _loadMore(p);
      _loadSupplierBanner(p);
    } catch (_) {
      if (mounted) setState(() { _error = 'Impossible de charger ce produit.'; _loading = false; });
    }
  }

  /// Récupère la bannière de vitrine du fournisseur (même source que sa page boutique).
  Future<void> _loadSupplierBanner(ProductDetail p) async {
    final slug = p.supplierSlug;
    if (slug == null || slug.isEmpty) return;
    try {
      final profile = await ref.read(supplierApiProvider).publicProfile(slug);
      final url = profile?.store.bannerUrl;
      if (mounted && url != null && url.isNotEmpty) setState(() => _supplierBanner = url);
    } catch (_) {}
  }

  /// Remplit « Vous aimerez aussi » source par source, sans doublons ni le produit courant.
  Future<void> _loadMore(ProductDetail p) async {
    final seen = <String>{p.id};
    final out = <Product>[];
    void addAll(List<Product> list) {
      for (final x in list) {
        if (out.length >= _moreMax) return;
        if (seen.add('${x.id}')) out.add(x);
      }
    }

    // 1) Produits similaires
    addAll(_similar);

    // 2) Même boutique
    final slug = p.supplierSlug;
    if (out.length < _moreTarget && slug != null && slug.isNotEmpty) {
      try {
        addAll(await ref.read(supplierApiProvider).publicProducts(slug, pageSize: 20));
      } catch (_) {}
    }

    // 3) Tendances, puis 4) recommandés
    final products = ref.read(productsApiProvider);
    if (out.length < _moreTarget) {
      try {
        addAll(await products.trending());
      } catch (_) {}
    }
    if (out.length < _moreTarget) {
      try {
        addAll(await products.recommended());
      } catch (_) {}
    }

    if (mounted) setState(() { _more = out; _moreLoading = false; });
  }

  // ── Logique prix (portée du web) ──
  List<PriceTier> get _tiers {
    final p = _p!;
    final ids = _selected.values.map((v) => v.id).toList()..sort();
    final key = ids.join('|');
    if (key.isNotEmpty) {
      for (final c in p.variantCombos) {
        if (c.key == key && c.priceTiers.isNotEmpty) return c.priceTiers;
      }
    }
    return p.priceTiers;
  }

  int _moqOf(ProductDetail p) {
    if (p.priceTiers.isNotEmpty) return p.priceTiers.first.minQty;
    return p.moq;
  }

  int get _moq => _tiers.isNotEmpty ? _tiers.first.minQty : _p!.moq;

  PriceTier? get _activeTier {
    final t = _tiers;
    if (t.isEmpty) return null;
    for (final tier in t) {
      if (_qty >= tier.minQty && (tier.maxQty == null || _qty <= tier.maxQty!)) return tier;
    }
    return t.first;
  }

  double get _unitPrice => _activeTier?.price ?? (_tiers.isNotEmpty ? _tiers.first.price : _p!.basePrice);
  double get _oldPrice {
    final t = _activeTier;
    if (t != null && t.oldPrice > 0) return t.oldPrice;
    return _p!.oldPrice;
  }

  int get _disc => _oldPrice > _unitPrice ? ((1 - _unitPrice / _oldPrice) * 100).round() : 0;
  bool get _qtyValid => _qty >= _moq;

  /// Unité du produit, « pièce » si le fournisseur ne l'a pas renseignée.
  String _unit(ProductDetail p) {
    final u = '${p.unit}'.trim();
    return (u.isEmpty || u == 'null') ? 'pièce' : u;
  }

  /// Unité au pluriel si besoin : « pièce » → « pièces ».
  String _u(ProductDetail p, int n) {
    final u = _unit(p);
    if (n <= 1 || u.isEmpty || u.endsWith('s') || u.endsWith('x')) return u;
    return '${u}s';
  }

  /// Libellé d'un palier : « 1 pièce », « 2–9 pièces », « ≥ 10 pièces ».
  String _tierLabel(ProductDetail p, PriceTier t) {
    final max = t.maxQty;
    if (max == null) return '≥ ${t.minQty} ${_u(p, t.minQty)}';
    if (max == t.minQty) return '${t.minQty} ${_u(p, t.minQty)}';
    return '${t.minQty}–$max ${_u(p, max)}';
  }

  /// Événement produit (fire-and-forget).
  void _trackEvent(String type) {
    final p = _p;
    if (p != null) _analytics.productEvent(p.id, type);
  }

  // Ouvre la vitrine du fournisseur — garde-fou si le slug manque.
  void _openSupplier(ProductDetail p) {
    final slug = p.supplierSlug;
    if (slug == null || slug.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Boutique du fournisseur indisponible.')),
      );
      return;
    }
    context.push('/fournisseur/$slug');
  }

  /// « Contacter la boutique » : ouvre le fil BROUILLON (comme le web).
  /// Rien n'est créé en base ici : si une conversation existe déjà pour ce
  /// produit, le brouillon bascule dessus ; sinon elle naît au 1er message.
  void _contactSupplier() {
    final p = _p;
    if (p == null) return;
    final slug = p.supplierSlug;
    if (slug == null || slug.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Boutique du fournisseur indisponible.')),
      );
      return;
    }
    final user = ref.read(authProvider).valueOrNull?.user;
    if (user == null) {
      context.push('/login');
      return;
    }
    _trackEvent('contact_supplier');
    final old = _oldPrice;
    context.push('/messages/new', extra: ChatDraft(
      supplierSlug: slug,
      productId: p.id,
      supplierName: p.supplierName,
      productName: p.name,
      productImage: _imgOverride ?? (p.images.isNotEmpty ? p.images.first : null),
      price: _unitPrice,
      oldPrice: old > _unitPrice ? old : null,
      disc: _disc,
    ));
  }

  /// « Personnaliser » / « Demander un devis » : ouvre la feuille de perso.
  /// Mode fixed → ligne ajoutée au panier ; mode quote → devis + messagerie.
  Future<void> _openCustomize() async {
    final p = _p;
    if (p == null) return;
    final user = ref.read(authProvider).valueOrNull?.user;
    if (user == null) {
      context.push('/login');
      return;
    }
    _trackEvent('open_customize');
    final added = await CustomizationSheet.show(
      context,
      product: p,
      variantId: _selected.values.isNotEmpty ? _selected.values.first.id : null,
      unitBasePrice: _unitPrice,
      initialQty: _qty,
    );
    if (added == true && mounted) {
      _trackEvent('add_to_cart_customized');
      setState(() => _added = true);
      Future.delayed(const Duration(seconds: 2), () { if (mounted) setState(() => _added = false); });
    }
  }

  /// Photos d'un avis en plein écran (swipe + zoom).
  void _openPhotos(List<String> photos, int index) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      useSafeArea: false,
      builder: (_) => _PhotoLightbox(photos: photos, initial: index),
    );
  }

  Future<void> _toggleWishlist() async {
    final next = !_wishlisted;
    setState(() => _wishlisted = next);
    try {
      final api = ref.read(productsApiProvider);
      next ? await api.addFavorite(_p!.id) : await api.removeFavorite(_p!.id);
    } catch (_) {
      if (mounted) setState(() => _wishlisted = !next);
    }
  }

  Future<void> _share() async {
    final url = 'https://groshop.tn/produit/${_p!.id}';
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lien du produit copié dans le presse-papier.')),
      );
    }
  }

  Future<void> _addToCart() async {
    if (!_qtyValid || !_p!.inStock || _busy) return;
    setState(() => _busy = true);
    try {
      final ok = await ref.read(cartProvider.notifier).add(_p!.id, _qty,
          variantId: _selected.values.isNotEmpty ? _selected.values.first.id : null);
      if (ok && mounted) {
        _trackEvent('add_to_cart');
        setState(() => _added = true);
        Future.delayed(const Duration(seconds: 2), () { if (mounted) setState(() => _added = false); });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Impossible d'ajouter au panier.")));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Aller à une case de la galerie. Si une image de variante était affichée,
  /// le PageView est recréé : on attend la frame suivante avant de sauter.
  void _goToSlide(int i) {
    setState(() {
      _imgOverride = null;
      _imgIndex = i;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_page.hasClients) _page.jumpToPage(i);
    });
  }

  /// Tap sur « X avis » → descend jusqu'à la section Avis (sous la barre épinglée).
  void _scrollToReviews() {
    final ctx = _reviewsKey.currentContext;
    if (ctx == null || !_scroll.hasClients) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final y = box.localToGlobal(Offset.zero).dy;
    final barBottom = MediaQuery.paddingOf(context).top + 56;
    final target = (_scroll.offset + y - barBottom - 8).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
  }

  /// PageTracker : pageview dès que le produit est chargé + temps passé
  /// (arrière-plan / sortie de la fiche), comme usePageTracking côté web.
  @override
  Widget build(BuildContext context) => PageTracker(
        pageType: 'product_detail',
        productId: _p?.id,
        child: _content(context),
      );

  Widget _content(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: _orange)));
    }
    if (_error != null || _p == null) {
      return Scaffold(
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error ?? 'Produit introuvable.', style: AppTheme.body(color: _mute)),
          TextButton(onPressed: () => context.go('/'), child: const Text('Retour à l’accueil')),
        ])),
      );
    }

    final p = _p!;
    final canCustomize = p.allowCustomization && !p.priceLocked;
    final isQuote = canCustomize && p.customizationMode == 'quote';
    final mustCustomize = canCustomize && (isQuote || (p.customizationMode == 'fixed' && p.customizationRequired));

    final topPad = MediaQuery.paddingOf(context).top;
    final w = MediaQuery.sizeOf(context).width;
    _collapseAt = (w - kToolbarHeight - topPad - 8).clamp(80.0, double.infinity);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (_collapsed ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light)
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: _pageBg,
        body: CustomScrollView(
          controller: _scroll,
          slivers: [
            _imageAppBar(context, p),
            if (_galleryCount > 1) SliverToBoxAdapter(child: _thumbs(p)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(children: [
                  _card(p),
                  _reassurance(p),
                  if (p.supplierName != null) _supplierCard(p),
                  if (p.specs.isNotEmpty) _specsBlock(p),
                  if (p.description.isNotEmpty) _descriptionBlock(p),
                  _reviewsSection(p),
                  _Fold(title: 'Questions et réponses',
                    child: QuestionsSection(productId: p.id)),
                  _moreSection(),
                  if (_reco.isNotEmpty) _row('Nos clients ont apprécié', _reco, adKey: 'reco-ad'),
                ]),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _bottomBar(p, isQuote: isQuote, mustCustomize: mustCustomize),
      ),
    );
  }

  // ── En-tête image plein cadre (style AliExpress) ──────────────────
  Widget _imageAppBar(BuildContext context, ProductDetail p) {
    final topPad = MediaQuery.paddingOf(context).top;
    final w = MediaQuery.sizeOf(context).width;
    final expanded = w; // hauteur de la galerie = largeur écran (carré plein cadre)
    const toolbar = 56.0;

    return SliverAppBar(
      pinned: true,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      toolbarHeight: toolbar,
      expandedHeight: expanded,
      flexibleSpace: LayoutBuilder(
        builder: (context, c) {
          final maxH = expanded;
          final minH = toolbar + topPad;
          final t = ((c.maxHeight - minH) / (maxH - minH)).clamp(0.0, 1.0);
          return _appBarContent(context, p, t, topPad);
        },
      ),
    );
  }

  String _counterLabel(ProductDetail p) {
    final onVideo = _hasVideo && _imgIndex == 0;
    final base = onVideo ? 'Vidéo · 1/$_galleryCount' : '${_imgIndex + 1} / $_galleryCount';
    return p.choiceGroups.isNotEmpty ? '$base  |  ${p.choiceGroups.first.name}' : base;
  }

  Widget _appBarContent(BuildContext context, ProductDetail p, double t, double topPad) {
    final showFloat = t > 0.5; // état déplié actif ?

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: _galleryFullBleed(p)),
        Positioned(
          top: 0, left: 0, right: 0, height: topPad + 64,
          child: IgnorePointer(
            child: Opacity(
              opacity: t,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x33000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: topPad + 6, left: 12, right: 12,
          child: Opacity(
            opacity: t,
            child: IgnorePointer(
              ignoring: !showFloat,
              child: Row(children: [
                _glassCircle(Icons.chevron_left_rounded, 26,
                    () => context.canPop() ? context.pop() : context.go('/')),
                const Spacer(),
                _glassCircle(Icons.search_rounded, 21, () => context.push('/recherche')),
                const SizedBox(width: 8),
                _glassCircle(Icons.share_outlined, 20, _share),
              ]),
            ),
          ),
        ),
        Positioned(
          bottom: 12, left: 12, right: 12,
          child: Opacity(
            opacity: t,
            child: IgnorePointer(
              ignoring: !showFloat,
              child: Row(children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: (_imgOverride == null && _galleryCount > 0)
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.92),
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 4, offset: Offset(0, 1))],
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              if (_hasVideo && _imgIndex == 0) ...[
                                const Icon(Icons.videocam_rounded, size: 14, color: _orange),
                                const SizedBox(width: 5),
                              ],
                              Flexible(
                                child: Text(
                                  _counterLabel(p),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.body(size: 12, weight: FontWeight.w600, color: _ink),
                                ),
                              ),
                            ]),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(width: 10),
                _glassCircle(
                  _wishlisted ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  21,
                  _toggleWishlist,
                  color: _wishlisted ? _orange : _ink,
                ),
              ]),
            ),
          ),
        ),
        Opacity(
          opacity: 1 - t,
          child: IgnorePointer(
            ignoring: showFloat,
            child: Container(
              color: Colors.white,
              padding: EdgeInsets.only(top: topPad),
              child: Align(alignment: Alignment.topCenter, child: _collapsedBar(context, p)),
            ),
          ),
        ),
      ],
    );
  }

  /// Galerie : vidéo en premier (si présente), puis les photos.
  Widget _galleryFullBleed(ProductDetail p) {
    if (_imgOverride != null) return _img(_imgOverride!);
    if (_galleryCount == 0) return const ColoredBox(color: Color(0xFFF4F4F2));
    final offset = _hasVideo ? 1 : 0;
    return PageView.builder(
      controller: _page,
      onPageChanged: (i) {
        setState(() => _imgIndex = i);
        _trackEvent('view_image');
      },
      itemCount: _galleryCount,
      itemBuilder: (_, i) {
        if (_hasVideo && i == 0) {
          return _VideoSlide(
            url: _videoUrl!,
            poster: _videoPoster ?? (p.images.isNotEmpty ? p.images.first : null),
            active: _imgIndex == 0 && !_collapsed,
          );
        }
        return _img(p.images[i - offset]);
      },
    );
  }

  /// Bouton rond blanc 44 px avec ombre douce (galerie).
  Widget _glassCircle(IconData icon, double size, VoidCallback onTap, {Color color = _ink}) => Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.92),
          shape: BoxShape.circle,
          boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 4, offset: Offset(0, 1))],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 44, height: 44, child: Icon(icon, size: size, color: color)),
          ),
        ),
      );

  Widget _collapsedBar(BuildContext context, ProductDetail p) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 12, 8),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: _ink),
            onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => context.push('/recherche'),
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: 40,
                padding: const EdgeInsets.only(left: 12, right: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _border),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text('Rechercher sur GROSHOP',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(size: 13.5, color: _faint)),
                  ),
                  Container(
                    width: 44, height: 30,
                    decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.search, size: 16, color: Colors.white),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(onTap: _share, child: const Icon(Icons.share_outlined, size: 20, color: _ink)),
        ]),
      );

  // ═══════════════════ ZONE SOUS L'IMAGE ═══════════════════
  // Nom → note · ventes · avis · stock → badges → prix (texte, sans carte)
  // → paliers orange → quantité + total → variantes.

  Widget _card(ProductDetail p) {
    final badges = _badges(p);
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p.name,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body(size: 17, weight: FontWeight.w600, color: _ink).copyWith(height: 1.35)),
        const SizedBox(height: 6),
        _ratingRow(p),
        if (badges.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: badges),
        ],
        if (p.priceLocked)
          _lockedPrice()
        else if (_isQuote)
          _quoteBlock()
        else
          _priceBlock(p),
        ...p.choiceGroups.map(_variantGroup),
        if (p.reference != null && p.reference!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Réf. ${p.reference}', style: AppTheme.body(size: 11.5, color: _faint)),
          ),
      ]),
    );
  }

  // ── Note · ventes · avis + stock à droite (une seule ligne) ──
  Widget _ratingRow(ProductDetail p) {
    final count = p.ratingCount > 0 ? p.ratingCount : _reviews.length;
    Widget dot() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text('·', style: AppTheme.body(size: 13, color: _mute)),
        );

    final left = <Widget>[];
    if (p.ratingAvg > 0) {
      left.addAll([
        Row(mainAxisSize: MainAxisSize.min, children: List.generate(5, (i) {
          final full = i < p.ratingAvg.floor();
          final half = !full && i < p.ratingAvg;
          return Icon(half ? Icons.star_half_rounded : Icons.star_rounded,
              size: 15, color: (full || half) ? _star : const Color(0xFFE5E7EB));
        })),
        const SizedBox(width: 5),
        Text(p.ratingAvg.toStringAsFixed(1), style: AppTheme.body(size: 13, weight: FontWeight.w700, color: _ink)),
      ]);
    }
    if (p.soldCount > 0) {
      if (left.isNotEmpty) left.add(dot());
      left.add(Text('${_soldLabel(p.soldCount)} vendus', style: AppTheme.body(size: 13, color: _mute)));
    }
    if (count > 0) {
      if (left.isNotEmpty) left.add(dot());
      left.add(GestureDetector(
        onTap: _scrollToReviews,
        child: Text('$count avis',
            style: AppTheme.body(size: 13, weight: FontWeight.w600, color: _blue)
                .copyWith(decoration: TextDecoration.underline, decorationColor: _blue)),
      ));
    }
    if (left.isEmpty) {
      left.add(Text('Nouveau produit', style: AppTheme.body(size: 13, color: _mute)));
    }

    return Row(children: [
      Expanded(child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 4, children: left)),
      const SizedBox(width: 8),
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(shape: BoxShape.circle, color: p.inStock ? _greenDot : _red),
      ),
      const SizedBox(width: 5),
      Text(p.inStock ? 'En stock' : 'Hors stock',
          style: AppTheme.body(size: 13, weight: FontWeight.w700, color: p.inStock ? _green : _red)),
    ]);
  }

  // ── Badges pleins et vifs (le stock est sur la ligne de note) ──
  List<Widget> _badges(ProductDetail p) {
    final b = <Widget>[];
    if (p.badgeChoice) b.add(_badge('Choice', const Color(0xFFFFCE00), _ink));
    if (_hasVideo) b.add(_badge('▶ Vidéo', const Color(0xFF8B5CF6), Colors.white));
    if (p.priceLocked) b.add(_badge('Prix réservé', const Color(0xFF00B8D9), Colors.white));
    if (_canCustomize) b.add(_badge(_isQuote ? 'Sur devis' : 'Personnalisable', _purple, Colors.white));
    return b;
  }

  Widget _badge(String t, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(t, style: AppTheme.body(size: 11, weight: FontWeight.w700, color: fg)),
      );

  // ── Prix : texte sur fond blanc, tag -X% orange, paliers, quantité ──
  Widget _priceBlock(ProductDetail p) {
    final t = _tiers;
    final promo = _oldPrice > _unitPrice;
    final saving = _oldPrice - _unitPrice;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(_fmt(_unitPrice),
                  style: AppTheme.body(size: 28, weight: FontWeight.w800, color: _ink)
                      .copyWith(letterSpacing: -0.5, height: 1.1)),
              const SizedBox(width: 5),
              Text('TND', style: AppTheme.body(size: 14, weight: FontWeight.w700, color: _ink)),
              const SizedBox(width: 5),
              Text('/ ${_unit(p)}', style: AppTheme.body(size: 14, color: _mute)),
              if (promo) ...[
                const SizedBox(width: 10),
                Text(_fmt(_oldPrice),
                    style: AppTheme.body(size: 13, color: _faint)
                        .copyWith(decoration: TextDecoration.lineThrough, decorationColor: _faint)),
                if (_disc > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(4)),
                    child: Text('-$_disc%',
                        style: AppTheme.body(size: 12, weight: FontWeight.w800, color: Colors.white)),
                  ),
                ],
              ],
            ],
          ),
        ),
        if (promo && saving > 0) ...[
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(style: AppTheme.body(size: 12.5, weight: FontWeight.w500, color: _mute), children: [
              const TextSpan(text: 'Promo grossiste · vous économisez '),
              TextSpan(text: '${_fmt(saving)} TND',
                  style: AppTheme.body(size: 12.5, weight: FontWeight.w800, color: _orange)),
              TextSpan(text: ' par ${_unit(p)}'),
            ]),
          ),
        ],
        if (t.length > 1) ...[
          const SizedBox(height: 14),
          _tierRow(p, t),
        ],
        const SizedBox(height: 14),
        _qtyRow(p),
        const SizedBox(height: 6),
        Text('Commande minimale : $_moq ${_u(p, _moq)}',
            style: AppTheme.body(
                size: 12,
                weight: _qtyValid ? FontWeight.w400 : FontWeight.w700,
                color: _qtyValid ? _faint : _orange)),
        if (_mustCustomize) ...[
          const SizedBox(height: 10),
          _customNote(p),
        ],
        if (_canCustomize && !_mustCustomize) ...[
          const SizedBox(height: 12),
          _customizeButton(p),
        ],
      ]),
    );
  }

  String _extraLabel(ProductDetail p) =>
      p.customizationExtra > 0 ? ' (+${_fmt(p.customizationExtra)} TND/${_unit(p)})' : '';

  /// Personnalisation obligatoire (mode fixed + required).
  Widget _customNote(ProductDetail p) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: _purpleTint, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Icon(Icons.auto_awesome, size: 14, color: _purple),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Personnalisation obligatoire${_extraLabel(p)}',
                style: AppTheme.body(size: 12.5, weight: FontWeight.w600, color: _purple)),
          ),
        ]),
      );

  /// Personnalisation optionnelle : bouton secondaire violet.
  Widget _customizeButton(ProductDetail p) => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _openCustomize,
          icon: const Icon(Icons.auto_awesome, size: 16, color: _purple),
          label: Text('Personnaliser${_extraLabel(p)}',
              style: AppTheme.body(size: 14, weight: FontWeight.w700, color: _purple)),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 46),
            side: const BorderSide(color: _purple, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            foregroundColor: _purple,
          ),
        ),
      );

  /// Mode devis : pas de prix ni de quantité, le fournisseur cote à la demande.
  Widget _quoteBlock() => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _purpleTint, borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.request_quote_outlined, size: 20, color: _purple),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Produit sur devis', style: AppTheme.body(size: 14.5, weight: FontWeight.w800, color: _purple)),
              const SizedBox(height: 3),
              Text('Décrivez votre personnalisation : la boutique vous enverra un prix dans la messagerie.',
                  style: AppTheme.body(size: 12.5, color: _sub).copyWith(height: 1.45)),
            ]),
          ),
        ]),
      );

  /// Paliers en sélecteur segmenté : piste grise, palier actif = carte blanche surélevée.
  /// Même largeur si ≤ 4, sinon la piste défile horizontalement.
  Widget _tierRow(ProductDetail p, List<PriceTier> t) {
    final Widget row = t.length <= 4
        ? Row(children: [
            for (var i = 0; i < t.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(child: _tierChip(p, t[i])),
            ],
          ])
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (var i = 0; i < t.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                SizedBox(width: 100, child: _tierChip(p, t[i])),
              ],
            ]),
          );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: _track, borderRadius: BorderRadius.circular(12)),
      child: row,
    );
  }

  Widget _tierChip(ProductDetail p, PriceTier tier) {
    final on = tier == _activeTier;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _qty = tier.minQty);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: on ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: on
              ? const [BoxShadow(color: Color(0x1F000000), blurRadius: 3, offset: Offset(0, 1))]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('${_fmt(tier.price)} TND',
                  style: AppTheme.body(size: 14.5, weight: FontWeight.w800, color: on ? _ink : _mute)),
            ),
            const SizedBox(height: 2),
            Text(_tierLabel(p, tier),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(size: 11.5, weight: FontWeight.w600, color: on ? _ink : _faint)),
          ],
        ),
      ),
    );
  }

  /// Quantité : libellé | − qté + | total à droite.
  Widget _qtyRow(ProductDetail p) {
    final total = _qty * _unitPrice;
    return Row(children: [
      Text('Quantité', style: AppTheme.body(size: 14, weight: FontWeight.w600, color: _ink)),
      const SizedBox(width: 12),
      Container(
        decoration: BoxDecoration(
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _stepBtn(Icons.remove_rounded, enabled: _qty > _moq,
              onTap: () => setState(() => _qty = (_qty - 1).clamp(_moq, 1 << 30))),
          SizedBox(
            width: 36,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('$_qty', textAlign: TextAlign.center,
                  style: AppTheme.body(size: 15, weight: FontWeight.w700, color: _ink)),
            ),
          ),
          _stepBtn(Icons.add_rounded, enabled: true, onTap: () => setState(() => _qty += 1)),
        ]),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Align(
          alignment: Alignment.centerRight,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              Text('Total', style: AppTheme.body(size: 12, color: _mute)),
              Text('${_fmt(total)} TND', style: AppTheme.body(size: 17, weight: FontWeight.w800, color: _ink)),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _stepBtn(IconData icon, {required bool enabled, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              onTap();
            }
          : null,
      child: SizedBox(
        width: 44,
        height: 40,
        child: Icon(icon, size: 20, color: enabled ? _ink : _border),
      ),
    );
  }

  /// Prix masqué (réservé aux boutiques vérifiées).
  Widget _lockedPrice() => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFE6FAFF), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.lock_outline_rounded, size: 18, color: Color(0xFF00B8D9)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Prix sur devis — contactez le fournisseur pour connaître ses tarifs.',
                style: AppTheme.body(size: 13, color: const Color(0xFF007A94))),
          ),
        ]),
      );

  // ── Variantes : vignettes 52 px (images) ou pastilles plates (texte) ──
  Widget _variantGroup(ChoiceGroup g) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text.rich(
              TextSpan(text: '${g.name} : ',
                  style: AppTheme.body(size: 14, weight: FontWeight.w700, color: _ink),
                  children: [TextSpan(text: _selected[g.id]?.name ?? '', style: AppTheme.body(size: 14, color: _sub))]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (g.variants.length > 1)
            Text('${g.variants.length} options', style: AppTheme.body(size: 12, color: _mute)),
        ]),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: g.variants.map((v) {
            final on = _selected[g.id]?.id == v.id;
            void pick() => setState(() {
                  HapticFeedback.selectionClick();
                  _trackEvent('select_variant');
                  _selected[g.id] = v;
                  if (v.imageUrl != null) _imgOverride = v.imageUrl;
                });
            if (v.imageUrl != null) {
              return GestureDetector(
                onTap: pick,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.only(right: 8),
                  width: 54,
                  height: 54,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: on ? _orange : _border, width: on ? 1.8 : 1),
                  ),
                  child: ClipRRect(borderRadius: BorderRadius.circular(7), child: _img(v.imageUrl!)),
                ),
              );
            }
            return GestureDetector(
              onTap: pick,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: on ? _orangeTint : _chipBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: on ? _orange : Colors.transparent, width: 1.5),
                ),
                child: Text(v.name,
                    style: AppTheme.body(size: 13, weight: on ? FontWeight.w700 : FontWeight.w500,
                        color: on ? _orange : _sub)),
              ),
            );
          }).toList()),
        ),
      ]),
    );
  }

  // ═══════════════════ SECTIONS ═══════════════════

  Widget _section({required Widget child, Key? key, EdgeInsets padding = const EdgeInsets.fromLTRB(16, 14, 16, 16)}) =>
      Container(
        key: key,
        width: double.infinity,
        margin: const EdgeInsets.only(top: _gap),
        padding: padding,
        color: Colors.white,
        child: child,
      );

  Widget _sectionHeader(String title, {String? action, VoidCallback? onAction}) => Row(children: [
        Expanded(child: Text(title, style: AppTheme.body(size: 16, weight: FontWeight.w700, color: _ink))),
        if (action != null && onAction != null) _link(action, onAction),
      ]);

  Widget _link(String label, VoidCallback onTap, {Color color = _blue}) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(label, style: AppTheme.body(size: 13, weight: FontWeight.w700, color: color)),
        ),
      );

  Widget _img(String url) => CachedNetworkImage(
        imageUrl: url, fit: BoxFit.cover, width: double.infinity, height: double.infinity,
        placeholder: (_, __) => const ColoredBox(color: Color(0xFFF4F4F2)),
        errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFFF4F4F2),
            child: Icon(Icons.image_outlined, color: _faint)),
      );

  Widget _thumbs(ProductDetail p) {
    final offset = _hasVideo ? 1 : 0;
    return Container(
      height: 68, color: Colors.white,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        itemCount: _galleryCount,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final on = _imgOverride == null && i == _imgIndex;
          final isVideo = _hasVideo && i == 0;
          final poster = _videoPoster ?? (p.images.isNotEmpty ? p.images.first : null);
          return GestureDetector(
            onTap: () => _goToSlide(i),
            child: Container(
              width: 56, height: 56,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: on ? _orange : Colors.transparent, width: 2)),
              clipBehavior: Clip.antiAlias,
              child: isVideo
                  ? Stack(fit: StackFit.expand, children: [
                      if (poster != null) _img(poster) else const ColoredBox(color: Color(0xFF2C2C2A)),
                      const ColoredBox(color: Color(0x59000000)),
                      const Center(child: Icon(Icons.play_arrow_rounded, size: 26, color: Colors.white)),
                    ])
                  : _img(p.images[i - offset]),
            ),
          );
        },
      ),
    );
  }

  // ── Réassurance : livraison, retours, paiement (lignes + chevron) ──
  Widget _reassurance(ProductDetail p) {
    var delivery = 'sous ${p.deliveryDays} jour(s)';
    if (!p.priceLocked) {
      delivery += p.shippingPrice > 0 ? ' · ${_fmt(p.shippingPrice)} TND' : ' · offerte';
    }

    final rows = [
      _InfoRow(Icons.local_shipping_outlined, 'Livraison', delivery, () => _infoSheet('Livraison', [
            _iconRow(Icons.local_shipping_outlined, 'Livré par GROSHOP'),
            _iconRow(Icons.event_outlined, 'Livraison estimée sous ${p.deliveryDays} jour(s)'),
            if (!p.priceLocked)
              _iconRow(p.shippingPrice > 0 ? Icons.payments_outlined : Icons.card_giftcard_outlined,
                  p.shippingPrice > 0 ? 'Frais de livraison : ${_fmt(p.shippingPrice)} TND' : 'Livraison offerte'),
            _iconRow(Icons.map_outlined, 'Livraison suivie partout en Tunisie'),
          ])),
      _InfoRow(Icons.autorenew_rounded, 'Retours', 'acceptés sous 7 jours', () => _infoSheet('Retours', [
            _iconRow(Icons.replay_outlined, 'Retours acceptés sous 7 jours'),
          ])),
      _InfoRow(Icons.verified_user_outlined, 'Paiement sécurisé', '100% sécurisé', () => _infoSheet('Paiement', [
            _iconRow(Icons.verified_user_outlined, 'Paiement 100% sécurisé'),
          ])),
    ];

    return _section(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++)
          InkWell(
            onTap: rows[i].onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: i < rows.length - 1 ? const Border(bottom: BorderSide(color: _line)) : null,
              ),
              child: Row(children: [
                Icon(rows[i].icon, size: 20, color: _green),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: rows[i].title,
                          style: AppTheme.body(size: 13.5, weight: FontWeight.w700, color: _ink)),
                      TextSpan(text: ' · ${rows[i].detail}', style: AppTheme.body(size: 13.5, color: _mute)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 20, color: _faint),
              ]),
            ),
          ),
      ]),
    );
  }

  void _infoSheet(String title, List<Widget> rows) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppTheme.body(size: 16, weight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 14),
            ...rows,
          ]),
        ),
      ),
    );
  }

  Widget _iconRow(IconData i, String t, {Color color = _green}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(i, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(t, style: AppTheme.body(size: 13.5, color: _sub))),
        ]),
      );

  // ── Carte boutique ──
  // Avec bannière : bande pleine largeur (bord à bord, 0 marge gauche/droite)
  // dont le fond est la bannière de la boutique, voile sombre, textes blancs.
  // Sans bannière : bande blanche classique.
  // Actions GROSHOP : uniquement « Voir la boutique » et « Contacter la boutique ».
  Widget _supplierCard(ProductDetail p) {
    final name = p.supplierName ?? '';
    final ratingCount = p.supplierRatingCount ?? 0;
    final hasRating = p.supplierRating != null && ratingCount > 0;
    final place = <String?>[p.supplierCity, p.supplierWilaya]
        .where((e) => e != null && e.trim().isNotEmpty)
        .map((e) => e!.trim())
        .toSet()
        .join(', ');

    final banner = _supplierBanner;
    final hasBanner = banner != null && banner.trim().isNotEmpty;

    final fg = hasBanner ? Colors.white : _ink;
    final fgSub = hasBanner ? Colors.white.withOpacity(0.88) : _mute;
    final linkColor = hasBanner ? Colors.white : _blue;
    const textShadow = [Shadow(color: Color(0x66000000), blurRadius: 6)];

    TextStyle st(double size, FontWeight w, Color c) =>
        AppTheme.body(size: size, weight: w, color: c).copyWith(shadows: hasBanner ? textShadow : null);

    const logo = 46.0;

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: logo, height: logo,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: hasBanner ? Colors.white : _line, width: hasBanner ? 2 : 1),
              boxShadow: hasBanner
                  ? const [BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 2))]
                  : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: p.supplierLogo != null && p.supplierLogo!.isNotEmpty
                ? _img(p.supplierLogo!)
                : Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: AppTheme.body(size: 18, weight: FontWeight.w600, color: _orange))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onTap: () => _openSupplier(p),
              behavior: HitTestBehavior.opaque,
              child: Row(children: [
                Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: st(15.5, FontWeight.w800, fg))),
                if (p.supplierVerified)
                  Padding(
                    padding: const EdgeInsets.only(left: 5),
                    child: Icon(Icons.verified_rounded, size: 16, color: hasBanner ? const Color(0xFF5CB8FF) : _blue),
                  ),
                Icon(Icons.chevron_right_rounded, size: 18, color: fg),
              ]),
            ),
            if (place.isNotEmpty) ...[
              const SizedBox(height: 3),
              Row(children: [
                Icon(Icons.location_on_outlined, size: 12, color: fgSub),
                const SizedBox(width: 2),
                Flexible(child: Text(place, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: st(12, FontWeight.w500, fgSub))),
              ]),
            ],
          ])),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (hasRating) ...[
              const Icon(Icons.star_rounded, size: 15, color: _star),
              const SizedBox(width: 4),
              Text(p.supplierRating!.toStringAsFixed(1), style: st(12.5, FontWeight.w700, fg)),
              Text(' ($ratingCount)', style: st(12.5, FontWeight.w400, fgSub)),
            ] else
              Text('Nouveau vendeur', style: st(12.5, FontWeight.w600, fgSub)),
          ]),
          if (p.soldCount > 0)
            Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Lottie.asset(
                  _soldLottie,
                  repeat: true,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.local_fire_department, size: 15, color: _orange),
                ),
              ),
              const SizedBox(width: 4),
              Text('${_soldLabel(p.soldCount)} vendus', style: st(12.5, FontWeight.w500, hasBanner ? fg : _sub)),
            ]),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _link('Voir la boutique ›', () => _openSupplier(p), color: linkColor),
          const SizedBox(width: 20),
          _link(_contacting ? 'Ouverture…' : 'Contacter la boutique ›', _contactSupplier, color: linkColor),
        ]),
      ]),
    );

    if (!hasBanner) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: _gap),
        color: Colors.white,
        child: content,
      );
    }

    // Bord à bord : aucune marge ni coin arrondi, la bannière prend toute la largeur.
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: _gap),
      child: Stack(children: [
        // Bannière de la boutique en fond
        Positioned.fill(child: _img(banner!)),
        // Voile : léger en haut, plus dense en bas pour la lisibilité des textes
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x4D000000), Color(0x99000000), Color(0xCC000000)],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),
        content,
      ]),
    );
  }

  // ── Caractéristiques : « Clé : valeur », grille 2 colonnes (1 gauche, 2 droite, 3 gauche…) ──
  Widget _specsBlock(ProductDetail p) {
    final shown = p.specs.take(4).toList();
    final rows = <Widget>[];
    for (var i = 0; i < shown.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 12));
      rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _specCell(shown[i].k, shown[i].v)),
        const SizedBox(width: 16),
        Expanded(child: i + 1 < shown.length ? _specCell(shown[i + 1].k, shown[i + 1].v) : const SizedBox()),
      ]));
    }

    return _section(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _sectionHeader('Caractéristiques',
            action: p.specs.length > 4 ? 'Tout voir ›' : null,
            onAction: () {
              _trackEvent('view_description');
              _specsSheet(p);
            }),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: _specsBg, borderRadius: BorderRadius.circular(10)),
          child: Column(children: rows),
        ),
      ]),
    );
  }

  /// Une caractéristique sur une ligne : « Matière : Plastique ».
  Widget _specCell(String label, String value) => Text.rich(
        TextSpan(children: [
          TextSpan(text: '$label : ', style: AppTheme.body(size: 13, color: _mute)),
          TextSpan(text: value, style: AppTheme.body(size: 13, weight: FontWeight.w700, color: _ink)),
        ]),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(height: 1.35),
      );

  void _specsSheet(ProductDetail p) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Caractéristiques', style: AppTheme.body(size: 16, weight: FontWeight.w800, color: _ink)),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Container(
                    decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(12)),
                    clipBehavior: Clip.antiAlias,
                    child: Column(children: List.generate(p.specs.length, (i) {
                      final s = p.specs[i];
                      return Container(
                        color: i.isOdd ? _specsBg : Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(child: Text(s.k, style: AppTheme.body(size: 13, color: _mute))),
                          const SizedBox(width: 10),
                          Expanded(child: Text(s.v, textAlign: TextAlign.right,
                              style: AppTheme.body(size: 13, weight: FontWeight.w700, color: _ink))),
                        ]),
                      );
                    })),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Description : 3 lignes + « Lire la suite » ──
  Widget _descriptionBlock(ProductDetail p) {
    final style = AppTheme.body(size: 13.5, color: _sub).copyWith(height: 1.55);
    return _section(
      child: LayoutBuilder(builder: (context, c) {
        final tp = TextPainter(
          text: TextSpan(text: p.description, style: style),
          maxLines: 3,
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: c.maxWidth);
        final overflows = tp.didExceedMaxLines;
        tp.dispose();

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Description', style: AppTheme.body(size: 16, weight: FontWeight.w700, color: _ink)),
          const SizedBox(height: 8),
          Text(p.description,
              maxLines: _descOpen ? null : 3,
              overflow: _descOpen ? TextOverflow.visible : TextOverflow.ellipsis,
              style: style),
          if (overflows) ...[
            const SizedBox(height: 4),
            _link(_descOpen ? 'Réduire' : 'Lire la suite ›', () {
              if (!_descOpen) _trackEvent('view_description');
              setState(() => _descOpen = !_descOpen);
            }),
          ],
        ]);
      }),
    );
  }

  // ── Avis : note globale + 3 avis, « Voir tous » déplie la liste ──
  Widget _stars(int n, double size) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) => Icon(
              i < n ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: _star,
            )),
      );

  Widget _reviewsSection(ProductDetail p) {
    final count = p.ratingCount > 0 ? p.ratingCount : _reviews.length;
    final shown = _allReviews ? _reviews : _reviews.take(3).toList();

    return _section(
      key: _reviewsKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Avis', style: AppTheme.body(size: 16, weight: FontWeight.w700, color: _ink)),
        const SizedBox(height: 12),
        if (_reviews.isEmpty && p.ratingAvg <= 0)
          Text('Aucun avis pour le moment.', style: AppTheme.body(size: 13.5, color: _mute))
        else ...[
          if (p.ratingAvg > 0)
            Row(children: [
              Text(p.ratingAvg.toStringAsFixed(1),
                  style: AppTheme.body(size: 28, weight: FontWeight.w800, color: _ink)),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _stars(p.ratingAvg.round(), 15),
                Text('$count avis', style: AppTheme.body(size: 12, color: _mute)),
              ]),
            ]),
          for (final r in shown)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.only(top: 10),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _line))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(r.reviewerName, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(size: 12.5, weight: FontWeight.w700, color: _ink)),
                  ),
                  const SizedBox(width: 6),
                  _stars(r.rating.round(), 13),
                ]),
                if (r.comment.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(r.comment, style: AppTheme.body(size: 13.5, color: _ink).copyWith(height: 1.45)),
                  ),
                if (r.photos.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      for (var i = 0; i < r.photos.length; i++)
                        GestureDetector(
                          onTap: () => _openPhotos(r.photos, i),
                          child: Container(
                            width: 64, height: 64,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: _line),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: _img(r.photos[i]),
                          ),
                        ),
                    ]),
                  ),
              ]),
            ),
          if (_reviews.length > 3) ...[
            const SizedBox(height: 8),
            _link(_allReviews ? 'Voir moins' : 'Voir tous les avis (${_reviews.length}) ›',
                () => setState(() => _allReviews = !_allReviews)),
          ],
        ],
      ]),
    );
  }

  // ── « Vous aimerez aussi » : similaires puis même boutique, puis le reste ──
  Widget _moreSection() {
    if (!_moreLoading && _more.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: _gap),
      padding: const EdgeInsets.symmetric(vertical: 16),
      color: Colors.white,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Vous aimerez aussi', style: AppTheme.body(size: 16, weight: FontWeight.w700, color: _ink)),
            const SizedBox(height: 2),
            Text('Produits similaires et de la même boutique',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTheme.body(size: 12, color: _mute)),
          ]),
        ),
        const SizedBox(height: 12),
        if (_moreLoading)
          const SizedBox(height: 160, child: Center(child: CircularProgressIndicator(color: _orange)))
        else
          _hScroll(_more, adKey: 'more-ad'),
      ]),
    );
  }

  /// Rangée horizontale sans hauteur imposée → plus d'overflow selon la taille des cartes.
  /// Une native ad est insérée après chaque groupe de [_adEvery] produits
  /// (jamais en fin de rangée). Si aucune pub n'est dispo, la cellule se referme.
  Widget _hScroll(List<Product> items, {required String adKey}) {
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      children.add(Padding(
        padding: EdgeInsets.only(left: i == 0 ? 0 : 12),
        child: SizedBox(width: _cardW, child: ProductCard(product: items[i])),
      ));
      final endOfGroup = (i + 1) % _adEvery == 0;
      final notLast = i < items.length - 1;
      if (endOfGroup && notLast) {
        children.add(NativeAdTile(
          key: ValueKey('$adKey-$i'),
          width: _cardW,
          height: _cardW / _adAspect,
          margin: const EdgeInsets.only(left: 12),
        ));
      }
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _row(String title, List<Product> items, {required String adKey, bool sponsored = false}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: _gap),
        padding: const EdgeInsets.symmetric(vertical: 16),
        color: Colors.white,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(title, style: AppTheme.body(size: 16, weight: FontWeight.w700, color: _ink)),
          ),
          const SizedBox(height: 12),
          _hScroll(items, adKey: adKey),
          if (sponsored) Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Sponsorisé', style: AppTheme.body(size: 11, color: _faint))),
        ]),
      );

  // ── Barre d'action sticky ──
  Widget _bottomBar(ProductDetail p, {required bool isQuote, required bool mustCustomize}) {
    Widget bar(List<Widget> children) => Container(
          decoration: const BoxDecoration(color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFEAEAE6)))),
          child: SafeArea(top: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(children: children),
          )),
        );

    if (p.priceLocked) {
      return bar([Expanded(child: _mainBtn(_contacting ? 'Ouverture…' : 'Contacter la boutique',
          Icons.chat_bubble_outline, _contactSupplier, enabled: !_contacting))]);
    }
    if (mustCustomize) {
      return bar([
        _contactIcon(),
        const SizedBox(width: 10),
        Expanded(child: _mainBtn(isQuote ? 'Demander un devis' : 'Personnaliser', Icons.auto_awesome, _openCustomize)),
      ]);
    }

    final String label;
    if (!p.inStock) {
      label = 'Indisponible';
    } else if (_busy) {
      label = 'Ajout…';
    } else if (_added) {
      label = '✓ Ajouté';
    } else {
      label = 'Ajouter au panier';
    }

    return bar([
      _contactIcon(),
      const SizedBox(width: 10),
      Expanded(child: _mainBtn(
        label,
        Icons.shopping_cart_outlined,
        _addToCart,
        enabled: p.inStock && _qtyValid && !_busy,
        color: _added ? _green : (!p.inStock ? const Color(0xFFB9BEC7) : _orange),
      )),
    ]);
  }

  Widget _contactIcon() => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _contacting ? null : _contactSupplier,
          child: SizedBox(
            width: 46, height: 46,
            child: _contacting
                ? const Center(
                    child: SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _orange)))
                : const Icon(Icons.chat_bubble_outline_rounded, size: 22, color: _ink),
          ),
        ),
      );

  Widget _mainBtn(String t, IconData i, VoidCallback onTap, {bool enabled = true, Color color = _orange}) => GestureDetector(
        onTap: enabled ? onTap : null,
        child: Opacity(opacity: enabled ? 1 : 0.6, child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(i, size: 19, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(t, maxLines: 1,
                    style: AppTheme.body(size: 16, weight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ]),
        )),
      );
}

// ═══════ Case vidéo de la galerie ═══════
/// Affiche l'affiche (poster) avec un bouton lecture. Le lecteur ne se charge
/// qu'au premier tap (pas de téléchargement inutile), puis tap = pause / lecture.
/// Se met en pause dès qu'on quitte la case ou qu'on fait défiler la page.
class _VideoSlide extends StatefulWidget {
  final String url;
  final String? poster;
  final bool active;
  const _VideoSlide({required this.url, this.poster, required this.active});

  @override
  State<_VideoSlide> createState() => _VideoSlideState();
}

class _VideoSlideState extends State<_VideoSlide> {
  VideoPlayerController? _c;
  bool _loading = false;
  bool _failed = false;
  bool _muted = false;

  @override
  void didUpdateWidget(covariant _VideoSlide old) {
    super.didUpdateWidget(old);
    if (!widget.active && (_c?.value.isPlaying ?? false)) {
      _c!.pause();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_loading) return;
    final c = _c;
    if (c == null) {
      setState(() {
        _loading = true;
        _failed = false;
      });
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      try {
        await ctrl.initialize();
        await ctrl.setLooping(true);
        if (!mounted) {
          ctrl.dispose();
          return;
        }
        _c = ctrl;
        await ctrl.play();
      } catch (_) {
        ctrl.dispose();
        _failed = true;
      }
      if (mounted) setState(() => _loading = false);
      return;
    }
    c.value.isPlaying ? await c.pause() : await c.play();
    if (mounted) setState(() {});
  }

  Future<void> _toggleMute() async {
    final c = _c;
    if (c == null) return;
    _muted = !_muted;
    await c.setVolume(_muted ? 0 : 1);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final ready = c != null && c.value.isInitialized;
    final playing = ready && c!.value.isPlaying;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF111111)),
          if (ready)
            Center(child: AspectRatio(aspectRatio: c!.value.aspectRatio, child: VideoPlayer(c)))
          else if (widget.poster != null)
            CachedNetworkImage(
              imageUrl: widget.poster!,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          if (!playing) const ColoredBox(color: Color(0x33000000)),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else if (_failed)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                child: Text('Vidéo indisponible · toucher pour réessayer',
                    textAlign: TextAlign.center,
                    style: AppTheme.body(size: 12.5, weight: FontWeight.w600, color: Colors.white)),
              ),
            )
          else if (!playing)
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.92),
                  shape: BoxShape.circle,
                  boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 16, offset: Offset(0, 4))],
                ),
                child: const Icon(Icons.play_arrow_rounded, size: 38, color: _orange),
              ),
            ),
          if (ready)
            Positioned(
              right: 14,
              top: MediaQuery.paddingOf(context).top + 56,
              child: GestureDetector(
                onTap: _toggleMute,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                  child: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, size: 18, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════ Section repliable bord à bord (style AliExpress) ═══════
/// Bande blanche pleine largeur, séparée de la précédente par un espace gris.
class _Fold extends StatefulWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  final bool defaultOpen;
  const _Fold({required this.title, required this.child, this.trailing, this.defaultOpen = false});

  @override
  State<_Fold> createState() => _FoldState();
}

class _FoldState extends State<_Fold> {
  late bool _open = widget.defaultOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: _gap),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 15, 12, 15),
              child: Row(children: [
                Expanded(
                  child: Text(widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(size: 16, weight: FontWeight.w700, color: _ink)),
                ),
                if (widget.trailing != null) ...[
                  const SizedBox(width: 8),
                  Flexible(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: widget.trailing!)),
                ],
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: _mute),
                ),
              ]),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: widget.child)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

// ═══════ Lightbox photos d'avis ═══════
/// Plein écran noir : swipe entre les photos, pinch pour zoomer, compteur.
class _PhotoLightbox extends StatefulWidget {
  final List<String> photos;
  final int initial;
  const _PhotoLightbox({required this.photos, required this.initial});

  @override
  State<_PhotoLightbox> createState() => _PhotoLightboxState();
}

class _PhotoLightboxState extends State<_PhotoLightbox> {
  late final PageController _pc = PageController(initialPage: widget.initial);
  late int _i = widget.initial;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Material(
      color: Colors.black,
      child: Stack(children: [
        PageView.builder(
          controller: _pc,
          itemCount: widget.photos.length,
          onPageChanged: (i) => setState(() => _i = i),
          itemBuilder: (_, i) => InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(
              child: CachedNetworkImage(
                imageUrl: widget.photos[i],
                fit: BoxFit.contain,
                placeholder: (_, __) => const CircularProgressIndicator(color: Colors.white),
                errorWidget: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 40),
              ),
            ),
          ),
        ),
        Positioned(
          top: top + 10, left: 16,
          child: widget.photos.length > 1
              ? Text('${_i + 1} / ${widget.photos.length}',
                  style: AppTheme.body(size: 14, weight: FontWeight.w600, color: Colors.white))
              : const SizedBox.shrink(),
        ),
        Positioned(
          top: top + 4, right: 8,
          child: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
          ),
        ),
      ]),
    );
  }
}