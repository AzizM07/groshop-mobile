import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../../../data/api/questions_api.dart';
import '../../../state/auth_provider.dart';

const _orange = Color(0xFFFF7A00);
const _ink = Color(0xFF0F1419);
const _sub = Color(0xFF3D4853);
const _mute = Color(0xFF6B7785);
const _faint = Color(0xFF9AA3AE);
const _line = Color(0xFFECEEF1);
const _green = Color(0xFF0E9F6E);
const _qBubble = Color(0xFFEEF2FF);
const _aBubble = Color(0xFFE9F9F0);

String _fmtDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd/$mm/${d.year}';
}

class QuestionsSection extends ConsumerStatefulWidget {
  final String productId;
  const QuestionsSection({super.key, required this.productId});

  @override
  ConsumerState<QuestionsSection> createState() => _QuestionsSectionState();
}

class _QuestionsSectionState extends ConsumerState<QuestionsSection> {
  static const _pageSize = 10;

  final _search = TextEditingController();
  Timer? _debounce;
  String _debouncedQuery = '';
  String _sort = 'useful';

  List<QQuestion> _items = [];
  int _total = 0, _answered = 0, _offset = 0;
  bool _loading = true;
  bool _askOpen = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearch);
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final q = _search.text.trim();
      if (q == _debouncedQuery) return;
      _debouncedQuery = q;
      _load(reset: true);
    });
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) setState(() => _loading = true);
    final off = reset ? 0 : _offset;
    try {
      final page = await ref.read(questionsApiProvider).list(
            widget.productId,
            sort: _sort,
            q: _debouncedQuery,
            limit: _pageSize,
            offset: off,
          );
      if (!mounted) return;
      setState(() {
        _total = page.total;
        _answered = page.answeredCount;
        _items = reset ? page.results : [..._items, ...page.results];
        _offset = off + _pageSize;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _loggedIn =>
      ref.read(authProvider).valueOrNull?.isAuthenticated ?? false;

  void _promptLogin() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Connexion requise.'),
        action: SnackBarAction(label: 'Se connecter', onPressed: () => context.push('/login')),
      ),
    );
  }

  void _onError(Object e) {
    if (e is DioException && e.response?.statusCode == 401) {
      _promptLogin();
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Une erreur est survenue.')),
      );
    }
  }

  Future<void> _ask(String body) async {
    try {
      final q = await ref.read(questionsApiProvider).ask(widget.productId, body);
      if (q == null || !mounted) return;
      setState(() {
        _items = [q, ..._items];
        _total += 1;
        _askOpen = false;
      });
    } catch (e) {
      _onError(e);
    }
  }

  Future<bool> _reply(String qid, String body) async {
    try {
      final a = await ref.read(questionsApiProvider).answer(qid, body);
      if (a == null || !mounted) return false;
      setState(() {
        final i = _items.indexWhere((q) => q.id == qid);
        if (i >= 0) _items[i].answers = [..._items[i].answers, a];
      });
      return true;
    } catch (e) {
      _onError(e);
      return false;
    }
  }

  Future<void> _likeQuestion(QQuestion q) async {
    setState(() {
      q.hasLiked = !q.hasLiked;
      q.likesCount += q.hasLiked ? 1 : -1;
    });
    try {
      await ref.read(questionsApiProvider).voteQuestion(q.id);
    } catch (e) {
      if (mounted) {
        setState(() {
          q.hasLiked = !q.hasLiked;
          q.likesCount += q.hasLiked ? 1 : -1;
        });
      }
      _onError(e);
    }
  }

  Future<void> _likeAnswer(QAnswer a) async {
    setState(() {
      a.hasLiked = !a.hasLiked;
      a.likesCount += a.hasLiked ? 1 : -1;
    });
    try {
      await ref.read(questionsApiProvider).voteAnswer(a.id);
    } catch (e) {
      if (mounted) {
        setState(() {
          a.hasLiked = !a.hasLiked;
          a.likesCount += a.hasLiked ? 1 : -1;
        });
      }
      _onError(e);
    }
  }

  Future<void> _report({required bool isAnswer, required String id}) async {
    try {
      final api = ref.read(questionsApiProvider);
      isAnswer ? await api.reportAnswer(id) : await api.reportQuestion(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Merci, signalement pris en compte.')),
        );
      }
    } catch (e) {
      _onError(e);
    }
  }

  Future<void> _deleteQuestion(QQuestion q) async {
    final ok = await _confirm('Supprimer cette question ?');
    if (!ok) return;
    try {
      await ref.read(questionsApiProvider).deleteQuestion(q.id);
      if (mounted) setState(() {
        _items.removeWhere((x) => x.id == q.id);
        _total = (_total - 1).clamp(0, 1 << 30);
      });
    } catch (e) {
      _onError(e);
    }
  }

  Future<void> _deleteAnswer(QQuestion q, QAnswer a) async {
    final ok = await _confirm('Supprimer cette réponse ?');
    if (!ok) return;
    try {
      await ref.read(questionsApiProvider).deleteAnswer(a.id);
      if (mounted) setState(() => q.answers.removeWhere((x) => x.id == a.id));
    } catch (e) {
      _onError(e);
    }
  }

  Future<bool> _confirm(String msg) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer', style: TextStyle(color: Color(0xFFDC2626))),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = ref.watch(authProvider).valueOrNull?.isAuthenticated ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _controls(loggedIn),
        const SizedBox(height: 6),
        if (_loading && _items.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Chargement…')))
        else if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                _debouncedQuery.isNotEmpty
                    ? 'Aucune question ne correspond.'
                    : 'Aucune question pour le moment.',
                style: AppTheme.body(size: 13.5, color: _faint),
              ),
            ),
          )
        else ...[
          for (int i = 0; i < _items.length; i++)
            _QuestionCard(
              question: _items[i],
              isTop: i == 0 && _sort == 'useful' && _debouncedQuery.isEmpty,
              loggedIn: loggedIn,
              onGoLogin: _promptLogin,
              onLikeQuestion: () => _likeQuestion(_items[i]),
              onLikeAnswer: _likeAnswer,
              onReportQuestion: () => _report(isAnswer: false, id: _items[i].id),
              onReportAnswer: (a) => _report(isAnswer: true, id: a.id),
              onDeleteQuestion: () => _deleteQuestion(_items[i]),
              onDeleteAnswer: (a) => _deleteAnswer(_items[i], a),
              onReply: (body) => _reply(_items[i].id, body),
            ),
          if (_items.length < _total)
            Center(
              child: TextButton(
                onPressed: _loading ? null : () => _load(),
                child: Text(_loading ? 'Chargement…' : 'Voir plus'),
              ),
            ),
        ],
      ],
    );
  }

  Widget _controls(bool loggedIn) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_answered > 0)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(10)),
              child: Text('$_answered question${_answered > 1 ? 's' : ''} répondue${_answered > 1 ? 's' : ''}',
                  style: AppTheme.body(size: 14, weight: FontWeight.w700, color: const Color(0xFF1B1B4B))),
            ),

          // Recherche
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: _line),
              borderRadius: BorderRadius.circular(999),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              const Icon(Icons.search, size: 18, color: _mute),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _search,
                  style: AppTheme.body(size: 14, color: _ink),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 11),
                    hintText: 'Rechercher dans les questions…',
                    hintStyle: AppTheme.body(size: 13.5, color: _faint),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),

          // Tri
          Row(children: [
            Text('Trier par', style: AppTheme.body(size: 13.5, weight: FontWeight.w700, color: _ink)),
            const SizedBox(width: 10),
            DropdownButton<String>(
              value: _sort,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'useful', child: Text('Les plus utiles')),
                DropdownMenuItem(value: 'recent', child: Text('Les plus récentes')),
                DropdownMenuItem(value: 'oldest', child: Text('Les plus anciennes')),
              ],
              onChanged: (v) {
                if (v == null || v == _sort) return;
                setState(() => _sort = v);
                _load(reset: true);
              },
            ),
          ]),
          const SizedBox(height: 8),

          // Poser une question
          if (!_askOpen)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  if (!loggedIn) { _promptLogin(); return; }
                  setState(() => _askOpen = true);
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: loggedIn ? _orange : _line, width: 1.5),
                  foregroundColor: loggedIn ? _orange : _mute,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
                child: Text(loggedIn ? 'Poser une question' : 'Connectez-vous pour poser une question',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            )
          else
            _InlineForm(
              hint: 'Écris ta question…',
              submitLabel: 'Publier',
              minLen: 5,
              onCancel: () => setState(() => _askOpen = false),
              onSubmit: (body) async {
                await _ask(body);
                return true;
              },
            ),
        ],
      ),
    );
  }
}

