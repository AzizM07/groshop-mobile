import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme.dart';
import '../../data/api/search_api.dart';

/// Page de recherche dédiée (ouverte au tap sur la barre du header).
/// Vide → recherches récentes. En frappe (≥2 car.) → autocomplétion.
class SearchEntryScreen extends ConsumerStatefulWidget {
  final String? initialQuery;
  const SearchEntryScreen({super.key, this.initialQuery});

  @override
  ConsumerState<SearchEntryScreen> createState() => _SearchEntryScreenState();
}

class _SearchEntryScreenState extends ConsumerState<SearchEntryScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _picker = ImagePicker();
  Timer? _debounce;

  List<String> _recent = const [];
  AutoResult _auto = AutoResult.empty;
  bool _loadingAuto = false;

  String get _q => _controller.text.trim();
  bool get _isRecentMode => _q.length < 2;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialQuery ?? '';
    _controller.addListener(_onChanged);
    _loadRecent();
    // autofocus + clavier
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final r = await ref.read(searchApiProvider).recentSearches();
    if (mounted) setState(() => _recent = r);
  }

  void _onChanged() {
    _debounce?.cancel();
    final q = _q;
    if (q.length < 2) {
      setState(() {
        _auto = AutoResult.empty;
        _loadingAuto = false;
      });
      return;
    }
    setState(() => _loadingAuto = true);
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final res = await ref.read(searchApiProvider).autocomplete(q);
      if (!mounted || _q != q) return;
      setState(() {
        _auto = res;
        _loadingAuto = false;
      });
    });
  }

  void _goSearch(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    _focus.unfocus();
    context.pushReplacement('/search?q=${Uri.encodeComponent(t)}');
  }

  void _goProduct(String id) {
    _focus.unfocus();
    context.push('/produit/$id');
  }

  Future<void> _clearRecent() async {
    await ref.read(searchApiProvider).clearRecentSearches();
    if (mounted) setState(() => _recent = const []);
  }

  Future<void> _visualSearch() async {
    _focus.unfocus();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final x = await _picker.pickImage(source: source, imageQuality: 85);
      if (x == null || !mounted) return;
      context.push('/visual-search', extra: x.path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d’ouvrir l’image.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: _isRecentMode ? _recentView() : _autocompleteView(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Barre du haut : back + champ (caméra | input | bouton noir) ──
  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF0F1419)),
            onPressed: () => context.pop(),
          ),
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.only(left: 12, right: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFDADDE1), width: 1.4),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _visualSearch,
                    child: const Icon(Icons.photo_camera_outlined,
                        size: 20, color: Color(0xFF6B7785)),
                  ),
                  Container(
                    width: 1, height: 20,
                    color: const Color(0xFFD9DEE3),
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _goSearch,
                      style: AppTheme.body(size: 15, color: const Color(0xFF0F1419)),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'Rechercher un produit…',
                        hintStyle:
                            AppTheme.body(size: 14.5, color: const Color(0xFF9AA3AE)),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _goSearch(_controller.text),
                    child: Container(
                      width: 54,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F1419),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Icon(Icons.search, size: 18, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Vue "vide" : recherches récentes ──
  Widget _recentView() {
    if (_recent.isEmpty) {
      return const SizedBox.shrink();
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            Text('Recherches récentes',
                style: AppTheme.body(
                    size: 15, weight: FontWeight.w700, color: const Color(0xFF0F1419))),
            const Spacer(),
            GestureDetector(
              onTap: _clearRecent,
              child: const Icon(Icons.delete_outline, size: 20, color: Color(0xFF9AA3AE)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _recent
              .map((t) => GestureDetector(
                    onTap: () => _goSearch(t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F2F4),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(t,
                          style: AppTheme.body(size: 13.5, color: const Color(0xFF3D4853))),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }

  // ── Vue "frappe" : autocomplétion ──
  Widget _autocompleteView() {
    if (_loadingAuto && _auto.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_auto.isEmpty) {
      return const SizedBox.shrink();
    }

    final rows = <Widget>[];

    // Complétions
    for (final c in _auto.completions) {
      rows.add(_completionRow(c));
    }
    // Produits
    if (_auto.products.isNotEmpty) {
      rows.add(_sectionHeader('Produits'));
      for (final p in _auto.products) {
        rows.add(_productRow(p));
      }
    }
    // Catégories
    if (_auto.categories.isNotEmpty) {
      rows.add(_sectionHeader('Catégories'));
      for (final c in _auto.categories) {
        rows.add(_categoryRow(c));
      }
    }

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      children: rows,
    );
  }

  Widget _sectionHeader(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
        child: Text(label.toUpperCase(),
            style: AppTheme.body(
                size: 11, weight: FontWeight.w700, color: const Color(0xFF9AA3AE))),
      );

  Widget _completionRow(String text) {
    final q = _q.toLowerCase();
    final matchesPrefix = q.isNotEmpty && text.toLowerCase().startsWith(q);
    final content = matchesPrefix
        ? Text.rich(TextSpan(
            style: AppTheme.body(size: 14, color: const Color(0xFF333333)),
            children: [
              TextSpan(text: text.substring(0, q.length)),
              TextSpan(
                  text: text.substring(q.length),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ))
        : Text(text, style: AppTheme.body(size: 14, color: const Color(0xFF333333)));

    return InkWell(
      onTap: () => _goSearch(text),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        child: Row(
          children: [
            const Icon(Icons.search, size: 16, color: Color(0xFFBBBBBB)),
            const SizedBox(width: 12),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  Widget _productRow(AutoProduct p) {
    return InkWell(
      onTap: () => _goProduct(p.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 38,
                height: 38,
                color: const Color(0xFFF4F5F7),
                child: (p.image != null && p.image!.isNotEmpty)
                    ? Image.network(p.image!, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox())
                    : const SizedBox(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(size: 14, color: const Color(0xFF333333))),
            ),
            if (p.price != null) ...[
              const SizedBox(width: 10),
              Text('${p.price!.toStringAsFixed(2)} TND',
                  style: AppTheme.body(
                      size: 13, weight: FontWeight.w700, color: const Color(0xFF0F1419))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _categoryRow(AutoCategory c) {
    return InkWell(
      onTap: () => _goSearch(c.name),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        child: Row(
          children: [
            const Icon(Icons.grid_view_outlined, size: 16, color: Color(0xFF9AA3AE)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(size: 14, color: const Color(0xFF333333))),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F5F7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('CATÉGORIE',
                  style: AppTheme.body(
                      size: 10, weight: FontWeight.w600, color: const Color(0xFF9AA3AE))),
            ),
          ],
        ),
      ),
    );
  }
}