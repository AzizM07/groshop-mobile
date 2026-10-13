import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/api/api_client.dart';

const _orange = Color(0xFFFF7A00);
const _ink = Color(0xFF0F1419);
const _sub = Color(0xFF3D4853);
const _mute = Color(0xFF6B7785);
const _faint = Color(0xFF9AA3AE);
const _line = Color(0xFFE8EAED);
const _soft = Color(0xFFFFF0E8);
const _inputBg = Color(0xFFF4F5F7);
const _threadBg = Color(0xFFEFEFF3);
const _green = Color(0xFF0E9F6E);
const _red = Color(0xFFFF0000);

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

/// Contexte transmis par la fiche produit (équivalent du `state.draft` web).
class ChatDraft {
  final String supplierSlug;
  final String productId;
  final String? supplierName;
  final String productName;
  final String? productImage;
  final double price;
  final double? oldPrice;
  final int disc;

  const ChatDraft({
    required this.supplierSlug,
    required this.productId,
    required this.productName,
    this.supplierName,
    this.productImage,
    this.price = 0,
    this.oldPrice,
    this.disc = 0,
  });
}

/// Fil BROUILLON (depuis un produit) : n'écrit RIEN en base.
/// - Si une conversation existe déjà pour ce fournisseur + produit → on bascule dessus.
/// - Sinon : accueil + carte produit ; la conversation n'est créée qu'au 1er envoi,
///   puis on remplace l'écran par le vrai fil.
class DraftChatScreen extends ConsumerStatefulWidget {
  final ChatDraft? draft;
  const DraftChatScreen({super.key, required this.draft});

  @override
  ConsumerState<DraftChatScreen> createState() => _DraftChatScreenState();
}

class _DraftChatScreenState extends ConsumerState<DraftChatScreen> {
  final _input = TextEditingController();
  Map? _supplier; // entête fournisseur renvoyée par /resolve/ (name, logo_url…)
  bool _sending = false;
  bool _showCard = true;

