import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/api/supplier_api.dart';
import '../../data/models/product.dart';
import '../../data/models/supplier_profile_models.dart';
import '../../widgets/product_card.dart';

// ── Palette identique à la page produit (orange GROSHOP mobile + accents vifs) ──
const _orange = Color(0xFFFF7A00);
const _orangeTint = Color(0xFFFFF4EA);
const _ink = Color(0xFF17171A);
const _sub = Color(0xFF3A3A40);
const _mute = Color(0xFF5C5C62);
const _faint = Color(0xFF8A8A90);
const _line = Color(0xFFEFEFEC);
const _border = Color(0xFFDEDEDA);
const _chipBg = Color(0xFFF5F6F8);
const _green = Color(0xFF12B84F);
const _blue = Color(0xFF1E88FF);
const _star = Color(0xFFFFB800);
const _starOff = Color(0xFFE5E7EB);
const _bg = Color(0xFFF2F2EF);
const _gap = 8.0;
const _tabsH = 50.0;

String _fmtCount(int n) {
  if (n >= 1000) {
    final v = n / 1000;
    return '${v.toStringAsFixed(n >= 10000 ? 0 : 1).replaceAll('.', ',')} K';
  }
  return '$n';
}

class SupplierProfileScreen extends ConsumerStatefulWidget {
  final String slug;
  const SupplierProfileScreen({super.key, required this.slug});
  @override
  ConsumerState<SupplierProfileScreen> createState() => _SupplierProfileScreenState();
}

class _SupplierProfileScreenState extends ConsumerState<SupplierProfileScreen> {
  SupplierProfile? _sp;
  List<Product> _products = const [];
  bool _loading = true;
  bool _notFound = false;

  bool _following = false;
  bool _copied = false;
  int _tab = 0; // 0 Accueil · 1 Produits · 2 Profil · 3 Avis

  final _scroll = ScrollController();
  final _productsKey = GlobalKey();
  final _profileKey = GlobalKey();
  final _reviewsKey = GlobalKey();

