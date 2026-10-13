import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/api/products_api.dart';
import '../../data/models/product.dart';
import '../../widgets/product_card.dart';

/// Même règles que VisualSearchModal.jsx.
const _allowedExt = {'jpg', 'jpeg', 'png', 'webp'};
const _maxBytes = 10 * 1024 * 1024; // 10 Mo

/// Erreur affichable telle quelle à l'utilisateur.
class _VsError implements Exception {
  final String message;
  const _VsError(this.message);
}

/// Clé : (chemin local, url distante) — un seul des deux est rempli.
/// autoDispose → une erreur n'est pas gardée en cache ; « Réessayer » relance.
final visualSearchProvider =
    FutureProvider.autoDispose.family<List<Product>, (String, String)>((ref, key) async {
  final (path, url) = key;
  final api = ref.read(productsApiProvider);

  if (url.isNotEmpty) return api.visualSearchByUrl(url);

  final file = File(path);
  if (!file.existsSync()) throw const _VsError('Image introuvable. Choisis-en une autre.');
  final ext = path.split('.').last.toLowerCase();
  if (!_allowedExt.contains(ext)) throw const _VsError('Format non supporté (JPG, PNG, WEBP).');
  if (await file.length() > _maxBytes) throw const _VsError('Image trop lourde (10 Mo max).');
  return api.visualSearch(path);
});

class VisualSearchScreen extends ConsumerWidget {
  /// Fichier local (galerie / appareil photo).
  final String imagePath;
  /// Ou URL publique d'image (ex. image d'un produit depuis Favoris / Historique).
  final String? imageUrl;
  const VisualSearchScreen({super.key, this.imagePath = '', this.imageUrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = imageUrl ?? '';
    final key = (imagePath, url);
    final hasInput = imagePath.isNotEmpty || url.isNotEmpty;
    final async = hasInput
        ? ref.watch(visualSearchProvider(key))
        : const AsyncValue<List<Product>>.data(<Product>[]);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        foregroundColor: const Color(0xFF0F1419),
        title: Text('Recherche par image',
            style: AppTheme.body(size: 16, weight: FontWeight.w700, color: const Color(0xFF0F1419))),
      ),
      body: async.when(
        loading: () => const _Loading(),
        error: (e, _) => ListView(children: [
          _EmptyState(
            icon: '⚠️',
            title: 'Recherche impossible',
            text: e is _VsError ? e.message : 'Vérifie ta connexion ou réessaie avec une autre image.',
            action: e is _VsError ? null : ('Réessayer', () => ref.invalidate(visualSearchProvider(key))),
          ),
        ]),
        data: (items) => CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Row(children: [
                ClipRRect(borderRadius: BorderRadius.circular(10), child: _preview(url)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text('Produits similaires',
                        style: AppTheme.body(size: 14, weight: FontWeight.w700, color: const Color(0xFF0F1419))),
                    const SizedBox(height: 2),
                    Text(
                      '${items.length} résultat${items.length > 1 ? 's' : ''} trouvé${items.length > 1 ? 's' : ''} par image',
                      style: AppTheme.body(size: 12.5, color: const Color(0xFF8A94A0)),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
          if (items.isEmpty)
            const SliverToBoxAdapter(
              child: _EmptyState(
                icon: '🖼️',
                title: 'Aucun produit similaire',
                text: 'Essaie avec une autre image ou une photo plus nette du produit.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 80),
              sliver: SliverToBoxAdapter(child: _MasonryGrid(items: items, columns: 2, gap: 8)),
            ),
        ]),
      ),
    );
  }

  Widget _preview(String url) {
    const empty = SizedBox(width: 56, height: 56, child: ColoredBox(color: Color(0xFFF0F0F0)));
    if (url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url, width: 56, height: 56, fit: BoxFit.cover,
        errorWidget: (_, __, ___) => empty,
      );
    }
    if (imagePath.isNotEmpty && File(imagePath).existsSync()) {
      return Image.file(File(imagePath), width: 56, height: 56, fit: BoxFit.cover, cacheWidth: 168);
    }
    return empty;
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(48),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: Color(0xFFFF7A00)),
            const SizedBox(height: 16),
            Text("Analyse de l'image…", style: AppTheme.body(size: 14, color: const Color(0xFF6B7785))),
          ]),
        ),
      );
}

/// Grille masonry : i % columns, colonnes de hauteur naturelle (pas d'overflow).
class _MasonryGrid extends StatelessWidget {
  final List<Product> items;
  final int columns;
  final double gap;
  const _MasonryGrid({required this.items, this.columns = 2, this.gap = 8});

  @override
  Widget build(BuildContext context) {
    final cols = List.generate(columns, (_) => <Product>[]);
    for (var i = 0; i < items.length; i++) {
      cols[i % columns].add(items[i]);
    }
    final children = <Widget>[];
    for (var c = 0; c < columns; c++) {
      if (c > 0) children.add(SizedBox(width: gap));
      children.add(Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var j = 0; j < cols[c].length; j++) ...[
            if (j > 0) SizedBox(height: gap),
            ProductCard(product: cols[c][j]),
          ],
        ]),
      ));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

class _EmptyState extends StatelessWidget {
  final String icon;
  final String title;
  final String text;
  final (String, VoidCallback)? action;
  const _EmptyState({required this.icon, required this.title, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Text(icon, style: const TextStyle(fontSize: 40)),
        const SizedBox(height: 12),
        Text(title,
            textAlign: TextAlign.center,
            style: AppTheme.body(size: 17, weight: FontWeight.w700, color: const Color(0xFF0F1419))),
        const SizedBox(height: 6),
        Text(text, textAlign: TextAlign.center, style: AppTheme.body(size: 13.5, color: const Color(0xFF9AA3AE))),
        if (action != null) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: action!.$2,
            style: OutlinedButton.styleFrom(
                shape: const StadiumBorder(), side: const BorderSide(color: Color(0xFF0F1419))),
            child: Text(action!.$1,
                style: AppTheme.body(size: 13.5, weight: FontWeight.w700, color: const Color(0xFF0F1419))),
          ),
        ],
      ]),
    );
  }
}