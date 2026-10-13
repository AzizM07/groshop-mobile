import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/api/auth_api.dart';
import '../../state/auth_provider.dart';
import '../../pages/auth/_shared/social_buttons.dart';
import '../../data/api/google_auth_helper.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  /// Retour : s'il y a un écran précédent on y revient, sinon on va à l'accueil
  /// (au lieu de laisser Android quitter l'app quand login est la racine).
  void _handleBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  /// Traduit n'importe quelle erreur de connexion en message lisible.
  String _mapError(Object e) {
    // Erreur réseau (serveur injoignable, pas d'internet, timeout)
    if (e is DioException) {
      return 'Pas de connexion au serveur. Vérifie ton internet.';
    }
    final raw = e is AuthException
        ? e.message
        : e.toString().replaceFirst('Exception: ', '');
    final status = e is AuthException ? e.statusCode : null;
    final m = raw.toLowerCase();

    if (status == 429 || m.contains('too many') || m.contains('throttl') || m.contains('limit')) {
      return 'Trop de tentatives. Réessaie dans quelques minutes.';
    }
    if (m.contains('incorrect') || m.contains('invalid')) {
      return 'Email ou mot de passe incorrect.';
    }
    if (m.contains('désactivé') || m.contains('disabled')) {
      return 'Ce compte a été désactivé.';
    }
    if (m.contains('obligatoire')) {
      return 'Saisis ton email et ton mot de passe.';
    }
    return raw.isEmpty ? 'Connexion impossible.' : raw;
  }

  /// Connexion : même schéma que l'inscription (qui, elle, affichait déjà
  /// ses erreurs) → appel DIRECT de l'API, puis rafraîchissement du provider.
  ///
  /// Pourquoi pas `authProvider.notifier.login()` ? Un AsyncNotifier qui fait
  /// `state = await AsyncValue.guard(...)` AVALE l'exception (elle part dans
  /// l'état du provider, pas dans ce catch) et fait passer le provider par
  /// « loading », ce qui peut faire reconstruire l'écran par le router →
  /// le message d'erreur n'était jamais affiché.
  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final email = _email.text.trim().toLowerCase();
    final pass = _pass.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Saisis ton email et ton mot de passe.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Lève AuthException sur 400/401/403/429 → affichée ci-dessous.
      await ref.read(authApiProvider).login(email, pass);
      // Succès : cookies posés → le provider se recharge (me()) et le router
      // redirige tout seul.
      ref.invalidate(authProvider);
    } catch (e) {
      if (mounted) setState(() => _error = _mapError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// « Mot de passe oublié ? » → feuille qui envoie le lien par email.
  /// L'email déjà tapé dans le formulaire est pré-rempli.
  void _openForgot() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _ForgotSheet(initialEmail: _email.text.trim()),
    );
  }

  /// Connexion sociale :
  ///  - Google → natif (signInWithGoogleNative → idToken → /auth/google/).
  ///  - Facebook → navigateur in-app (Custom Tabs / ASWebAuthenticationSession)
  ///    + retour via le deep link groshop://auth-callback.
  /// provider ∈ 'google' | 'facebook'.
  Future<void> _social(String provider) async {
    if (provider.toLowerCase() == 'google') {
      try {
        final idToken = await signInWithGoogleNative();
        if (idToken == null) return; // annulé par l'utilisateur
        await ref.read(authProvider.notifier).signInWithGoogle(idToken);
      } catch (e) {
        debugPrint('GOOGLE ERR >>> $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Connexion Google impossible.')),
          );
        }
      }
      return;
    }

    // Facebook : flow navigateur in-app existant
    try {
      final result = await FlutterWebAuth2.authenticate(
        url: '${AppConfig.apiBaseUrl}/auth/$provider/start/?platform=mobile',
        callbackUrlScheme: 'groshop',
      );
      final code = Uri.parse(result).queryParameters['code'];
      if (code == null) throw Exception('code manquant');
      await ref.read(authProvider.notifier).exchangeSocialCode(code);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connexion annulée ou impossible.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // false → on intercepte le retour nous-mêmes (jamais de sortie d'app ici).
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            Column(
              children: [
                // ── Titre en haut ──
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(19, 20, 20, 0),
                    child: Text.rich(
                      TextSpan(
                        text: 'Bienvenue dans ',
                        style: AppTheme.body(
                            size: 21,
                            weight: FontWeight.w800,
                            color: AppColors.text),
                        children: [
                          TextSpan(
                            text: 'GROSHOP',
                            style: AppTheme.body(
                                size: 21,
                                weight: FontWeight.w800,
                                color: AppColors.primary),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

                // ── Image : agrandie au maximum de la largeur ──
                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 110, vertical: 0),
                    child: SizedBox(
                      width: double.infinity,
                      child: Image.asset(
                        'assets/images/login_hero.png',
                        fit: BoxFit.fitWidth,
                        alignment: Alignment.topCenter,
                        errorBuilder: (_, __, ___) => Container(
                          color: AppColors.primarySoft,
                          alignment: Alignment.center,
                          child: Icon(Icons.shopping_cart_outlined,
                              size: 60, color: AppColors.primary),
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Feuille blanche : occupe le reste, pas de scroll ──
                Container(
                  width: double.infinity,
                  transform: Matrix4.translationValues(0, -18, 0),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(26)),
                    boxShadow: [
                      BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 16,
                          offset: Offset(0, -4)),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    minimum: const EdgeInsets.only(bottom: 18),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 22, 22, 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Connexion',
                              style: AppTheme.body(
                                  size: 24,
                                  weight: FontWeight.w800,
                                  color: AppColors.text)),
                          const SizedBox(height: 5),
                          _SignupLine(onTap: () => context.go('/signup')),
                          const SizedBox(height: 18),

                          if (_error != null) _ErrorBox(_error!),

                          const _FieldLabel('Adresse email'),
                          _AuthField(
                            controller: _email,
                            hint: 'votre@email.com',
                            icon: Icons.mail_outline,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 10),

                          const _FieldLabel('Mot de passe'),
                          _AuthField(
                            controller: _pass,
                            hint: 'Mot de passe',
                            icon: Icons.lock_outline,
                            obscure: _obscure,
                            suffix: IconButton(
                              icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 20,
                                  color: AppColors.muted),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),

                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _openForgot,
                              style: TextButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6)),
                              child: Text('Mot de passe oublié ?',
                                  style: AppTheme.body(
                                      size: 12.5,
                                      weight: FontWeight.w600,
                                      color: AppColors.text)),
                            ),
                          ),
                          const SizedBox(height: 6),

                          _PrimaryButton(
                              label: 'Se connecter',
                              loading: _loading,
                              onPressed: _submit),
                          const SizedBox(height: 16),
                          const _OrDivider(),
                          const SizedBox(height: 14),

                          SocialButtons(onSelect: _social),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // ── Bouton retour (toujours visible → accueil ou écran précédent) ──
            Positioned(
              top: 0,
              left: 4,
              child: SafeArea(
                bottom: false,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  color: AppColors.text,
                  onPressed: _handleBack,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════ Mot de passe oublié ═══════════════

/// Feuille « Mot de passe oublié » : envoie le lien de réinitialisation.
/// Le mail contient un lien vers la page web /reset-password (même flux que
/// le site) — l'utilisateur y choisit son nouveau mot de passe puis revient
/// se connecter dans l'app.
class _ForgotSheet extends ConsumerStatefulWidget {
  final String initialEmail;
  const _ForgotSheet({required this.initialEmail});
  @override
  ConsumerState<_ForgotSheet> createState() => _ForgotSheetState();
}

class _ForgotSheetState extends ConsumerState<_ForgotSheet> {
  late final _email = TextEditingController(text: widget.initialEmail);
  bool _busy = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    final email = _email.text.trim().toLowerCase();
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Adresse email invalide.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final msg = await ref.read(authApiProvider).requestPasswordReset(email);
      if (mounted) setState(() => _success = msg);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.statusCode == 429
          ? 'Trop de demandes. Réessaie dans un moment.'
          : e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Pas de connexion. Réessaie.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 10, 22, 22 + bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            Text('Mot de passe oublié',
                style: AppTheme.body(
                    size: 20, weight: FontWeight.w800, color: AppColors.text)),
            const SizedBox(height: 6),
            Text(
              _success == null
                  ? 'Saisis l’email de ton compte : on t’envoie un lien pour choisir un nouveau mot de passe.'
                  : 'Ouvre le lien reçu par email (valable 1 heure), choisis ton nouveau mot de passe, puis reviens te connecter ici.',
              style: AppTheme.body(size: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 18),
            if (_success != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.mark_email_read_outlined,
                      size: 20, color: Color(0xFF059669)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_success!,
                        style: AppTheme.body(
                            size: 13, color: const Color(0xFF065F46))),
                  ),
                ]),
              ),
              const SizedBox(height: 18),
              _PrimaryButton(
                  label: 'Fermer',
                  loading: false,
                  onPressed: () => Navigator.pop(context)),
            ] else ...[
              if (_error != null) _ErrorBox(_error!),
              _AuthField(
                controller: _email,
                hint: 'votre@email.com',
                icon: Icons.mail_outline,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              _PrimaryButton(
                  label: 'Envoyer le lien', loading: _busy, onPressed: _send),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════ Widgets partagés (locaux à l'écran) ═══════════════

/// Petite étiquette au-dessus d'un champ (aligne à gauche, pleine largeur).
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 7, left: 2),
        child: Text(text,
            style: AppTheme.body(
                size: 12.5, weight: FontWeight.w600, color: AppColors.text)),
      ),
    );
  }
}

class _HeaderFallback extends StatelessWidget {
  final String line1, line2;
  const _HeaderFallback({required this.line1, required this.line2});
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 40),
      alignment: Alignment.bottomLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(line1,
              style: AppTheme.body(
                  size: 22, weight: FontWeight.w800, color: Colors.white)),
          Text(line2,
              style: AppTheme.body(
                  size: 22,
                  weight: FontWeight.w800,
                  color: Colors.white.withOpacity(0.85))),
        ],
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData? icon;
  final String? prefix;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  const _AuthField({
    required this.controller,
    required this.hint,
    this.icon,
    this.prefix,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: AppTheme.body(size: 14, color: AppColors.text),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTheme.body(size: 13.5, color: AppColors.muted),
        prefixIcon: icon != null
            ? Icon(icon, size: 20, color: AppColors.muted)
            : null,
        prefixText: prefix,
        prefixStyle: AppTheme.body(size: 13.5, color: AppColors.text),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFFF3F4F6),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onPressed;
  const _PrimaryButton(
      {required this.label, required this.loading, required this.onPressed});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: const Color(0xFFD1D5DB),
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
        child: loading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Text(label,
                style: AppTheme.body(
                    size: 15, weight: FontWeight.w700, color: Colors.white)),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const Expanded(child: Divider(color: Color(0xFFE5E7EB), height: 1)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text('ou continuer avec',
            style: AppTheme.body(size: 11.5, color: AppColors.muted)),
      ),
      const Expanded(child: Divider(color: Color(0xFFE5E7EB), height: 1)),
    ]);
  }
}

