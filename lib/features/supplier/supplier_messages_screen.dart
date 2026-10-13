import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../data/models/messaging_models.dart';
import '../../state/conversation_provider.dart';
import '../../state/auth_provider.dart';

const _orange = Color(0xFFFF5E20);
const _orangeTint = Color(0x1AFF5E20);
const _ring = Color(0x4DFF5E20);
const _seenBlue = Color(0xFF34B7F1);
const _ink = Color(0xFF0F1419);
const _mute = Color(0xFF6B7280);
const _faint = Color(0xFF9AA3AE);

String _fmtTime(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  final now = DateTime.now();
  bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  if (sameDay(l, now)) {
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
  if (now.difference(l).inDays < 7) {
    const wd = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'];
    return wd[(l.weekday - 1) % 7];
  }
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}';
}

String _initials(String? name) {
  final parts = (name ?? '?').trim().split(RegExp(r'\s+'));
  return parts.take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();
}

// ══════════════ Liste des conversations (côté fournisseur → affiche l'acheteur) ══════════════
class SupplierMessagesScreen extends ConsumerStatefulWidget {
  const SupplierMessagesScreen({super.key});
  @override
  ConsumerState<SupplierMessagesScreen> createState() => _SupplierMessagesScreenState();
}

class _SupplierMessagesScreenState extends ConsumerState<SupplierMessagesScreen> {
  String _search = '';
  String _filter = 'all';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final convs = ref.watch(conversationsProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        Text('Messages', style: AppTheme.body(size: 26, weight: FontWeight.w800, color: _ink)),
        const SizedBox(height: 4),
        convs.maybeWhen(
          data: (list) {
            final unread = list.fold(0, (s, c) => s + c.unreadCount);
            return Text(unread > 0 ? '$unread message${unread > 1 ? 's' : ''} non lu${unread > 1 ? 's' : ''}.' : 'Tout est lu.',
                style: AppTheme.body(size: 12.5, color: _mute));
          },
          orElse: () => Text('Vos conversations clients.', style: AppTheme.body(size: 12.5, color: _mute)),
        ),
        const SizedBox(height: 14),

        // Recherche
        Container(
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFEFECE4))),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            const Icon(Icons.search, size: 16, color: _faint),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _search = v),
                style: AppTheme.body(size: 13, color: _ink),
                decoration: InputDecoration(
                  isDense: true, border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  hintText: 'Client, ville, produit…',
                  hintStyle: AppTheme.body(size: 13, color: _faint),
                ),
              ),
            ),
            if (_search.isNotEmpty)
              GestureDetector(
                onTap: () { _searchCtrl.clear(); setState(() => _search = ''); },
                child: const Icon(Icons.close, size: 16, color: _faint),
              ),
          ]),
        ),
        const SizedBox(height: 12),

        // Filtres
        Row(children: [
          for (final f in const [('all', 'Tous'), ('unread', 'Non lus')])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() => _filter = f.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: _filter == f.$1 ? _orangeTint : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: _filter == f.$1 ? null : Border.all(color: const Color(0xFFEFECE4)),
                  ),
                  child: Text(f.$2,
                      style: AppTheme.body(size: 11.5,
                          weight: _filter == f.$1 ? FontWeight.w700 : FontWeight.w500,
                          color: _filter == f.$1 ? _orange : _faint)),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 12),

        convs.when(
          loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator(color: _orange))),
          error: (_, __) => Padding(padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(child: Text('Impossible de charger.', style: AppTheme.body(size: 13, color: _faint)))),
          data: (list) {
            final q = _search.toLowerCase();
            final filtered = list.where((c) {
              if (_filter == 'unread' && !(c.unreadCount > 0)) return false;
              if (q.isNotEmpty) {
                final hay = '${c.buyer?.fullName ?? c.buyerName} ${c.buyer?.city ?? ''} ${c.productName ?? ''}'.toLowerCase();
                if (!hay.contains(q)) return false;
              }
              return true;
            }).toList();

            if (filtered.isEmpty) {
              return Padding(padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: Text('Aucune conversation', style: AppTheme.body(size: 13, color: _faint))));
            }
            return Container(
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFEFECE4))),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (var i = 0; i < filtered.length; i++) _row(filtered[i], i > 0),
              ]),
            );
          },
        ),
      ],
    );
  }

  Widget _row(Conversation c, bool border) {
    final name = c.buyer?.fullName ?? c.buyerName;
    final unread = c.unreadCount > 0;
    final preview = c.lastMessage ?? 'Démarrer la conversation';
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _ChatView(conversationId: c.id)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: unread ? _orangeTint : Colors.white,
          border: Border(
            top: border ? const BorderSide(color: Color(0xFFF5F3EE)) : BorderSide.none,
            left: BorderSide(color: unread ? _orange : Colors.transparent, width: 3),
          ),
        ),
        child: Row(children: [
          _Avatar(name: name, avatarUrl: c.buyer?.avatarUrl, size: 42, online: c.buyer?.isOnline ?? false),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(size: 13, weight: unread ? FontWeight.w700 : FontWeight.w600, color: _ink))),
                  Text(_fmtTime(c.lastMsgAt),
                      style: AppTheme.body(size: 10, weight: unread ? FontWeight.w700 : FontWeight.w500,
                          color: unread ? _orange : _faint)),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  Expanded(
                    child: Text('${c.productName != null ? '${c.productName} · ' : ''}$preview',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(size: 11.5, color: unread ? _ink : _faint)),
                  ),
                  if (unread)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      constraints: const BoxConstraints(minWidth: 18),
                      height: 18,
                      decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(999)),
                      alignment: Alignment.center,
                      child: Text('${c.unreadCount}',
                          style: AppTheme.body(size: 9.5, weight: FontWeight.w700, color: Colors.white)),
                    ),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ══════════════ Fil (côté fournisseur → affiche l'acheteur) ══════════════
class _ChatView extends ConsumerStatefulWidget {
  final String conversationId;
  const _ChatView({required this.conversationId});
  @override
  ConsumerState<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<_ChatView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void dispose() { _input.dispose(); _scroll.dispose(); super.dispose(); }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _input.clear();
    final ok = await ref.read(conversationProvider(widget.conversationId).notifier).send(text);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Échec de l'envoi.")));
    }
    if (mounted) setState(() => _sending = false);
    _toBottom();
  }

  @override
  Widget build(BuildContext context) {
    final myId = ref.watch(authProvider).valueOrNull?.user?.id;
    final st = ref.watch(conversationProvider(widget.conversationId));
    ref.listen(conversationProvider(widget.conversationId), (_, __) => _toBottom());

    final name = st.detail?.buyer?.fullName ?? st.detail?.buyerName ?? 'Client';
    final online = st.detail?.buyer?.isOnline ?? false;
    final city = st.detail?.buyer?.city;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
          // En-tête
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0EDE5)))),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back, color: _ink),
                  onPressed: () => Navigator.of(context).pop()),
              _Avatar(name: name, avatarUrl: st.detail?.buyer?.avatarUrl, size: 36, online: online),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(size: 13.5, weight: FontWeight.w700, color: _ink)),
                    Text('${online ? 'En ligne' : 'Hors ligne'}${city != null ? ' · $city' : ''}',
                        style: AppTheme.body(size: 10.5, color: online ? const Color(0xFF059669) : _faint)),
                  ],
                ),
              ),
            ]),
          ),

          if (st.detail?.productName != null)
            Container(
              width: double.infinity, color: _orangeTint,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(children: [
                const Icon(Icons.inventory_2_outlined, size: 13, color: _orange),
                const SizedBox(width: 7),
                Flexible(child: Text(st.detail!.productName!, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(size: 11.5, weight: FontWeight.w600, color: _orange))),
              ]),
            ),

          Expanded(
            child: st.loading
                ? const Center(child: CircularProgressIndicator(color: _orange))
                : st.messages.isEmpty
                    ? Center(child: Text('Aucun message. Envoyez le premier !',
                        style: AppTheme.body(size: 13, color: _faint)))
                    : ListView.separated(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                        itemCount: st.messages.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 9),
                        itemBuilder: (_, i) => _bubble(st.messages[i], st.messages[i].senderId == '$myId', name, st.detail?.buyer?.avatarUrl),
                      ),
          ),

          // Saisie
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFF0EDE5)))),
            child: Row(children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: const Color(0xFFF4F4F2), borderRadius: BorderRadius.circular(999)),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _input,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    style: AppTheme.body(size: 13.5, color: _ink),
                    decoration: InputDecoration(
                      isDense: true, border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 11),
                      hintText: 'Écrivez votre message…',
                      hintStyle: AppTheme.body(size: 13.5, color: _faint),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              GestureDetector(
                onTap: _sending ? null : _send,
                child: Container(width: 40, height: 40,
                  decoration: BoxDecoration(color: _sending ? const Color(0xFFEAE7DF) : _orange, shape: BoxShape.circle),
                  child: const Icon(Icons.send, size: 16, color: Colors.white)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _bubble(ChatMessage m, bool mine, String buyerName, String? avatar) {
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: mine ? _orange : const Color(0xFFF7F7F5),
        border: mine ? null : Border.all(color: const Color(0xFFEAE7DF)),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(15), topRight: const Radius.circular(15),
          bottomLeft: Radius.circular(mine ? 15 : 4), bottomRight: Radius.circular(mine ? 4 : 15),
        ),
      ),
      child: Text(m.isText ? m.content : (m.content.isNotEmpty ? m.content : '📋 Devis'),
          style: AppTheme.body(size: 13.5, color: mine ? Colors.white : _ink).copyWith(height: 1.4)),
    );

    final meta = Padding(
      padding: EdgeInsets.only(top: 3, left: mine ? 0 : 4, right: mine ? 2 : 0),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(_fmtTime(m.createdAt), style: AppTheme.body(size: 9.5, color: _faint)),
        if (mine) ...[
          const SizedBox(width: 3),
          Icon(m.isRead ? Icons.done_all : Icons.done, size: 13, color: m.isRead ? _seenBlue : _faint),
        ],
      ]),
    );

    if (mine) {
      return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [bubble, meta]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _Avatar(name: buyerName, avatarUrl: avatar, size: 26, online: false),
        const SizedBox(width: 7),
        Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [bubble, meta])),
      ],
    );
  }
}

// ══════════════ Avatar ══════════════
class _Avatar extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final double size;
  final bool online;
  const _Avatar({required this.name, this.avatarUrl, this.size = 40, this.online = false});

  @override
  Widget build(BuildContext context) {
    final base = (avatarUrl != null && avatarUrl!.isNotEmpty)
        ? ClipOval(child: Image.network(avatarUrl!, width: size, height: size, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallback()))
        : _fallback();
    if (!online) return base;
    return Stack(clipBehavior: Clip.none, children: [
      base,
      Positioned(
        right: 0, bottom: 0,
        child: Container(width: size * 0.26, height: size * 0.26,
            decoration: BoxDecoration(color: const Color(0xFF22C55E), shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2))),
      ),
    ]);
  }

  Widget _fallback() => Container(
        width: size, height: size,
        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: _ring, width: 1.5)),
        alignment: Alignment.center,
        child: Text(_initials(name),
            style: AppTheme.body(size: size * 0.34, weight: FontWeight.w700, color: _orange)),
      );
}