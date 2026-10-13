import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/models/messaging_models.dart';
import '../../state/auth_provider.dart';
import '../../state/conversation_provider.dart';

const _orange = Color(0xFFFF7A00);
const _ink = Color(0xFF0F1419);
const _faint = Color(0xFF9AA3AE);
const _line = Color(0xFFE8EAED);
const _bg = Color(0xFFF4F5F7);
const _seen = Color(0xFF34B7F1);

class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId;
  const ChatScreen({super.key, required this.conversationId});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
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
    if (!ok && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Échec de l'envoi.")));
    if (mounted) setState(() => _sending = false);
    _toBottom();
  }

  String _time(DateTime? d) {
    if (d == null) return '';
    final n = DateTime.now();
    final l = d.toLocal();
    if (l.day == n.day && l.month == n.month && l.year == n.year) {
      return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
    }
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final myId = ref.watch(authProvider).valueOrNull?.user?.id;
    final st = ref.watch(conversationProvider(widget.conversationId));
    ref.listen(conversationProvider(widget.conversationId), (_, __) => _toBottom());

    final name = st.detail?.supplierName ?? '…';
    final online = st.detail?.supplier?.isOnline ?? false;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          _appBar(name, online),
          Expanded(
            child: st.loading
                ? const Center(child: CircularProgressIndicator(color: _orange))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: st.messages.length,
                    itemBuilder: (_, i) => _bubble(st.messages[i], st.messages[i].senderId == '$myId'),
                  ),
          ),
          _composer(),
        ]),
      ),
    );
  }

  Widget _appBar(String name, bool online) => Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back, size: 22), onPressed: () => context.pop()),
          Container(width: 40, height: 40,
            decoration: const BoxDecoration(color: Color(0xFFFFF0E8), shape: BoxShape.circle),
            child: const Icon(Icons.storefront, size: 20, color: _orange)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(name, style: AppTheme.body(size: 15, weight: FontWeight.w700, color: _ink)),
            Text(online ? 'En ligne' : 'Hors ligne',
                style: AppTheme.body(size: 12, color: online ? const Color(0xFF0E9F6E) : _faint)),
          ]),
        ]),
      );

  Widget _bubble(ChatMessage m, bool mine) {
    if (!m.isText) {
      return Align(
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: const Color(0xFFEDE7FF), borderRadius: BorderRadius.circular(10)),
          child: Text(m.content.isNotEmpty ? m.content : 'Devis', style: AppTheme.body(size: 12.5, color: const Color(0xFF5B21B6))),
        ),
      );
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.76),
        margin: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: mine ? _orange : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(mine ? 16 : 4), bottomRight: Radius.circular(mine ? 4 : 16)),
              border: mine ? null : Border.all(color: _line),
            ),
            child: Text(m.content, style: AppTheme.body(size: 14, color: mine ? Colors.white : _ink).copyWith(height: 1.45)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_time(m.createdAt), style: AppTheme.body(size: 10.5, color: _faint)),
              if (mine) Padding(padding: const EdgeInsets.only(left: 4),
                  child: Icon(m.isRead ? Icons.done_all : Icons.done, size: 14, color: m.isRead ? _seen : _faint)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _composer() => Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: _line))),
        child: SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: Container(
              constraints: const BoxConstraints(maxHeight: 110),
              decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                controller: _input, minLines: 1, maxLines: 4,
                decoration: const InputDecoration(border: InputBorder.none, hintText: 'Écrivez votre message…'),
                style: AppTheme.body(size: 14, color: _ink),
              ),
            )),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: Container(width: 42, height: 42,
                decoration: BoxDecoration(color: _sending ? const Color(0xFFDDDDDD) : _orange, shape: BoxShape.circle),
                child: const Icon(Icons.send, size: 18, color: Colors.white)),
            ),
          ]),
        )),
      );
}