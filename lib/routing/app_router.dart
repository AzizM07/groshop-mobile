import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../state/auth_provider.dart';
import '../state/cart_provider.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/home/home_screen.dart';
import '../features/shell/buyer_shell.dart';
import '../features/categories/categories_screen.dart';
import '../features/search/search_screen.dart';
import '../features/search/search_entry_screen.dart';
import '../features/search/visual_search_screen.dart';
import '../features/supplier/supplier_shell.dart';
import '../features/supplier/supplier_dashboard_screen.dart';
import '../features/supplier/supplier_orders_screen.dart';
import '../features/supplier/supplier_products_screen.dart';
import '../features/supplier/supplier_product_form_screen.dart';
import '../features/supplier/supplier_messages_screen.dart';
import '../features/supplier/supplier_settings_screen.dart';
import '../features/supplier/supplier_stats_screen.dart';
import '../features/supplier/supplier_reviews_screen.dart';
import '../features/supplier/supplier_access_screen.dart';
import '../features/supplier/supplier_profile_screen.dart';
import '../features/product/product_screen.dart';
import '../features/cart/cart_screen.dart';
import '../features/checkout/checkout_screen.dart';
import '../features/orders/order_confirmation_screen.dart';
import '../features/account/account_screen.dart';
import '../features/messages/messages_screen.dart';
import '../features/messages/chat_screen.dart';
import '../features/messages/draft_chat_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/favoris/favoris_screen.dart';
import '../features/historique/historique_screen.dart';
import '../features/boutiques/boutiques_suivies_screen.dart';
import '../features/orders/commandes_screen.dart';
import '../features/assistance/assistance_screen.dart';
import '../features/settings/settings_screen.dart';

class _RouterNotifier extends ChangeNotifier {
  final Ref _ref;
  _RouterNotifier(this._ref) {
    _ref.listen(authProvider, (_, __) => notifyListeners());
  }

  String? redirect(BuildContext context, GoRouterState state) {
    final loc = state.matchedLocation;

    // Le splash gère lui-même sa sortie → on ne le redirige jamais.
    if (loc == '/splash') return null;

    final auth = _ref.read(authProvider);
    if (auth.isLoading) return null;

    final st = auth.valueOrNull ?? const AuthState();
    final loggedIn = st.isAuthenticated;
    final isSupplier = st.isSupplier;
    final onAuthPage = loc == '/login' || loc == '/signup';

    final protected = loc.startsWith('/dashboard') ||
        loc.startsWith('/supplier') ||
        loc.startsWith('/messages/') || // fil de discussion + brouillon /messages/new
        loc.startsWith('/checkout') || // /checkout + /checkout/paiement
        loc.startsWith('/commande/') || // /commande/confirmation
        loc == '/favoris' ||
        loc == '/historique' ||
        loc == '/boutiques-suivies' ||
        loc == '/commandes' ||
        loc == '/assistance' ||
        loc == '/parametres';

    if (!loggedIn) return protected ? '/login' : null;

    if (isSupplier && (loc == '/' || loc.startsWith('/dashboard'))) return '/supplier';

    if (loc.startsWith('/supplier')) {
      if (!isSupplier) return '/';
      final sup = st.supplier;
      if (sup == null || !sup.isApproved) return '/pending';
      if (!sup.hasActiveSubscription && loc != '/supplier/plan') return '/supplier/plan';
    }

    if (onAuthPage) return isSupplier ? '/supplier' : '/';
    return null;
  }
}

