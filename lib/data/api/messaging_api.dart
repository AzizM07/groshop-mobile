import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/messaging_models.dart';
import 'api_client.dart';

final messagingApiProvider = Provider<MessagingApi>((ref) => MessagingApi(ref.read(dioProvider)));

class MessagingApi {
  final Dio _dio;
  MessagingApi(this._dio);

  dynamic _decode(dynamic data) {
    if (data is String) {
      try {
        return jsonDecode(data);
      } catch (_) {
        return null;
      }
    }
    return data;
  }

  // GET /messaging/  → liste des conversations
  Future<List<Conversation>> conversations() async {
    final d = _decode((await _dio.get('/messaging/')).data);
    final list = (d is List) ? d : (d is Map ? (d['results'] ?? const []) : const []);
    return (list as List).whereType<Map>().map(Conversation.fromJson).toList();
  }

  // GET /messaging/{id}/  → détail (messages + server_time)
  Future<ConversationDetail?> conversation(String id) async {
    final d = _decode((await _dio.get('/messaging/$id/')).data);
    return (d is Map) ? ConversationDetail.fromJson(d) : null;
  }

  // GET /messaging/{id}/poll/?after=&mark_read=
  Future<PollResult> poll(String id, {DateTime? after, bool markRead = true}) async {
    final qp = <String, dynamic>{'mark_read': markRead ? '1' : '0'};
    if (after != null) qp['after'] = after.toUtc().toIso8601String();
    final d = _decode((await _dio.get('/messaging/$id/poll/', queryParameters: qp)).data);
    return (d is Map) ? PollResult.fromJson(d) : const PollResult();
  }

  // POST /messaging/{id}/send/  { content, attachment_url }
  Future<ChatMessage?> sendMessage(String id, String content, {String attachmentUrl = ''}) async {
    final d = _decode((await _dio.post('/messaging/$id/send/',
            data: {'content': content, 'attachment_url': attachmentUrl}))
        .data);
    return (d is Map) ? ChatMessage.fromJson(d) : null;
  }
}