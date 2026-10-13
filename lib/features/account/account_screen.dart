import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import '../../core/links.dart';
import '../../core/theme.dart';
import '../../data/api/account_api.dart';
import '../../data/api/orders_api.dart';
import '../../data/api/products_api.dart';
import '../../data/api/support_api.dart';
import '../../data/models/followed_shop.dart';
import '../../data/models/product.dart';
import '../../state/auth_provider.dart';
import '../../state/cart_provider.dart';
import '../../state/seen_store.dart';
import '../../widgets/product_card.dart';

const _orange = Color(0xFFFF7A00);
const _ink = Color(0xFF0F1419);
const _mute = Color(0xFF6B7785);
const _faint = Color(0xFF9AA3AE);
const _line = Color(0xFFE8EAED);
const _bg = Color(0xFFF4F5F7);

/// Rouge vif et lumineux des pastilles de notification (jamais foncé).
const _badgeRed = Color(0xFFFF3B30);

/// Animation Lottie à gauche de « Commencez à vendre sur GROSHOP ».
/// ⚠️ Mets ici le nom de ton fichier, et déclare-le dans pubspec.yaml.
const _sellLottie = 'assets/lottie/sell.json';

String _fmt(num n) => n.toStringAsFixed(2).replaceAll('.', ',');

/// Couleurs pleines et intenses de l'avatar (toutes lisibles avec une lettre blanche).
const _avatarColors = <Color>[
  Color(0xFFFF7A00), // orange GROSHOP
  Color(0xFFE53935), // rouge
  Color(0xFFD81B60), // framboise
  Color(0xFF8E24AA), // violet
  Color(0xFF5E35B1), // violet profond
  Color(0xFF3949AB), // indigo
  Color(0xFF1E88E5), // bleu
  Color(0xFF00897B), // sarcelle
  Color(0xFF43A047), // vert
  Color(0xFFF4511E), // corail
];

