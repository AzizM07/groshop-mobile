// lib/features/checkout/checkout_screen.dart — GROSHOP mobile
// Port Flutter de CheckoutPage.jsx. Parcours en étapes (bouton « Commander » du panier) :
//   1. Checkout  — articles commandés + totaux
//   2. Livraison — adresse, mode de livraison, note pour le livreur
//   3. Paiement  — écran suivant (création de la commande au passage 2 → 3)
//
// Dépendances : flutter pub add flutter_map latlong2 geolocator
// (dio, flutter_riverpod, go_router sont déjà dans le projet)

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' hide Path; // latlong2 a aussi une classe Path → conflit avec dart:ui

import '../../core/theme.dart';
import '../../data/api/api_client.dart' show dioProvider; // Dio de l'app (cookies + CSRF + refresh)
import '../../data/models/cart.dart';
import '../../state/cart_provider.dart';

// ─── Style ───────────────────────────────────────────────────────
const _orange = Color(0xFFFF7A00);
const _orangeDeep = Color(0xFFFF5E00);
const _orangeSoft = Color(0xFFFFF1E3);
const _orangeTint = Color(0xFFFFF8F2);
const _ink = Color(0xFF14171A);
const _mute = Color(0xFF6B7280);
const _faint = Color(0xFFA0A7B0);
const _line = Color(0xFFE8EAED);
const _bg = Color(0xFFF5F6F8);
const _green = Color(0xFF16A34A);
const _red = Color(0xFFDC2626);

const _defaultCoords = LatLng(36.800095, 10.173364); // Tunis

// ─── Endpoints (mêmes que ../lib/api côté web) ──────────────────
const _epAddresses = '/auth/addresses/'; // vues adresses montées dans users/urls.py → /api/auth/addresses/
const _epShippingOptions = '/orders/shipping-options/'; // optionnel : fallback si 404
const _epOrders = '/orders/create/'; // /orders/ = liste (GET seulement) → 405 en POST

/// Nombre d'articles visibles dans le checkout avant « Voir les autres ».
const _recapPreview = 3;

const _countries = [
  ('TN', '🇹🇳', 'Tunisie'),
  ('FR', '🇫🇷', 'France'),
  ('DZ', '🇩🇿', 'Algérie'),
  ('MA', '🇲🇦', 'Maroc'),
  ('IT', '🇮🇹', 'Italie'),
];
const _gouvernorats = [
  'Ariana', 'Béja', 'Ben Arous', 'Bizerte', 'Gabès', 'Gafsa', 'Jendouba',
  'Kairouan', 'Kasserine', 'Kébili', 'Le Kef', 'Mahdia', 'La Manouba', 'Médenine',
  'Monastir', 'Nabeul', 'Sfax', 'Sidi Bouzid', 'Siliana', 'Sousse', 'Tataouine',
  'Tozeur', 'Tunis', 'Zaghouan',
];

String _countryName(String? code) =>
    _countries.firstWhere((c) => c.$1 == code, orElse: () => ('', '', code ?? 'Tunisie')).$3;

String _fmtPrice(double p) =>
    p <= 0 ? 'Gratuit' : '${p % 1 == 0 ? p.toStringAsFixed(0) : p.toStringAsFixed(2)} TND';

/// 12345.5 → « 12 345,50 » (même format que le panier).
String _fmtMoney(num n) {
  final s = n.toStringAsFixed(2);
  final p = s.split('.');
  final b = StringBuffer();
  for (var i = 0; i < p[0].length; i++) {
    if (i > 0 && (p[0].length - i) % 3 == 0) b.write(' ');
    b.write(p[0][i]);
  }
  return '${b.toString()},${p[1]}';
}

final _nominatim = Dio(BaseOptions(
  baseUrl: 'https://nominatim.openstreetmap.org',
  headers: {'User-Agent': 'GROSHOP-mobile/1.0 (groshop.tn)'}, // requis par Nominatim
  connectTimeout: const Duration(seconds: 8),
  receiveTimeout: const Duration(seconds: 8),
));

/// Le client Dio de l'app a `validateStatus: s < 500` : un 400/401/404 ne lève
/// PAS d'exception, il revient comme une réponse normale. On vérifie donc le
/// statut nous-mêmes, sinon une erreur 400 serait prise pour une commande créée.
Response<T> _ensureOk<T>(Response<T> r) {
  final code = r.statusCode ?? 0;
  if (code >= 200 && code < 300) return r;
  throw DioException(
    requestOptions: r.requestOptions,
    response: r,
    type: DioExceptionType.badResponse,
  );
}

/// Message lisible depuis une réponse d'erreur DRF ({error}, {detail} ou {champ: [msg]}).
String? _apiMessage(Object? data) {
  if (data is! Map) return null;
  for (final k in ['error', 'detail', 'non_field_errors']) {
    final v = data[k];
    if (v is String && v.isNotEmpty) return v;
    if (v is List && v.isNotEmpty) return '${v.first}';
  }
  for (final v in data.values) {
    if (v is List && v.isNotEmpty) return '${v.first}';
    if (v is String && v.isNotEmpty) return v;
  }
  return null;
}