final _routerNotifierProvider = Provider<_RouterNotifier>((ref) => _RouterNotifier(ref));

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(_routerNotifierProvider);
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),

      // ── Coque acheteur avec barre du bas (5 branches) ──
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => BuyerShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, __) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/categories', builder: (_, __) => const CategoriesScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/dashboard/messages', builder: (_, __) => const MessagesScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/panier', builder: (_, __) => const CartScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/dashboard', builder: (_, __) => const AccountScreen())]),
        ],
      ),

      // ── Hors coque (pas de barre du bas) ──
      // Page de saisie de recherche (historique + autocomplétion).
      GoRoute(
        path: '/recherche',
        builder: (_, s) => SearchEntryScreen(initialQuery: s.extra as String?),
      ),
      // Résultats : lit ?cat=<id> et ?q=<texte> (recherche texte, liens directs).
      // Les catégories de l'accueil s'affichent DANS l'accueil (header fixe).
      GoRoute(
        path: '/search',
        builder: (_, s) => SearchScreen(
          categoryId: s.uri.queryParameters['cat'],
          query: s.uri.queryParameters['q'],
        ),
      ),
      // Recherche par image : fichier local via extra, OU ?url=<image publique>.
      GoRoute(
        path: '/visual-search',
        builder: (_, s) => VisualSearchScreen(
          imagePath: s.extra is String ? s.extra as String : '',
          imageUrl: s.uri.queryParameters['url'],
        ),
      ),
      GoRoute(path: '/produit/:id', builder: (_, s) => ProductScreen(id: s.pathParameters['id']!)),
      // Vitrine publique fournisseur (par slug).
      GoRoute(path: '/fournisseur/:slug', builder: (_, s) => SupplierProfileScreen(slug: s.pathParameters['slug']!)),

      // ── Messagerie ──
      // ⚠️ /messages/new AVANT /messages/:id, sinon « new » serait lu comme un id.
      // Fil BROUILLON ouvert depuis une fiche produit (contexte via `extra`) :
      // rien n'est créé en base avant le 1er message.
      GoRoute(
        path: '/messages/new',
        builder: (_, s) => DraftChatScreen(draft: s.extra is ChatDraft ? s.extra as ChatDraft : null),
      ),
      GoRoute(path: '/messages/:id', builder: (_, s) => ChatScreen(conversationId: s.pathParameters['id']!)),

      // ── Checkout : livraison (adresse + mode) ──
      // Les lignes cochées arrivent du panier via `extra`. Sans extra (lien
      // direct, redémarrage à chaud), on retombe sur tout le panier.
      GoRoute(
        path: '/checkout',
        builder: (_, s) {
          final extra = s.extra;
          final lines = extra is List<CheckoutLine>
              ? extra
              : ref
                  .read(cartProvider)
                  .items
                  .map((it) => CheckoutLine(
                        cartItemId: it.id,
                        productId: it.productId.toString(),
                        quantity: it.quantity,
                      ))
                  .toList();
          return CheckoutScreen(lines: lines);
        },
      ),
      // Appelées par CheckoutScreen — écrans encore à construire.
      GoRoute(path: '/checkout/paiement', builder: (_, __) => const _Stub('Paiement')),
      // Confirmation : commande passée via `extra` (juste après le POST)…
      GoRoute(
        path: '/commande/confirmation',
        builder: (_, s) => OrderConfirmationScreen(
          order: s.extra is Map ? Map<String, dynamic>.from(s.extra as Map) : null,
        ),
      ),
      // …ou rechargée par id (lien depuis « Mes commandes », notification…).
      GoRoute(
        path: '/commande/:id/confirmation',
        builder: (_, s) => OrderConfirmationScreen(orderId: s.pathParameters['id']),
      ),
      GoRoute(path: '/dashboard/addresses', builder: (_, __) => const _Stub('Mes adresses')),

      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
      GoRoute(path: '/pending', builder: (_, __) => const _Stub('Compte en attente')),

      // ── Commandes acheteur (?tab=pending|in_production|shipped|delivered|review) ──
      GoRoute(
        path: '/commandes',
        builder: (_, s) => CommandesScreen(initialTab: s.uri.queryParameters['tab']),
      ),

      // ── Assistance (chat centre d'aide) & paramètres ──
      GoRoute(path: '/assistance', builder: (_, __) => const AssistanceScreen()),
      GoRoute(path: '/parametres', builder: (_, __) => const SettingsScreen()),

      // ── Mon activité ──
      GoRoute(path: '/favoris', builder: (_, __) => const FavorisScreen()),
      GoRoute(path: '/historique', builder: (_, __) => const HistoriqueScreen()),
      GoRoute(path: '/boutiques-suivies', builder: (_, __) => const BoutiquesSuiviesScreen()),

      // ── Espace fournisseur (coque avec barre du bas) ──
      GoRoute(path: '/supplier', builder: (_, __) => const SupplierShell(index: 0, child: SupplierDashboardScreen())),
      GoRoute(path: '/supplier/orders', builder: (_, __) => const SupplierShell(index: 1, child: SupplierOrdersScreen())),
      GoRoute(path: '/supplier/products', builder: (_, __) => const SupplierShell(index: 2, child: SupplierProductsScreen())),
      GoRoute(path: '/supplier/messages', builder: (_, __) => const SupplierShell(index: 3, child: SupplierMessagesScreen())),
      GoRoute(path: '/supplier/settings', builder: (_, __) => const SupplierShell(index: 4, child: SupplierSettingsScreen())),

      // ── Espace fournisseur (plein écran, sans barre du bas) ──
      GoRoute(path: '/supplier/stats', builder: (_, __) => const SupplierStatsScreen()),
      GoRoute(path: '/supplier/reviews', builder: (_, __) => const SupplierReviewsScreen()),
      GoRoute(path: '/supplier/access', builder: (_, __) => const SupplierAccessScreen()),
      // Formulaire produit : ajout…
      GoRoute(
        path: '/supplier/products/new',
        builder: (_, __) => const SupplierProductFormScreen(),
      ),
      // …et modification d'un produit existant.
      GoRoute(
        path: '/supplier/products/:id/edit',
        builder: (_, s) => SupplierProductFormScreen(productId: s.pathParameters['id']),
      ),
      GoRoute(path: '/supplier/plan', builder: (_, __) => const _Stub('Choisir un plan')),
    ],
  );
});

class _Stub extends StatelessWidget {
  final String title;
  const _Stub(this.title);
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(child: Text('$title — à construire')),
      );
}