import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/api/messaging_api.dart';
import '../data/models/messaging_models.dart';

// ══════════════ LISTE des conversations ══════════════
final conversationsProvider =
    FutureProvider<List<Conversation>>((ref) => ref.read(messagingApiProvider).conversations());

// ══════════════ FIL d'une conversation (polling + accusés de lecture) ══════════════
class ConvState {
  final ConversationDetail? detail;
  final List<ChatMessage> messages;
  final bool loading;
  const ConvState({this.detail, this.messages = const [], this.loading = true});
}

class ConversationNotifier extends AutoDisposeFamilyNotifier<ConvState, String> {
  Timer? _timer;
  DateTime? _cursor;
  final Set<String> _seen = {};

  @override
  ConvState build(String conversationId) {
    ref.onDispose(() => _timer?.cancel());
    _boot();
    return const ConvState(loading: true);
  }

  MessagingApi get _api => ref.read(messagingApiProvider);

  Future<void> _boot() async {
    try {
      final d = await _api.conversation(arg);
      if (d == null) { state = const ConvState(loading: false); return; }
      _seen..clear()..addAll(d.messages.map((m) => m.id));
      _cursor = d.serverTime;
      state = ConvState(detail: d, messages: d.messages, loading: false);
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(milliseconds: 2800), (_) => _poll());
    } catch (_) {
      state = const ConvState(loading: false);
    }
  }

  Future<void> _poll() async {
    try {
      final res = await _api.poll(arg, after: _cursor);
      if (res.serverTime != null) _cursor = res.serverTime;

      final incoming = res.messages.where((m) => !_seen.contains(m.id)).toList();
      var msgs = state.messages;
      var changed = false;

      if (incoming.isNotEmpty) {
        _seen.addAll(incoming.map((m) => m.id));
        msgs = [...msgs, ...incoming];
        changed = true;
      }
      if (res.readIds.isNotEmpty) {
        final rd = res.readIds.toSet();
        msgs = [
          for (final m in msgs) (rd.contains(m.id) && !m.isRead) ? m.copyWith(isRead: true) : m,
        ];
        changed = true;
      }
      if (changed) state = ConvState(detail: state.detail, messages: msgs, loading: false);
    } catch (_) {/* on retentera */}
  }

  Future<bool> send(String content) async {
    try {
      final sent = await _api.sendMessage(arg, content);
      if (sent == null) return false;
      if (state.messages.any((m) => m.id == sent.id)) return true;
      _seen.add(sent.id);
      state = ConvState(detail: state.detail, messages: [...state.messages, sent], loading: false);
      return true;
    } catch (_) {
      return false;
    }
  }
}

final conversationProvider =
    NotifierProvider.autoDispose.family<ConversationNotifier, ConvState, String>(ConversationNotifier.new);