/// Couleur « aléatoire » mais STABLE pour un même compte : dérivée de son
/// identifiant, elle reste la même à chaque ouverture et sur tous les appareils.
Color _avatarColor(String seed) {
  var h = 0;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff; // hash maison : String.hashCode n'est pas garanti stable
  }
  return _avatarColors[h % _avatarColors.length];
}

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});
  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> with WidgetsBindingObserver {
  List<Map<String, dynamic>>? _orders, _toReview;
  List<Product>? _favorites, _recommended;
  List<FollowedShop>? _shops;
  SeenStore? _seen;
  int _supportUnread = 0;

  // ── Rafraîchissement automatique ────────────────────────────────
  GoRouter? _router;
  String? _myPath; // chemin de cet écran (ex. /compte), lu une seule fois
  bool _away = false; // l'utilisateur est sur un autre onglet / une page poussée
  bool _refreshing = false; // évite les rafraîchissements en double
  StreamSubscription<RemoteMessage>? _pushSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    // Notif reçue app ouverte (réponse support, commande expédiée…) → badges à jour.
    _pushSub = FirebaseMessaging.onMessage.listen((_) => _refreshCounts());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_router == null) {
      _router = GoRouter.of(context);
      _myPath = GoRouterState.of(context).matchedLocation;
      _router!.routerDelegate.addListener(_onRouteChanged);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router?.routerDelegate.removeListener(_onRouteChanged);
    _pushSub?.cancel();
    super.dispose();
  }

  String? get _currentPath => _router?.routerDelegate.currentConfiguration.uri.path;

  bool get _isVisible => _currentPath == _myPath;

  /// Retour sur l'onglet Compte (depuis le panier, le catalogue, ou une page
  /// poussée comme /commandes) → on recharge les compteurs.
  void _onRouteChanged() {
    if (!_isVisible) {
      _away = true;
      return;
    }
    if (_away) {
      _away = false;
      _refreshCounts();
    }
  }

  /// App remise au premier plan pendant que l'écran Compte est affiché.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isVisible) _refreshCounts();
  }

  void _safeSet(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  /// Chargement complet (ouverture + pull-to-refresh). Attend VRAIMENT toutes
  /// les requêtes : le spinner reste affiché jusqu'à la fin.
  Future<void> _load() => Future.wait([
        _loadSeen(),
        _loadOrders(),
        _loadFavorites(),
        _loadShops(),
        _loadSupportUnread(),
        _loadRecommended(),
      ]);

  /// Rechargement léger : uniquement ce qui alimente les compteurs et badges
  /// (pas les recommandations). Ignoré si un rechargement est déjà en cours.
  Future<void> _refreshCounts() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await Future.wait([_loadOrders(), _loadFavorites(), _loadShops(), _loadSupportUnread()]);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _loadSeen() => ref
      .read(seenStoreProvider.future)
      .then((s) => _safeSet(() => _seen = s))
      .catchError((_) {});

  Future<void> _loadRecommended() => ref
      .read(productsApiProvider)
      .recommended()
      .then((d) => _safeSet(() => _recommended = d))
      .catchError((_) => _safeSet(() => _recommended = <Product>[]));

  Future<void> _loadOrders() {
    final orders = ref.read(ordersApiProvider);
    return Future.wait([
      orders.list().then((d) => _safeSet(() => _orders = d)).catchError((_) => _safeSet(() => _orders = [])),
      orders.toReview().then((d) => _safeSet(() => _toReview = d)).catchError((_) => _safeSet(() => _toReview = [])),
    ]);
  }

  /// Réponses du centre d'aide non lues (poll `peek=1` : ne les marque pas lues).
  Future<void> _loadSupportUnread() => ref
      .read(supportApiProvider)
      .unreadCount()
      .then((n) => _safeSet(() => _supportUnread = n))
      .catchError((_) {});

  Future<void> _loadShops() => ref
      .read(accountApiProvider)
      .followedShops()
      .then((d) => _safeSet(() => _shops = d))
      .catchError((_) => _safeSet(() => _shops = <FollowedShop>[]));

  Future<void> _loadFavorites() async {
    try {
      final d = await ref.read(accountApiProvider).favorites();
      _safeSet(() => _favorites = d);
    } catch (_) {
      _safeSet(() => _favorites = <Product>[]);
    }
  }

  // ── Navigation ──────────────────────────────────────────────────
  // Au retour, _refreshCounts est appelé ici ET par l'écouteur de route :
  // le verrou _refreshing garantit qu'une seule série de requêtes part.

  /// Ouvre la page Commandes (sur un onglet précis si [tab]).
  Future<void> _openOrders([String? tab]) async {
    if (tab == null || tab == 'delivered') _markSeen('orders:delivered', _deliveredIds);
    await context.push(tab == null ? '/commandes' : '/commandes?tab=$tab');
    if (mounted) _refreshCounts();
  }

  Future<void> _openAssistance() async {
    await context.push('/assistance');
    if (mounted) _refreshCounts();
  }

  /// Ouvre la page Favoris (l'utilisateur a pu en retirer là-bas).
  Future<void> _openFavoris() async {
    _markSeen('favoris:promo', _promoFavIds);
    await context.push('/favoris');
    if (mounted) _refreshCounts();
  }

  Future<void> _openShops() async {
    await context.push('/boutiques-suivies');
    if (mounted) _refreshCounts();
  }

  // ── Badges « nouveau » ──────────────────────────────────────────

  Iterable<String> get _deliveredIds =>
      (_orders ?? const []).where((o) => o['status'] == 'delivered').map((o) => '${o['id']}');

  /// Favoris actuellement en promo (ancien prix > prix actuel).
  Iterable<String> get _promoFavIds =>
      (_favorites ?? const <Product>[]).where((p) => p.oldPrice != null && p.oldPrice! > p.basePrice).map((p) => p.id);

  /// Commandes passées à « Livrée » depuis la dernière visite de l'onglet.
  int get _newDelivered => (_seen == null || _orders == null) ? 0 : _seen!.unseen('orders:delivered', _deliveredIds);

  /// Favoris passés en promo depuis la dernière visite des Favoris.
  int get _newPromos => (_seen == null || _favorites == null) ? 0 : _seen!.unseen('favoris:promo', _promoFavIds);

  /// Nouveaux produits publiés par les boutiques suivies.
  int get _newShopProducts => (_shops ?? const <FollowedShop>[]).fold(0, (a, s) => a + s.newProductsCount);

  Future<void> _markSeen(String key, Iterable<String> ids) async {
    await _seen?.markSeen(key, ids.toList());
    _safeSet(() {});
  }

  int _countBy(bool Function(Map) f) => (_orders ?? const []).where(f).length;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).valueOrNull?.user;
    if (user == null) {
      return Scaffold(
        backgroundColor: _bg,
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text('Connectez-vous pour accéder à votre compte.', textAlign: TextAlign.center),
          ),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: () => context.go('/login'), child: const Text('Se connecter')),
        ])),
      );
    }

    final initial = (user.fullName.isNotEmpty ? user.fullName : user.email).characters.first.toUpperCase();
    // Graine de la couleur : l'id du compte (repli sur l'email s'il est vide).
    final idSeed = '${user.id}';
    final avatarBg = _avatarColor(idSeed.isNotEmpty && idSeed != 'null' ? idSeed : user.email);
    final cartCount = ref.watch(cartProvider).count;
    final statuses = [
      ('En attente', Icons.account_balance_wallet_outlined,
          _countBy((o) => o['status'] == 'pending' || o['status'] == 'confirmed' || o['status'] == 'call_confirmed'), 'pending'),
      ('En production', Icons.inventory_2_outlined, _countBy((o) => o['status'] == 'in_production'), 'in_production'),
      ('Expédiées', Icons.local_shipping_outlined, _countBy((o) => o['status'] == 'shipped'), 'shipped'),
      ('À évaluer', Icons.star_outline, (_toReview ?? const []).length, 'review'),
      ('Livrées', Icons.check_circle_outline, _newDelivered, 'delivered'),
    ];

    // Police système très agrandie → on plafonne à 1.3× sur cet écran :
    // lisible, mais aucune mise en page ne peut plus exploser.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: _orange,
            onRefresh: _load,
            child: ListView(
              // Toujours scrollable : le pull-to-refresh marche même si la page est courte.
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                _header(user.fullName.isNotEmpty ? user.fullName : user.email.split('@').first, initial, avatarBg),
                _statsRow(cartCount),
                _ordersSection(statuses),
                _activitySection(),
                _favoritesSection(),
                _sellCta(),
                _explore(),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Bloc blanc. Espacement vertical resserré (marge 6, padding 12) pour
  /// une page moins longue.
  Widget _block({required Widget child, EdgeInsets? padding}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 6),
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: Colors.white,
        child: child,
      );

  /// Avatar : cercle de couleur pleine et intense (propre au compte) + initiale blanche.
  Widget _header(String name, String initial, Color avatarBg) => Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(children: [
          Container(width: 40, height: 40,
            decoration: BoxDecoration(color: avatarBg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(initial, style: AppTheme.body(size: 17, weight: FontWeight.w700, color: Colors.white))),
          const SizedBox(width: 11),
          Expanded(child: Text(name, overflow: TextOverflow.ellipsis,
              style: AppTheme.body(size: 16, weight: FontWeight.w700, color: _ink))),
          // Assistance en orange GROSHOP pour qu'on la repère tout de suite.
          IconButton(onPressed: _openAssistance, icon: _BadgeIcon(icon: Icons.headset_mic_outlined, count: _supportUnread, color: _orange, size: 24)),
          IconButton(onPressed: () => context.push('/parametres'), icon: const Icon(Icons.settings_outlined, color: _ink)),
        ]),
      );

  Widget _statsRow(int cartCount) => _block(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(children: [
          _stat('${(_orders ?? const []).length}', 'Commandes', () => _openOrders()),
          Container(width: 1, height: 28, color: _line),
          _stat('${(_toReview ?? const []).length}', 'À évaluer', () => _openOrders('review')),
          Container(width: 1, height: 28, color: _line),
          _stat('$cartCount', 'Panier', () => context.go('/panier')),
        ]),
      );

  Widget _stat(String v, String l, VoidCallback tap) => Expanded(
        child: GestureDetector(
          onTap: tap,
          behavior: HitTestBehavior.opaque,
          child: Column(children: [
            FittedBox(fit: BoxFit.scaleDown,
                child: Text(v, maxLines: 1, style: AppTheme.body(size: 18, weight: FontWeight.w700, color: _ink))),
            const SizedBox(height: 2),
            Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.body(size: 11.5, color: _mute)),
          ]),
        ),
      );

  Widget _ordersSection(List<(String, IconData, int, String)> statuses) => _block(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 11),
            child: Row(children: [
              Expanded(child: Text('Mes commandes', style: AppTheme.body(size: 16, weight: FontWeight.w600, color: _ink))),
              GestureDetector(onTap: () => _openOrders(),
                behavior: HitTestBehavior.opaque,
                child: Row(children: [Text('Voir tout', style: AppTheme.body(size: 13, color: _mute)),
                    const Icon(Icons.chevron_right, size: 15, color: _mute)])),
            ])),
          Row(children: statuses.map((s) => Expanded(child: GestureDetector(
            onTap: () => _openOrders(s.$4),
            behavior: HitTestBehavior.opaque,
            child: Column(children: [
              _BadgeIcon(icon: s.$2, count: s.$3),
              const SizedBox(height: 6),
              Text(s.$1, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(size: 11, color: const Color(0xFF3D4853))),
            ]),
          ))).toList()),
        ]),
      );

  Widget _activitySection() => _block(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 11),
            child: Text('Mon activité', style: AppTheme.body(size: 16, weight: FontWeight.w600, color: _ink))),
          Row(children: [
            _activityItem(Icons.favorite_border, 'Favoris', _openFavoris, badge: _newPromos),
            _activityItem(Icons.history, 'Historique', () => context.push('/historique')),
            _activityItem(Icons.storefront_outlined, 'Boutiques suivies', _openShops, badge: _newShopProducts),
          ]),
        ]),
      );

  Widget _activityItem(IconData i, String l, VoidCallback onTap, {int badge = 0}) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Column(children: [
            _BadgeIcon(icon: i, count: badge),
            const SizedBox(height: 6),
            Text(l, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: AppTheme.body(size: 11, color: const Color(0xFF3D4853))),
          ]),
        ),
      );

  // Favoris : plus d'espace vide en bas du bloc (padding bas 16 → 10, état vide plus compact).
  Widget _favoritesSection() {
    return _block(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Favoris', style: AppTheme.body(size: 15, weight: FontWeight.w700, color: _ink))),
          if ((_favorites?.isNotEmpty ?? false))
            GestureDetector(onTap: _openFavoris,
                behavior: HitTestBehavior.opaque,
                child: Text('Voir tout ›', style: AppTheme.body(size: 12, color: _mute))),
        ]),
        const SizedBox(height: 10),
        if (_favorites == null)
          const SizedBox(height: 80, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: _orange)))
        else if (_favorites!.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(10)),
            child: Column(children: [
              const Icon(Icons.inventory_2_outlined, size: 26, color: _faint),
              const SizedBox(height: 4),
              Text('Aucun favori', style: AppTheme.body(size: 12.5, color: _mute)),
            ]),
          )
        else
          // Pas de hauteur imposée : la rangée prend exactement la hauteur de son
          // contenu → aucun débordement, quelle que soit la taille du texte.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _favorites!.take(8).length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  _favTile(_favorites![i]),
                ],
              ],
            ),
          ),
      ]),
    );
  }

  Widget _favTile(Product p) => GestureDetector(
        onTap: () => context.push('/produit/${p.id}'),
        child: SizedBox(
          width: 82,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 82,
                height: 82,
                child: (p.primaryImage != null && p.primaryImage!.isNotEmpty)
                    ? CachedNetworkImage(imageUrl: p.primaryImage!, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFFF4F5F7)))
                    : const ColoredBox(color: Color(0xFFF4F5F7), child: Icon(Icons.inventory_2_outlined, color: _faint)),
              ),
            ),
            const SizedBox(height: 4),
            // Prix long (« 12 345,00 TND ») : rétrécit au lieu de passer à la ligne.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('${_fmt(p.basePrice)} TND', maxLines: 1,
                  style: AppTheme.body(size: 12, weight: FontWeight.w700, color: _orange)),
            ),
            if (p.moq != null)
              Text('Min. ${p.moq}', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(size: 10, color: _mute)),
          ]),
        ),
      );

  Widget _sellCta() => GestureDetector(
        onTap: () => openExternal(context, '/devenir-fournisseur'),
        child: _block(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            const _SellLottie(size: 40), // ⭐ animation à la place de l'icône
            const SizedBox(width: 12),
            Expanded(child: Text('Commencez à vendre sur GROSHOP', maxLines: 2, overflow: TextOverflow.ellipsis,
                style: AppTheme.body(size: 15, weight: FontWeight.w500, color: _ink))),
            const Icon(Icons.open_in_new, size: 18, color: _ink),
          ]),
        ),
      );

  Widget _explore() => _block(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('Explorer plus', style: AppTheme.body(size: 15, weight: FontWeight.w700, color: _ink))),
          const SizedBox(height: 10),
          if (_recommended == null)
            const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: _orange)))
          else if (_recommended!.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(child: Text('Aucune recommandation', style: AppTheme.body(size: 12, color: _faint))))
          else
            // 2 colonnes où chaque carte prend sa hauteur naturelle : une grille à
            // ratio fixe déborde dès qu'un nom fait 2 lignes ou que la police grossit.
            _masonry(_recommended!.take(10).toList()),
        ]),
      );
}

