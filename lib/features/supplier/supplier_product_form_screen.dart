import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../data/api/network_error.dart';
import '../../data/api/product_form_api.dart';
import '../../data/api/supplier_api.dart';
import '../../widgets/no_connection_view.dart';

// ═══════ Palette (identique au dashboard) ═══════
const _orange = Color(0xFFFF8A00);
const _orangeSoft = Color(0xFFFFEEDB);
const _orangeLine = Color(0xFFFFC380);
const _green = Color(0xFF1FB57A);
const _red = Color(0xFFE5484D);
const _redSoft = Color(0xFFFFE4E4);
const _amber = Color(0xFF8A5A00);
const _amberSoft = Color(0xFFFFF4D6);
const _violet = Color(0xFF8B5CF6);
const _violetSoft = Color(0xFFF0EAFF);
const _bg = Color(0xFFFAFAFB);
const _ink = Color(0xFF1E1E2D);
const _sub = Color(0xFF4A4A5A);
const _mute = Color(0xFF8A8A99);
const _faint = Color(0xFFB5B5C3);
const _tile = Color(0xFFF4F4F6);
const _line = Color(0xFFE9E9EF);

const _shadow = <BoxShadow>[
  BoxShadow(color: Color(0x0F1B1B3A), blurRadius: 24, offset: Offset(0, 8)),
];

const _shipModes = [('free', 'Gratuite'), ('flat', 'Fixe'), ('tiered', 'Par tranche'), ('per_block', 'Par palier')];
const _fieldTypes = [('text', 'Texte court'), ('number', 'Nombre'), ('image', 'Image'), ('file', 'Fichier'), ('color', 'Couleur')];

String _fmt3(num v) => v.toStringAsFixed(3);
double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
int? _int(String s) => int.tryParse(s.trim());
String _s(dynamic v) => v == null ? '' : v.toString();
int _uid = 0;
String _newId() => 'id${_uid++}';

// ═══════ Modèles d'état ═══════
class _TierRow {
  final min = TextEditingController();
  final price = TextEditingController();
  final old = TextEditingController();
  _TierRow([String m = '', String p = '', String o = '']) {
    min.text = m;
    price.text = p;
    old.text = o;
  }
  bool get complete => min.text.trim().isNotEmpty && price.text.trim().isNotEmpty;
  void dispose() {
    min.dispose();
    price.dispose();
    old.dispose();
  }
}

class _ShipRow {
  final min = TextEditingController();
  final price = TextEditingController();
  _ShipRow([String m = '', String p = '']) {
    min.text = m;
    price.text = p;
  }
  bool get complete => min.text.trim().isNotEmpty && price.text.trim().isNotEmpty;
  void dispose() {
    min.dispose();
    price.dispose();
  }
}

class _SpecRow {
  final key = TextEditingController();
  final val = TextEditingController();
  _SpecRow([String k = '', String v = '']) {
    key.text = k;
    val.text = v;
  }
  void dispose() {
    key.dispose();
    val.dispose();
  }
}

class _Img {
  final String id = _newId();
  String url;
  bool primary;
  bool uploading;
  _Img({this.url = '', this.primary = false, this.uploading = false});
}

class _Variant {
  final name = TextEditingController();
  String imageUrl;
  bool uploading = false;
  _Variant([String n = '', this.imageUrl = '']) {
    name.text = n;
  }
  void dispose() => name.dispose();
}

class _Group {
  final name = TextEditingController();
  final variants = <_Variant>[];
  _Group([String n = '']) {
    name.text = n;
  }
  void dispose() {
    name.dispose();
    for (final v in variants) {
      v.dispose();
    }
  }
}

class _Combo {
  final String id = _newId();
  final sel = <int, String>{};
  final tiers = <_TierRow>[_TierRow()];
  void dispose() {
    for (final t in tiers) {
      t.dispose();
    }
  }
}

class _CField {
  final String id = _newId();
  final label = TextEditingController();
  final maxChars = TextEditingController();
  String type;
  bool required;
  _CField({String l = '', this.type = 'text', this.required = true, String mc = ''}) {
    label.text = l;
    maxChars.text = mc;
  }
  void dispose() {
    label.dispose();
    maxChars.dispose();
  }
}

/// Validation des tranches (port exact de priceTierIssues du web).
({List<String?> errs, bool ok}) _tierIssues(List<_TierRow> rows) {
  final errs = List<String?>.filled(rows.length, null);
  var ok = true;
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    if (!r.complete) continue;
    final min = _num(r.min.text) ?? 0;
    final price = _num(r.price.text) ?? 0;
    final old = r.old.text.trim().isEmpty ? null : _num(r.old.text);
    if (min < 1) {
      errs[i] = 'Quantité de départ ≥ 1';
      ok = false;
      continue;
    }
    if (i > 0) {
      final prev = rows[i - 1];
      final pMin = _num(prev.min.text);
      final pPrice = _num(prev.price.text);
      if (pMin != null && min <= pMin) {
        errs[i] = 'La quantité doit dépasser la tranche précédente';
        ok = false;
        continue;
      }
      if (pPrice != null && price >= pPrice) {
        errs[i] = 'Le prix doit être inférieur à la tranche précédente (${_fmt3(pPrice)})';
        ok = false;
        continue;
      }
    }
    if (old != null && old <= price) {
      errs[i] = "L'ancien prix doit être supérieur au prix";
      ok = false;
    }
  }
  return (errs: errs, ok: ok);
}

String _tierRange(List<dynamic> rows, int i) {
  String minOf(dynamic r) => r is _TierRow ? r.min.text.trim() : (r as _ShipRow).min.text.trim();
  final m = _int(minOf(rows[i]));
  if (m == null) return '—';
  final next = i + 1 < rows.length ? _int(minOf(rows[i + 1])) : null;
  if (next == null) return '$m+';
  return '$m–${next - 1 < m ? m : next - 1}';
}

// ═══════ Écran ═══════
class SupplierProductFormScreen extends ConsumerStatefulWidget {
  /// null = ajout, sinon id du produit à modifier.
  final String? productId;
  const SupplierProductFormScreen({super.key, this.productId});

  @override
  ConsumerState<SupplierProductFormScreen> createState() => _SupplierProductFormScreenState();
}

class _SupplierProductFormScreenState extends ConsumerState<SupplierProductFormScreen> {
  bool get _isEdit => widget.productId != null;

  // Chargement (édition)
  bool _pageLoading = false;
  Object? _loadError;

  // Général
  final _name = TextEditingController();
  final _unit = TextEditingController();
  final _brand = TextEditingController();
  final _reference = TextEditingController();
  final _description = TextEditingController();
  String _category = '';
  final _specs = <_SpecRow>[];

  // Médias
  final _images = <_Img>[];
  String _videoUrl = '';
  String _videoPoster = '';
  bool _videoUploading = false;

  // Prix
  final _tiers = <_TierRow>[_TierRow()];
  bool _priceHidden = false;

  // Variantes
  final _groups = <_Group>[];
  final _combos = <_Combo>[];

  // Personnalisation
  bool _custAllow = false;
  String _custMode = 'fixed';
  bool _custRequired = false;
  final _custExtra = TextEditingController();
  final _custInstructions = TextEditingController();
  final _custFields = <_CField>[];