// ─── Modèles ─────────────────────────────────────────────────────

/// Une ligne du panier à commander. On garde cart_item_id : le backend s'en
/// sert pour conserver prix négocié (devis), surcoût perso et personnalisation.
class CheckoutLine {
  final String cartItemId;
  final String productId;
  final int quantity;
  const CheckoutLine({required this.cartItemId, required this.productId, required this.quantity});

  Map<String, dynamic> toJson() =>
      {'cart_item_id': cartItemId, 'product_id': productId, 'quantity': quantity};
}

class Address {
  final String id;
  final String fullName, phone, country, region, city, postalCode, street, additional;
  final bool isDefault;
  final double? lat, lng;

  const Address({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.country,
    required this.region,
    required this.city,
    required this.postalCode,
    required this.street,
    required this.additional,
    required this.isDefault,
    this.lat,
    this.lng,
  });

  factory Address.fromJson(Map<String, dynamic> j) {
    double? d(Object? v) => v == null ? null : double.tryParse(v.toString());
    String s(Object? v) => v?.toString() ?? '';
    return Address(
      id: s(j['id']),
      fullName: s(j['full_name']),
      phone: s(j['phone']),
      country: s(j['country']).isEmpty ? 'TN' : s(j['country']),
      region: s(j['region']),
      city: s(j['city']),
      postalCode: s(j['postal_code']),
      street: s(j['street']),
      additional: s(j['additional']),
      isDefault: j['is_default'] == true,
      lat: d(j['latitude']),
      lng: d(j['longitude']),
    );
  }

  Address copyWith({bool? isDefault}) => Address(
        id: id, fullName: fullName, phone: phone, country: country, region: region,
        city: city, postalCode: postalCode, street: street, additional: additional,
        isDefault: isDefault ?? this.isDefault, lat: lat, lng: lng,
      );

  String get line => [street, city, region, postalCode, _countryName(country)]
      .where((e) => e.trim().isNotEmpty)
      .join(', ');

  LatLng? get coords => (lat != null && lng != null) ? LatLng(lat!, lng!) : null;
}

class ShippingOption {
  final String id;
  final String title, sub;
  final double price;
  final bool express;
  const ShippingOption({required this.id, required this.title, required this.sub, required this.price, this.express = false});

  factory ShippingOption.fromJson(Map<String, dynamic> j) => ShippingOption(
        id: j['id'].toString(),
        title: j['title']?.toString() ?? 'Livraison',
        sub: j['sub']?.toString() ?? '',
        price: double.tryParse('${j['price'] ?? 0}') ?? 0,
        express: '${j['title']}'.toLowerCase().contains('express'),
      );
}

const _fallbackShipping = [
  ShippingOption(id: '0', title: 'Livraison standard', sub: 'Reçu en 3–5 jours', price: 0),
  ShippingOption(id: '1', title: 'Livraison express', sub: 'Reçu en 24–48 h', price: 12, express: true),
];

// ═════════════════════════════════════════════════════════════════
// ÉCRAN
// ═════════════════════════════════════════════════════════════════
class CheckoutScreen extends ConsumerStatefulWidget {
  /// Lignes sélectionnées dans le panier (passées via GoRouter `extra`).
  final List<CheckoutLine> lines;
  const CheckoutScreen({super.key, required this.lines});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  List<Address> _addresses = [];
  bool _addrLoading = true;
  String? _selectedId;
  LatLng? _selectedCoords;

  List<ShippingOption> _shippingOptions = _fallbackShipping;
  bool _shippingLoading = false;
  String? _shippingId = _fallbackShipping.first.id;

  final _notes = TextEditingController();
  String? _error;
  bool _submitting = false;
  bool _showAllItems = false;
  int _step = 0; // 0 = Checkout · 1 = Livraison (2 = Paiement, écran suivant)

  Dio get _api => ref.read(dioProvider);

  Address? get _selected {
    for (final a in _addresses) {
      if (a.id == _selectedId) return a;
    }
    return null;
  }