  double _topPad = 0, _bannerH = 240;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_spy);
    _load();
  }

  @override
  void dispose() {
    _scroll.removeListener(_spy);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(supplierApiProvider);
    try {
      final profile = await api.publicProfile(widget.slug);
      if (profile == null) {
        if (mounted) setState(() { _notFound = true; _loading = false; });
        return;
      }
      final products =
          await api.publicProducts(widget.slug, pageSize: 12).catchError((_) => <Product>[]);
      if (!mounted) return;
      setState(() { _sp = profile; _products = products; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _notFound = true; _loading = false; });
    }
  }

  double get _threshold => _topPad + _tabsH;

  void _spy() {
    if (!_scroll.hasClients) return;
    int active = 0;
    final entries = [_productsKey, _profileKey, _reviewsKey];
    for (var i = 0; i < entries.length; i++) {
      final ctx = entries[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox) continue;
      final dy = box.localToGlobal(Offset.zero).dy;
      if (dy <= _threshold + 4) active = i + 1;
    }
    if (active != _tab) setState(() => _tab = active);
  }

  void _goTo(int i) {
    setState(() => _tab = i);
    if (i == 0) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      return;
    }
    final key = [_productsKey, _profileKey, _reviewsKey][i - 1];
    final ctx = key.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject();
    if (box is! RenderBox) return;
    final dy = box.localToGlobal(Offset.zero).dy;
    final target = (_scroll.offset + dy - _threshold)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _share() async {
    await Clipboard.setData(ClipboardData(text: 'https://groshop.tn/fournisseur/${widget.slug}'));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1800), () { if (mounted) setState(() => _copied = false); });
  }

  Future<void> _contact() async {
    final api = ref.read(supplierApiProvider);
    try {
      final id = await api.startConversation(widget.slug);
      if (!mounted) return;
      if (id != null && id.isNotEmpty) {
        context.push('/messages/$id');
      } else {
        context.push('/dashboard/messages');
      }
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 401) {
        context.push('/login');
      } else {
        _snack("Impossible d'ouvrir la messagerie pour le moment.");
      }
    } catch (_) {
      if (mounted) _snack("Impossible d'ouvrir la messagerie pour le moment.");
    }
  }

  void _toggleFollow() {
    HapticFeedback.selectionClick();
    setState(() => _following = !_following);
  }

  @override
  Widget build(BuildContext context) {
    _topPad = MediaQuery.paddingOf(context).top;
    _bannerH = (MediaQuery.sizeOf(context).height * 0.4).clamp(200.0, 340.0);

    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _orange)),
      );
    }
    if (_notFound || _sp == null) {
      return Scaffold(
        backgroundColor: _bg,
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Ce fournisseur est introuvable.', style: AppTheme.body(size: 15, color: _sub)),
          const SizedBox(height: 6),
          TextButton(onPressed: () => context.go('/'),
              child: Text('Retour à l’accueil', style: AppTheme.body(weight: FontWeight.w700, color: _orange))),
        ])),
      );
    }

    final sp = _sp!;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          top: true,
          bottom: false,
          child: CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(child: _bannerAndCard(sp)),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabsHeaderDelegate(
                  active: _tab,
                  labels: const ['Accueil', 'Produits', 'Profil', 'Avis'],
                  onTap: _goTo,
                ),
              ),
              SliverToBoxAdapter(child: _statsRow(sp)),
              SliverToBoxAdapter(
                child: Container(key: _productsKey, child: _productsSection()),
              ),
              SliverToBoxAdapter(
                child: Container(key: _profileKey, child: _profileSection(sp.store)),
              ),
              SliverToBoxAdapter(
                child: Container(key: _reviewsKey, child: _reviewsSection(sp)),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
        bottomNavigationBar: _bottomBar(),
      ),
    );
  }

  // ── Bannière + carte identité qui chevauche ──
  Widget _bannerAndCard(SupplierProfile sp) {
    final store = sp.store;
    final hasBanner = store.bannerUrl != null && store.bannerUrl!.isNotEmpty;
    return Column(children: [
      SizedBox(
        height: _bannerH,
        child: Stack(fit: StackFit.expand, children: [
          hasBanner
              ? CachedNetworkImage(imageUrl: store.bannerUrl!, fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 150),
                  placeholder: (_, __) => const ColoredBox(color: Color(0xFFE9E9E6)),
                  errorWidget: (_, __, ___) => _bannerFallback())
              : _bannerFallback(),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Color(0x33000000), Color(0x00000000), Color(0x99000000)],
                stops: [0.0, 0.35, 1.0],
              ),
            ),
          ),
          Positioned(
            top: 10, left: 12, right: 12,
            child: Row(children: [
              _glassCircle(Icons.chevron_left_rounded, 26,
                  () => context.canPop() ? context.pop() : context.go('/')),
              const Spacer(),
              _glassCircle(_copied ? Icons.check_rounded : Icons.share_outlined, 20, _share,
                  color: _copied ? _green : _ink),
            ]),
          ),
          if (store.heroTitle != null)
            Positioned(left: 16, right: 16, bottom: 34, child: Text(
              store.heroTitle!,
              maxLines: 3, overflow: TextOverflow.ellipsis,
              style: AppTheme.body(size: 15.5, weight: FontWeight.w700, color: Colors.white).copyWith(
                  height: 1.35, shadows: const [Shadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 1))]),
            )),
        ]),
      ),
      Transform.translate(
        offset: const Offset(0, -20),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _identityCard(sp)),
      ),
    ]);
  }

  /// Sans bannière : dégradé orange lumineux plutôt qu'un gris plat.
  Widget _bannerFallback() => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFFFF9A3D), _orange],
          ),
        ),
      );

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

  Widget _identityCard(SupplierProfile sp) {
    final store = sp.store;
    final place = ['${sp.city}', sp.wilaya].where((e) => e.trim().isNotEmpty).map((e) => e.trim()).toSet().join(', ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 6))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: _line, width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: store.logoUrl != null && store.logoUrl!.isNotEmpty
                ? CachedNetworkImage(imageUrl: store.logoUrl!, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _logoFallback(sp.companyName))
                : _logoFallback(sp.companyName),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(sp.companyName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(size: 18, weight: FontWeight.w800, color: _ink))),
              if (sp.verified) const Padding(padding: EdgeInsets.only(left: 5),
                  child: Icon(Icons.verified_rounded, size: 18, color: _blue)),
            ]),
            if (place.isNotEmpty) ...[
              const SizedBox(height: 3),
              Row(children: [
                const Icon(Icons.location_on_outlined, size: 13, color: _mute),
                const SizedBox(width: 3),
                Flexible(child: Text(place,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.body(size: 12.5, color: _mute))),
              ]),
            ],
          ])),
        ]),
        const SizedBox(height: 12),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 6, children: [
          if (sp.ratingCount > 0) ...[
            _stars(sp.ratingAvg, 15),
            Text(sp.ratingAvg.toStringAsFixed(1), style: AppTheme.body(size: 13, weight: FontWeight.w700, color: _ink)),
            _dot(),
            GestureDetector(onTap: () => _goTo(3), child: Text('${sp.ratingCount} avis',
                style: AppTheme.body(size: 13, weight: FontWeight.w600, color: _blue)
                    .copyWith(decoration: TextDecoration.underline, decorationColor: _blue))),
          ] else
            Text('Nouveau vendeur', style: AppTheme.body(size: 13, weight: FontWeight.w600, color: _mute)),
          _dot(),
          Text('${_fmtCount(sp.followersCount)} abonnés', style: AppTheme.body(size: 13, color: _mute)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _followBtn(height: 44)),
          const SizedBox(width: 8),
          Expanded(child: _filledBtn('Contacter', Icons.chat_bubble_outline_rounded, _contact, height: 44)),
        ]),
      ]),
    );
  }

  Widget _dot() => Text('·', style: AppTheme.body(size: 13, color: _mute));

  Widget _logoFallback(String name) => Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
      style: AppTheme.body(size: 24, weight: FontWeight.w700, color: _orange)));

  /// 5 étoiles avec demi-étoile (même rendu que la page produit).
  Widget _stars(double v, double size) => Row(mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final full = i < v.floor();
        final half = !full && i < v;
        return Icon(half ? Icons.star_half_rounded : Icons.star_rounded,
            size: size, color: (full || half) ? _star : _starOff);
      }));

  // ── Stats (section Accueil) ──
  Widget _statsRow(SupplierProfile sp) {
    final years = _years(sp.createdAt);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(children: [
        _statCard(Icons.inventory_2_outlined, '${_products.length}${_products.length >= 12 ? '+' : ''}', 'Produits'),
        const SizedBox(width: 8),
        _statCard(Icons.people_outline_rounded, _fmtCount(sp.followersCount), 'Abonnés'),
        const SizedBox(width: 8),
        _statCard(Icons.workspace_premium_outlined,
            years != null ? '$years ${years > 1 ? 'ans' : 'an'}' : '—', 'Ancienneté'),
      ]),
    );
  }

  int? _years(String createdAt) {
    if (createdAt.isEmpty) return null;
    final dt = DateTime.tryParse(createdAt);
    if (dt == null) return null;
    final y = DateTime.now().year - dt.year;
    return y < 1 ? 1 : y;
  }

  Widget _statCard(IconData icon, String value, String label) => Expanded(child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Icon(icon, size: 18, color: _orange),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: AppTheme.body(size: 17, weight: FontWeight.w800, color: _ink)),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppTheme.body(size: 11.5, color: _mute)),
        ]),
      ));

  // ── Section blanche bord à bord (comme la page produit) ──
  Widget _section({required List<Widget> children}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: _gap),
        padding: const EdgeInsets.only(bottom: 16),
        color: Colors.white,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  // ── Section produits ──
  Widget _productsSection() {
    return _section(children: [
      _sectionTitle('Catalogue', 'Nos produits',
          'Découvrez la gamme disponible en gros pour les professionnels.'),
      if (_products.isEmpty)
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('Aucun produit pour le moment.', style: AppTheme.body(size: 13.5, color: _mute)))
      else
        Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: _masonry()),
    ]);
  }

  Widget _masonry() {
    final left = <Widget>[], right = <Widget>[];
    for (var i = 0; i < _products.length; i++) {
      final card = Padding(padding: const EdgeInsets.only(bottom: 14),
          child: ProductCard(product: _products[i]));
      (i.isEven ? left : right).add(card);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: left)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: right)),
    ]);
  }

  // ── Section profil / à propos ──
  Widget _profileSection(SupplierStore store) {
    final hasAny = store.description != null || store.mission != null ||
        store.aboutImages.isNotEmpty || store.certifications.isNotEmpty;
    return _section(children: [
      _sectionTitle('Qui sommes-nous', "Profil de l'entreprise",
          "Découvrez l'histoire, la mission et les coulisses de ce fournisseur."),
      Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!hasAny)
              Text('Ce fournisseur n’a pas encore complété son profil.',
                  style: AppTheme.body(size: 13.5, color: _mute)),
            if (store.description != null)
              Text(store.description!, style: AppTheme.body(size: 13.5, color: _sub).copyWith(height: 1.65)),
            if (store.mission != null) ...[
              const SizedBox(height: 16),
              Text('Notre mission', style: AppTheme.body(size: 15, weight: FontWeight.w700, color: _ink)),
              const SizedBox(height: 6),
              Text(store.mission!, style: AppTheme.body(size: 13.5, color: _sub).copyWith(height: 1.65)),
            ],
            if (store.aboutImages.isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(height: 120, child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: store.aboutImages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(imageUrl: store.aboutImages[i], width: 160, height: 120, fit: BoxFit.cover,
                      placeholder: (_, __) => const ColoredBox(color: Color(0xFFF2F3F5)),
                      errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFFF2F3F5))),
                ),
              )),
            ],
            if (store.certifications.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: store.certifications.map((c) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: _chipBg, borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.workspace_premium_rounded, size: 14, color: _orange),
                  const SizedBox(width: 5),
                  Text(c, style: AppTheme.body(size: 12, weight: FontWeight.w700, color: _ink)),
                ]),
              )).toList()),
            ],
          ])),
    ]);
  }

  // ── Section avis ──
  Widget _reviewsSection(SupplierProfile sp) {
    final reviews = sp.reviews;
    return _section(children: [
      _sectionTitle('Témoignages', 'Avis clients',
          'Ce que disent les professionnels qui font confiance à ce fournisseur.'),
      if (reviews.isEmpty)
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('Aucun avis pour le moment.', style: AppTheme.body(size: 13.5, color: _mute)))
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (sp.ratingCount > 0)
              Row(children: [
                Text(sp.ratingAvg.toStringAsFixed(1),
                    style: AppTheme.body(size: 28, weight: FontWeight.w800, color: _ink)),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _stars(sp.ratingAvg, 15),
                  Text('${sp.ratingCount} avis', style: AppTheme.body(size: 12, color: _mute)),
                ]),
              ]),
            ...reviews.take(8).map(_reviewTile),
          ]),
        ),
    ]);
  }

  Widget _reviewTile(SupplierReview r) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.only(top: 12),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: _line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 17, backgroundColor: _orange,
                backgroundImage: r.avatarUrl.isNotEmpty ? CachedNetworkImageProvider(r.avatarUrl) : null,
                child: r.avatarUrl.isEmpty
                    ? Text(r.authorName.isNotEmpty ? r.authorName[0].toUpperCase() : '?',
                        style: AppTheme.body(size: 14, weight: FontWeight.w700, color: Colors.white))
                    : null),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.authorName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(size: 13.5, weight: FontWeight.w700, color: _ink)),
              const SizedBox(height: 2),
              Row(children: [
                _stars(r.rating, 13),
                if (r.city.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Flexible(child: Text(r.city, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(size: 12, color: _mute))),
                ],
              ]),
            ])),
          ]),
          if (r.text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8),
              child: Text(r.text, style: AppTheme.body(size: 13.5, color: _ink).copyWith(height: 1.5))),
          if (r.images.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10),
              child: SizedBox(height: 72, child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: r.images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(imageUrl: r.images[i], width: 72, height: 72, fit: BoxFit.cover,
                      placeholder: (_, __) => const ColoredBox(color: Color(0xFFF2F3F5)),
                      errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFFF2F3F5))),
                ),
              ))),
        ]),
      );

  // ── Barre d'action fixe (même hauteur que la page produit) ──
  Widget _bottomBar() => Container(
        decoration: const BoxDecoration(color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFEAEAE6)))),
        child: SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            Material(
              color: _following ? _orangeTint : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: _following ? _orange : _border),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _toggleFollow,
                child: SizedBox(
                  width: 46, height: 46,
                  child: Icon(_following ? Icons.check_rounded : Icons.person_add_alt_1_outlined,
                      size: 21, color: _following ? _orange : _ink),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: _outlineBtn('Catalogue', () => _goTo(1))),
            const SizedBox(width: 10),
            Expanded(child: _filledBtn('Contacter', Icons.chat_bubble_outline_rounded, _contact, height: 46)),
          ]),
        )),
      );

  // ── Petits helpers UI ──
  Widget _sectionTitle(String small, String title, String subtitle) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(small.toUpperCase(),
              style: AppTheme.body(size: 11.5, weight: FontWeight.w800, color: _orange).copyWith(letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(title, style: AppTheme.body(size: 19, weight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 4),
          Text(subtitle, style: AppTheme.body(size: 13, color: _mute).copyWith(height: 1.45)),
        ]),
      );

  Widget _filledBtn(String t, IconData i, VoidCallback onTap, {double height = 46}) => Material(
        color: _orange,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(i, size: 17, color: Colors.white),
              const SizedBox(width: 6),
              Flexible(child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(t, style: AppTheme.body(size: 15, weight: FontWeight.w700, color: Colors.white)),
              )),
            ]),
          ),
        ),
      );

  Widget _outlineBtn(String t, VoidCallback onTap) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: 46,
            child: Center(child: Text(t, style: AppTheme.body(size: 15, weight: FontWeight.w700, color: _ink))),
          ),
        ),
      );

  Widget _followBtn({double height = 44}) => Material(
        color: _following ? _orangeTint : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: _following ? _orange : _border, width: _following ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _toggleFollow,
          child: SizedBox(
            height: height,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(_following ? Icons.check_rounded : Icons.person_add_alt_1_outlined,
                  size: 17, color: _following ? _orange : _ink),
              const SizedBox(width: 6),
              Text(_following ? 'Abonné' : 'Suivre',
                  style: AppTheme.body(size: 14.5, weight: FontWeight.w700, color: _following ? _orange : _ink)),
            ]),
          ),
        ),
      );
}

// ── En-tête collant des onglets (scroll-spy) ──
class _TabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  final int active;
  final List<String> labels;
  final void Function(int) onTap;
  _TabsHeaderDelegate({required this.active, required this.labels, required this.onTap});

  @override
  double get minExtent => _tabsH;
  @override
  double get maxExtent => _tabsH;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      height: _tabsH,
      decoration: const BoxDecoration(color: Colors.white,
          border: Border(bottom: BorderSide(color: _line))),
      child: Row(children: List.generate(labels.length, (i) {
        final on = i == active;
        return Expanded(child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(i),
          child: Stack(alignment: Alignment.center, children: [
            Text(labels[i], style: AppTheme.body(
                size: 14, weight: on ? FontWeight.w800 : FontWeight.w600, color: on ? _ink : _mute)),
            Positioned(bottom: 0, child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: on ? 28 : 0, height: 3,
              decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(2)),
            )),
          ]),
        ));
      })),
    );
  }

  @override
  bool shouldRebuild(covariant _TabsHeaderDelegate old) => old.active != active;
}