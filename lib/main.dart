import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/push_service.dart';
import 'data/api/api_client.dart';
import 'data/storage/cookie_store.dart';
import 'data/storage/shared_preferences_provider.dart';
import 'firebase_options.dart';
import 'state/auth_provider.dart';
// ⚠️ Fichier où est déclaré `routerProvider` : adapte le nom s'il diffère
// (dans VS Code : Ctrl+Shift+F → « final routerProvider »).
import 'routing/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase (notifications push). Une erreur ici ne doit jamais bloquer l'app.
  var firebaseReady = false;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    firebaseReady = true;
  } catch (e) {
    debugPrint('🔔 Firebase non initialisé : $e');
  }

  // Ads (nécessite google_mobile_ads dans pubspec.yaml).
  await MobileAds.instance.initialize();

  // Init des dépendances, puis on lance la vraie racine.
  final store = CookieStore();
  final dio = await buildDio(store);
  final prefs = await SharedPreferences.getInstance();

  // Conteneur créé ici (au lieu de ProviderScope) pour pouvoir donner le
  // routeur au service de notifications AVANT le premier écran : un tap sur
  // une notification qui a lancé l'app ouvre ainsi le bon écran.
  final container = ProviderContainer(overrides: [
    cookieStoreProvider.overrideWithValue(store),
    dioProvider.overrideWithValue(dio),
    sharedPreferencesProvider.overrideWithValue(prefs),
  ]);

  if (firebaseReady) {
    try {
      await PushService.instance.init(router: container.read(routerProvider));
    } catch (e) {
      debugPrint('🔔 PushService non initialisé : $e');
    }
  }

  runApp(UncontrolledProviderScope(
    container: container,
    child: _PushGate(enabled: firebaseReady, child: const GroshopApp()),
  ));
}

/// Enregistre le téléphone pour les notifications dès que l'utilisateur est
/// connecté (au démarrage s'il l'est déjà, ou juste après sa connexion),
/// et le retire quand il se déconnecte.
class _PushGate extends ConsumerStatefulWidget {
  final bool enabled;
  final Widget child;
  const _PushGate({required this.enabled, required this.child});

  @override
  ConsumerState<_PushGate> createState() => _PushGateState();
}

class _PushGateState extends ConsumerState<_PushGate> {
  bool _registered = false;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    ref.listenManual(authProvider, (prev, next) {
      final loggedIn = next.valueOrNull?.isAuthenticated ?? false;
      if (loggedIn && !_registered) {
        _registered = true;
        PushService.instance.register(ref.read(dioProvider));
      } else if (!loggedIn && _registered) {
        _registered = false;
        PushService.instance.unregister();
      }
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}