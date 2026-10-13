import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/links.dart';
import '../../core/theme.dart';
import '../../data/api/account_api.dart';
import '../../state/auth_provider.dart';
import '../../widgets/saved_list_kit.dart';

const _langs = <(String, String)>[('fr', 'Français'), ('en', 'English'), ('ar', 'العربية')];
const _langKey = 'groshop_lang'; // même clé que le localStorage web

const _green = Color(0xFF0E9F6E);

/// Règles du nouveau mot de passe — mêmes règles, même ordre et mêmes
/// messages que `_validate_new_password` côté Django (users/views.py).
final _pwdRules = <(String, String, bool Function(String))>[
  ('12 caractères minimum', 'Le mot de passe doit contenir au moins 12 caractères.', (p) => p.length >= 12),
  ('Une majuscule', 'Le mot de passe doit contenir une lettre majuscule.', (p) => RegExp(r'[A-Z]').hasMatch(p)),
  ('Une minuscule', 'Le mot de passe doit contenir une lettre minuscule.', (p) => RegExp(r'[a-z]').hasMatch(p)),
  ('Un chiffre', 'Le mot de passe doit contenir un chiffre.', (p) => RegExp(r'[0-9]').hasMatch(p)),
  ('Un caractère spécial', 'Le mot de passe doit contenir un caractère spécial.', (p) => RegExp(r'[^A-Za-z0-9]').hasMatch(p)),
];

/// Message lisible depuis une erreur (corps DRF, réseau, throttle).
String _errorText(Object e, String fallback) {
  if (e is DioException) {
    final msg = AccountApi.messageOf(e.response?.data);
    if (msg != null) return msg;
    if (e.response?.statusCode == 429) return 'Trop de tentatives. Réessayez dans quelques minutes.';
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Pas de connexion. Réessayez.';
    }
  }
  return fallback;
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _lang = 'fr';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final v = p.getString(_langKey);
      if (mounted && _langs.any((l) => l.$1 == v)) setState(() => _lang = v!);
    });
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _pickLanguage() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: SavedColors.line, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Langue', style: AppTheme.body(size: 17, weight: FontWeight.w700, color: SavedColors.ink)),
            ),
          ),
          for (final l in _langs)
            ListTile(
              title: Text(l.$2, style: AppTheme.body(size: 15, color: SavedColors.ink)),
              trailing: l.$1 == _lang ? const Icon(Icons.check, color: SavedColors.orange) : null,
              onTap: () => Navigator.pop(c, l.$1),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (picked == null || picked == _lang) return;
    setState(() => _lang = picked);
    (await SharedPreferences.getInstance()).setString(_langKey, picked);
    try {
      await ref.read(accountApiProvider).setLanguage(picked);
      if (mounted) _snack('Langue enregistrée.');
    } catch (_) {
      if (mounted) _snack('Langue enregistrée sur cet appareil.');
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Se déconnecter', style: TextStyle(color: SavedColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(authProvider.notifier).logout();
      // Invalide le jeton push de l'appareil : le compte déconnecté ne doit
      // plus recevoir de notifications ici. Un nouveau jeton sera créé au
      // prochain login. Best-effort : un échec ne bloque pas la déconnexion.
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}
      if (mounted) context.go('/login');
    } catch (_) {
      if (mounted) _snack('Déconnexion impossible. Vérifiez votre connexion.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).valueOrNull?.user;
    final name = user == null
        ? ''
        : (user.fullName.isNotEmpty ? user.fullName : user.email.split('@').first);
    final langLabel = _langs.firstWhere((l) => l.$1 == _lang).$2;

    return Scaffold(
      backgroundColor: SavedColors.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(padding: EdgeInsets.zero, children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(4, 8, 14, 8),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: SavedColors.ink),
                onPressed: () => context.canPop() ? context.pop() : context.go('/dashboard'),
              ),
              Text('Paramètres', style: AppTheme.body(size: 21, weight: FontWeight.w700, color: SavedColors.ink)),
            ]),
          ),

          if (user != null)
            _group([
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Container(
                    width: 46, height: 46,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: SavedColors.soft, shape: BoxShape.circle),
                    child: Text(name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
                        style: AppTheme.body(size: 19, weight: FontWeight.w700, color: SavedColors.orange)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(size: 16, weight: FontWeight.w700, color: SavedColors.ink)),
                      const SizedBox(height: 2),
                      Text(user.email, overflow: TextOverflow.ellipsis,
                          style: AppTheme.body(size: 13, color: SavedColors.mute)),
                    ]),
                  ),
                ]),
              ),
            ]),

          _group([
            _row(Icons.lock_outline, 'Changer le mot de passe', onTap: () => showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const _PasswordDialog(),
                )),
            _row(Icons.location_on_outlined, 'Adresses de livraison', onTap: () => showSoon(context, 'Adresses')),
            _row(Icons.translate, 'Langue', value: langLabel, onTap: _pickLanguage),
            _row(Icons.notifications_none, 'Notifications', onTap: () => showSoon(context, 'Notifications'), last: true),
          ]),

          _group([
            _row(Icons.headset_mic_outlined, 'Aide et assistance', onTap: () => context.push('/assistance')),
            _row(Icons.work_outline, 'Devenir fournisseur', external: true,
                onTap: () => openExternal(context, '/devenir-fournisseur')),
            _row(Icons.menu_book_outlined, 'Blog GROSHOP', external: true,
                onTap: () => openExternal(context, '/blogs'), last: true),
          ]),

          if (user != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              color: Colors.white,
              child: InkWell(
                onTap: _logout,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text('Se déconnecter',
                        style: AppTheme.body(size: 15, weight: FontWeight.w600, color: SavedColors.danger)),
                  ),
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('GROSHOP.tn', style: AppTheme.body(size: 12, color: SavedColors.faint))),
          ),
        ]),
      ),
    );
  }

  Widget _group(List<Widget> children) => Container(
        margin: const EdgeInsets.only(top: 8),
        color: Colors.white,
        child: Column(children: children),
      );

  Widget _row(IconData icon, String label,
          {String? value, required VoidCallback onTap, bool external = false, bool last = false}) =>
      InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            border: last ? null : const Border(bottom: BorderSide(color: SavedColors.line)),
          ),
          child: Row(children: [
            Icon(icon, size: 21, color: SavedColors.ink),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: AppTheme.body(size: 15, color: SavedColors.ink))),
            if (value != null) ...[
              Text(value, style: AppTheme.body(size: 14, color: SavedColors.mute)),
              const SizedBox(width: 4),
            ],
            Icon(external ? Icons.open_in_new : Icons.chevron_right, size: external ? 17 : 20, color: SavedColors.faint),
          ]),
        ),
      );
}

