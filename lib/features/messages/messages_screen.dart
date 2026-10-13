import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/models/messaging_models.dart';
import '../../state/auth_provider.dart';
import '../../state/conversation_provider.dart';

const _orange = Color(0xFFFF7A00);
const _ink = Color(0xFF0F1419);
const _mute = Color(0xFF6B7785);
const _faint = Color(0xFF9AA3AE);
const _line = Color(0xFFE8EAED);
const _soft = Color(0xFFFFF0E8);
const _bg = Color(0xFFF4F5F7);

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});
  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  String _q = '';
  bool _unreadOnly = false;

  String _fmtDate(DateTime? d) {
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).valueOrNull?.user;
    if (user == null) {
      return Scaffold(backgroundColor: Colors.white, body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Connectez-vous pour voir vos messages.'),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: () => context.go('/login'), child: const Text('Se connecter')),
      ])));
    }

    final convs = ref.watch(conversationsProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(30)),
              child: Row(children: [
                const Icon(Icons.search, size: 17, color: _faint),
                const SizedBox(width: 8),
                Expanded(child: TextField(
                  onChanged: (v) => setState(() => _q = v),
                  decoration: const InputDecoration(
                    isDense: true, border: InputBorder.none,
                    hintText: 'Rechercher des messages ou des fournisseurs'),
                  style: AppTheme.body(size: 14, color: _ink),
                )),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(children: [
              _tab('Toutes', !_unreadOnly, () => setState(() => _unreadOnly = false)),
              const SizedBox(width: 8),
              _tab('Non lus', _unreadOnly, () => setState(() => _unreadOnly = true)),
            ]),
          ),
          Expanded(
            child: convs.when(
              loading: () => const Center(child: CircularProgressIndicator(color: _orange)),
              error: (_, __) => Center(child: Text('Impossible de charger.', style: AppTheme.body(color: _mute))),
              data: (list) {
                var filtered = list.where((c) {
                  if (_unreadOnly && c.unreadCount == 0) return false;
                  if (_q.isEmpty) return true;
                  final hay = '${c.supplierName} ${c.lastMessage ?? ''}'.toLowerCase();
                  return hay.contains(_q.toLowerCase());
                }).toList();
                if (filtered.isEmpty) {
                  return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.chat_bubble_outline, size: 40, color: _faint),
                    const SizedBox(height: 10),
                    Text(_q.isNotEmpty ? 'Aucun résultat' : 'Aucune conversation', style: AppTheme.body(size: 13.5, color: _faint)),
                  ]));
                }
                return RefreshIndicator(
                  color: _orange,
                  onRefresh: () async { ref.invalidate(conversationsProvider); await ref.read(conversationsProvider.future); },
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _tile(filtered[i]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _tab(String label, bool active, VoidCallback tap) => GestureDetector(
        onTap: tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: active ? _ink : _line),
          ),
          child: Text(label, style: AppTheme.body(size: 13.5, weight: active ? FontWeight.w700 : FontWeight.w500, color: active ? _ink : _mute)),
        ),
      );

  Widget _tile(Conversation c) => InkWell(
        onTap: () => context.push('/messages/${c.id}'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF4F4F4)))),
          child: Row(children: [
            _avatar(c.supplier?.logoUrl, c.supplier?.isOnline ?? false),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(c.supplierName, overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(size: 15, weight: FontWeight.w700, color: _ink))),
                Text(_fmtDate(c.lastMsgAt), style: AppTheme.body(size: 11.5, color: _faint)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: Text(c.lastMessage ?? 'Démarrer la conversation',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(size: 13, weight: c.unreadCount > 0 ? FontWeight.w600 : FontWeight.w400,
                        color: c.unreadCount > 0 ? _ink : _mute))),
                if (c.unreadCount > 0) Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  constraints: const BoxConstraints(minWidth: 18), height: 18,
                  decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(9)),
                  alignment: Alignment.center,
                  child: Text('${c.unreadCount}', style: AppTheme.body(size: 10.5, weight: FontWeight.w700, color: Colors.white)),
                ),
              ]),
            ])),
          ]),
        ),
      );

  Widget _avatar(String? logo, bool online) => Stack(clipBehavior: Clip.none, children: [
        Container(width: 48, height: 48,
          decoration: const BoxDecoration(color: _soft, shape: BoxShape.circle),
          clipBehavior: Clip.antiAlias,
          child: (logo != null && logo.isNotEmpty)
              ? CachedNetworkImage(imageUrl: logo, fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const Icon(Icons.storefront, size: 22, color: _orange))
              : const Icon(Icons.storefront, size: 22, color: _orange)),
        if (online) Positioned(bottom: 1, right: 1, child: Container(width: 11, height: 11,
            decoration: BoxDecoration(color: const Color(0xFF0E9F6E), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
      ]);
}