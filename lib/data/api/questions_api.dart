import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';

// ── Modèles Q&R ──
class QAnswer {
  final String id;
  final String body;
  final String authorName;
  final String createdAt;
  int likesCount;
  bool hasLiked;
  final bool isMine;
  final bool fromSupplier;
  QAnswer({
    required this.id,
    required this.body,
    required this.authorName,
    required this.createdAt,
    required this.likesCount,
    required this.hasLiked,
    required this.isMine,
    required this.fromSupplier,
  });

  factory QAnswer.fromJson(Map m) => QAnswer(
        id: '${m['id']}',
        body: m['body']?.toString() ?? '',
        authorName: m['author_name']?.toString() ?? '',
        createdAt: m['created_at']?.toString() ?? '',
        likesCount: (m['likes_count'] as num?)?.toInt() ?? 0,
        hasLiked: m['has_liked'] == true,
        isMine: m['is_mine'] == true,
        fromSupplier: m['from_supplier'] == true,
      );
}

class QQuestion {
  final String id;
  final String body;
  final String authorName;
  final String createdAt;
  int likesCount;
  bool hasLiked;
  final bool isMine;
  List<QAnswer> answers;
  QQuestion({
    required this.id,
    required this.body,
    required this.authorName,
    required this.createdAt,
    required this.likesCount,
    required this.hasLiked,
    required this.isMine,
    required this.answers,
  });

  factory QQuestion.fromJson(Map m) => QQuestion(
        id: '${m['id']}',
        body: m['body']?.toString() ?? '',
        authorName: m['author_name']?.toString() ?? '',
        createdAt: m['created_at']?.toString() ?? '',
        likesCount: (m['likes_count'] as num?)?.toInt() ?? 0,
        hasLiked: m['has_liked'] == true,
        isMine: m['is_mine'] == true,
        answers: (m['answers'] is List)
            ? (m['answers'] as List).whereType<Map>().map(QAnswer.fromJson).toList()
            : <QAnswer>[],
      );
}

class QuestionsPage {
  final int total;
  final int answeredCount;
  final List<QQuestion> results;
  const QuestionsPage({this.total = 0, this.answeredCount = 0, this.results = const []});
}

final questionsApiProvider = Provider<QuestionsApi>((ref) => QuestionsApi(ref.read(dioProvider)));

class QuestionsApi {
  final Dio _dio;
  QuestionsApi(this._dio);

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

  // GET /products/{id}/questions/?sort=&q=&limit=&offset=
  Future<QuestionsPage> list(
    String productId, {
    String sort = 'useful',
    String q = '',
    int limit = 10,
    int offset = 0,
  }) async {
    final qp = <String, dynamic>{'sort': sort, 'limit': limit, 'offset': offset};
    if (q.isNotEmpty) qp['q'] = q;
    final data = _decode((await _dio.get('/products/$productId/questions/', queryParameters: qp)).data);
    if (data is! Map) return const QuestionsPage();
    final results = (data['results'] is List)
        ? (data['results'] as List).whereType<Map>().map(QQuestion.fromJson).toList()
        : <QQuestion>[];
    return QuestionsPage(
      total: (data['total'] as num?)?.toInt() ?? results.length,
      answeredCount: (data['answered_count'] as num?)?.toInt() ?? 0,
      results: results,
    );
  }

  // POST /products/{id}/questions/  { body }
  Future<QQuestion?> ask(String productId, String body) async {
    final data = _decode((await _dio.post('/products/$productId/questions/', data: {'body': body})).data);
    return (data is Map) ? QQuestion.fromJson(data) : null;
  }

  // POST /products/questions/{qid}/answer/  { body }
  Future<QAnswer?> answer(String questionId, String body) async {
    final data = _decode((await _dio.post('/products/questions/$questionId/answer/', data: {'body': body})).data);
    return (data is Map) ? QAnswer.fromJson(data) : null;
  }

  Future<void> voteQuestion(String id) => _dio.post('/products/questions/$id/vote/');
  Future<void> voteAnswer(String id) => _dio.post('/products/answers/$id/vote/');
  Future<void> reportQuestion(String id) => _dio.post('/products/questions/$id/report/');
  Future<void> reportAnswer(String id) => _dio.post('/products/answers/$id/report/');
  Future<void> deleteQuestion(String id) => _dio.delete('/products/questions/$id/');
  Future<void> deleteAnswer(String id) => _dio.delete('/products/answers/$id/');
}