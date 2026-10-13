import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../data/api/customization_api.dart';
import '../../../data/models/product_detail.dart';
import '../../../state/cart_provider.dart';

const _orange = Color(0xFFFF7A00);
const _purple = Color(0xFF6D3EF5);
const _purpleTint = Color(0xFFF3EEFF);
const _ink = Color(0xFF17171A);
const _sub = Color(0xFF3A3A40);
const _mute = Color(0xFF5C5C62);
const _faint = Color(0xFF8A8A90);
const _line = Color(0xFFECEEF1);
const _soft = Color(0xFFF7F8FA);

const _maxUploadBytes = 15 * 1024 * 1024; // 15 Mo, comme le backend

/// Couleurs proposées pour un champ « color » (+ saisie hexadécimale libre).
const _palette = <String>[
  '#000000', '#FFFFFF', '#E53935', '#FF7A00', '#FDD835', '#43A047',
  '#1E88E5', '#3949AB', '#8E24AA', '#D81B60', '#6D4C41', '#9E9E9E',
];

String _fmt(num n) {
  final s = n.toStringAsFixed(2);
  final p = s.split('.');
  final b = StringBuffer();
  for (var i = 0; i < p[0].length; i++) {
    if (i > 0 && (p[0].length - i) % 3 == 0) b.write(' ');
    b.write(p[0][i]);
  }
  return '${b.toString()},${p[1]}';
}

Color? _hexColor(String? v) {
  if (v == null) return null;
  final h = v.trim().replaceFirst('#', '');
  if (h.length != 6) return null;
  final n = int.tryParse(h, radix: 16);
  return n == null ? null : Color(0xFF000000 | n);
}

/// Popup de personnalisation (bottom sheet), partagée par les modes :
/// - `fixed` → ajoute au panier une ligne personnalisée ;
/// - `quote` → crée une demande de devis puis ouvre la conversation.
class CustomizationSheet extends ConsumerStatefulWidget {
  final ProductDetail product;
  final String? variantId;
  final double unitBasePrice;
  final int initialQty;

  const CustomizationSheet({
    super.key,
    required this.product,
    this.variantId,
    required this.unitBasePrice,
    required this.initialQty,
  });

  /// Ouvre la feuille. Renvoie `true` si une ligne a été ajoutée au panier.
  static Future<bool?> show(
    BuildContext context, {
    required ProductDetail product,
    String? variantId,
    required double unitBasePrice,
    required int initialQty,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CustomizationSheet(
        product: product,
        variantId: variantId,
        unitBasePrice: unitBasePrice,
        initialQty: initialQty,
      ),
    );
  }

  @override
  ConsumerState<CustomizationSheet> createState() => _CustomizationSheetState();
}

class _CustomizationSheetState extends ConsumerState<CustomizationSheet> {
  final Map<String, String> _values = {};
  final Map<String, bool> _uploading = {};
  final Map<String, TextEditingController> _ctrls = {};
  late int _qty;
  bool _submitting = false;
  String? _error;

  ProductDetail get _p => widget.product;
  bool get _isQuote => _p.customizationMode == 'quote';
  int get _moq => _p.moq < 1 ? 1 : _p.moq;
  String get _unit => _p.unit.trim().isEmpty ? 'pièce' : _p.unit;
  double get _unitPrice => widget.unitBasePrice + _p.customizationExtra;