/// Colonnes gauche/droite en alternance, sans hauteur imposée.
Widget _masonry(List<Product> items) {
  final left = <Widget>[], right = <Widget>[];
  for (var i = 0; i < items.length; i++) {
    (i.isEven ? left : right).add(Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ProductCard(product: items[i]),
    ));
  }
  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
    const SizedBox(width: 10),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
  ]);
}

/// Animation Lottie du bloc « Commencez à vendre ».
/// [scale] zoome le dessin si le fichier a beaucoup de marge vide (comme la loupe).
/// Fichier introuvable → icône d'origine (mallette dans un cercle).
class _SellLottie extends StatelessWidget {
  final double size;
  final double scale;
  const _SellLottie({this.size = 40, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Transform.scale(
        scale: scale,
        child: Lottie.asset(
          _sellLottie,
          width: size,
          height: size,
          fit: BoxFit.contain,
          repeat: true,
          errorBuilder: (_, __, ___) => Container(
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _ink, width: 1.5)),
            child: Icon(Icons.work_outline, size: size * 0.48, color: _ink),
          ),
        ),
      ),
    );
  }
}

/// Icône avec pastille rouge vif pleine (nombre blanc) en haut à droite ; rien si [count] = 0.
class _BadgeIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color color;
  final double size;
  const _BadgeIcon({required this.icon, required this.count, this.color = const Color(0xFF3D4853), this.size = 25});

  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, children: [
        Icon(icon, size: size, color: color),
        if (count > 0)
          Positioned(
            top: -6,
            right: -9,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(minWidth: 17),
              height: 17,
              decoration: BoxDecoration(
                color: _badgeRed,
                borderRadius: BorderRadius.circular(9),
                // Pastille 100 % rouge (pas de contour blanc), seul le nombre est blanc.
                // Léger halo rouge : la pastille « brille » sans foncer la couleur.
                boxShadow: [BoxShadow(color: _badgeRed.withOpacity(.35), blurRadius: 4, offset: const Offset(0, 1))],
              ),
              alignment: Alignment.center,
              child: Text(count > 99 ? '99+' : '$count',
                  style: AppTheme.body(size: 9.5, weight: FontWeight.w700, color: Colors.white)),
            ),
          ),
      ]);
}