// lib/core/push_service.dart — GROSHOP mobile
// Notifications push via Firebase Cloud Messaging (FCM).
//
// • Enregistre le token FCM de l'appareil auprès de Django
//   (POST /notifications/register/ — même endpoint que le site web).
// • Affiche les notifications reçues quand l'app est OUVERTE (Android ne le
//   fait pas tout seul) via flutter_local_notifications.
// • Au tap sur une notification, ouvre l'écran indiqué par `data.link`
//   (ex. « /produit/<id> », « /commandes », ou une URL https://groshop.tn/...).
//
// Dépendances :
//   flutter pub add firebase_core firebase_messaging flutter_local_notifications

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

import '../firebase_options.dart'; // généré par `flutterfire configure`

/// Messages reçus app fermée / en arrière-plan : Android les affiche tout seul
/// (bloc « notification » du message). Ce handler doit rester une fonction
/// de premier niveau.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final FirebaseMessaging _fm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  GoRouter? _router;
  Dio? _dio;
  String? _token;
  bool _initialized = false;

  static const _channel = AndroidNotificationChannel(
    'groshop_default',
    'Notifications GROSHOP',
    description: 'Commandes, messages et promotions',
    importance: Importance.high,
  );

  /// À appeler UNE fois au démarrage, après Firebase.initializeApp().
  Future<void> init({required GoRouter router}) async {
    if (_initialized) return;
    _initialized = true;
    _router = router;

    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

    // Notifications locales (affichage quand l'app est au premier plan)
    // flutter_local_notifications ≥ 20 : paramètres NOMMÉS (settings:, id:, …)
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (r) => _open(r.payload),
    );
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // iOS : afficher aussi la bannière quand l'app est ouverte
    await _fm.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

    // App ouverte → on affiche nous-mêmes
    FirebaseMessaging.onMessage.listen(_showForeground);

    // Tap sur une notification, app en arrière-plan
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m.data['link']));

    // Tap sur une notification, app complètement fermée
    final initial = await _fm.getInitialMessage();
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(initial.data['link']));
    }

    // Le token peut changer (réinstallation, nettoyage…) → on le renvoie
    _fm.onTokenRefresh.listen((t) {
      _token = t;
      _send(t);
    });
  }

  /// À appeler juste APRÈS la connexion (ou au démarrage si déjà connecté).
  /// Demande la permission (Android 13+ / iOS) puis enregistre le token.
  Future<void> register(Dio dio) async {
    _dio = dio;
    final settings = await _fm.requestPermission(alert: true, badge: true, sound: true);
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('🔕 Notifications refusées par l’utilisateur');
      return;
    }
    final t = await _fm.getToken();
    if (t == null) return;
    _token = t;
    debugPrint('🔔 Token FCM : $t'); // pratique pour un test depuis la console Firebase
    await _send(t);
  }

  /// À appeler AVANT la déconnexion : l'appareil ne reçoit plus les
  /// notifications de ce compte.
  Future<void> unregister() async {
    final d = _dio, t = _token;
    if (d == null || t == null) return;
    try {
      await d.post('/notifications/unregister/', data: {'token': t});
    } catch (_) {}
  }

  Future<void> _send(String token) async {
    final d = _dio;
    if (d == null) return; // pas encore connecté : register() l'enverra
    try {
      final r = await d.post('/notifications/register/', data: {
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
      debugPrint('🔔 Enregistrement token → HTTP ${r.statusCode}');
    } catch (e) {
      debugPrint('🔔 Enregistrement token échoué : $e');
    }
  }

  void _showForeground(RemoteMessage m) {
    final n = m.notification;
    if (n == null) return;
    if (Platform.isIOS) return; // iOS l'affiche déjà (presentation options)
    _local.show(
      id: m.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFFFF7A00),
        ),
      ),
      payload: m.data['link'],
    );
  }

  /// `link` peut être un chemin (« /produit/123 ») ou une URL complète
  /// (« https://groshop.tn/produit/123 ») : on garde le chemin, qui correspond
  /// aux routes de l'app.
  void _open(String? link) {
    if (link == null || link.trim().isEmpty) return;
    var path = link.trim();
    final uri = Uri.tryParse(path);
    if (uri != null && uri.hasScheme) {
      path = uri.path.isEmpty ? '/' : uri.path;
      if (uri.hasQuery) path = '$path?${uri.query}';
    }
    try {
      _router?.push(path);
    } catch (e) {
      debugPrint('🔔 Lien de notification inconnu : $link ($e)');
      _router?.go('/');
    }
  }
}