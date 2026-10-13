import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/api/account_api.dart';
import '../../data/models/followed_shop.dart';
import '../../widgets/saved_list_kit.dart';

class BoutiquesSuiviesScreen extends ConsumerStatefulWidget {
  const BoutiquesSuiviesScreen({super.key});
  @override
  ConsumerState<BoutiquesSuiviesScreen> createState() => _BoutiquesSuiviesScreenState();
}

class _BoutiquesSuiviesScreenState extends ConsumerState<BoutiquesSuiviesScreen> {
  List<FollowedShop>? _list;
  bool _editing = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(accountApiProvider).followedShops();
      if (mounted) setState(() => _list = d);
    } catch (_) {
      if (mounted) setState(() => _list = <FollowedShop>[]);
    }
  }

  Future<void> _unfollowSelected() async {
    final ids = _selected.toList();
    setState(() {
      _list = (_list ?? const []).where((s) => !ids.contains(s.id)).toList();
      _selected.clear();
      _editing = false;
    });
    final api = ref.read(accountApiProvider);
    await Future.wait(ids.map((id) => api.unfollowShop(id).catchError((_) {})));
  }

  void _toggleSel(String id) => setState(() {
        _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
      });

  bool get _allSelected => (_list?.isNotEmpty ?? false) && _selected.length == _list!.length;

  void _toggleAll() => setState(() {
        if (_allSelected) {
          _selected.clear();
        } else {
          _selected
            ..clear()
            ..addAll(_list!.map((s) => s.id));
        }
      });

  void _toggleEdit() => setState(() {
        _editing = !_editing;
        _selected.clear();
      });

  @override
  Widget build(BuildContext context) {
    final loading = _list == null;
    final list = _list ?? const <FollowedShop>[];
    final showList = !loading && list.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SavedHeader(title: 'Boutiques suivies', editing: _editing, onToggleEdit: _toggleEdit),
          SavedTab(label: 'Toutes les boutiques (${list.length})'),
          Expanded(
            child: loading
                ? const RowSkeleton(imageSize: 52, circle: true)
                : list.isEmpty
                    ? const SavedEmpty(
                        icon: Icons.storefront_outlined,
                        message: 'Vous ne suivez aucune boutique pour le moment.',
                      )
                    : RefreshIndicator(
                        color: SavedColors.orange,
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          children: [
                            for (final s in list)
                              _ShopRow(
                                s: s,
                                editing: _editing,
                                selected: _selected.contains(s.id),
                                onToggleSel: () => _toggleSel(s.id),
                              ),
                          ],
                        ),
                      ),
          ),
        ]),
      ),
      bottomNavigationBar: (_editing && showList)
          ? SelectionBar(
              allSelected: _allSelected,
              count: _selected.length,
              actionLabel: 'Ne plus suivre',
              onToggleAll: _toggleAll,
              onAction: _unfollowSelected,
            )
          : null,
    );
  }
}

/// Ligne boutique : logo · nom (+ badge vérifié) · ville · nb produits · Visiter
/// + aperçu de 3 produits.
class _ShopRow extends StatelessWidget {
  final FollowedShop s;
  final bool editing;
  final bool selected;
  final VoidCallback onToggleSel;
  const _ShopRow({required this.s, required this.editing, required this.selected, required this.onToggleSel});

  @override
  Widget build(BuildContext context) {
    void open() {
      if (s.slug.isNotEmpty) context.push('/fournisseur/${s.slug}');
    }

    final meta = [
      if (s.city != null) s.city!,
      '${s.productCount} produit${s.productCount > 1 ? 's' : ''}',
    ].join(' · ');

    return GestureDetector(
      onTap: editing ? onToggleSel : open,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SavedColors.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (editing)
              Padding(padding: const EdgeInsets.only(right: 12), child: SelectCheckbox(checked: selected)),
            _Logo(s: s),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(size: 15, weight: FontWeight.w700, color: SavedColors.ink)),
                  ),
                  if (s.verified) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.verified, size: 16, color: Color(0xFF1D72F3)),
                  ],
                ]),
                const SizedBox(height: 3),
                Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(size: 12.5, color: SavedColors.mute)),
              ]),
            ),
            if (!editing)
              GestureDetector(
                onTap: open,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: SavedColors.ink),
                  ),
                  child: Text('Visiter',
                      style: AppTheme.body(size: 13, weight: FontWeight.w600, color: SavedColors.ink)),
                ),
              ),
          ]),
          if (!editing && s.previewImages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: i < s.previewImages.length
                            ? CachedNetworkImage(
                                imageUrl: s.previewImages[i], fit: BoxFit.cover,
                                placeholder: (_, __) => const ColoredBox(color: SavedColors.bg),
                                errorWidget: (_, __, ___) => const ColoredBox(color: SavedColors.bg))
                            : const ColoredBox(color: SavedColors.bg),
                      ),
                    ),
                  ),
                ],
              ]),
            ),
        ]),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  final FollowedShop s;
  const _Logo({required this.s});

  @override
  Widget build(BuildContext context) {
    final initial = Container(
      color: SavedColors.soft,
      alignment: Alignment.center,
      child: Text(s.name.isNotEmpty ? s.name.characters.first.toUpperCase() : '?',
          style: AppTheme.body(size: 19, weight: FontWeight.w700, color: SavedColors.orange)),
    );
    return ClipOval(
      child: SizedBox(
        width: 52, height: 52,
        child: s.logo != null
            ? CachedNetworkImage(
                imageUrl: s.logo!, fit: BoxFit.cover,
                placeholder: (_, __) => initial,
                errorWidget: (_, __, ___) => initial)
            : initial,
      ),
    );
  }
}