class _ErrorBox extends StatelessWidget {
  final String msg;
  const _ErrorBox(this.msg);
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withOpacity(0.35)),
      ),
      child: Text('⚠️  $msg',
          style: AppTheme.body(size: 12.5, color: AppColors.primaryDark)),
    );
  }
}

class _SignupLine extends StatelessWidget {
  final VoidCallback onTap;
  const _SignupLine({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text.rich(TextSpan(
        text: 'Pas de compte ? ',
        style: AppTheme.body(size: 12.5, color: AppColors.muted),
        children: [
          TextSpan(
              text: "S'inscrire",
              style: AppTheme.body(
                  size: 12.5, weight: FontWeight.w700, color: AppColors.primary)),
        ],
      )),
    );
  }
}

// À COLLER en bas de login_screen.dart — utilisé par signup_screen.dart
// pour réutiliser exactement les mêmes widgets.
class LoginScreenWidgets {
  Widget headerFallback(String l1, String l2) =>
      _HeaderFallback(line1: l1, line2: l2);
  Widget errorBox(String m) => _ErrorBox(m);
  Widget orDivider() => const _OrDivider();
  Widget primaryButton(
          {required String label,
          required bool loading,
          required VoidCallback onPressed}) =>
      _PrimaryButton(label: label, loading: loading, onPressed: onPressed);

  Widget socialButtons(ValueChanged<String> onSelect) =>
      SocialButtons(onSelect: onSelect);

  Widget field({
    required TextEditingController controller,
    required String hint,
    IconData? icon,
    String? prefix,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
  }) =>
      _AuthField(
          controller: controller,
          hint: hint,
          icon: icon,
          prefix: prefix,
          obscure: obscure,
          suffix: suffix,
          keyboardType: keyboardType,
          onChanged: onChanged);
}