  ShippingOption? get _shipping => _shippingOptions.where((o) => o.id == _shippingId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  // ── Données ──
  Future<void> _loadAddresses() async {
    setState(() => _addrLoading = true);
    try {
      final r = _ensureOk(await _api.get(_epAddresses));
      final d = r.data;
      final raw = d is List ? d : ((d is Map ? d['results'] : null) as List? ?? const []);
      final list = raw.map((e) => Address.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      if (!mounted) return;
      setState(() {
        _addresses = list;
        _selectedId ??= (list.where((a) => a.isDefault).firstOrNull ?? list.firstOrNull)?.id;
      });
      _onAddressChanged();
    } catch (_) {
      if (mounted) setState(() => _addresses = []);
    } finally {
      if (mounted) setState(() => _addrLoading = false);
    }
  }

  void _onAddressChanged() {
    final a = _selected;
    if (a == null) return;
    _loadShipping(a);
    _resolveCoords(a);
  }

  Future<void> _loadShipping(Address a) async {
    setState(() => _shippingLoading = true);
    try {
      final r = _ensureOk(await _api.get(_epShippingOptions, queryParameters: {'address_id': a.id}));
      final d = r.data;
      final raw = d is List ? d : ((d is Map ? d['results'] : null) as List? ?? const []);
      final opts = raw.map((e) => ShippingOption.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      if (opts.isEmpty) throw Exception('empty');
      if (!mounted) return;
      setState(() {
        _shippingOptions = opts;
        if (!opts.any((o) => o.id == _shippingId)) _shippingId = opts.first.id;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _shippingOptions = _fallbackShipping;
        if (!_fallbackShipping.any((o) => o.id == _shippingId)) _shippingId = _fallbackShipping.first.id;
      });
    } finally {
      if (mounted) setState(() => _shippingLoading = false);
    }
  }

  /// Coordonnées de l'adresse sélectionnée : stockées, sinon géocodage Nominatim.
  Future<void> _resolveCoords(Address a) async {
    if (a.coords != null) {
      setState(() => _selectedCoords = a.coords);
      return;
    }
    setState(() => _selectedCoords = null);
    final q = [a.street, a.city, a.region, a.postalCode, a.country].where((e) => e.isNotEmpty).join(', ');
    if (q.isEmpty) return;
    try {
      final r = await _nominatim.get('/search', queryParameters: {'format': 'json', 'limit': 1, 'q': q});
      final list = r.data as List?;
      if (list == null || list.isEmpty || !mounted || _selectedId != a.id) return;
      setState(() => _selectedCoords = LatLng(
            double.parse('${list[0]['lat']}'),
            double.parse('${list[0]['lon']}'),
          ));
    } catch (_) {/* carte masquée si introuvable */}
  }

  Future<void> _createAddress(Map<String, dynamic> form) async {
    final r = _ensureOk(await _api.post(_epAddresses, data: form));
    final created = Address.fromJson(Map<String, dynamic>.from(r.data as Map));
    if (!mounted) return;
    setState(() {
      final rest = _addresses
          .where((a) => a.id != created.id)
          .map((a) => created.isDefault ? a.copyWith(isDefault: false) : a);
      _addresses = [created, ...rest];
      _selectedId = created.id;
      _error = null;
    });
    _onAddressChanged();
  }

  Future<void> _openAddressSheet() async {
    HapticFeedback.lightImpact();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddressSheet(
        initial: _selectedCoords ?? _defaultCoords,
        onSave: _createAddress,
      ),
    );
  }

  void _goToDelivery(List<CartItem> items) {
    if (items.isEmpty) return setState(() => _error = 'Votre panier est vide');
    HapticFeedback.selectionClick();
    setState(() { _error = null; _step = 1; });
  }

  void _backToCheckout() {
    HapticFeedback.selectionClick();
    setState(() { _error = null; _step = 0; });
  }

  Future<void> _goToPayment() async {
    if (_submitting) return;
    if (widget.lines.isEmpty) return setState(() => _error = 'Votre panier est vide');
    final a = _selected;
    if (a == null) return setState(() => _error = 'Veuillez choisir une adresse de livraison');

    setState(() { _error = null; _submitting = true; });

    // TODO : pas encore de sélecteur de paiement → COD en dur (comme le web).
    const paymentMethod = 'cod';
    final payload = {
      'address_id': a.id,
      'payment_method': paymentMethod,
      'notes': _notes.text.trim(),
      // ⚠️ cart_item_id pour chaque ligne : sinon le backend recalcule les prix
      // depuis les price_tiers et perd devis / perso / CustomizationRequest.
      'items': widget.lines.map((l) => l.toJson()).toList(),
    };

    try {
      final r = _ensureOk(await _api.post(_epOrders, data: payload));
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final created = r.data;
      ref.invalidate(cartProvider); // recharge le panier : les articles commandés disparaissent
      if (paymentMethod == 'cod') {
        context.go('/commande/confirmation', extra: created);
      } else {
        context.push('/checkout/paiement', extra: (created as Map)['id']);
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        setState(() => _error = 'Votre session a expiré. Reconnectez-vous.');
      } else {
        setState(() => _error = _apiMessage(e.response?.data) ?? 'Erreur lors de la création de la commande');
      }
    } catch (e) {
      setState(() => _error = 'Erreur lors de la création de la commande');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── UI ──
  @override
  Widget build(BuildContext context) {
    // Articles commandés = lignes du panier sélectionnées (via cart_item_id).
    final cart = ref.watch(cartProvider);
    final ids = widget.lines.map((l) => l.cartItemId).toSet();
    final items = cart.items.where((it) => ids.contains(it.id)).toList();

    double subtotal = 0;
    for (final it in items) {
      subtotal += it.lineTotal;
    }
    final grandTotal = subtotal + (_shipping?.price ?? 0);

    final onCheckout = _step == 0;

    return PopScope(
      canPop: onCheckout,
      onPopInvoked: (didPop) {
        if (!didPop) _backToCheckout(); // retour Android : Livraison → Checkout
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 0,
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 30, color: _ink),
              onPressed: onCheckout ? () => context.pop() : _backToCheckout,
            ),
            title: Text(onCheckout ? 'Checkout' : 'Livraison',
                style: AppTheme.body(size: 17, weight: FontWeight.w800, color: _ink)),
            actions: const [
              Padding(
                padding: EdgeInsets.only(right: 14),
                child: Icon(Icons.lock_outline_rounded, size: 19, color: _mute),
              ),
            ],
          ),
          body: Column(
            children: [
              _Stepper(current: _step),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: ListView(
                    key: ValueKey(_step),
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    children: [
                      if (onCheckout)
                        // ── Étape 1 : Checkout ──
                        _SectionCard(
                          icon: Icons.receipt_long_outlined,
                          title: 'Checkout',
                          trailing: items.isEmpty
                              ? null
                              : Text('${items.length} ${items.length > 1 ? 'articles' : 'article'}',
                                  style: AppTheme.body(size: 12, color: _mute)),
                          child: _checkoutContent(items),
                        )
                      else ...[
                        // ── Étape 2 : Livraison ──
                        _SectionCard(
                          icon: Icons.location_on_outlined,
                          title: 'Adresse de livraison',
                          child: _addressContent(),
                        ),
                        const SizedBox(height: 12),
                        _SectionCard(
                          icon: Icons.local_shipping_outlined,
                          title: 'Mode de livraison',
                          child: _shippingContent(),
                        ),
                        const SizedBox(height: 12),
                        _SectionCard(
                          icon: Icons.sticky_note_2_outlined,
                          title: 'Note pour le livreur',
                          trailing: Text('Optionnel', style: AppTheme.body(size: 11.5, color: _faint)),
                          child: _Input(
                            controller: _notes,
                            hint: 'Instructions de livraison, horaires…',
                            maxLines: 3,
                          ),
                        ),
                      ],
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: _error == null
                            ? const SizedBox.shrink()
                            : Padding(
                                key: ValueKey(_error),
                                padding: const EdgeInsets.only(top: 12),
                                child: _ErrorBanner(message: _error!),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: onCheckout
              ? _BottomBar(
                  loading: false,
                  label: 'Continuer vers la livraison',
                  info: items.isEmpty
                      ? null
                      : '${items.length} ${items.length > 1 ? 'articles' : 'article'} · ${_fmtMoney(subtotal)} TND',
                  onTap: () => _goToDelivery(items),
                )
              : _BottomBar(
                  loading: _submitting,
                  label: 'Continuer vers le paiement',
                  info: '${_shipping?.title ?? 'Livraison'} · Total ${_fmtMoney(grandTotal)} TND',
                  onTap: _goToPayment,
                ),
        ),
      ),
    );
  }

  // ── Étape 1 · Checkout : articles + totaux ──
  Widget _checkoutContent(List<CartItem> items) {
    if (items.isEmpty) {
      return Text('Les articles sélectionnés ne sont plus dans votre panier.',
          style: AppTheme.body(size: 13, color: _mute));
    }

    double subtotal = 0, savings = 0;
    int units = 0;
    for (final it in items) {
      subtotal += it.lineTotal;
      savings += it.lineSavings;
      units += it.quantity;
    }
    final total = subtotal; // la livraison s'ajoute à l'étape 2

    final shown = (_showAllItems || items.length <= _recapPreview) ? items : items.take(_recapPreview).toList();
    final hidden = items.length - _recapPreview;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) Container(height: 1, color: _line, margin: const EdgeInsets.symmetric(vertical: 10)),
          _RecapItem(item: shown[i], onTap: () => context.push('/produit/${shown[i].productId}')),
        ],
        if (items.length > _recapPreview)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _showAllItems = !_showAllItems),
              style: TextButton.styleFrom(
                foregroundColor: _orange,
                padding: const EdgeInsets.only(top: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _showAllItems ? 'Réduire' : 'Voir ${hidden > 1 ? 'les $hidden autres articles' : "l'autre article"}',
                style: AppTheme.body(size: 12.5, weight: FontWeight.w700, color: _orange),
              ),
            ),
          ),
        Container(height: 1, color: _line, margin: const EdgeInsets.only(top: 14, bottom: 12)),
        _sumLine('Sous-total ($units ${units > 1 ? 'unités' : 'unité'})', '${_fmtMoney(subtotal)} TND'),
        if (savings > 0) _sumLine('Économies', '− ${_fmtMoney(savings)} TND', color: _orange),
        _sumLine('Livraison', 'Choisie à l’étape suivante', color: _faint),
        Container(height: 1, color: _line, margin: const EdgeInsets.symmetric(vertical: 10)),
        Row(children: [
          Flexible(
            child: Text.rich(
              TextSpan(text: 'Total ', style: AppTheme.body(size: 15, weight: FontWeight.w700, color: _ink),
                  children: [TextSpan(text: 'TVA incluse, hors livraison', style: AppTheme.body(size: 12, color: _faint))]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text('${_fmtMoney(total)} TND', maxLines: 1,
                  style: AppTheme.body(size: 19, weight: FontWeight.w800, color: _ink)),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _sumLine(String label, String value, {Color color = _ink}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTheme.body(size: 13, color: _mute)),
          ),
          const SizedBox(width: 10),
          Text(value, maxLines: 1, style: AppTheme.body(size: 13, weight: FontWeight.w600, color: color)),
        ]),
      );

  // ── Étape 2 · Adresse ──
  Widget _addressContent() {
    if (_addrLoading) {
      return Column(children: const [_Skeleton(height: 74), SizedBox(height: 10), _Skeleton(height: 120)]);
    }
    if (_addresses.isEmpty) {
      return _EmptyAddress(onAdd: _openAddressSheet);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in _addresses) ...[
          _AddressTile(
            address: a,
            selected: a.id == _selectedId,
            onTap: () {
              if (a.id == _selectedId) return;
              HapticFeedback.selectionClick();
              setState(() { _selectedId = a.id; _error = null; });
              _onAddressChanged();
            },
          ),
          const SizedBox(height: 10),
        ],
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          child: _selectedCoords == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _MapPreview(coords: _selectedCoords!),
                ),
        ),
        _DashedButton(label: 'Ajouter une adresse', icon: Icons.add_rounded, onTap: _openAddressSheet),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => context.push('/dashboard/addresses'),
            style: TextButton.styleFrom(foregroundColor: _mute, padding: const EdgeInsets.only(top: 8)),
            child: Text('Gérer mes adresses',
                style: AppTheme.body(size: 12.5, color: _mute).copyWith(decoration: TextDecoration.underline)),
          ),
        ),
      ],
    );
  }

  // ── Étape 2 · Mode de livraison ──
  Widget _shippingContent() {
    if (_shippingLoading) {
      return Column(children: const [_Skeleton(height: 66), SizedBox(height: 10), _Skeleton(height: 66)]);
    }
    return Column(
      children: [
        for (var i = 0; i < _shippingOptions.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _ShippingTile(
            option: _shippingOptions[i],
            selected: _shippingOptions[i].id == _shippingId,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _shippingId = _shippingOptions[i].id);
            },
          ),
        ],
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// COMPOSANTS
// ═════════════════════════════════════════════════════════════════

/// Étapes Checkout → Livraison → Paiement.
class _Stepper extends StatelessWidget {
  final int current;
  const _Stepper({required this.current});

  @override
  Widget build(BuildContext context) {
    const labels = ['Checkout', 'Livraison', 'Paiement'];
    final children = <Widget>[];
    for (var i = 0; i < labels.length; i++) {
      if (i > 0) {
        children.add(Expanded(
          child: Container(
            height: 2,
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
              color: i <= current ? _orange : _line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ));
      }
      final done = i < current, active = i == current;
      children.add(Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done || active ? _orange : Colors.white,
              border: Border.all(color: done || active ? _orange : _line, width: 1.5),
              boxShadow: active
                  ? [BoxShadow(color: _orange.withOpacity(.30), blurRadius: 10, offset: const Offset(0, 3))]
                  : null,
            ),
            child: done
                ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                : Text('${i + 1}',
                    style: AppTheme.body(size: 12, weight: FontWeight.w800, color: active ? Colors.white : _faint)),
          ),
          const SizedBox(height: 5),
          Text(labels[i],
              style: AppTheme.body(
                size: 11,
                weight: active ? FontWeight.w800 : FontWeight.w500,
                color: active ? _ink : (done ? _orange : _faint),
              )),
        ],
      ));
    }
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(28, 6, 28, 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: children),
    );
  }
}