// ══════════════ Carte question ══════════════
class _QuestionCard extends StatefulWidget {
  final QQuestion question;
  final bool isTop;
  final bool loggedIn;
  final VoidCallback onGoLogin;
  final VoidCallback onLikeQuestion;
  final ValueChanged<QAnswer> onLikeAnswer;
  final VoidCallback onReportQuestion;
  final ValueChanged<QAnswer> onReportAnswer;
  final VoidCallback onDeleteQuestion;
  final ValueChanged<QAnswer> onDeleteAnswer;
  final Future<bool> Function(String) onReply;

  const _QuestionCard({
    required this.question,
    required this.isTop,
    required this.loggedIn,
    required this.onGoLogin,
    required this.onLikeQuestion,
    required this.onLikeAnswer,
    required this.onReportQuestion,
    required this.onReportAnswer,
    required this.onDeleteQuestion,
    required this.onDeleteAnswer,
    required this.onReply,
  });

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  bool _replyOpen = false;
  bool _showAllAnswers = false;

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final answers = _showAllAnswers || q.answers.length <= 2 ? q.answers : q.answers.sublist(0, 2);
    final hidden = q.answers.length - answers.length;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.isTop)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.thumb_up_alt_outlined, size: 13, color: _green),
                const SizedBox(width: 6),
                Text('Question la plus utile',
                    style: AppTheme.body(size: 12, weight: FontWeight.w800, color: _green)),
              ]),
            ),

          _bubble(q.body, _qBubble, alignRight: false),
          const SizedBox(height: 8),
          _authorRow(
            name: q.authorName,
            date: q.createdAt,
            isMine: q.isMine,
            liked: q.hasLiked,
            likes: q.likesCount,
            onLike: () => widget.loggedIn ? widget.onLikeQuestion() : widget.onGoLogin(),
            onReport: widget.onReportQuestion,
            onDelete: widget.onDeleteQuestion,
          ),

          // Réponses
          for (final a in answers) _answerBlock(a),

          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 24),
              child: GestureDetector(
                onTap: () => setState(() => _showAllAnswers = true),
                child: Text('Voir $hidden réponse${hidden > 1 ? 's' : ''} de plus',
                    style: AppTheme.body(size: 13, weight: FontWeight.w700, color: const Color(0xFF1B1B4B))
                        .copyWith(decoration: TextDecoration.underline)),
              ),
            ),

          // Répondre
          Align(
            alignment: Alignment.centerRight,
            child: _replyOpen
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: OutlinedButton(
                      onPressed: () {
                        if (!widget.loggedIn) { widget.onGoLogin(); return; }
                        setState(() => _replyOpen = true);
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: widget.loggedIn ? _orange : _line, width: 1.5),
                        foregroundColor: widget.loggedIn ? _orange : _mute,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                      child: Text(widget.loggedIn ? 'Répondre' : 'Connectez-vous pour répondre',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ),
          ),
          if (_replyOpen)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 24),
              child: _InlineForm(
                hint: 'Écris ta réponse…',
                submitLabel: 'Répondre',
                minLen: 2,
                onCancel: () => setState(() => _replyOpen = false),
                onSubmit: (body) async {
                  final ok = await widget.onReply(body);
                  if (ok && mounted) setState(() => _replyOpen = false);
                  return ok;
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _answerBlock(QAnswer a) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, left: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _bubble(a.body, _aBubble, alignRight: true),
          const SizedBox(height: 6),
          Row(children: [
            _avatar(a.authorName, 28),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                Text('Réponse de ${a.authorName}', style: AppTheme.body(size: 12.5, color: _mute)),
                if (a.fromSupplier)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFFFEDE4), borderRadius: BorderRadius.circular(5)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.verified, size: 11, color: _orange),
                      const SizedBox(width: 3),
                      Text('Fournisseur',
                          style: AppTheme.body(size: 10.5, weight: FontWeight.w800, color: _orange)),
                    ]),
                  ),
                Text('· ${_fmtDate(a.createdAt)}', style: AppTheme.body(size: 12, color: _faint)),
              ]),
            ),
            _reportBtn(() => widget.onReportAnswer(a)),
            _likeBtn(
              liked: a.hasLiked,
              likes: a.likesCount,
              onTap: () => widget.loggedIn ? widget.onLikeAnswer(a) : widget.onGoLogin(),
            ),
            if (a.isMine)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFDC2626)),
                onPressed: () => widget.onDeleteAnswer(a),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _authorRow({
    required String name,
    required String date,
    required bool isMine,
    required bool liked,
    required int likes,
    required VoidCallback onLike,
    required VoidCallback onReport,
    required VoidCallback onDelete,
  }) {
    return Row(children: [
      _avatar(name, 34),
      const SizedBox(width: 10),
      Expanded(
        child: Text('Demandée par $name · ${_fmtDate(date)}',
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: AppTheme.body(size: 12.5, color: _mute)),
      ),
      _reportBtn(onReport),
      _likeBtn(liked: liked, likes: likes, onTap: onLike),
      if (isMine)
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFDC2626)),
          onPressed: onDelete,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
    ]);
  }

  Widget _bubble(String text, Color bg, {required bool alignRight}) {
    return Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Text(text, style: AppTheme.body(size: 14, color: _ink).copyWith(height: 1.45)),
    );
  }

  Widget _avatar(String name, double size) {
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: size, height: size,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFF1F3F7)),
      alignment: Alignment.center,
      child: Text(letter,
          style: AppTheme.body(size: size * 0.4, weight: FontWeight.w800, color: const Color(0xFF1B1B4B))),
    );
  }

  Widget _likeBtn({required bool liked, required int likes, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(liked ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
              size: 15, color: liked ? _orange : _sub),
          const SizedBox(width: 4),
          Text('$likes', style: AppTheme.body(size: 12.5, weight: FontWeight.w700, color: liked ? _orange : _sub)),
        ]),
      ),
    );
  }

  Widget _reportBtn(VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Icon(Icons.flag_outlined, size: 15, color: Color(0xFF1B1B4B)),
      ),
    );
  }
}

