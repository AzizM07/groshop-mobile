import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';

final supportApiProvider = Provider<SupportApi>((ref) => SupportApi(ref.read(dioProvider)));

/// Message du chat support — forme de `_msg_dict()` dans support/views.py.
class SupportMessage {
  final String id;
  final bool fromAgent;
  final String content;
  final String? attachmentUrl;
  final bool isRead;
  /// ISO brut renvoyé par Django (réutilisé tel quel pour `?after=`).
  final String createdAtRaw;
  final bool pending; // envoi local en cours (optimiste)

  const SupportMessage({
    required this.id,
    required this.fromAgent,
    required this.content,
    this.attachmentUrl,
    this.isRead = false,
    this.createdAtRaw = '',
    this.pending = false,
  });

  DateTime? get createdAt => DateTime.tryParse(createdAtRaw)?.toLocal();

  factory SupportMessage.fromJson(Map<String, dynamic> j) => SupportMessage(
        id: '${j['id']}',
        fromAgent: j['sender_type'] == 'agent',
        content: '${j['content'] ?? ''}',
        attachmentUrl: (j['attachment_url'] as String?)?.isNotEmpty == true ? j['attachment_url'] as String : null,
        isRead: j['is_read'] == true,
        createdAtRaw: '${j['created_at'] ?? ''}',
      );
}

/// Réponse du poll GET /support/<token>/messages/.
class SupportPoll {
  final String status; // 'open' | 'closed'
  final int unread;    // renseigné seulement avec peek=1
  final List<SupportMessage> messages;
  const SupportPoll({required this.status, required this.unread, required this.messages});
}

class SupportApi {
  final Dio _dio;
  SupportApi(this._dio);

  static List<SupportMessage> _msgs(dynamic list) => list is List
      ? list.whereType<Map>().map((e) => SupportMessage.fromJson(e.cast<String, dynamic>())).toList()
      : const [];

  /// GET /support/mine/ → `{conversation_token, conversation}` ou `{conversation: null}`.
  /// Renvoie le token de la dernière conversation de l'utilisateur, ou null.
  Future<String?> mine() async {
    final d = (await _dio.get('/support/mine/')).data;
    if (d is! Map || d['conversation'] == null) return null;
    final t = d['conversation_token'];
    return (t == null || '$t'.isEmpty) ? null : '$t';
  }

  /// POST /support/start/ {name?, email?, message?, page_url?}
  /// Crée la conversation ET poste le 1er message en un seul appel.
  Future<({String token, SupportMessage? first})> start({
    String? name,
    String? email,
    String? message,
  }) async {
    final d = (await _dio.post('/support/start/', data: {
      if (name != null && name.isNotEmpty) 'name': name,
      if (email != null && email.isNotEmpty) 'email': email,
      if (message != null && message.isNotEmpty) 'message': message,
      'page_url': 'app://mobile/assistance',
    })).data as Map;
    final first = d['first_message'];
    return (
      token: '${d['conversation_token']}',
      first: first is Map ? SupportMessage.fromJson(first.cast<String, dynamic>()) : null,
    );
  }

  /// GET /support/<token>/messages/?after=<iso>&peek=1
  /// - [after] : ne renvoie que les messages postérieurs (poll incrémental).
  /// - [peek]  : ne marque PAS les messages agent comme lus, renvoie `unread`.
  Future<SupportPoll> poll(String token, {String? after, bool peek = false}) async {
    final d = (await _dio.get('/support/$token/messages/', queryParameters: {
      if (after != null && after.isNotEmpty) 'after': after,
      if (peek) 'peek': '1',
    })).data as Map;
    return SupportPoll(
      status: '${d['status'] ?? 'open'}',
      unread: (d['unread'] as num?)?.toInt() ?? 0,
      messages: _msgs(d['messages']),
    );
  }

  /// POST /support/<token>/messages/ {content} → le message créé.
  Future<SupportMessage> send(String token, String content) async {
    final d = (await _dio.post('/support/$token/messages/', data: {'content': content})).data;
    return SupportMessage.fromJson((d as Map).cast<String, dynamic>());
  }

  /// Nombre de réponses agent non lues (badge du casque), sans les marquer lues.
  Future<int> unreadCount() async {
    final token = await mine();
    if (token == null) return 0;
    return (await poll(token, peek: true)).unread;
  }
}