  @override
  void initState() {
    super.initState();
    _qty = widget.initialQty < _moq ? _moq : widget.initialQty;
    for (final f in _p.customizationFields) {
      if (!f.isUpload) _ctrls[f.id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(String id, String v) => setState(() {
        _values[id] = v;
        _error = null;
      });

  // ── Upload image / fichier ──
  Future<void> _pick(CustomizationField f) async {
    final isImage = f.fieldType == 'image';
    // file_picker ≥ 12 : API statique, un seul fichier → PlatformFile? (null = annulé)
    final file = await FilePicker.pickFile(
      type: isImage ? FileType.image : FileType.custom,
      allowedExtensions: isImage ? null : const ['jpg', 'jpeg', 'png', 'webp', 'pdf', 'svg', 'ai', 'eps'],
    );
    if (file == null) return;
    final size = file.lengthSync() ?? await file.length();
    if (size != null && size > _maxUploadBytes) {
      setState(() => _error = 'Fichier trop lourd (max 15 Mo).');
      return;
    }
    setState(() {
      _uploading[f.id] = true;
      _error = null;
    });
    try {
      // Lecture en mémoire : marche aussi pour les URI content:// d'Android (pas de chemin fichier)
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxUploadBytes) throw Exception('Fichier trop lourd (max 15 Mo).');
      final url = await ref.read(customizationApiProvider).uploadBytes(bytes, filename: file.name);
      if (mounted) _set(f.id, url);
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e, "Échec de l'upload."));
    } finally {
      if (mounted) setState(() => _uploading[f.id] = false);
    }
  }

  String? _validate() {
    if (_qty < _moq) return 'Quantité minimale : $_moq $_unit';
    for (final f in _p.customizationFields) {
      if (f.required && (_values[f.id] ?? '').trim().isEmpty) {
        return 'Le champ « ${f.label} » est obligatoire';
      }
    }
    if (_uploading.values.any((b) => b)) return 'Attends la fin des uploads';
    return null;
  }

