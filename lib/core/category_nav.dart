import 'package:flutter/material.dart';

/// Mémoire partagée entre les barres de catégories des différentes pages
/// (accueil, résultats). Permet :
///  • de faire partir la pilule de l'ancienne catégorie vers la nouvelle,
///  • de garder la même position de défilement des puces d'une page à l'autre,
///  • de connaître le sens du déplacement (droite / gauche) pour la transition.
class CategoryNav {
  CategoryNav._();

  /// Clé de la catégorie quittée (null = aucune). '__home__' = « Pour vous ».
  static String? lastActiveKey;

  /// Position de défilement horizontale des puces à reprendre.
  static double scrollOffset = 0;

  /// Sens du dernier déplacement : 1 = vers la droite, -1 = vers la gauche.
  /// Par défaut -1 : un « retour » fait sortir la page vers la droite.
  static int lastDir = -1;

  /// Vrai pendant une navigation lancée depuis les puces : l'accueil glisse
  /// alors avec la page de résultats (effet « onglets »). Faux pour toute autre
  /// navigation (fiche produit, etc.) : l'accueil ne bouge pas.
  static bool fromChips = false;

  static const duration = Duration(milliseconds: 320);
  static const curve = Curves.easeOutCubic;

  static int _token = 0;

  /// À appeler juste avant une navigation depuis les puces.
  /// (Jeton : deux touchers rapides ne se « coupent » pas mutuellement.)
  static void beginChipNavigation(int dir) {
    lastDir = dir;
    fromChips = true;
    final t = ++_token;
    Future.delayed(duration + const Duration(milliseconds: 80), () {
      if (t != _token) return;
      fromChips = false;
      lastDir = -1; // un « retour » système ressort vers la droite
    });
  }
}

/// Transition de la page de résultats : glissement horizontal pleine largeur,
/// SANS fondu (aucune transparence → pas d'écran noir, pas de recalcul coûteux).
///
/// • Entrée : arrive du côté de la catégorie touchée ([dirIn] = 1 droite, -1 gauche).
/// • Retour (pop) : repart dans le sens opposé à la navigation.
/// • Recouverte par une autre catégorie (remplacement) : part à l'opposé,
///   collée à la nouvelle page, comme un défilement d'onglets.
Widget categoryAxisTransition(
  Animation<double> animation,
  Animation<double> secondary,
  Widget child, {
  required int dirIn,
}) {
  final inAnim = CurvedAnimation(
    parent: animation,
    curve: CategoryNav.curve,
    reverseCurve: CategoryNav.curve.flipped,
  );
  final outAnim = CurvedAnimation(parent: secondary, curve: CategoryNav.curve);

  return AnimatedBuilder(
    animation: Listenable.merge([animation, secondary]),
    // RepaintBoundary + fond opaque : la page se déplace comme une seule image.
    child: RepaintBoundary(child: ColoredBox(color: Colors.white, child: child)),
    builder: (context, child) {
      final forward = animation.status != AnimationStatus.reverse;
      final inDx = forward ? dirIn.toDouble() : -CategoryNav.lastDir.toDouble();
      // Recouverte : seulement pour un changement de catégorie (pas pour une
      // fiche produit ouverte par-dessus, qui garde son animation habituelle).
      final outDx = CategoryNav.fromChips ? -CategoryNav.lastDir * outAnim.value : 0.0;
      final dx = inDx * (1 - inAnim.value) + outDx;
      return FractionalTranslation(translation: Offset(dx, 0), child: child);
    },
  );
}

/// Transition de l'accueil quand une page de résultats le recouvre (ou le
/// découvre) depuis les puces : il glisse vers la gauche, collé à la page qui
/// arrive. « Pour vous » étant la première puce, l'accueil est toujours à gauche.
Widget categoryCoveredTransition(Animation<double> secondary, Widget child) {
  final outAnim = CurvedAnimation(
    parent: secondary,
    curve: CategoryNav.curve,
    reverseCurve: CategoryNav.curve.flipped,
  );
  return AnimatedBuilder(
    animation: secondary,
    child: RepaintBoundary(child: child),
    builder: (context, child) {
      if (!CategoryNav.fromChips) return child!;
      return FractionalTranslation(translation: Offset(-outAnim.value, 0), child: child);
    },
  );
}