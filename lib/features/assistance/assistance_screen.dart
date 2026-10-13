import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/api/support_api.dart';
import '../../state/auth_provider.dart';
import '../../widgets/saved_list_kit.dart';

/// Discussion avec le centre d'aide GROSHOP (app Django `support`),
/// équivalent mobile de la page web /assistance.
///
/// - Reprise : GET /support/mine/ → conversation_token de la dernière conversation.
/// - 1er message sans conversation : POST /support/start/ {message} (1 seul appel).
/// - Poll incrémental toutes les 4 s : ?after=<created_at du dernier message>.
///   Sans `peek` → les réponses agent sont marquées lues côté serveur.
class AssistanceScreen extends ConsumerStatefulWidget {
  const AssistanceScreen({super.key});
  @override
  ConsumerState<AssistanceScreen> createState() => _AssistanceScreenState();
}

class _AssistanceScreenState extends ConsumerState<AssistanceScreen> {
  static const _pollEvery = Duration(seconds: 4);

  String? _token;
  String _status = 'open';
  List<SupportMessage> _msgs = const [];
  bool _loading = true;
  bool _sending = false;
  bool _polling = false;
  Timer? _timer;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final api = ref.read(supportApiProvider);
    try {
      _token = await api.mine();
      if (_token != null) {
        final p = await api.poll(_token!);
        _msgs = p.messages;
        _status = p.status;
      }
    } catch (_) {/* hors-ligne : on réessaiera au poll / au 1er envoi */}
    if (!mounted) return;
    setState(() => _loading = false);
    _toBottom(animate: false);
    _timer = Timer.periodic(_pollEvery, (_) => _poll());
  }

  /// Dernier message confirmé par le serveur (repère pour `?after=`).
  String? get _lastServerIso {
    for (final m in _msgs.reversed) {
      if (!m.pending && m.createdAtRaw.isNotEmpty) return m.createdAtRaw;
    }
    return null;
  }

  /// Ajoute [incoming] en évitant les doublons (id) ; remplace le message local [replaceId].
  void _merge(List<SupportMessage> incoming, {String? replaceId}) {
    final base = replaceId == null ? _msgs : _msgs.where((m) => m.id != replaceId).toList();
    final ids = base.map((m) => m.id).toSet();
    final fresh = incoming.where((m) => !ids.contains(m.id)).toList();
    if (fresh.isEmpty && replaceId == null) return;
    // Les messages locals « en cours » restent en bas.
    final confirmed = base.where((m) => !m.pending).toList()..addAll(fresh);
    final pending = base.where((m) => m.pending).toList();
    setState(() => _msgs = [...confirmed, ...pending]);
    _toBottom();
  }

  Future<void> _poll() async {
    final token = _token;
    if (token == null || _polling || !mounted) return;
    _polling = true;
    try {
      final p = await ref.read(supportApiProvider).poll(token, after: _lastServerIso);
      if (!mounted) return;
      if (p.status != _status) setState(() => _status = p.status);
      _merge(p.messages);
    } catch (_) {/* on réessaie au prochain tick */} finally {
      _polling = false;
    }
  }

  void _toBottom({bool animate = true}) => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final max = _scroll.position.maxScrollExtent;
        animate
            ? _scroll.animateTo(max, duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
            : _scroll.jumpTo(max);
      });

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final local = SupportMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      fromAgent: false,
      content: text,
      createdAtRaw: DateTime.now().toIso8601String(),
      pending: true,
    );
    setState(() {
      _sending = true;
      _msgs = [..._msgs, local];
    });
    _input.clear();
    _toBottom();

    final api = ref.read(supportApiProvider);
    try {
      if (_token == null) {
        final user = ref.read(authProvider).valueOrNull?.user;
        final r = await api.start(name: user?.fullName, email: user?.email, message: text);
        _token = r.token;
        _merge([if (r.first != null) r.first!], replaceId: local.id);
      } else {
        final m = await api.send(_token!, text);
        _merge([m], replaceId: local.id);
        if (_status == 'closed') setState(() => _status = 'open'); // le serveur rouvre le ticket
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _msgs = _msgs.where((m) => m.id != local.id).toList());
      _input.text = text;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Message non envoyé. Vérifiez votre connexion.')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  static String _hm(DateTime? d) {
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SavedColors.bg,
      body: SafeArea(
        child: Column(children: [
          _header(),
          if (_status == 'closed')
            Container(
              width: double.infinity,
              color: const Color(0xFFFFF7ED),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                'Cette conversation a été clôturée. Écrivez un message pour la rouvrir.',
                style: AppTheme.body(size: 12.5, color: const Color(0xFF9A3412)),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: SavedColors.orange))
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                    children: [
                      _bubble(const SupportMessage(
                        id: 'welcome',
                        fromAgent: true,
                        content: 'Bonjour ! Comment pouvons-nous vous aider ? '
                            'Commande, livraison, paiement ou compte : écrivez-nous ici.',
                      )),
                      for (final m in _msgs) _bubble(m),
                    ],
                  ),
          ),
          _composer(),
        ]),
      ),
    );
  }

  Widget _header() => Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(4, 8, 14, 10),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: SavedColors.ink),
            onPressed: () => context.canPop() ? context.pop() : context.go('/dashboard'),
          ),
          Container(
            width: 38, height: 38,
            decoration: const BoxDecoration(color: SavedColors.soft, shape: BoxShape.circle),
            child: const Icon(Icons.headset_mic_outlined, size: 20, color: SavedColors.orange),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Centre d'aide GROSHOP",
                  style: AppTheme.body(size: 16, weight: FontWeight.w700, color: SavedColors.ink)),
              const SizedBox(height: 2),
              Text('Réponse en général en quelques minutes',
                  style: AppTheme.body(size: 12, color: SavedColors.green)),
            ]),
          ),
        ]),
      );

  Widget _bubble(SupportMessage m) {
    final mine = !m.fromAgent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: mine ? SavedColors.orange : Colors.white,
              border: mine ? null : Border.all(color: SavedColors.line),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(mine ? 16 : 4),
                bottomRight: Radius.circular(mine ? 4 : 16),
              ),
            ),
            child: Opacity(
              opacity: m.pending ? 0.6 : 1,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                if (m.content.isNotEmpty)
                  Text(m.content,
                      style: AppTheme.body(size: 14.5, color: mine ? Colors.white : SavedColors.ink)
                          .copyWith(height: 1.35)),
                if (m.attachmentUrl != null)
                  Padding(
                    padding: EdgeInsets.only(top: m.content.isNotEmpty ? 6 : 0),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.attach_file, size: 15, color: mine ? Colors.white : SavedColors.mute),
                      const SizedBox(width: 4),
                      Text('Pièce jointe',
                          style: AppTheme.body(size: 13, color: mine ? Colors.white : SavedColors.mute)),
                    ]),
                  ),
              ]),
            ),
          ),
        ),
        if (m.createdAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
            child: Text(m.pending ? 'Envoi…' : _hm(m.createdAt),
                style: AppTheme.body(size: 11, color: SavedColors.faint)),
          ),
      ]),
    );
  }

  Widget _composer() => Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(color: SavedColors.bg, borderRadius: BorderRadius.circular(22)),
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                style: AppTheme.body(size: 14.5, color: SavedColors.ink),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Écrire un message…',
                  hintStyle: AppTheme.body(size: 14.5, color: SavedColors.faint),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _send,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: _sending ? SavedColors.faint : SavedColors.orange,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send_rounded, size: 20, color: Colors.white),
            ),
          ),
        ]),
      );
}