/// Carte de section avec pastille icône.
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final Widget child;
  const _SectionCard({required this.icon, required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 14, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: _orangeSoft, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: _orange),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: AppTheme.body(size: 15, weight: FontWeight.w800, color: _ink))),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Ligne produit du checkout : vignette, nom, variante, quantité × prix, total.
class _RecapItem extends StatelessWidget {
  final CartItem item;
  final VoidCallback onTap;
  const _RecapItem({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final it = item;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 58,
            height: 58,
            child: (it.imageUrl != null && it.imageUrl!.isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: it.imageUrl!,
                    fit: BoxFit.cover,
                    memCacheWidth: 174,
                    errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFFF3F4F6)),
                  )
                : const ColoredBox(
                    color: Color(0xFFF3F4F6),
                    child: Icon(Icons.inventory_2_outlined, size: 22, color: _faint),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: AppTheme.body(size: 13.5, weight: FontWeight.w600, color: _ink).copyWith(height: 1.3)),
            if (it.variantName != null && it.variantName!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(it.variantName!, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(size: 12, color: _faint)),
            ],
            const SizedBox(height: 4),
            Text('${it.quantity} × ${_fmtMoney(it.unitPrice)} TND',
                maxLines: 1, style: AppTheme.body(size: 12, color: _mute)),
          ]),
        ),
        const SizedBox(width: 10),
        Text('${_fmtMoney(it.lineTotal)} TND',
            style: AppTheme.body(size: 14, weight: FontWeight.w800, color: _ink)),
      ]),
    );
  }
}

