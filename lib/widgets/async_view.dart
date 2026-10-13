import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/network_error.dart';
import '../state/connectivity_provider.dart';
import 'no_connection_view.dart';

/// Remplace `value.when(...)` partout.
///
/// - Chargement (ou réessai)            → cercle qui tourne
/// - Erreur réseau + rien en cache      → NoConnectionView
/// - Erreur réseau + données déjà là    → on GARDE les données + bandeau
/// - Autre erreur + rien en cache       → GenericErrorView (pas de code brut)
/// - Connexion qui revient              → réessai automatique
///
/// [topInset] : hauteur d'un header SUPERPOSÉ au contenu (ex. l'accueil, dont
/// le contenu défile derrière le header). Le bandeau hors-ligne et les écrans
/// d'erreur/chargement sont alors décalés d'autant pour rester visibles, et le
/// bandeau flotte au-dessus des données au lieu de les pousser.
class AsyncView<T> extends ConsumerStatefulWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.onRetry,
    required this.data,
    this.minSpinner = const Duration(milliseconds: 700),
    this.topInset = 0,
  });

  final AsyncValue<T> value;

  /// Ex : `() => ref.refresh(productsProvider.future)`
  final Future<Object?> Function() onRetry;

  final Widget Function(T data) data;

  /// Durée minimale du cercle, sinon il clignote quand l'échec est instantané
  /// (mode avion → erreur en quelques ms).
  final Duration minSpinner;

  /// Hauteur d'un header superposé (0 = header classique au-dessus).
  final double topInset;

  @override
  ConsumerState<AsyncView<T>> createState() => _AsyncViewState<T>();
}

class _AsyncViewState<T> extends ConsumerState<AsyncView<T>> {
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await Future.wait<Object?>([
        widget.onRetry().catchError((Object _) => null),
        Future<Object?>.delayed(widget.minSpinner),
      ]);
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  /// Décale un écran plein (chargement / erreur) sous un header superposé.
  Widget _inset(Widget child) =>
      widget.topInset > 0 ? Padding(padding: EdgeInsets.only(top: widget.topInset), child: child) : child;

  @override
  Widget build(BuildContext context) {
    // Relance auto quand le réseau revient.
    ref.listen<AsyncValue<bool>>(connectivityProvider, (prev, next) {
      final wasOffline = prev?.valueOrNull == false;
      final isOnline = next.valueOrNull == true;
      if (wasOffline && isOnline && widget.value.hasError) _retry();
    });

    final value = widget.value;
    final offline = ref.watch(connectivityProvider).valueOrNull == false;

    // 1) Données déjà chargées → on les garde toujours.
    if (value.hasValue) {
      final showBanner = (value.hasError && isNetworkError(value.error)) || offline;
      final banner = AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: showBanner ? OfflineBanner(onRetry: _retry) : const SizedBox(width: double.infinity),
      );

      // Header superposé : le bandeau FLOTTE juste sous le header,
      // les données continuent de défiler derrière (rien ne saute).
      if (widget.topInset > 0) {
        return Stack(children: [
          Positioned.fill(child: widget.data(value.requireValue)),
          Positioned(top: widget.topInset, left: 0, right: 0, child: banner),
        ]);
      }

      return Column(
        children: [
          banner,
          Expanded(child: widget.data(value.requireValue)),
        ],
      );
    }

    // 2) Rien en cache : cercle pendant le chargement / réessai.
    if (_retrying || value.isLoading || !value.hasError) {
      return _inset(const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF7A00)),
      ));
    }

    // 3) Rien en cache + erreur.
    if (isNetworkError(value.error)) {
      return _inset(NoConnectionView(onRetry: _retry));
    }
    return _inset(GenericErrorView(onRetry: _retry));
  }
}