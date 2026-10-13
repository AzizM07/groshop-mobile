import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// true = une interface réseau est active (Wi-Fi / données).
/// Sert à relancer automatiquement quand la connexion revient.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  yield _isOnline(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(_isOnline).distinct();
});

bool _isOnline(List<ConnectivityResult> results) =>
    results.any((r) => r != ConnectivityResult.none);