class _Radio extends StatelessWidget {
  final bool on;
  const _Radio({required this.on});
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: on ? _orange : const Color(0xFFCCD0D5), width: 2),
      ),
      alignment: Alignment.center,
      child: AnimatedScale(
        scale: on ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: _orange, shape: BoxShape.circle)),
      ),
    );
  }
}

class _AddressTile extends StatelessWidget {
  final Address address;
  final bool selected;
  final VoidCallback onTap;
  const _AddressTile({required this.address, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = address;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected ? _orangeTint : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? _orange : _line, width: selected ? 1.6 : 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: _Radio(on: selected)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      text: a.fullName,
                      style: AppTheme.body(size: 14, weight: FontWeight.w700, color: _ink),
                      children: [
                        if (a.phone.isNotEmpty)
                          TextSpan(
                            text: '  ·  ${a.phone}',
                            style: AppTheme.body(size: 12.5, weight: FontWeight.w500, color: _mute),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(a.line, style: AppTheme.body(size: 12.5, color: _mute).copyWith(height: 1.45)),
                  if (a.isDefault) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(color: _orangeSoft, borderRadius: BorderRadius.circular(20)),
                      child: Text('Par défaut',
                          style: AppTheme.body(size: 10.5, weight: FontWeight.w700, color: _orangeDeep)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyAddress extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyAddress({required this.onAdd});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(color: _orangeSoft, shape: BoxShape.circle),
          child: const Icon(Icons.add_location_alt_outlined, color: _orange, size: 26),
        ),
        const SizedBox(height: 10),
        Text('Où livrer votre commande ?', style: AppTheme.body(size: 14, weight: FontWeight.w800, color: _ink)),
        const SizedBox(height: 4),
        Text('Ajoutez une adresse, on la retient pour la prochaine fois.',
            textAlign: TextAlign.center, style: AppTheme.body(size: 12.5, color: _mute)),
        const SizedBox(height: 14),
        SizedBox(
          height: 44,
          child: FilledButton.icon(
            onPressed: onAdd,
            style: FilledButton.styleFrom(
              backgroundColor: _orange,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text('Ajouter une adresse', style: AppTheme.body(size: 13.5, weight: FontWeight.w700, color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}

class _Pin extends StatelessWidget {
  final double size;
  const _Pin({this.size = 40});
  @override
  Widget build(BuildContext context) {
    return Icon(Icons.location_on_rounded, size: size, color: _orange, shadows: const [
      Shadow(color: Color(0x55000000), blurRadius: 8, offset: Offset(0, 3)),
    ]);
  }
}

/// Aperçu non interactif de l'adresse sélectionnée.
class _MapPreview extends StatelessWidget {
  final LatLng coords;
  const _MapPreview({required this.coords});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 130,
        child: Stack(children: [
          FlutterMap(
            key: ValueKey(coords),
            options: MapOptions(
              initialCenter: coords,
              initialZoom: 15,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'tn.groshop.groshop',
              ),
              MarkerLayer(markers: [
                Marker(point: coords, width: 44, height: 44, alignment: Alignment.topCenter, child: const _Pin()),
              ]),
            ],
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _line),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ShippingTile extends StatelessWidget {
  final ShippingOption option;
  final bool selected;
  final VoidCallback onTap;
  const _ShippingTile({required this.option, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final free = option.price <= 0;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? _orangeTint : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? _orange : _line, width: selected ? 1.6 : 1),
        ),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: selected ? _orange : _orangeSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(option.express ? Icons.bolt_rounded : Icons.local_shipping_outlined,
                size: 22, color: selected ? Colors.white : _orange),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(option.title, style: AppTheme.body(size: 14, weight: FontWeight.w700, color: _ink)),
              if (option.sub.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(option.sub, style: AppTheme.body(size: 12, color: _mute)),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          Text(_fmtPrice(option.price),
              style: AppTheme.body(size: 13.5, weight: FontWeight.w800, color: free ? _green : _ink)),
          const SizedBox(width: 10),
          _Radio(on: selected),
        ]),
      ),
    );
  }
}

class _DashedButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _DashedButton({required this.label, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: CustomPaint(
          painter: _DashedBorderPainter(color: _orange, radius: 14),
          child: SizedBox(
            height: 48,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 19, color: _orange),
              const SizedBox(width: 6),
              Text(label, style: AppTheme.body(size: 13.5, weight: FontWeight.w700, color: _orange)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(0.7);
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 6), paint);
        d += 10;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) => old.color != color || old.radius != radius;
}

class _Skeleton extends StatefulWidget {
  final double height;
  const _Skeleton({required this.height});
  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: .45, end: 1.0).animate(_c),
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(color: const Color(0xFFEFF1F4), borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded, size: 18, color: _red),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: AppTheme.body(size: 12.5, weight: FontWeight.w600, color: _red))),
      ]),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final bool loading;
  final String label;
  final String? info;
  final VoidCallback onTap;
  const _BottomBar({required this.loading, required this.label, required this.onTap, this.info});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, -4))],
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.paddingOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (info != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.verified_user_outlined, size: 14, color: _green),
              const SizedBox(width: 5),
              Flexible(
                child: Text(info!, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(size: 11.5, color: _mute)),
              ),
            ]),
          ),
        GestureDetector(
          onTap: loading ? null : onTap,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: loading ? .75 : 1,
            child: Container(
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFFF8A1F), _orangeDeep]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: _orangeDeep.withOpacity(.30), blurRadius: 14, offset: const Offset(0, 5))],
              ),
              child: loading
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Flexible(
                        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: AppTheme.body(size: 15.5, weight: FontWeight.w800, color: Colors.white)),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 19, color: Colors.white),
                    ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Champs ──