  // Disponibilité & livraison
  bool _inStock = true;
  String _shipMode = 'flat';
  final _shipPrice = TextEditingController();
  final _blockSize = TextEditingController(text: '10');
  final _blockPrice = TextEditingController();
  final _deliveryDays = TextEditingController(text: '3');
  final _shipTiers = <_ShipRow>[_ShipRow()];

  // Envoi
  Map<String, String> _errors = {};
  bool _submitting = false;

  final _keys = {
    for (final k in ['name', 'category', 'price_tiers', 'combos', 'customization', 'shipping', 'images'])
      k: GlobalKey(),
  };

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (_isEdit) _loadProduct();
  }

  @override
  void dispose() {
    for (final c in [
      _name, _unit, _brand, _reference, _description, _custExtra, _custInstructions,
      _shipPrice, _blockSize, _blockPrice, _deliveryDays,
    ]) {
      c.dispose();
    }
    for (final x in _specs) {
      x.dispose();
    }
    for (final x in _tiers) {
      x.dispose();
    }
    for (final x in _groups) {
      x.dispose();
    }
    for (final x in _combos) {
      x.dispose();
    }
    for (final x in _custFields) {
      x.dispose();
    }
    for (final x in _shipTiers) {
      x.dispose();
    }
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String _errMsg(Object e) {
    if (isNetworkError(e)) return 'Pas de connexion Internet. Réessayez.';
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map) {
        for (final k in ['error', 'detail', 'message']) {
          if (d[k] is String) return d[k] as String;
        }
        for (final entry in d.entries) {
          final v = entry.value;
          if (v is List && v.isNotEmpty) return '${entry.key} : ${v.first}';
        }
      }
      if (e.response?.statusCode == 401) return 'Session expirée. Reconnecte-toi puis réessaie.';
    }
    return 'Une erreur est survenue. Réessayez.';
  }

  // ═══════ Chargement (édition) ═══════
  Future<void> _loadProduct() async {
    setState(() {
      _pageLoading = true;
      _loadError = null;
    });
    try {
      final p = await ref.read(productFormApiProvider).detail(widget.productId!);
      if (!mounted) return;
      _hydrate(p);
      setState(() => _pageLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _pageLoading = false;
          _loadError = e;
        });
      }
    }
  }

  void _hydrate(Map<String, dynamic> p) {
    _name.text = _s(p['name']);
    final cat = p['category'] ?? p['category_id'];
    _category = cat is Map ? _s(cat['id']) : _s(cat);
    _description.text = _s(p['description']);
    _brand.text = _s(p['brand']);
    _reference.text = _s(p['reference']);
    _unit.text = _s(p['unit']);
    _inStock = p['in_stock'] != false;
    _shipMode = _s(p['shipping_mode']).isEmpty ? 'flat' : _s(p['shipping_mode']);
    _shipPrice.text = _s(p['shipping_price_tnd']);
    _blockSize.text = _s(p['shipping_block_size'] ?? 10);
    _blockPrice.text = _s(p['shipping_block_price']);
    _deliveryDays.text = _s(p['delivery_days'] ?? 3);
    _videoUrl = _s(p['video_url']);
    _videoPoster = _s(p['video_poster_url']);
    _priceHidden = p['price_visibility'] == 'verified_only';

    // Caractéristiques
    for (final line in _s(p['specs_raw']).split('\n')) {
      if (line.trim().isEmpty) continue;
      final idx = line.indexOf(':');
      _specs.add(idx == -1
          ? _SpecRow(line.trim())
          : _SpecRow(line.substring(0, idx).trim(), line.substring(idx + 1).trim()));
    }

    // Images
    for (final im in (p['images'] as List? ?? const []).whereType<Map>()) {
      final url = _s(im['url']).isNotEmpty ? _s(im['url']) : _s(im['image']);
      if (url.isNotEmpty) _images.add(_Img(url: url, primary: im['is_primary'] == true));
    }
    if (_images.isNotEmpty && !_images.any((i) => i.primary)) _images.first.primary = true;

    // Tranches
    final tiers = (p['price_tiers'] as List? ?? const []).whereType<Map>().toList();
    if (tiers.isNotEmpty) {
      for (final t in _tiers) {
        t.dispose();
      }
      _tiers
        ..clear()
        ..addAll(tiers.map((t) => _TierRow(_s(t['min_qty']), _s(t['price_tnd']), _s(t['old_price_tnd']))));
    }
    final ship = (p['shipping_tiers'] as List? ?? const []).whereType<Map>().toList();
    if (ship.isNotEmpty) {
      for (final t in _shipTiers) {
        t.dispose();
      }
      _shipTiers
        ..clear()
        ..addAll(ship.map((t) => _ShipRow(_s(t['min_qty']), _s(t['price_tnd']))));
    }

    // Groupes & variantes
    for (final g in (p['choice_groups'] as List? ?? const []).whereType<Map>()) {
      final grp = _Group(_s(g['name']));
      for (final v in (g['variants'] as List? ?? const []).whereType<Map>()) {
        grp.variants.add(_Variant(_s(v['name']), _s(v['image_url']).isNotEmpty ? _s(v['image_url']) : _s(v['image'])));
      }
      _groups.add(grp);
    }

    // Combinaisons
    for (final c in (p['variant_combos'] as List? ?? const []).whereType<Map>()) {
      final combo = _Combo();
      for (final s in (c['selections'] as List? ?? const []).whereType<Map>()) {
        final gi = _groups.indexWhere((g) => g.name.text == _s(s['group']));
        if (gi >= 0) combo.sel[gi] = _s(s['variant']);
      }
      final ct = (c['price_tiers'] as List? ?? const []).whereType<Map>().toList();
      if (ct.isNotEmpty) {
        for (final t in combo.tiers) {
          t.dispose();
        }
        combo.tiers
          ..clear()
          ..addAll(ct.map((t) => _TierRow(_s(t['min_qty']), _s(t['price_tnd']), _s(t['old_price_tnd']))));
      }
      _combos.add(combo);
    }

    // Personnalisation
    _custAllow = p['allow_customization'] == true;
    _custMode = _s(p['customization_mode']).isEmpty ? 'fixed' : _s(p['customization_mode']);
    _custRequired = p['customization_required'] == true;
    _custExtra.text = _s(p['customization_extra_price_tnd']);
    _custInstructions.text = _s(p['customization_instructions']);
    for (final f in (p['customization_fields'] as List? ?? const []).whereType<Map>()) {
      final cons = f['constraints'] is Map ? f['constraints'] as Map : const {};
      _custFields.add(_CField(
        l: _s(f['label']),
        type: _s(f['field_type']).isEmpty ? 'text' : _s(f['field_type']),
        required: f['required'] != false,
        mc: _s(cons['max_chars']),
      ));
    }
  }

  // ═══════ Médias ═══════
  Future<void> _pickImages() async {
    final files = await _picker.pickMultiImage(imageQuality: 85, maxWidth: 2000);
    if (files.isEmpty) return;
    final api = ref.read(productFormApiProvider);
    for (final f in files) {
      final im = _Img(uploading: true);
      setState(() => _images.add(im));
      try {
        final url = await api.uploadImage(f.path);
        if (!mounted) return;
        setState(() {
          im
            ..url = url
            ..uploading = false;
          if (!_images.any((x) => x.primary && x.url.isNotEmpty)) im.primary = true;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _images.remove(im));
        _snack(_errMsg(e));
      }
    }
  }

  void _removeImage(_Img im) => setState(() {
        _images.remove(im);
        if (_images.isNotEmpty && !_images.any((x) => x.primary)) _images.first.primary = true;
      });

  void _setPrimary(_Img im) => setState(() {
        for (final x in _images) {
          x.primary = identical(x, im);
        }
      });

  Future<void> _pickVideo() async {
    final f = await _picker.pickVideo(source: ImageSource.gallery);
    if (f == null) return;
    setState(() => _videoUploading = true);
    try {
      final r = await ref.read(productFormApiProvider).uploadVideo(f.path);
      if (!mounted) return;
      setState(() {
        _videoUrl = r.url;
        _videoPoster = r.poster;
      });
    } catch (e) {
      if (mounted) _snack(_errMsg(e));
    } finally {
      if (mounted) setState(() => _videoUploading = false);
    }
  }

  Future<void> _pickVariantImage(_Variant v) async {
    final f = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1200);
    if (f == null) return;
    setState(() => v.uploading = true);
    try {
      final url = await ref.read(productFormApiProvider).uploadImage(f.path);
      if (mounted) setState(() => v.imageUrl = url);
    } catch (e) {
      if (mounted) _snack(_errMsg(e));
    } finally {
      if (mounted) setState(() => v.uploading = false);
    }
  }

  // ═══════ Groupes utiles ═══════
  List<({int gi, String name, List<String> variants})> get _namedGroups => [
        for (var gi = 0; gi < _groups.length; gi++)
          (
            gi: gi,
            name: _groups[gi].name.text.trim(),
            variants: _groups[gi].variants.map((v) => v.name.text.trim()).where((x) => x.isNotEmpty).toList(),
          )
      ].where((g) => g.name.isNotEmpty && g.variants.isNotEmpty).toList();

  // ═══════ Envoi ═══════
  Future<void> _submit(String status) async {
    final errs = <String, String>{};
    if (_name.text.trim().isEmpty) errs['name'] = 'Nom requis';
    if (_category.isEmpty) errs['category'] = 'Catégorie requise';
    if (_videoUploading) errs['images'] = 'Attends la fin de l’upload vidéo';
    if (_images.any((i) => i.uploading)) errs['images'] = 'Attends la fin des uploads';

    final complete = _tiers.where((t) => t.complete).toList();
    if (complete.isEmpty) {
      errs['price_tiers'] = 'Ajoute au moins une tranche de prix';
    } else if (!_tierIssues(_tiers).ok) {
      errs['price_tiers'] = 'Corrige les tranches en rouge';
    }

    if (_shipMode == 'tiered' && !_shipTiers.any((t) => t.complete)) {
      errs['shipping'] = 'Ajoute au moins une tranche de livraison';
    }
    if (_shipMode == 'per_block' && (_blockSize.text.trim().isEmpty || _blockPrice.text.trim().isEmpty)) {
      errs['shipping'] = 'Renseigne le palier et le frais par palier';
    }

    final named = _namedGroups;
    final comboKeys = <String>[];
    for (final c in _combos) {
      final picked = named.where((g) => (c.sel[g.gi] ?? '').isNotEmpty).toList();
      final hasTiers = c.tiers.any((t) => t.complete);
      if (picked.isEmpty && !hasTiers) continue;
      if (picked.length != named.length) {
        errs['combos'] = 'Choisis une option par groupe';
        break;
      }
      if (!_tierIssues(c.tiers).ok || !hasTiers) {
        errs['combos'] = 'Corrige les tranches des prix par variante';
        break;
      }
      comboKeys.add(named.map((g) => c.sel[g.gi]).join('|'));
    }
    if (!errs.containsKey('combos') && comboKeys.toSet().length != comboKeys.length) {
      errs['combos'] = 'Deux prix spécifiques visent la même combinaison';
    }

    final customFields = _custFields.where((f) => f.label.text.trim().isNotEmpty).toList();
    if (_custAllow && customFields.isEmpty) {
      errs['customization'] = "Ajoute au moins un champ que l'acheteur devra remplir";
    }
    if (_custAllow && _custMode == 'fixed' && _custExtra.text.trim().isNotEmpty) {
      final v = _num(_custExtra.text);
      if (v == null || v < 0) errs['customization'] = 'Surcoût perso invalide';
    }

    setState(() => _errors = errs);
    if (errs.isNotEmpty) {
      _scrollTo(errs.keys.first);
      return;
    }

    List<Map<String, dynamic>> tiersJson(List<_TierRow> rows) => rows
        .where((t) => t.complete)
        .map((t) => {
              'min_qty': _int(t.min.text) ?? _num(t.min.text)?.round() ?? 0,
              'price_tnd': _num(t.price.text) ?? 0,
              'old_price_tnd': t.old.text.trim().isEmpty ? null : _num(t.old.text),
            })
        .toList();

    final specsRaw = _specs
        .where((r) => r.key.text.trim().isNotEmpty)
        .map((r) => '${r.key.text.trim()}: ${r.val.text.trim()}')
        .join('\n');

    final payload = <String, dynamic>{
      'name': _name.text.trim(),
      'category': _category,
      'description': _description.text,
      'brand': _brand.text,
      'reference': _reference.text,
      'unit': _unit.text,
      'specs_raw': specsRaw,
      'video_url': _videoUrl,
      'video_poster_url': _videoPoster,
      'in_stock': _inStock,
      'delivery_days': _int(_deliveryDays.text) ?? 3,
      'shipping_mode': _shipMode,
      'shipping_price_tnd': _shipMode == 'flat' ? (_num(_shipPrice.text) ?? 0) : 0,
      'shipping_block_size': _int(_blockSize.text) ?? 10,
      'shipping_block_price': _shipMode == 'per_block' ? (_num(_blockPrice.text) ?? 0) : 0,
      'price_visibility': _priceHidden ? 'verified_only' : 'public',
      'status': status,
      'images': [
        for (final (i, im) in _images.where((x) => x.url.isNotEmpty).indexed)
          {'url': im.url, 'is_primary': im.primary, 'sort_order': i},
      ],
      'price_tiers': tiersJson(_tiers),
      'shipping_tiers': _shipMode == 'tiered'
          ? _shipTiers
              .where((t) => t.complete)
              .map((t) => {'min_qty': _int(t.min.text) ?? 0, 'price_tnd': _num(t.price.text) ?? 0})
              .toList()
          : <Map<String, dynamic>>[],
      'choice_groups': [
        for (final (gi, g) in _groups.where((g) => g.name.text.trim().isNotEmpty).indexed)
          {
            'name': g.name.text.trim(),
            'sort_order': gi,
            'variants': [
              for (final (vi, v) in g.variants.where((v) => v.name.text.trim().isNotEmpty).indexed)
                {'name': v.name.text.trim(), 'image_url': v.imageUrl, 'sort_order': vi},
            ],
          },
      ],
      'variant_combos': _combos
          .map((c) => {
                'selections': named
                    .where((g) => (c.sel[g.gi] ?? '').isNotEmpty)
                    .map((g) => {'group': g.name, 'variant': c.sel[g.gi]})
                    .toList(),
                'price_tiers': tiersJson(c.tiers),
              })
          .where((c) =>
              (c['selections'] as List).length == named.length &&
              (c['selections'] as List).isNotEmpty &&
              (c['price_tiers'] as List).isNotEmpty)
          .toList(),
      'allow_customization': _custAllow,
      'customization_mode': _custAllow ? _custMode : 'fixed',
      'customization_required': _custAllow && _custMode == 'fixed' ? _custRequired : false,
      'customization_extra_price_tnd': _custAllow && _custMode == 'fixed' ? (_num(_custExtra.text) ?? 0) : 0,
      'customization_instructions': _custAllow ? _custInstructions.text : '',
      'customization_fields': _custAllow
          ? [
              for (final (i, f) in customFields.indexed)
                {
                  'label': f.label.text.trim(),
                  'field_type': f.type,
                  'required': f.required,
                  'sort_order': i,
                  'constraints': (_int(f.maxChars.text) != null) ? {'max_chars': _int(f.maxChars.text)} : {},
                },
            ]
          : <Map<String, dynamic>>[],
    };

    setState(() => _submitting = true);
    try {
      final api = ref.read(productFormApiProvider);
      if (_isEdit) {
        await api.update(widget.productId!, payload);
      } else {
        await api.create(payload);
      }
      ref.invalidate(supplierMyProductsProvider);
      if (!mounted) return;
      _snack(status == 'draft' ? 'Brouillon enregistré.' : 'Produit envoyé pour validation.');
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/supplier/products');
      }
    } catch (e) {
      if (mounted) _snack(_errMsg(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _scrollTo(String key) {
    final ctx = _keys[key]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), alignment: 0.1);
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/supplier/products');
    }
  }

  // ═══════ Build ═══════
  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_isEdit && _pageLoading) {
      body = const Center(child: CircularProgressIndicator(color: _orange));
    } else if (_isEdit && _loadError != null) {
      body = isNetworkError(_loadError)
          ? NoConnectionView(onRetry: _loadProduct)
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 40, color: _red),
                    const SizedBox(height: 12),
                    Text('Impossible de charger le produit',
                        style: AppTheme.body(size: 16, weight: FontWeight.w700, color: _ink)),
                    const SizedBox(height: 16),
                    _softBtn('Retour aux produits', _back),
                  ],
                ),
              ),
            );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (_errors.isNotEmpty) _errorBanner(),
          _mediaSection(),
          _generalSection(),
          _priceSection(),
          _variantsSection(),
          _customizationSection(),
          _stockSection(),
          _shippingSection(),
        ],
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            Expanded(child: body),
          ],
        ),
      ),
      bottomNavigationBar: (_isEdit && (_pageLoading || _loadError != null)) ? null : _bottomBar(),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(
          children: [
            _circleBtn(Icons.arrow_back_rounded, _back),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_isEdit ? 'Modifier le produit' : 'Ajouter un produit',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(size: 19, weight: FontWeight.w800, color: _ink)),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: _violetSoft, borderRadius: BorderRadius.circular(999)),
                    child: Text(_isEdit ? 'Édition' : 'Brouillon',
                        style: AppTheme.body(size: 10.5, weight: FontWeight.w700, color: _violet)),
                  ),
                ],
              ),
            ),
            if (!(_isEdit && _pageLoading)) _circleBtn(Icons.visibility_outlined, _showPreview, tint: true),
          ],
        ),
      );

  Widget _circleBtn(IconData icon, VoidCallback onTap, {bool tint = false}) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: tint ? _orangeSoft : Colors.white,
            shape: BoxShape.circle,
            boxShadow: tint ? null : _shadow,
          ),
          child: Icon(icon, size: 20, color: tint ? _orange : _ink),
        ),
      );

  Widget _bottomBar() => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(color: Color(0x141B1B3A), blurRadius: 20, offset: Offset(0, -4))],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(child: _softBtn('Brouillon', _submitting ? null : () => _submit('draft'))),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: _submitting ? null : () => _submit('pending_review'),
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: _submitting ? _orange.withOpacity(0.6) : _orange,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [BoxShadow(color: Color(0x40FF8A00), blurRadius: 14, offset: Offset(0, 5))],
                      ),
                      child: Center(
                        child: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.check_circle_outline_rounded, size: 18, color: Colors.white),
                                  const SizedBox(width: 7),
                                  Flexible(
                                    child: Text(_isEdit ? 'Enregistrer et soumettre' : 'Soumettre',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTheme.body(size: 14, weight: FontWeight.w700, color: Colors.white)),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _softBtn(String t, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: _orangeSoft, borderRadius: BorderRadius.circular(16)),
          child: Center(
            child: Text(t,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(size: 14, weight: FontWeight.w700, color: _orange)),
          ),
        ),
      );

  Widget _errorBanner() => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _redSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF7B4B6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 19, color: _red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errors.length == 1 ? '1 champ à corriger' : '${_errors.length} champs à corriger',
                    style: AppTheme.body(size: 14, weight: FontWeight.w800, color: _red),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final e in _errors.entries)
              GestureDetector(
                onTap: () => _scrollTo(e.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      const Text('•  ', style: TextStyle(color: _red)),
                      Expanded(
                        child: Text(e.value,
                            style: AppTheme.body(size: 12.5, color: _red)
                                .copyWith(decoration: TextDecoration.underline, decorationColor: _red)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );

  // ═══════ Primitives de formulaire ═══════
  Widget _section({
    Key? key,
    required IconData icon,
    required String title,
    Widget? trailing,
    required List<Widget> children,
  }) =>
      Container(
        key: key,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: _shadow),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(color: _orangeSoft, shape: BoxShape.circle),
                  child: Icon(icon, size: 16, color: _orange),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: AppTheme.body(size: 15.5, weight: FontWeight.w800, color: _ink))),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      );

  Widget _label(String text, {bool required = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(TextSpan(
          text: text,
          style: AppTheme.body(size: 12.5, weight: FontWeight.w600, color: _sub),
          children: [if (required) TextSpan(text: ' *', style: AppTheme.body(size: 12.5, color: _orange))],
        )),
      );

  InputDecoration _deco(String hint, {bool error = false, bool dense = false}) => InputDecoration(
        hintText: hint,
        hintStyle: AppTheme.body(size: 13.5, color: _faint),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: dense ? 10 : 14, vertical: dense ? 11 : 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: error ? _red : _line, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: error ? _red : _orange, width: 1.5),
        ),
      );

  Widget _input(
    TextEditingController c,
    String hint, {
    bool number = false,
    bool integer = false,
    int maxLines = 1,
    bool error = false,
    bool dense = false,
    TextAlign align = TextAlign.start,
  }) =>
      TextField(
        controller: c,
        onChanged: (_) => _refresh(),
        maxLines: maxLines,
        textAlign: align,
        cursorColor: _orange,
        keyboardType: number ? TextInputType.numberWithOptions(decimal: !integer) : null,
        style: AppTheme.body(size: 13.5, color: _ink),
        decoration: _deco(hint, error: error, dense: dense),
      );

  Widget _field(String label, TextEditingController c, String hint,
          {bool required = false, String? error, String? helper, bool number = false, bool integer = false, int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(label, required: required),
            _input(c, hint, number: number, integer: integer, maxLines: maxLines, error: error != null),
            if (error != null || helper != null)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(error ?? helper!,
                    style: AppTheme.body(size: 11.5, color: error != null ? _red : _faint)),
              ),
          ],
        ),
      );

  Widget _helper(String t) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(t, style: AppTheme.body(size: 11.5, color: _faint).copyWith(height: 1.45)),
      );

  Widget _errText(String? t) => t == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(t, style: AppTheme.body(size: 12, weight: FontWeight.w600, color: _red)),
        );

  Widget _info(IconData icon, String text, {bool warn = false}) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: warn ? _amberSoft : _orangeSoft, borderRadius: BorderRadius.circular(14)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: warn ? _amber : _orange),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: AppTheme.body(size: 12, color: warn ? _amber : _sub).copyWith(height: 1.5)),
            ),
          ],
        ),
      );

  Widget _addBtn(String t, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.45 : 1,
          child: Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _orangeSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _orangeLine),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_rounded, size: 17, color: _orange),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(t, style: AppTheme.body(size: 12.5, weight: FontWeight.w700, color: _orange)),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _delBtn(VoidCallback? onTap, {double size = 42}) => GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.35 : 1,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: _redSoft, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.delete_outline_rounded, size: 18, color: _red),
          ),
        ),
      );

  Widget _seg<T>(List<(T, String)> options, T value, ValueChanged<T> onChange, {T? dangerValue}) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: options.map((o) {
          final on = o.$1 == value;
          final danger = on && dangerValue != null && o.$1 == dangerValue;
          final fg = danger ? _red : (on ? _orange : _sub);
          return GestureDetector(
            onTap: () => onChange(o.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: danger ? _redSoft : (on ? _orangeSoft : Colors.white),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: danger ? _red : (on ? _orange : _line), width: 1.5),
              ),
              child: Text(o.$2, style: AppTheme.body(size: 13, weight: FontWeight.w600, color: fg)),
            ),
          );
        }).toList(),
      );

  Widget _switchCard({
    required bool value,
    required ValueChanged<bool> onChanged,
    required String title,
    required String desc,
    bool warn = false,
    IconData? icon,
  }) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: warn && value ? _amberSoft : _tile,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (icon != null) ...[Icon(icon, size: 16, color: _orange), const SizedBox(width: 6)],
                      Expanded(child: Text(title, style: AppTheme.body(size: 14, weight: FontWeight.w700, color: _ink))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(desc, style: AppTheme.body(size: 12, color: _mute).copyWith(height: 1.45)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.white,
              activeTrackColor: _orange,
            ),
          ],
        ),
      );

  // ═══════ Section : médias ═══════
  Widget _mediaSection() => _section(
        key: _keys['images'],
        icon: Icons.image_outlined,
        title: 'Images & vidéo',
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final im in _images) _imgThumb(im),
              GestureDetector(
                onTap: _pickImages,
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: _orangeSoft,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _orangeLine, width: 1.5),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_photo_alternate_outlined, size: 24, color: _orange),
                      const SizedBox(height: 4),
                      Text('Ajouter', style: AppTheme.body(size: 11, weight: FontWeight.w700, color: _orange)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          _helper('L’image marquée ★ est la principale, affichée sur la carte produit. PNG, JPG, WEBP · max 5 Mo.'),
          _errText(_errors['images']),
          const SizedBox(height: 16),
          _label('Vidéo produit'),
          if (_videoUrl.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(12)),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_videoPoster.isNotEmpty)
                          Image.network(_videoPoster, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
                        const Center(child: Icon(Icons.play_circle_fill_rounded, size: 28, color: Colors.white)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Vidéo ajoutée', style: AppTheme.body(size: 13, weight: FontWeight.w600, color: _ink)),
                  ),
                  _delBtn(() => setState(() {
                        _videoUrl = '';
                        _videoPoster = '';
                      })),
                ],
              ),
            )
          else
            GestureDetector(
              onTap: _videoUploading ? null : _pickVideo,
              child: Container(
                height: 84,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _tile,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _line, width: 1.5),
                ),
                child: _videoUploading
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: _orange),
                          ),
                          const SizedBox(height: 6),
                          Text('Envoi et compression…', style: AppTheme.body(size: 11.5, color: _mute)),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.videocam_outlined, size: 24, color: _faint),
                          const SizedBox(height: 4),
                          Text('Ajouter une vidéo · MP4, MOV · max 100 Mo',
                              style: AppTheme.body(size: 11.5, color: _mute)),
                        ],
                      ),
              ),
            ),
        ],
      );

  Widget _imgThumb(_Img im) => SizedBox(
        width: 84,
        height: 84,
        child: Stack(
          children: [
            Container(
              width: 84,
              height: 84,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: _tile,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: im.primary ? _orange : Colors.transparent, width: 2),
              ),
              child: im.uploading
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: _orange),
                      ),
                    )
                  : Image.network(im.url,
                      width: 84,
                      height: 84,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: _faint)),
            ),
            if (!im.uploading) ...[
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => _removeImage(im),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(color: Color(0x991E1E2D), shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                  ),
                ),
              ),
              Positioned(
                bottom: 4,
                left: 4,
                child: GestureDetector(
                  onTap: () => _setPrimary(im),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: im.primary ? _orange : const Color(0x991E1E2D),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(im.primary ? Icons.star_rounded : Icons.star_border_rounded,
                        size: 15, color: Colors.white),
                  ),
                ),
              ),
            ],
          ],
        ),
      );

  // ═══════ Section : général ═══════
  Widget _generalSection() {
    final cats = ref.watch(productFormCategoriesProvider);
    final catLabel = _categoryLabel(cats.valueOrNull ?? const []);

    return _section(
      icon: Icons.inventory_2_outlined,
      title: 'Général',
      children: [
        Container(
          key: _keys['name'],
          child: _field('Nom du produit', _name, 'Ex : T-shirt coton premium 180g',
              required: true, error: _errors['name']),
        ),

        // Catégorie
        Padding(
          key: _keys['category'],
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('Catégorie', required: true),
              GestureDetector(
                onTap: () => _openCategoryPicker(cats.valueOrNull ?? const []),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _errors['category'] != null ? _red : _line, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          catLabel ?? (cats.isLoading ? 'Chargement…' : 'Sélectionner une catégorie'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(size: 13.5, color: catLabel != null ? _ink : _faint),
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down_rounded, color: _mute),
                    ],
                  ),
                ),
              ),
              if (_errors['category'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(_errors['category']!, style: AppTheme.body(size: 11.5, color: _red)),
                ),
            ],
          ),
        ),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _field('Unité', _unit, 'pièce', helper: 'pièce, mètre, lot…')),
            const SizedBox(width: 10),
            Expanded(child: _field('Marque', _brand, 'Sfax Textile')),
          ],
        ),
        _field('Référence', _reference, 'Ex : TS-180-BLK', helper: 'Code produit / fabricant (optionnel)'),
        _field('Description', _description, 'Matière, finitions, taille du lot…', maxLines: 5),

        // Caractéristiques
        _label('Caractéristiques'),
        for (final r in _specs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(child: _input(r.key, 'Matière', dense: true)),
                const SizedBox(width: 8),
                Expanded(child: _input(r.val, '100% coton', dense: true)),
                const SizedBox(width: 8),
                _delBtn(() => setState(() {
                      _specs.remove(r);
                      r.dispose();
                    })),
              ],
            ),
          ),
        _addBtn('Ajouter une caractéristique', () => setState(() => _specs.add(_SpecRow()))),
      ],
    );
  }

  String? _categoryLabel(List<Map<String, dynamic>> cats) {
    if (_category.isEmpty) return null;
    for (final root in cats) {
      if (_s(root['id']) == _category) return _s(root['name']);
      for (final ch in (root['children'] as List? ?? const []).whereType<Map>()) {
        if (_s(ch['id']) == _category) return '${_s(root['name'])} › ${_s(ch['name'])}';
      }
    }
    return null;
  }

  void _openCategoryPicker(List<Map<String, dynamic>> cats) {
    if (cats.isEmpty) {
      ref.invalidate(productFormCategoriesProvider);
      _snack('Catégories en cours de chargement, réessaie dans un instant.');
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (_, scroll) => Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: _line, borderRadius: BorderRadius.circular(3)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Choisir une catégorie',
                    style: AppTheme.body(size: 17, weight: FontWeight.w800, color: _ink)),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                children: [
                  for (final root in cats) ...[
                    if ((root['children'] as List? ?? const []).isEmpty)
                      _catTile(ctx, _s(root['id']), _s(root['name']))
                    else ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
                        child: Text(_s(root['name']),
                            style: AppTheme.body(size: 12, weight: FontWeight.w800, color: _mute)),
                      ),
                      for (final ch in (root['children'] as List).whereType<Map>())
                        _catTile(ctx, _s(ch['id']), _s(ch['name'])),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _catTile(BuildContext ctx, String id, String name) {
    final on = id == _category;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        Navigator.pop(ctx);
        setState(() {
          _category = id;
          _errors.remove('category');
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: on ? _orangeSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(name,
                  style: AppTheme.body(
                      size: 14, weight: on ? FontWeight.w700 : FontWeight.w500, color: on ? _orange : _ink)),
            ),
            if (on) const Icon(Icons.check_rounded, size: 18, color: _orange),
          ],
        ),
      ),
    );
  }

  // ═══════ Tranches (prix) — réutilisé pour produit et combinaisons ═══════
  Widget _tierEditor(List<_TierRow> rows) {
    final errs = _tierIssues(rows).errs;
    Widget head(String t) =>
        Expanded(child: Text(t, textAlign: TextAlign.center, style: AppTheme.body(size: 10.5, weight: FontWeight.w600, color: _faint)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          head('À partir de'),
          const SizedBox(width: 6),
          head('Prix (TND)'),
          const SizedBox(width: 6),
          head('Ancien prix'),
          const SizedBox(width: 6),
          const SizedBox(width: 54),
          const SizedBox(width: 6),
          const SizedBox(width: 38),
        ]),
        const SizedBox(height: 6),
        for (var i = 0; i < rows.length; i++) ...[
          Row(
            children: [
              Expanded(child: _input(rows[i].min, '1', number: true, integer: true, dense: true, align: TextAlign.center)),
              const SizedBox(width: 6),
              Expanded(
                child: _input(rows[i].price, '0.000',
                    number: true, dense: true, align: TextAlign.center, error: errs[i] != null),
              ),
              const SizedBox(width: 6),
              Expanded(child: _input(rows[i].old, '—', number: true, dense: true, align: TextAlign.center)),
              const SizedBox(width: 6),
              Container(
                width: 54,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(color: _orangeSoft, borderRadius: BorderRadius.circular(10)),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_tierRange(rows, i),
                      style: AppTheme.body(size: 11, weight: FontWeight.w700, color: _orange)),
                ),
              ),
              const SizedBox(width: 6),
              _delBtn(
                rows.length <= 1
                    ? null
                    : () => setState(() {
                          final r = rows.removeAt(i);
                          r.dispose();
                        }),
                size: 38,
              ),
            ],
          ),
          if (errs[i] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 13, color: _red),
                  const SizedBox(width: 4),
                  Expanded(child: Text(errs[i]!, style: AppTheme.body(size: 11.5, color: _red))),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
        _addBtn('Ajouter une tranche', () => setState(() => rows.add(_TierRow()))),
      ],
    );
  }

  // ═══════ Section : prix ═══════
  Widget _priceSection() {
    final first = _tiers.isNotEmpty ? _tiers.first.min.text.trim() : '';
    final unit = _unit.text.trim().isEmpty ? 'pièce' : _unit.text.trim();
    return _section(
      key: _keys['price_tiers'],
      icon: Icons.sell_outlined,
      title: 'Prix par tranche',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: _orangeSoft, borderRadius: BorderRadius.circular(999)),
        child: Text('MOQ ${first.isEmpty ? '—' : '$first $unit'}',
            style: AppTheme.body(size: 11, weight: FontWeight.w700, color: _orange)),
      ),
      children: [
        _info(Icons.sell_outlined,
            'Fixe un prix qui baisse selon la quantité commandée, c’est le principe du gros. Ex : 1–9 à 25 TND, 10–49 à 22 TND, 50+ à 18 TND. La première tranche définit la quantité minimum de commande (MOQ).'),
        _tierEditor(_tiers),
        _errText(_errors['price_tiers']),
        _helper('Le prix doit diminuer quand la quantité augmente. La borne haute de chaque tranche se calcule toute seule.'),
        const SizedBox(height: 16),
        _switchCard(
          value: _priceHidden,
          onChanged: (v) => setState(() => _priceHidden = v),
          title: 'Masquer le prix aux non-boutiques',
          desc: 'Seules les boutiques vérifiées et les clients que vous aurez débloqués verront le prix.',
          warn: true,
        ),
      ],
    );
  }

  // ═══════ Section : variantes ═══════
  Widget _variantsSection() {
    final named = _namedGroups;
    return _section(
      key: _keys['combos'],
      icon: Icons.style_outlined,
      title: 'Choix & variantes',
      children: [
        _info(Icons.auto_awesome_outlined,
            'Optionnel. Crée un choix (ex : Couleur) avec ses variantes (Rouge, Bleu…) si l’acheteur doit sélectionner une option. Tu pourras ensuite fixer un prix pour une combinaison précise.'),
        for (var gi = 0; gi < _groups.length; gi++) _groupCard(gi),
        _addBtn('Ajouter un choix (${_groups.length}/5)',
            _groups.length >= 5 ? null : () => setState(() => _groups.add(_Group()))),
        if (named.isEmpty)
          _helper('Ajoute au moins un choix avec ses variantes pour fixer un prix spécifique à une combinaison.')
        else ...[
          const SizedBox(height: 18),
          const Divider(color: _line, height: 1),
          const SizedBox(height: 16),
          Text('Prix par combinaison (optionnel)', style: AppTheme.body(size: 13.5, weight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 4),
          Text('Par défaut, toutes les combinaisons utilisent le barème du produit.',
              style: AppTheme.body(size: 12, color: _mute)),
          const SizedBox(height: 12),
          for (final c in _combos) _comboCard(c, named),
          _addBtn('Prix spécifique pour une combinaison', () => setState(() => _combos.add(_Combo()))),
        ],
        _errText(_errors['combos']),
      ],
    );
  }

  Widget _groupCard(int gi) {
    final g = _groups[gi];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _input(g.name, 'Nom du choix (ex : Couleur)', dense: true)),
              const SizedBox(width: 8),
              _delBtn(() => setState(() {
                    _groups.removeAt(gi);
                    g.dispose();
                    for (final c in _combos) {
                      c.sel.remove(gi);
                      final shifted = <int, String>{};
                      c.sel.forEach((k, v) => shifted[k > gi ? k - 1 : k] = v);
                      c.sel
                        ..clear()
                        ..addAll(shifted);
                    }
                  })),
            ],
          ),
          const SizedBox(height: 10),
          for (final v in g.variants)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: v.uploading ? null : () => _pickVariantImage(v),
                    child: Container(
                      width: 42,
                      height: 42,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _line, width: 1.5),
                      ),
                      child: v.uploading
                          ? const Padding(
                              padding: EdgeInsets.all(11),
                              child: CircularProgressIndicator(strokeWidth: 2, color: _orange),
                            )
                          : v.imageUrl.isNotEmpty
                              ? Image.network(v.imageUrl, fit: BoxFit.cover)
                              : const Icon(Icons.add_photo_alternate_outlined, size: 18, color: _faint),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _input(v.name, 'Ex : Rose, XL…', dense: true)),
                  const SizedBox(width: 8),
                  _delBtn(() => setState(() {
                        g.variants.remove(v);
                        v.dispose();
                      }), size: 38),
                ],
              ),
            ),
          _addBtn('Ajouter une variante', () => setState(() => g.variants.add(_Variant()))),
        ],
      ),
    );
  }

  Widget _comboCard(_Combo c, List<({int gi, String name, List<String> variants})> named) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final g in named)
                        _dropdown(
                          hint: '${g.name}…',
                          value: g.variants.contains(c.sel[g.gi]) ? c.sel[g.gi] : null,
                          items: g.variants,
                          onChanged: (v) => setState(() => c.sel[g.gi] = v ?? ''),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _delBtn(() => setState(() {
                      _combos.remove(c);
                      c.dispose();
                    })),
              ],
            ),
            const SizedBox(height: 12),
            _tierEditor(c.tiers),
          ],
        ),
      );

  Widget _dropdown({
    required String hint,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: value != null ? _orange : _line, width: 1.5),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            hint: Text(hint, style: AppTheme.body(size: 13, color: _faint)),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _mute),
            borderRadius: BorderRadius.circular(14),
            style: AppTheme.body(size: 13, weight: FontWeight.w600, color: _ink),
            items: items.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: onChanged,
          ),
        ),
      );

  // ═══════ Section : personnalisation ═══════
  Widget _customizationSection() => Container(
        key: _keys['customization'],
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: _shadow),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _switchCard(
              value: _custAllow,
              onChanged: (v) => setState(() => _custAllow = v),
              title: 'Autoriser la personnalisation',
              desc: "L'acheteur pourra remplir des champs (nom, photo, fichier…) avant de commander.",
              icon: Icons.auto_awesome_outlined,
            ),
            if (_custAllow) ...[
              const SizedBox(height: 16),
              _field("Instructions pour l'acheteur", _custInstructions,
                  'Ex : Envoyez votre logo en HD (300dpi), PNG ou AI, fond transparent.',
                  maxLines: 3, helper: 'Ce qu’il doit envoyer, formats acceptés, contraintes…'),
              _label('Comment fixer le prix ?'),
              _modeRadio('fixed', 'Prix fixe', "Je sais combien facturer en plus. L'acheteur commande directement."),
              const SizedBox(height: 8),
              _modeRadio('quote', 'Sur devis', "Je veux voir la demande avant de fixer le prix. L'acheteur attend ma réponse."),
              const SizedBox(height: 16),
              if (_custMode == 'fixed') ...[
                _label('La personnalisation est…'),
                _seg<bool>(const [(false, 'Optionnelle'), (true, 'Obligatoire')], _custRequired,
                    (v) => setState(() => _custRequired = v)),
                _helper(_custRequired
                    ? '« Obligatoire » : l’acheteur DOIT personnaliser pour commander (ex. bracelet avec prénom).'
                    : '« Optionnelle » : l’acheteur peut choisir de personnaliser ou non (ex. mug photo).'),
                const SizedBox(height: 14),
                _field('Surcoût par unité (TND)', _custExtra, '0.000',
                    number: true, helper: 'Laisser à 0 si le prix perso est déjà inclus.'),
              ] else
                _info(Icons.warning_amber_rounded,
                    'Chaque demande arrivera dans ta messagerie. Tu répondras avec un prix et une validité. L’acheteur pourra accepter pour ajouter au panier.',
                    warn: true),
              const Divider(color: _line, height: 1),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text("Champs à remplir par l'acheteur",
                      style: AppTheme.body(size: 13.5, weight: FontWeight.w800, color: _ink)),
                  const SizedBox(width: 6),
                  Text('(${_custFields.length}/12)', style: AppTheme.body(size: 11.5, color: _faint)),
                ],
              ),
              const SizedBox(height: 10),
              if (_custFields.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Aucun champ. Ajoutes-en au moins un.', style: AppTheme.body(size: 12, color: _faint)),
                ),
              for (var i = 0; i < _custFields.length; i++) _customFieldCard(i),
              _addBtn('Ajouter un champ',
                  _custFields.length >= 12 ? null : () => setState(() => _custFields.add(_CField()))),
            ],
            _errText(_errors['customization']),
          ],
        ),
      );

  Widget _modeRadio(String mode, String title, String desc) {
    final on = _custMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _custMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: on ? _orangeSoft : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? _orange : _line, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 20,
              height: 20,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: on ? _orange : _faint, width: 2),
              ),
              child: on
                  ? Center(
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(color: _orange, shape: BoxShape.circle),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTheme.body(size: 14, weight: FontWeight.w700, color: on ? _orange : _ink)),
                  const SizedBox(height: 3),
                  Text(desc, style: AppTheme.body(size: 12, color: _mute).copyWith(height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _customFieldCard(int i) {
    final f = _custFields[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(color: _orangeSoft, shape: BoxShape.circle),
                child: Center(
                  child: Text('${i + 1}', style: AppTheme.body(size: 12, weight: FontWeight.w800, color: _orange)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _input(f.label, 'Ex : Prénom à graver, Photo…', dense: true)),
              const SizedBox(width: 8),
              _delBtn(() => setState(() {
                    _custFields.remove(f);
                    f.dispose();
                  }), size: 38),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: 34),
              Expanded(
                child: _dropdownTyped(
                  value: f.type,
                  items: _fieldTypes,
                  onChanged: (v) => setState(() => f.type = v),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => f.required = !f.required),
                child: Row(
                  children: [
                    Checkbox(
                      value: f.required,
                      onChanged: (v) => setState(() => f.required = v ?? true),
                      activeColor: _orange,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    Text('Requis', style: AppTheme.body(size: 12.5, color: _sub)),
                  ],
                ),
              ),
            ],
          ),
          if (f.type == 'text') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(width: 34),
                Expanded(child: _input(f.maxChars, 'Nb max de caractères (optionnel)', number: true, integer: true, dense: true)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _dropdownTyped({
    required String value,
    required List<(String, String)> items,
    required ValueChanged<String> onChanged,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _line, width: 1.5),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _mute),
            borderRadius: BorderRadius.circular(14),
            style: AppTheme.body(size: 13, weight: FontWeight.w600, color: _ink),
            items: items.map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2))).toList(),
            onChanged: (v) => onChanged(v ?? value),
          ),
        ),
      );

  // ═══════ Section : disponibilité ═══════
  Widget _stockSection() => _section(
        icon: Icons.layers_outlined,
        title: 'Disponibilité',
        children: [
          _seg<bool>(const [(true, 'En stock'), (false, 'Hors stock')], _inStock,
              (v) => setState(() => _inStock = v), dangerValue: false),
          _helper('« Hors stock » affiche un badge sur la fiche produit et bloque l’ajout au panier.'),
        ],
      );

  // ═══════ Section : livraison ═══════
  Widget _shippingSection() => _section(
        key: _keys['shipping'],
        icon: Icons.local_shipping_outlined,
        title: 'Livraison',
        children: [
          _seg<String>(_shipModes, _shipMode, (v) => setState(() => _shipMode = v)),
          const SizedBox(height: 16),
          if (_shipMode == 'flat')
            _field('Frais de livraison (TND)', _shipPrice, '0.000',
                number: true, helper: 'Montant unique quelle que soit la quantité'),
          if (_shipMode == 'per_block')
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field('Tous les (articles)', _blockSize, '10',
                      number: true, integer: true, helper: 'Palier de quantité'),
                ),
                const SizedBox(width: 10),
                Expanded(child: _field('Frais par palier (TND)', _blockPrice, '0.000', number: true)),
              ],
            ),
          if (_shipMode == 'tiered') ...[
            for (var i = 0; i < _shipTiers.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _input(_shipTiers[i].min, 'À partir de',
                          number: true, integer: true, dense: true, align: TextAlign.center),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _input(_shipTiers[i].price, 'Frais TND', number: true, dense: true, align: TextAlign.center),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 54,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(color: _orangeSoft, borderRadius: BorderRadius.circular(10)),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(_tierRange(_shipTiers, i),
                            style: AppTheme.body(size: 11, weight: FontWeight.w700, color: _orange)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _delBtn(
                      _shipTiers.length <= 1
                          ? null
                          : () => setState(() {
                                final r = _shipTiers.removeAt(i);
                                r.dispose();
                              }),
                      size: 38,
                    ),
                  ],
                ),
              ),
            _addBtn('Ajouter une tranche', () => setState(() => _shipTiers.add(_ShipRow()))),
            const SizedBox(height: 14),
          ],
          if (_shipMode == 'free')
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text('Livraison offerte pour ce produit.', style: AppTheme.body(size: 12.5, color: _green)),
            ),
          _errText(_errors['shipping']),
          const SizedBox(height: 6),
          _field('Délai estimé (jours)', _deliveryDays, '3', number: true, integer: true),
        ],
      );

  // ═══════ Aperçu en direct ═══════
  void _showPreview() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: _line, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            Row(
              children: [
                Text('Aperçu en direct', style: AppTheme.body(size: 17, weight: FontWeight.w800, color: _ink)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: _violetSoft, borderRadius: BorderRadius.circular(999)),
                  child: Text('Live', style: AppTheme.body(size: 10.5, weight: FontWeight.w700, color: _violet)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _previewCard(),
          ],
        ),
      ),
    );
  }

  Widget _previewCard() {
    _Img? primary;
    for (final im in _images) {
      if (im.url.isEmpty) continue;
      if (im.primary) {
        primary = im;
        break;
      }
      primary ??= im;
    }
    final valid = _tiers.where((t) => t.complete).toList();
    final firstTier = valid.isEmpty ? null : valid.first;
    final catLabel = _categoryLabel(ref.read(productFormCategoriesProvider).valueOrNull ?? const []);
    final meta = [catLabel, _brand.text.trim()].where((x) => x != null && x.isNotEmpty).join(' · ');
    final unit = _unit.text.trim().isEmpty ? 'pièce' : _unit.text.trim();
    final ship = switch (_shipMode) {
      'free' => 'Livraison gratuite',
      'flat' => _shipPrice.text.trim().isEmpty
          ? 'Frais de livraison à définir'
          : '${_fmt3(_num(_shipPrice.text) ?? 0)} TND livraison',
      'tiered' => 'Livraison par tranche',
      _ => _blockPrice.text.trim().isEmpty
          ? 'Livraison par palier'
          : '${_fmt3(_num(_blockPrice.text) ?? 0)} TND / ${_blockSize.text.trim().isEmpty ? 10 : _blockSize.text.trim()} art.',
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: _shadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(18)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (primary != null)
                    Image.network(primary.url, fit: BoxFit.cover)
                  else
                    const Center(child: Icon(Icons.image_outlined, size: 40, color: _faint)),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: _inStock ? _green : _red,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(_inStock ? 'En stock' : 'Hors stock',
                          style: AppTheme.body(size: 10.5, weight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                  if (_custAllow)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_awesome, size: 12, color: _orange),
                            const SizedBox(width: 4),
                            Text('Perso', style: AppTheme.body(size: 10.5, weight: FontWeight.w700, color: _orange)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(_name.text.trim().isEmpty ? 'Nom du produit…' : _name.text.trim(),
              style: AppTheme.body(
                  size: 16, weight: FontWeight.w800, color: _name.text.trim().isEmpty ? _faint : _ink)),
          const SizedBox(height: 3),
          Text(meta.isEmpty ? 'Catégorie · Marque' : meta, style: AppTheme.body(size: 12, color: _mute)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _priceHidden ? _amberSoft : _tile, borderRadius: BorderRadius.circular(16)),
            child: _priceHidden
                ? Row(
                    children: [
                      const Icon(Icons.lock_outline_rounded, size: 15, color: _amber),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('Prix réservé aux boutiques vérifiées',
                            style: AppTheme.body(size: 12.5, weight: FontWeight.w600, color: _amber)),
                      ),
                    ],
                  )
                : firstTier == null
                    ? Text('Ajoute une tranche de prix…', style: AppTheme.body(size: 12.5, color: _faint))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.end,
                            spacing: 8,
                            children: [
                              Text('${_fmt3(_num(firstTier.price.text) ?? 0)} TND',
                                  style: AppTheme.body(size: 20, weight: FontWeight.w800, color: _orange)),
                              if (firstTier.old.text.trim().isNotEmpty)
                                Text('${_fmt3(_num(firstTier.old.text) ?? 0)} TND',
                                    style: AppTheme.body(size: 13, color: _faint)
                                        .copyWith(decoration: TextDecoration.lineThrough)),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'MOQ : ${firstTier.min.text.trim()} $unit'
                            '${valid.length > 1 ? ' · ${valid.length} tranches de prix' : ''}',
                            style: AppTheme.body(size: 11.5, color: _mute),
                          ),
                        ],
                      ),
          ),
          for (final g in _namedGroups) ...[
            const SizedBox(height: 12),
            Text(g.name, style: AppTheme.body(size: 11.5, weight: FontWeight.w700, color: _faint)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: g.variants
                  .map((v) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: _tile, borderRadius: BorderRadius.circular(999)),
                        child: Text(v, style: AppTheme.body(size: 12, weight: FontWeight.w600, color: _sub)),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.local_shipping_outlined, size: 15, color: _faint),
              const SizedBox(width: 6),
              Expanded(
                child: Text('$ship · ${_deliveryDays.text.trim().isEmpty ? 3 : _deliveryDays.text.trim()} j',
                    style: AppTheme.body(size: 12, color: _mute)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}