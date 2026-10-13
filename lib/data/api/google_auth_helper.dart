import 'package:google_sign_in/google_sign_in.dart';

/// Le client ID WEB (celui utilisé par Django dans GOOGLE_CLIENT_ID) —
/// garantit que l'idToken renvoyé aura la bonne audience pour passer
/// google_one_tap tel quel, sans changement côté backend.
const _webClientId =
    '714757960599-8s72nke0b78nstg5qqcd69qqgesgheb1.apps.googleusercontent.com';

final _googleSignIn = GoogleSignIn(
  serverClientId: _webClientId,
  scopes: ['email', 'profile'],
);

/// Retourne l'idToken Google, ou null si l'utilisateur a annulé.
Future<String?> signInWithGoogleNative() async {
  final account = await _googleSignIn.signIn();
  if (account == null) return null;
  final auth = await account.authentication;
  return auth.idToken;
}