  ChatDraft? get _d => widget.draft;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    if (_d == null) {
      // Ouvert sans contexte (ex. redémarrage) → retour à la liste
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/dashboard/messages');
      });
    } else {
      _resolve();
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// GET /messaging/resolve/<slug>/?product_id= → {id} si la conv existe, sinon {supplier}.
  Future<void> _resolve() async {
    final d = _d!;
    try {
      final r = await ref.read(dioProvider).get(
            '/messaging/resolve/${d.supplierSlug}/',
            queryParameters: {'product_id': d.productId},
          );
      if (!mounted) return;
      final data = r.data;
      if (data is Map && data['id'] != null) {
        context.pushReplacement('/messages/${data['id']}');
      } else if (data is Map && data['supplier'] is Map) {
        setState(() => _supplier = data['supplier'] as Map);
      }
    } catch (_) {
      // silencieux : on garde l'entête issue du produit
    }
  }

  /// 1er message → crée la conversation, envoie, puis remplace par le vrai fil.
  Future<void> _send([String? override]) async {
    final d = _d!;
    final text = (override ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final dio = ref.read(dioProvider);
    try {
      final r = await dio.post('/messaging/start/${d.supplierSlug}/', data: {'product_id': d.productId});
      final convId = (r.data is Map) ? r.data['id'] : null;
      if (convId == null) throw Exception('conversation introuvable');
      await dio.post('/messaging/$convId/send/', data: {'content': text});
      if (mounted) context.pushReplacement('/messages/$convId');
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Échec de l'envoi.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return const Scaffold(backgroundColor: Colors.white);

    final name = (_supplier?['name'] ?? _supplier?['company_name'] ?? d.supplierName ?? '…').toString();
    final logo = _supplier?['logo_url']?.toString();

    return Scaffold(
      backgroundColor: _threadBg,
      body: SafeArea(
        child: Column(children: [
          _header(d, name),
          Expanded(child: _welcome(logo)),
          if (_showCard) _productCard(d),
          _composer(),
        ]),
      ),
    );
  }

  // ── Entête : retour · nom · « Nouvelle conversation » · boutique ──
  Widget _header(ChatDraft d, String name) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: _line))),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 22, color: _ink),
            onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(size: 15, weight: FontWeight.w700, color: _ink)),
              Text('Nouvelle conversation', style: AppTheme.body(size: 12, color: _faint)),
            ]),
          ),
          IconButton(
            tooltip: 'Boutique',
            icon: const Icon(Icons.storefront_outlined, size: 23, color: _ink),
            onPressed: () => context.push('/fournisseur/${d.supplierSlug}'),
          ),
        ]),
      );

  // ── Zone d'accueil (aucun message, rien n'est créé) ──
  Widget _welcome(String? logo) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
        child: Column(children: [
          Container(
            width: 72, height: 72,
            decoration: const BoxDecoration(color: _soft, shape: BoxShape.circle),
            clipBehavior: Clip.antiAlias,
            child: (logo != null && logo.isNotEmpty)
                ? CachedNetworkImage(imageUrl: logo, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const Icon(Icons.storefront, size: 30, color: _orange))
                : const Icon(Icons.storefront, size: 30, color: _orange),
          ),
          const SizedBox(height: 16),
          Text('Bienvenue !', style: AppTheme.body(size: 20, weight: FontWeight.w700, color: _ink)),
          const SizedBox(height: 18),
          Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const Icon(Icons.verified_user_outlined, size: 26, color: _green),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(style: AppTheme.body(size: 14, color: _sub).copyWith(height: 1.5), children: [
                    const TextSpan(text: 'Discutez et commandez sur '),
                    TextSpan(text: 'GROSHOP', style: AppTheme.body(size: 14, weight: FontWeight.w700, color: _sub)),
                    const TextSpan(text: ' pour bénéficier de la protection des commandes.'),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      );

  // ── Carte produit (contexte, en bas) — pas un message ──
  Widget _productCard(ChatDraft d) {
    final hasPromo = d.oldPrice != null && d.oldPrice! > d.price;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: _line))),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Text('Prendre des renseignements sur ce produit :',
                style: AppTheme.body(size: 13, color: _mute)),
          ),
          GestureDetector(
            onTap: () => setState(() => _showCard = false),
            child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.close_rounded, size: 18, color: _faint)),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Container(
            width: 58, height: 58,
            decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(10)),
            clipBehavior: Clip.antiAlias,
            child: (d.productImage != null && d.productImage!.isNotEmpty)
                ? CachedNetworkImage(imageUrl: d.productImage!, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const SizedBox.shrink())
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: _fmt(d.price), style: AppTheme.body(size: 18, weight: FontWeight.w600, color: _ink)),
                TextSpan(text: ' TND', style: AppTheme.body(size: 12, weight: FontWeight.w600, color: _ink)),
              ])),
              if (hasPromo)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(children: [
                    Text('${_fmt(d.oldPrice!)} TND',
                        style: AppTheme.body(size: 12, color: _faint)
                            .copyWith(decoration: TextDecoration.lineThrough, decorationColor: _faint)),
                    if (d.disc > 0) ...[
                      const SizedBox(width: 6),
                      Text('-${d.disc}%', style: AppTheme.body(size: 11, weight: FontWeight.w800, color: _red)),
                    ],
                  ]),
                ),
              const SizedBox(height: 2),
              Text(d.productName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(size: 12, color: _mute)),
            ]),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _sending
                ? null
                : () => _send('Bonjour, je suis intéressé par « ${d.productName} ». Est-il disponible ?'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: _sending ? const Color(0xFFDDDDDD) : _orange,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Text('Envoyer', style: AppTheme.body(size: 14, weight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ]),
      ]),
    );
  }

  // ── Saisie (crée la conversation au 1er envoi) ──
  Widget _composer() {
    final canSend = _input.text.trim().isNotEmpty && !_sending;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: _line))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 110),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: _inputBg,
              border: Border.all(color: _line),
              borderRadius: BorderRadius.circular(20),
            ),
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(border: InputBorder.none, hintText: 'Veuillez entrer votre message…'),
              style: AppTheme.body(size: 14, color: _ink),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: canSend ? () => _send() : null,
          child: Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: canSend ? _orange : const Color(0xFFDDDDDD), shape: BoxShape.circle),
            child: _sending
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send, size: 18, color: Colors.white),
          ),
        ),
      ]),
    );
  }
}