// ─────────────────────────── Mot de passe ───────────────────────────

class _PasswordDialog extends ConsumerStatefulWidget {
  const _PasswordDialog();
  @override
  ConsumerState<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends ConsumerState<_PasswordDialog> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Coche les règles en direct pendant la saisie.
    _new.addListener(_rebuild);
    _confirm.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _error = null);

    if (_old.text.isEmpty || _new.text.isEmpty || _confirm.text.isEmpty) {
      setState(() => _error = 'Remplissez tous les champs.');
      return;
    }
    for (final r in _pwdRules) {
      if (!r.$3(_new.text)) {
        setState(() => _error = r.$2);
        return;
      }
    }
    if (_new.text == _old.text) {
      setState(() => _error = 'Le nouveau mot de passe doit être différent de l\'actuel.');
      return;
    }
    if (_new.text != _confirm.text) {
      setState(() => _error = 'Les deux mots de passe ne correspondent pas.');
      return;
    }

    setState(() => _busy = true);
    // Récupérés AVANT le pop : après fermeture, le context du dialogue n'est plus fiable.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      // Django renvoie de nouveaux cookies (access + refresh) : le cookie jar
      // les enregistre, la session de CET appareil reste donc active.
      await ref.read(accountApiProvider).changePassword(_old.text, _new.text);
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(const SnackBar(
        content: Text('Mot de passe modifié. Vos autres appareils ont été déconnectés.'),
      ));
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e, 'Impossible de modifier le mot de passe.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _deco(String label) => InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      );

  Widget _rules() => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(spacing: 12, runSpacing: 4, children: [
          for (final r in _pwdRules)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(r.$3(_new.text) ? Icons.check : Icons.circle_outlined,
                  size: r.$3(_new.text) ? 15 : 10,
                  color: r.$3(_new.text) ? _green : SavedColors.faint),
              const SizedBox(width: 4),
              Text(r.$1, style: TextStyle(fontSize: 12, color: r.$3(_new.text) ? _green : SavedColors.faint)),
            ]),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final mismatch = _confirm.text.isNotEmpty && _new.text.isNotEmpty && _confirm.text != _new.text;
    return PopScope(
      // Pas de fermeture (bouton retour Android) pendant l'envoi.
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Changer le mot de passe'),
        content: SingleChildScrollView(
          child: AutofillGroup(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: _old,
                obscureText: !_show,
                enabled: !_busy,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.next,
                decoration: _deco('Mot de passe actuel'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _new,
                obscureText: !_show,
                enabled: !_busy,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                decoration: _deco('Nouveau mot de passe'),
              ),
              _rules(),
              const SizedBox(height: 12),
              TextField(
                controller: _confirm,
                obscureText: !_show,
                enabled: !_busy,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: _deco('Confirmer').copyWith(
                  errorText: mismatch ? 'Ne correspond pas' : null,
                ),
              ),
              Row(children: [
                Checkbox(value: _show, onChanged: _busy ? null : (v) => setState(() => _show = v ?? false)),
                const Text('Afficher'),
              ]),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: SavedColors.danger, fontSize: 13)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Annuler')),
          TextButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'Envoi…' : 'Enregistrer', style: const TextStyle(color: SavedColors.orange)),
          ),
        ],
      ),
    );
  }
}