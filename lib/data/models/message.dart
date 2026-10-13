class ChatMessage {
  final String id, senderId, content;
  final String? attachmentUrl, messageType;
  final bool isRead;
  final DateTime? createdAt;

  const ChatMessage({
    required this.id, required this.senderId, required this.content,
    this.attachmentUrl, this.messageType, this.isRead = false, this.createdAt,
  });

  bool get isText => messageType == null || messageType == 'text';

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: '${j['id']}',
        senderId: '${j['sender_id'] ?? ''}',
        content: j['content'] ?? '',
        attachmentUrl: (j['attachment_url'] ?? '').toString().isEmpty ? null : j['attachment_url'],
        messageType: j['message_type'],
        isRead: j['is_read'] == true,
        createdAt: j['created_at'] != null ? DateTime.tryParse(j['created_at']) : null,
      );
}

class ChatSupplierInfo {
  final String? name, slug, logoUrl;
  final bool isOnline;
  const ChatSupplierInfo({this.name, this.slug, this.logoUrl, this.isOnline = false});
  factory ChatSupplierInfo.fromJson(Map j) => ChatSupplierInfo(
        name: j['name'] ?? j['company_name'],
        slug: j['slug'],
        logoUrl: j['logo_url'],
        isOnline: j['is_online'] == true,
      );
}

class Conversation {
  final String id;
  final ChatSupplierInfo? supplier;
  final String supplierName;
  final String? lastMessage;
  final DateTime? lastMsgAt;
  final int unreadCount;

  const Conversation({
    required this.id, this.supplier, this.supplierName = 'Fournisseur',
    this.lastMessage, this.lastMsgAt, this.unreadCount = 0,
  });

  factory Conversation.fromJson(Map<String, dynamic> j) {
    final lm = j['last_message'];
    final supMap = (j['supplier'] is Map) ? j['supplier'] as Map : null;
    return Conversation(
      id: '${j['id']}',
      supplier: supMap != null ? ChatSupplierInfo.fromJson(supMap) : null,
      supplierName: j['supplier_name'] ?? supMap?['name'] ?? 'Fournisseur',
      lastMessage: (lm is Map) ? lm['content'] : null,
      lastMsgAt: j['last_msg_at'] != null ? DateTime.tryParse(j['last_msg_at']) : null,
      unreadCount: (j['unread_count'] is num) ? (j['unread_count'] as num).toInt() : 0,
    );
  }
}

/// Détail = entête fournisseur + liste des messages + server_time (pour le poll).
class ConversationDetail {
  final String id;
  final ChatSupplierInfo? supplier;
  final String supplierName, supplierSlug;
  final List<ChatMessage> messages;
  final DateTime? serverTime;

  const ConversationDetail({
    required this.id, this.supplier, this.supplierName = '…', this.supplierSlug = '',
    this.messages = const [], this.serverTime,
  });

  factory ConversationDetail.fromJson(Map<String, dynamic> j) {
    final supMap = (j['supplier'] is Map) ? j['supplier'] as Map : null;
    return ConversationDetail(
      id: '${j['id']}',
      supplier: supMap != null ? ChatSupplierInfo.fromJson(supMap) : null,
      supplierName: j['supplier_name'] ?? supMap?['name'] ?? '…',
      supplierSlug: j['supplier_slug'] ?? supMap?['slug'] ?? '',
      messages: (j['messages'] as List? ?? [])
          .whereType<Map>().map((m) => ChatMessage.fromJson(m.cast<String, dynamic>())).toList(),
      serverTime: j['server_time'] != null ? DateTime.tryParse(j['server_time']) : null,
    );
  }
}