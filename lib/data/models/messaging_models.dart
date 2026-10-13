// Modèle messagerie UNIFIÉ (acheteur + fournisseur).
// Une conversation porte les deux parties : `supplier` et `buyer`.
// L'écran acheteur affiche le fournisseur ; l'écran fournisseur affiche l'acheteur.

int _i(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

bool _b(dynamic v) => v == true;
DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

class ChatSupplierInfo {
  final String? name, slug, logoUrl;
  final bool isOnline;
  const ChatSupplierInfo({this.name, this.slug, this.logoUrl, this.isOnline = false});

  factory ChatSupplierInfo.fromJson(Map j) => ChatSupplierInfo(
        name: (j['name'] ?? j['company_name'])?.toString(),
        slug: j['slug']?.toString(),
        logoUrl: j['logo_url']?.toString(),
        isOnline: _b(j['is_online']),
      );
}

class ChatBuyer {
  final String? id, fullName, city, avatarUrl;
  final bool isOnline;
  const ChatBuyer({this.id, this.fullName, this.city, this.avatarUrl, this.isOnline = false});

  factory ChatBuyer.fromJson(Map j) => ChatBuyer(
        id: j['id'] == null ? null : '${j['id']}',
        fullName: j['full_name']?.toString(),
        city: j['city']?.toString(),
        avatarUrl: j['avatar_url']?.toString(),
        isOnline: _b(j['is_online']),
      );
}

class ChatMessage {
  final String id, senderId, content;
  final String? attachmentUrl, messageType;
  final bool isRead;
  final DateTime? createdAt;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.content,
    this.attachmentUrl,
    this.messageType,
    this.isRead = false,
    this.createdAt,
  });

  bool get isText => messageType == null || messageType == 'text';

  ChatMessage copyWith({bool? isRead}) => ChatMessage(
        id: id, senderId: senderId, content: content,
        attachmentUrl: attachmentUrl, messageType: messageType,
        isRead: isRead ?? this.isRead, createdAt: createdAt,
      );

  factory ChatMessage.fromJson(Map j) => ChatMessage(
        id: '${j['id']}',
        senderId: '${j['sender_id'] ?? ''}',
        content: j['content']?.toString() ?? '',
        attachmentUrl: (j['attachment_url']?.toString().isEmpty ?? true) ? null : j['attachment_url'].toString(),
        messageType: j['message_type']?.toString(),
        isRead: _b(j['is_read']),
        createdAt: _dt(j['created_at']),
      );
}

class Conversation {
  final String id;
  final ChatSupplierInfo? supplier;
  final ChatBuyer? buyer;
  final String supplierName;
  final String buyerName;
  final String? lastMessage;
  final DateTime? lastMsgAt;
  final int unreadCount;
  final String? productName;
  final String? productId;

  const Conversation({
    required this.id,
    this.supplier,
    this.buyer,
    this.supplierName = 'Fournisseur',
    this.buyerName = 'Client',
    this.lastMessage,
    this.lastMsgAt,
    this.unreadCount = 0,
    this.productName,
    this.productId,
  });

  // Alias pour compat avec l'écran fournisseur.
  String? get lastMessagePreview => lastMessage;

  factory Conversation.fromJson(Map j) {
    final lm = j['last_message'];
    final supMap = (j['supplier'] is Map) ? j['supplier'] as Map : null;
    final buyMap = (j['buyer'] is Map) ? j['buyer'] as Map : null;
    return Conversation(
      id: '${j['id']}',
      supplier: supMap != null ? ChatSupplierInfo.fromJson(supMap) : null,
      buyer: buyMap != null ? ChatBuyer.fromJson(buyMap) : null,
      supplierName: (j['supplier_name'] ?? supMap?['name'])?.toString() ?? 'Fournisseur',
      buyerName: (j['buyer_name'] ?? buyMap?['full_name'])?.toString() ?? 'Client',
      lastMessage: (lm is Map) ? lm['content']?.toString() : null,
      lastMsgAt: _dt(j['last_msg_at']) ?? (lm is Map ? _dt(lm['created_at']) : null),
      unreadCount: _i(j['unread_count']),
      productName: j['product_name']?.toString(),
      productId: j['product_id'] == null ? null : '${j['product_id']}',
    );
  }
}

class ConversationDetail {
  final String id;
  final ChatSupplierInfo? supplier;
  final ChatBuyer? buyer;
  final String supplierName, buyerName, supplierSlug;
  final String? productName, productId;
  final List<ChatMessage> messages;
  final DateTime? serverTime;

  const ConversationDetail({
    required this.id,
    this.supplier,
    this.buyer,
    this.supplierName = '…',
    this.buyerName = 'Client',
    this.supplierSlug = '',
    this.productName,
    this.productId,
    this.messages = const [],
    this.serverTime,
  });

  factory ConversationDetail.fromJson(Map j) {
    final supMap = (j['supplier'] is Map) ? j['supplier'] as Map : null;
    final buyMap = (j['buyer'] is Map) ? j['buyer'] as Map : null;
    return ConversationDetail(
      id: '${j['id']}',
      supplier: supMap != null ? ChatSupplierInfo.fromJson(supMap) : null,
      buyer: buyMap != null ? ChatBuyer.fromJson(buyMap) : null,
      supplierName: (j['supplier_name'] ?? supMap?['name'])?.toString() ?? '…',
      buyerName: (j['buyer_name'] ?? buyMap?['full_name'])?.toString() ?? 'Client',
      supplierSlug: (j['supplier_slug'] ?? supMap?['slug'])?.toString() ?? '',
      productName: j['product_name']?.toString(),
      productId: j['product_id'] == null ? null : '${j['product_id']}',
      messages: (j['messages'] is List)
          ? (j['messages'] as List).whereType<Map>().map(ChatMessage.fromJson).toList()
          : const [],
      serverTime: _dt(j['server_time']),
    );
  }
}

class PollResult {
  final List<ChatMessage> messages;
  final List<String> readIds;
  final DateTime? serverTime;
  const PollResult({this.messages = const [], this.readIds = const [], this.serverTime});

  factory PollResult.fromJson(Map j) => PollResult(
        messages: (j['messages'] is List)
            ? (j['messages'] as List).whereType<Map>().map(ChatMessage.fromJson).toList()
            : const [],
        readIds: (j['read_ids'] is List) ? (j['read_ids'] as List).map((e) => '$e').toList() : const [],
        serverTime: _dt(j['server_time']),
      );
}