  Future<void> _submit() async {
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    final values = [
      for (final f in _p.customizationFields)
        if ((_values[f.id] ?? '').trim().isNotEmpty)
          {'field_id': f.id, 'label': f.label, 'field_type': f.fieldType, 'value': _values[f.id]!.trim()},
    ];
    final api = ref.read(customizationApiProvider);
    final router = GoRouter.of(context);
    final nav = Navigator.of(context);

    try {
      if (!_isQuote) {
        await api.addToCart(productId: _p.id, quantity: _qty, variantId: widget.variantId, values: values);
        await ref.read(cartProvider.notifier).refresh(); // badge panier à jour
        nav.pop(true);
      } else {
        final conv = await api.createRequest(
            productId: _p.id, quantity: _qty, variantId: widget.variantId, values: values);
        nav.pop(false);
        router.push(conv != null ? '/messages/$conv' : '/dashboard/messages');
      }
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        nav.pop(false);
        router.push('/login');
        return;
      }
      if (mounted) setState(() => _error = apiErrorMessage(e, 'Une erreur est survenue.'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.92;
    final kb = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _header(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (_p.customizationInstructions != null) _instructions(_p.customizationInstructions!),
                  if (_p.customizationFields.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text('Aucun champ de personnalisation configuré.',
                          textAlign: TextAlign.center, style: AppTheme.body(size: 14, color: _mute)),
                    ),
                  for (final f in _p.customizationFields) _field(f),
                  _qtyRow(),
                  const SizedBox(height: 12),
                  if (!_isQuote) _priceBox() else _quoteHint(),
                  if (_error != null) _errorBox(_error!),
                ]),
              ),
            ),
            _footer(),
          ]),
        ),
      ),
    );
  }

  // ── En-tête ──
  Widget _header() => Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 12, 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
        child: Column(children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: const Color(0xFFDDDDDD), borderRadius: BorderRadius.circular(2)),
          ),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: _purpleTint, borderRadius: BorderRadius.circular(6)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_isQuote ? Icons.request_quote_outlined : Icons.auto_awesome, size: 13, color: _purple),
                    const SizedBox(width: 5),
                    Text(_isQuote ? 'Sur devis' : 'Personnaliser',
                        style: AppTheme.body(size: 11.5, weight: FontWeight.w700, color: _purple)),
                  ]),
                ),
                const SizedBox(height: 8),
                Text(_p.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(size: 17, weight: FontWeight.w800, color: _ink).copyWith(height: 1.3)),
              ]),
            ),
            const SizedBox(width: 8),
            Material(
              color: const Color(0xFFF4F5F7),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _submitting ? null : () => Navigator.of(context).pop(false),
                child: const SizedBox(width: 36, height: 36, child: Icon(Icons.close_rounded, size: 20, color: _ink)),
              ),
            ),
          ]),
        ]),
      );

  Widget _instructions(String text) => Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8F3),
          border: Border.all(color: const Color(0xFFFFE1CE)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: _orange),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppTheme.body(size: 13, color: _sub).copyWith(height: 1.5))),
        ]),
      );

  // ── Un champ selon son type ──
  Widget _field(CustomizationField f) {
    final label = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: f.label, style: AppTheme.body(size: 12.5, weight: FontWeight.w700, color: _sub)),
        if (f.required) TextSpan(text: ' *', style: AppTheme.body(size: 12.5, weight: FontWeight.w700, color: _orange)),
      ])),
    );

    Widget body;
    switch (f.fieldType) {
      case 'number':
        body = _input(f, keyboard: const TextInputType.numberWithOptions(decimal: true),
            formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]);
        break;
      case 'color':
        body = _colorInput(f);
        break;
      case 'image':
      case 'file':
        body = _upload(f);
        break;
      default:
        body = _input(f, maxLength: f.maxChars ?? 200, hint: 'Ta saisie…');
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [label, body]),
    );
  }

  InputDecoration _deco({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: AppTheme.body(size: 14, color: _faint),
        isDense: true,
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _line, width: 1.5)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _purple, width: 1.5)),
      );

  Widget _input(CustomizationField f,
          {TextInputType? keyboard, List<TextInputFormatter>? formatters, int? maxLength, String? hint}) =>
      TextField(
        controller: _ctrls[f.id],
        keyboardType: keyboard,
        inputFormatters: formatters,
        maxLength: maxLength,
        onChanged: (v) => _set(f.id, v),
        style: AppTheme.body(size: 14, color: _ink),
        decoration: _deco(hint: hint),
      );

  Widget _colorInput(CustomizationField f) {
    final current = _values[f.id];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final hex in _palette)
          GestureDetector(
            onTap: () {
              _ctrls[f.id]?.text = hex;
              _set(f.id, hex);
            },
            child: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: _hexColor(hex),
                shape: BoxShape.circle,
                border: Border.all(
                  color: current?.toUpperCase() == hex ? _purple : _line,
                  width: current?.toUpperCase() == hex ? 3 : 1.5,
                ),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: _hexColor(current) ?? Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _line, width: 1.5),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _ctrls[f.id],
            maxLength: 7,
            onChanged: (v) => _set(f.id, v.trim()),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]'))],
            style: AppTheme.body(size: 14, color: _ink),
            decoration: _deco(hint: '#000000'),
          ),
        ),
      ]),
    ]);
  }

  Widget _upload(CustomizationField f) {
    final isImage = f.fieldType == 'image';
    final url = _values[f.id];
    final busy = _uploading[f.id] == true;

    if (url != null && url.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(10)),
        child: Stack(children: [
          if (isImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: Center(child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain)),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.description_outlined, size: 20, color: _orange),
                const SizedBox(width: 10),
                Expanded(child: Text('Fichier uploadé', style: AppTheme.body(size: 13, color: _ink))),
              ]),
            ),
          Positioned(
            top: 4, right: 4,
            child: GestureDetector(
              onTap: () => _set(f.id, ''),
              child: Container(
                width: 26, height: 26,
                decoration: const BoxDecoration(color: Color(0xB30F1419), shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, size: 15, color: Colors.white),
              ),
            ),
          ),
        ]),
      );
    }

    return GestureDetector(
      onTap: busy ? null : () => _pick(f),
      child: Container(
        constraints: const BoxConstraints(minHeight: 130),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFBFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E4EA), width: 2),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (busy)
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: _purple))
          else
            Icon(isImage ? Icons.image_outlined : Icons.upload_file_outlined, size: 26, color: const Color(0xFFC2C8D0)),
          const SizedBox(height: 8),
          Text(busy ? 'Upload en cours…' : 'Touchez pour ajouter ${isImage ? 'une image' : 'un fichier'}',
              textAlign: TextAlign.center, style: AppTheme.body(size: 13, color: _mute)),
          if (!busy) ...[
            const SizedBox(height: 4),
            Text(isImage ? 'PNG, JPG, WebP · max 15 Mo' : 'Images, PDF, SVG, AI, EPS · max 15 Mo',
                style: AppTheme.body(size: 11, color: _faint)),
          ],
        ]),
      ),
    );
  }

  // ── Quantité (stepper, bornée par la MOQ) ──
  Widget _qtyRow() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: const Color(0xFFFAFBFC), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('QUANTITÉ', style: AppTheme.body(size: 11, weight: FontWeight.w800, color: _faint)),
              const SizedBox(height: 3),
              Text.rich(TextSpan(style: AppTheme.body(size: 13, color: _mute), children: [
                const TextSpan(text: 'MOQ : '),
                TextSpan(text: '$_moq $_unit', style: AppTheme.body(size: 13, weight: FontWeight.w700, color: _ink)),
              ])),
            ]),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _line, width: 1.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _step(Icons.remove_rounded, _qty > _moq, () => setState(() => _qty -= 1)),
              SizedBox(
                width: 40,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('$_qty', style: AppTheme.body(size: 15, weight: FontWeight.w800, color: _ink)),
                ),
              ),
              _step(Icons.add_rounded, true, () => setState(() => _qty += 1)),
            ]),
          ),
        ]),
      );

  Widget _step(IconData icon, bool enabled, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onTap();
              }
            : null,
        child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 19, color: enabled ? _ink : _line)),
      );

  // ── Prix total (mode fixed) ──
  Widget _priceBox() {
    final extra = _p.customizationExtra;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('PRIX TOTAL', style: AppTheme.body(size: 11, weight: FontWeight.w800, color: _faint)),
            const SizedBox(height: 3),
            Text.rich(TextSpan(style: AppTheme.body(size: 12, color: _mute), children: [
              TextSpan(text: '$_qty × ${_fmt(widget.unitBasePrice)}'),
              if (extra > 0) TextSpan(text: ' + ${_fmt(extra)} perso', style: AppTheme.body(size: 12, color: _purple)),
              const TextSpan(text: ' TND'),
            ])),
          ]),
        ),
        const SizedBox(width: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('${_fmt(_unitPrice * _qty)} TND',
              style: AppTheme.body(size: 20, weight: FontWeight.w900, color: _orange)),
        ),
      ]),
    );
  }

  Widget _quoteHint() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF9E7),
          border: Border.all(color: const Color(0xFFFDE68A)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline_rounded, size: 15, color: Color(0xFF92600A)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Le fournisseur recevra ta demande et t'enverra un devis dans la messagerie. "
              "Tu pourras ensuite l'accepter pour ajouter au panier.",
              style: AppTheme.body(size: 12.5, color: const Color(0xFF78530A)).copyWith(height: 1.5),
            ),
          ),
        ]),
      );

  Widget _errorBox(String msg) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFDF1F1),
          border: Border.all(color: const Color(0xFFFBCACA)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(msg, style: AppTheme.body(size: 13, color: const Color(0xFFD32F2F))),
      );

  // ── Pied de feuille ──
  Widget _footer() => Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: _line))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(children: [
              OutlinedButton(
                onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 46),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  side: const BorderSide(color: _line, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  foregroundColor: _sub,
                ),
                child: Text('Annuler', style: AppTheme.body(size: 14, weight: FontWeight.w700, color: _sub)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: _submitting ? null : _submit,
                  child: Opacity(
                    opacity: _submitting ? 0.7 : 1,
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(12)),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        if (_submitting)
                          const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        else
                          Icon(_isQuote ? Icons.send_rounded : Icons.shopping_cart_outlined, size: 17, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(_submitting ? 'Envoi…' : (_isQuote ? 'Demander un devis' : 'Ajouter au panier'),
                            style: AppTheme.body(size: 15, weight: FontWeight.w800, color: Colors.white)),
                      ]),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
}