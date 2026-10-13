import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/api/auth_api.dart';
import '../../data/api/google_auth_helper.dart';
import '../../state/auth_provider.dart';
// Réutilise les widgets déclarés dans login_screen.dart (même package)
import 'login_screen.dart' show LoginScreenWidgets;

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});
  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  bool _obscure = true;
  bool _cgu = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _pass.dispose();
    super.dispose();
  }

  /// Retour : écran précédent si possible, sinon la page de connexion
  /// (au lieu de laisser Android quitter l'app).
  void _handleBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/login');
    }
  }

  String? _validate() {
    if (_name.text.trim().length < 2) return 'Entre ton nom complet.';
    if (!_email.text.contains('@') || !_email.text.contains('.')) {
      return 'Adresse email invalide.';
    }
    if (_phone.text.length != 8) return 'Le numéro doit faire 8 chiffres.';
    if (_pass.text.length < 8) return 'Mot de passe : 8 caractères minimum.';
    if (!_cgu) return 'Tu dois accepter les conditions d’utilisation.';
    return null;
  }

  String _mapSignupError(AuthException e) {
    final f = e.fields;
    String? first(String key) {
      final v = f[key];
      if (v is List && v.isNotEmpty) return v.first.toString();
      if (v is String) return v;
      return null;
    }

    final email = first('email');
    if (email != null) {
      final s = email.toLowerCase();
      if (s.contains('exist') || s.contains('déjà') || s.contains('unique')) {
        return 'Cet email est déjà utilisé.';
      }
      return 'Adresse email invalide.';
    }
    final phone = first('phone');
    if (phone != null) {
      final s = phone.toLowerCase();
      if (s.contains('exist') || s.contains('déjà') || s.contains('unique')) {
        return 'Ce numéro est déjà utilisé.';
      }
      return 'Numéro de téléphone invalide.';
    }
    final pass = first('password');
    if (pass != null) return pass;
    return e.message;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final v = _validate();
    if (v != null) {
      setState(() => _error = v);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authApiProvider).registerBuyer(
            fullName: _name.text.trim(),
            email: _email.text.trim().toLowerCase(),
            phone: '+216${_phone.text}',
            password: _pass.text,
          );
      // les cookies sont posés → on rafraîchit l'état auth
      ref.invalidate(authProvider);
    } on AuthException catch (e) {
      setState(() => _error = _mapSignupError(e));
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Même logique que login_screen.dart :
  ///  - Google → natif (signInWithGoogleNative → idToken → /auth/google/).
  ///  - Facebook → flow navigateur in-app + deep link groshop://auth-callback.
  Future<void> _social(String provider) async {
    if (provider.toLowerCase() == 'google') {
      try {
        final idToken = await signInWithGoogleNative();
        if (idToken == null) return; // annulé par l'utilisateur
        await ref.read(authProvider.notifier).signInWithGoogle(idToken);
      } catch (e) {
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
          const SnackBar(content: Text('Impossible d’ouvrir la connexion.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final W = LoginScreenWidgets(); // réutilise les widgets partagés de login
    final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
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

                  // ── Image (hauteur fixe car on est dans un scroll) ──
                  SizedBox(
                    height: 175,
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 90),
                      child: Image.asset(
                        'assets/images/login_hero.png',
                        fit: BoxFit.contain,
                        alignment: Alignment.topCenter,
                        errorBuilder: (_, __, ___) => Container(
                          color: AppColors.primarySoft,
                          alignment: Alignment.center,
                          child: Icon(Icons.shopping_cart_outlined,
                              size: 56, color: AppColors.primary),
                        ),
                      ),
                    ),
                  ),

                  // ── Feuille blanche arrondie (le formulaire) ──
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
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(22, 22, 22, 24 + bottomSafe),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Inscription',
                              style: AppTheme.body(
                                  size: 24,
                                  weight: FontWeight.w800,
                                  color: AppColors.text)),
                          const SizedBox(height: 5),
                          GestureDetector(
                            onTap: () => context.go('/login'),
                            child: Text.rich(TextSpan(
                              text: 'Déjà un compte ? ',
                              style: AppTheme.body(
                                  size: 12.5, color: AppColors.muted),
                              children: [
                                TextSpan(
                                    text: 'Se connecter',
                                    style: AppTheme.body(
                                        size: 12.5,
                                        weight: FontWeight.w700,
                                        color: AppColors.primary)),
                              ],
                            )),
                          ),
                          const SizedBox(height: 18),

                          if (_error != null) W.errorBox(_error!),

                          W.field(
                              controller: _name,
                              hint: 'Nom complet',
                              icon: Icons.person_outline),
                          const SizedBox(height: 12),
                          W.field(
                              controller: _email,
                              hint: 'Adresse email',
                              icon: Icons.mail_outline,
                              keyboardType: TextInputType.emailAddress),
                          const SizedBox(height: 12),
                          W.field(
                              controller: _phone,
                              hint: 'Téléphone',
                              prefix: '🇹🇳 +216  ',
                              keyboardType: TextInputType.phone,
                              onChanged: (v) {
                                final digits = v.replaceAll(RegExp(r'\D'), '');
                                if (digits.length > 8) {
                                  _phone.text = digits.substring(0, 8);
                                  _phone.selection = TextSelection.collapsed(
                                      offset: _phone.text.length);
                                }
                              }),
                          const SizedBox(height: 12),
                          W.field(
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
                              )),
                          const SizedBox(height: 14),

                          // Case CGU
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: Checkbox(
                                  value: _cgu,
                                  onChanged: (v) =>
                                      setState(() => _cgu = v ?? false),
                                  activeColor: AppColors.primary,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(5)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text.rich(TextSpan(
                                    text: "J'accepte les ",
                                    style: AppTheme.body(
                                        size: 12, color: AppColors.muted),
                                    children: [
                                      TextSpan(
                                          text: 'CGU',
                                          style: AppTheme.body(
                                              size: 12,
                                              weight: FontWeight.w600,
                                              color: AppColors.text)),
                                      const TextSpan(text: ' et la '),
                                      TextSpan(
                                          text: 'politique de confidentialité',
                                          style: AppTheme.body(
                                              size: 12,
                                              weight: FontWeight.w600,
                                              color: AppColors.text)),
                                    ],
                                  )),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          W.primaryButton(
                              label: 'Créer mon compte',
                              loading: _loading,
                              onPressed: _submit),
                          const SizedBox(height: 20),
                          W.orDivider(),
                          const SizedBox(height: 16),
                          W.socialButtons(_social),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Bouton retour ──
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