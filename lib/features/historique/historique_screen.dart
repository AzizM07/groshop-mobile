import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/api/account_api.dart';
import '../../data/api/products_api.dart';
import '../../data/models/history_entry.dart';
import '../../data/models/product.dart';
import '../../widgets/saved_list_kit.dart';

class HistoriqueScreen extends ConsumerStatefulWidget {
  const HistoriqueScreen({super.key});
  @override
  ConsumerState<HistoriqueScreen> createState() => _HistoriqueScreenState();
}

class _HistoriqueScreenState extends ConsumerState<HistoriqueScreen> {
  List<HistoryEntry>? _list;
  List<Product>? _reco;
  bool _editing = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final account = ref.read(accountApiProvider);
    final products = ref.read(productsApiProvider);
    account.history().then((d) {
      if (mounted) setState(() => _list = d);
    }).catchError((_) {
      if (mounted) setState(() => _list = <HistoryEntry>[]);
    });
    products.recommended().then((d) {
      if (mounted) setState(() => _reco = d);
    }).catchError((_) {
      if (mounted) setState(() => _reco = <Product>[]);
    });
  }

  Future<void> _removeSelected() async {
    final ids = _selected.toList();
    setState(() {
      _list = (_list ?? const []).where((e) => !ids.contains(e.product.id)).toList();
      _selected.clear();
      _editing = false;
    });
    try {
      await ref.read(accountApiProvider).removeHistory(ids);
    } catch (_) {/* optimiste */}
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Effacer l'historique ?"),
        content: const Text('Tous les produits consultés seront retirés de cette liste.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Effacer', style: TextStyle(color: SavedColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _list = const [];
      _selected.clear();
      _editing = false;
    });
    try {
      await ref.read(accountApiProvider).clearHistory();
    } catch (_) {/* optimiste */}
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
            ..addAll(_list!.map((e) => e.product.id));
        }
      });

  void _toggleEdit() => setState(() {
        _editing = !_editing;
        _selected.clear();
      });

  static String _dayLabel(DateTime? d) {
    if (d == null) return 'Plus ancien';
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff <= 0) return "Aujourd'hui";
    if (diff == 1) return 'Hier';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  List<Widget> _rows(List<HistoryEntry> list) {
    final out = <Widget>[];
    String? current;
    for (final e in list) {
      final label = _dayLabel(e.viewedAt);
      if (label != current) {
        current = label;
        out.add(Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 2),
          child: Text(label, style: AppTheme.body(size: 13, weight: FontWeight.w600, color: SavedColors.mute)),
        ));
      }
      out.add(ProductSavedRow(
        p: e.product,
        editing: _editing,
        selected: _selected.contains(e.product.id),
        onToggleSel: () => _toggleSel(e.product.id),
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final loading = _list == null;
    final list = _list ?? const <HistoryEntry>[];
    final reco = (_reco ?? const <Product>[]).take(10).toList();
    final showList = !loading && list.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SavedHeader(title: 'Historique', editing: _editing, onToggleEdit: _toggleEdit),
          SavedTab(
            label: 'Tous les articles (${list.length})',
            trailing: (showList && !_editing)
                ? GestureDetector(
                    onTap: _clearAll,
                    child: Text('Tout effacer', style: AppTheme.body(size: 12.5, color: SavedColors.faint)),
                  )
                : null,
          ),
          Expanded(
            child: loading
                ? const RowSkeleton()
                : list.isEmpty
                    ? const SavedEmpty(icon: Icons.history, message: 'Aucun produit consulté récemment.')
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        children: [
                          ..._rows(list),
                          if (reco.isNotEmpty && !_editing) RecoSection(items: reco),
                        ],
                      ),
          ),
        ]),
      ),
      bottomNavigationBar: (_editing && showList)
          ? SelectionBar(
              allSelected: _allSelected,
              count: _selected.length,
              actionLabel: 'Retirer',
              onToggleAll: _toggleAll,
              onAction: _removeSelected,
            )
          : null,
    );
  }
}