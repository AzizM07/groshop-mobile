import 'package:cookie_jar/cookie_jar.dart';
import 'package:path_provider/path_provider.dart';

/// Jar de cookies PERSISTANT (survit au redémarrage), comme le cookie store
/// d'un navigateur. Stocke access_token / refresh_token / csrftoken.
class CookieStore {
  PersistCookieJar? _jar;

  Future<PersistCookieJar> jar() async {
    if (_jar != null) return _jar!;
    final dir = await getApplicationSupportDirectory();
    _jar = PersistCookieJar(
      ignoreExpires: false,
      storage: FileStorage('${dir.path}/.cookies/'),
    );
    return _jar!;
  }

  Future<String?> read(String name, Uri uri) async {
    final j = await jar();
    final cookies = await j.loadForRequest(uri);
    for (final c in cookies) {
      if (c.name == name) return c.value;
    }
    return null;
  }

  Future<bool> hasSession(Uri uri) async {
    final j = await jar();
    final cookies = await j.loadForRequest(uri);
    return cookies.any((c) => c.name == 'access_token' || c.name == 'refresh_token');
  }

  Future<void> clear() async {
    final j = await jar();
    await j.deleteAll();
  }
}