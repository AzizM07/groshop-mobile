import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'native_ad_pool.dart';

/// Cellule native ad.
///
/// Deux usages :
/// - Sans [width] / [height] / [autoHeight] : la cellule remplit la taille
///   imposée par le parent (comportement historique).
/// - Mode auto (dès qu'un de ces paramètres est donné) : la cellule calcule
///   elle-même sa hauteur = largeur (image carrée) + hauteur du texte, comme
///   une carte produit — [height] est alors ignoré. Elle se referme
///   complètement (0 × 0, [margin] compris) si aucune pub n'est dispo.
class NativeAdTile extends ConsumerStatefulWidget {
  const NativeAdTile({
    super.key,
    this.width,
    this.height,
    this.autoHeight = false,
    this.margin = EdgeInsets.zero,
  });

  /// Largeur imposée (obligatoire dans une rangée horizontale).
  final double? width;

  /// Ancien paramètre : conservé pour compatibilité, active le mode auto.
  final double? height;

  /// Mode auto sans largeur imposée (la cellule prend la largeur du parent).
  final bool autoHeight;

  /// Marge appliquée uniquement quand la cellule est visible.
  final EdgeInsets margin;

  bool get _selfSized => width != null || height != null || autoHeight;

  /// Hauteur d'une carte pub pour une largeur donnée : image carrée + texte.
  /// Doit rester alignée sur res/layout/groshop_native_ad.xml :
  ///   fixe  = en-tête 18 + 6 · marge titre 6 · marge étoiles 2 · bouton 7 + 28 · bas 4 (+ marge 6)
  ///   texte = titre 2 lignes (~36) + étoiles (~14), multiplié par la taille de police système.
  static double heightFor(BuildContext context, double width) {
    const fixed = 77.0;
    const text = 50.0;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);
    return width + fixed + text * scale;
  }

  @override
  ConsumerState<NativeAdTile> createState() => _NativeAdTileState();
}

class _NativeAdTileState extends ConsumerState<NativeAdTile>
    with AutomaticKeepAliveClientMixin {
  NativeAd? _ad;
  bool _givenUp = false; // vrai = aucune ad dispo → on masque la cellule

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tryTake();
  }

  // Essaie de piocher une ad prête ; réessaie une fois plus tard si le pool
  // n'a encore rien (le temps que les 1res ads chargent au démarrage).
  void _tryTake() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ad = ref.read(nativeAdPoolProvider.notifier).take();
      if (ad != null) {
        setState(() => _ad = ad);
      } else {
        // 2e chance après un court délai (pool encore en train de charger).
        Future.delayed(const Duration(seconds: 3), () {
          if (!mounted || _ad != null) return;
          final retry = ref.read(nativeAdPoolProvider.notifier).take();
          if (retry != null) {
            setState(() => _ad = retry);
          } else {
            setState(() => _givenUp = true); // vraiment rien → on masque
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _ad?.dispose(); // l'ad appartient à la cellule une fois piochée
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Aucune ad : cellule refermée. En mode auto, rien ne reste ;
    // en mode historique, le parent garde la place qu'il a réservée.
    if (_givenUp) return const SizedBox.shrink();

    // En attente → skeleton ; sinon l'AdWidget remplit la taille disponible.
    final Widget body = _ad == null
        ? const _AdSkeleton()
        : SizedBox.expand(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AdWidget(ad: _ad!),
            ),
          );

    if (!widget._selfSized) return body;

    return Padding(
      padding: widget.margin,
      child: LayoutBuilder(builder: (context, c) {
        final w = widget.width ?? (c.maxWidth.isFinite ? c.maxWidth : 150.0);
        return SizedBox(width: w, height: NativeAdTile.heightFor(context, w), child: body);
      }),
    );
  }
}

/// Skeleton animé (shimmer maison, sans package) affiché le temps qu'une ad
/// soit prête. Remplit la taille disponible → aucun saut de layout.
class _AdSkeleton extends StatefulWidget {
  const _AdSkeleton();
  @override
  State<_AdSkeleton> createState() => _AdSkeletonState();
}

class _AdSkeletonState extends State<_AdSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment(-1 - 2 * _c.value, 0),
              end: Alignment(1 - 2 * _c.value, 0),
              colors: const [Color(0xFFEDEFF1), Color(0xFFF6F7F8), Color(0xFFEDEFF1)],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
        );
      },
    );
  }
}