class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(text, style: AppTheme.body(size: 12, weight: FontWeight.w600, color: _mute)),
      );
}

InputDecoration _decoration(String? hint) => InputDecoration(
      hintText: hint,
      hintStyle: AppTheme.body(size: 14, color: _faint),
      filled: true,
      fillColor: const Color(0xFFF8F9FA),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _orange, width: 1.5)),
    );

class _Input extends StatelessWidget {
  final TextEditingController controller;
  final String? label, hint;
  final int maxLines;
  final TextInputType? keyboard;
  final ValueChanged<String>? onChanged;
  const _Input({required this.controller, this.label, this.hint, this.maxLines = 1, this.keyboard, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (label != null) _Label(label!),
      TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboard,
        onChanged: onChanged,
        cursorColor: _orange,
        style: AppTheme.body(size: 14, color: _ink),
        decoration: _decoration(hint),
      ),
    ]);
  }
}

class _Dropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<(String, String)> items; // (value, label)
  final ValueChanged<String?> onChanged;
  final String? hint;
  const _Dropdown({required this.label, required this.value, required this.items, required this.onChanged, this.hint});

  @override
  Widget build(BuildContext context) {
    final safe = items.any((i) => i.$1 == value) ? value : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Label(label),
      DropdownButtonFormField<String>(
        value: safe,
        isExpanded: true,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _mute),
        borderRadius: BorderRadius.circular(12),
        dropdownColor: Colors.white,
        menuMaxHeight: 320,
        style: AppTheme.body(size: 14, color: _ink),
        decoration: _decoration(hint),
        items: [for (final i in items) DropdownMenuItem(value: i.$1, child: Text(i.$2, overflow: TextOverflow.ellipsis))],
        onChanged: onChanged,
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════
// FEUILLE « NOUVELLE ADRESSE » (carte + formulaire + reverse geocoding)
// ═════════════════════════════════════════════════════════════════
class _AddressSheet extends StatefulWidget {
  final LatLng initial;
  final Future<void> Function(Map<String, dynamic> form) onSave;
  const _AddressSheet({required this.initial, required this.onSave});

  @override
  State<_AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends State<_AddressSheet> {
  final _map = MapController();
  late LatLng _pos = widget.initial;

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _postal = TextEditingController();
  final _street = TextEditingController();
  final _extra = TextEditingController();
  String _country = 'TN';
  String? _region;
  bool _isDefault = false;

  bool _geocoding = false;
  bool _locating = false;
  bool _saving = false;
  String? _error;
  Timer? _debounce;

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _phone.text.trim().isNotEmpty &&
      _street.text.trim().isNotEmpty &&
      _city.text.trim().isNotEmpty &&
      (_region ?? '').isNotEmpty;

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_name, _phone, _city, _postal, _street, _extra]) {
      c.dispose();
    }
    super.dispose();
  }

  void _movePin(LatLng p, {bool moveCamera = false}) {
    setState(() => _pos = p);
    if (moveCamera) _map.move(p, 16);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _reverseGeocode);
  }

  /// Remplit automatiquement les champs quand le pin bouge.
  Future<void> _reverseGeocode() async {
    final p = _pos;
    setState(() => _geocoding = true);
    try {
      final r = await _nominatim.get('/reverse', queryParameters: {
        'format': 'json',
        'lat': p.latitude,
        'lon': p.longitude,
        'accept-language': 'fr',
      });
      final addr = (r.data as Map?)?['address'] as Map?;
      if (addr == null || !mounted || p != _pos) return;
      setState(() {
        final road = addr['road'] ?? addr['pedestrian'] ?? addr['neighbourhood'];
        if (road != null) _street.text = '$road';
        final city = addr['city'] ?? addr['town'] ?? addr['village'] ?? addr['suburb'];
        if (city != null) _city.text = '$city';
        if (addr['postcode'] != null) _postal.text = '${addr['postcode']}';
        final cc = '${addr['country_code'] ?? ''}'.toUpperCase();
        if (_countries.any((c) => c.$1 == cc)) _country = cc;
        final state = '${addr['state'] ?? addr['region'] ?? ''}'.toLowerCase();
        final match = _gouvernorats.where((g) => state.contains(g.toLowerCase())).firstOrNull;
        if (match != null) _region = match;
      });
    } catch (_) {
      /* on laisse l'utilisateur saisir à la main */
    } finally {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw 'Activez la localisation de votre téléphone.';
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw 'Autorisez l’accès à la position pour GROSHOP.';
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      _movePin(LatLng(pos.latitude, pos.longitude), moveCamera: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is String ? e : 'Impossible de récupérer votre position.')),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (!_valid || _saving || _geocoding) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onSave({
        'full_name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'country': _country,
        'region': _region,
        'city': _city.text.trim(),
        'postal_code': _postal.text.trim(),
        'street': _street.text.trim(),
        'additional': _extra.text.trim(),
        'is_default': _isDefault,
        'latitude': double.parse(_pos.latitude.toStringAsFixed(6)),
        'longitude': double.parse(_pos.longitude.toStringAsFixed(6)),
      });
      if (mounted) Navigator.of(context).pop();
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final body = e.response?.data;
      // 🔎 Diagnostic : visible dans le terminal de `flutter run`.
      debugPrint('❌ POST $_epAddresses → ${code ?? e.type} | body: $body');
      if (mounted) {
        setState(() => _error = _apiMessage(body) ??
            (code == null
                ? 'Connexion au serveur impossible (${e.type.name}).'
                : 'Erreur serveur ($code). Réessayez plus tard.'));
      }
    } catch (e, st) {
      debugPrint('❌ Enregistrement adresse : $e\n$st');
      if (mounted) setState(() => _error = 'Erreur inattendue : $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _valid && !_saving && !_geocoding;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Poignée + titre
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: _line, borderRadius: BorderRadius.circular(4))),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 8, 6),
            child: Row(children: [
              Expanded(
                child: Text('Nouvelle adresse', style: AppTheme.body(size: 18, weight: FontWeight.w800, color: _ink)),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: _mute),
              ),
            ]),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                // Carte interactive
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 210,
                    child: Stack(children: [
                      FlutterMap(
                        mapController: _map,
                        options: MapOptions(
                          initialCenter: _pos,
                          initialZoom: 15,
                          onTap: (_, p) => _movePin(p),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'tn.groshop.groshop',
                          ),
                          MarkerLayer(markers: [
                            Marker(point: _pos, width: 48, height: 48, alignment: Alignment.topCenter, child: const _Pin(size: 46)),
                          ]),
                        ],
                      ),
                      Positioned(
                        left: 10,
                        top: 10,
                        child: Material(
                          color: _orange,
                          shape: const StadiumBorder(),
                          elevation: 3,
                          shadowColor: _orange.withOpacity(.4),
                          child: InkWell(
                            customBorder: const StadiumBorder(),
                            onTap: _locating ? null : _locate,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                _locating
                                    ? const SizedBox(
                                        width: 14, height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.my_location_rounded, size: 15, color: Colors.white),
                                const SizedBox(width: 6),
                                Text(_locating ? 'Localisation…' : 'Ma position',
                                    style: AppTheme.body(size: 12, weight: FontWeight.w700, color: Colors.white)),
                              ]),
                            ),
                          ),
                        ),
                      ),
                      if (_geocoding)
                        Positioned(
                          right: 10,
                          top: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const SizedBox(
                                width: 12, height: 12,
                                child: CircularProgressIndicator(strokeWidth: 1.8, color: _orange)),
                              const SizedBox(width: 6),
                              Text('Adresse…', style: AppTheme.body(size: 11, weight: FontWeight.w600, color: _mute)),
                            ]),
                          ),
                        ),
                    ]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 2),
                  child: Text('Touchez la carte pour placer le repère — les champs se remplissent seuls.',
                      style: AppTheme.body(size: 11, color: _faint)),
                ),
                const SizedBox(height: 16),

                Row(children: [
                  Expanded(child: _Input(controller: _name, label: 'Nom complet', hint: 'Destinataire', onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Input(
                      controller: _phone, label: 'Téléphone', hint: '+216 …',
                      keyboard: TextInputType.phone, onChanged: (_) => setState(() {}),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: _Dropdown(
                      label: 'Pays',
                      value: _country,
                      items: [for (final c in _countries) (c.$1, '${c.$2}  ${c.$3}')],
                      onChanged: (v) => setState(() => _country = v ?? 'TN'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Dropdown(
                      label: 'Gouvernorat',
                      value: _region,
                      hint: 'Choisir…',
                      items: [for (final g in _gouvernorats) (g, g)],
                      onChanged: (v) => setState(() => _region = v),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(flex: 3, child: _Input(controller: _city, label: 'Ville', hint: 'Ville', onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: _Input(controller: _postal, label: 'Code postal', hint: '1000', keyboard: TextInputType.number)),
                ]),
                const SizedBox(height: 12),
                _Input(controller: _street, label: 'Adresse', hint: 'Rue, numéro, quartier…', onChanged: (_) => setState(() {})),
                const SizedBox(height: 12),
                _Input(controller: _extra, label: 'Complément (optionnel)', hint: 'Apt, étage, bâtiment'),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  value: _isDefault,
                  onChanged: (v) => setState(() => _isDefault = v),
                  activeColor: _orange,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Définir comme adresse par défaut',
                      style: AppTheme.body(size: 13.5, weight: FontWeight.w600, color: _ink)),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  _ErrorBanner(message: _error!),
                ],
              ],
            ),
          ),
          // Bouton enregistrer
          Container(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + MediaQuery.paddingOf(context).bottom),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: _line))),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: canSave ? _save : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _orange,
                  disabledBackgroundColor: _orange.withOpacity(.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                    : Text('Enregistrer l’adresse',
                        style: AppTheme.body(size: 15, weight: FontWeight.w800, color: Colors.white)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}