// ══════════════ Formulaire de saisie (question / réponse) ══════════════
class _InlineForm extends StatefulWidget {
  final String hint;
  final String submitLabel;
  final int minLen;
  final int maxLen;
  final VoidCallback? onCancel;
  final Future<bool> Function(String) onSubmit;

  const _InlineForm({
    required this.hint,
    required this.submitLabel,
    required this.onSubmit,
    this.minLen = 5,
    this.maxLen = 1000,
    this.onCancel,
  });

  @override
  State<_InlineForm> createState() => _InlineFormState();
}

class _InlineFormState extends State<_InlineForm> {
  final _c = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  int get _len => _c.text.trim().length;
  bool get _valid => _len >= widget.minLen;

  Future<void> _submit() async {
    if (!_valid || _busy) return;
    setState(() => _busy = true);
    final ok = await widget.onSubmit(_c.text.trim());
    if (!mounted) return;
    if (ok) _c.clear();
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TextField(
          controller: _c,
          maxLines: 3,
          minLines: 2,
          maxLength: widget.maxLen,
          onChanged: (_) => setState(() {}),
          style: AppTheme.body(size: 14, color: _ink),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: AppTheme.body(size: 13.5, color: _faint),
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _line)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _orange, width: 1.4)),
          ),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (widget.onCancel != null)
            TextButton(onPressed: _busy ? null : widget.onCancel, child: const Text('Annuler')),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: (_valid && !_busy) ? _submit : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _orange,
              disabledBackgroundColor: const Color(0xFFCFD3DA),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(_busy ? '…' : widget.submitLabel,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ),
        ]),
      ],
    );
  }
}