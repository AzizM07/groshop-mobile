import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mémorise, par section, les ids déjà « vus » par l'utilisateur,
/// pour afficher des badges « nouveau » (nombre en haut à droite des icônes).
///
/// Premier passage sur une section (clé absente) : l'état actuel sert de
/// référence → 0 nouveau. Sinon, tout ce qui a été installé avant la mise à jour
/// apparaîtrait comme « nouveau ».
class SeenStore {
  static const _prefix = 'seen:';
  static const _maxIds = 500;
  final SharedPreferences _p;
  SeenStore(this._p);

  /// Nombre d'[ids] jamais vus dans la section [key].
  int unseen(String key, Iterable<String> ids) {
    final stored = _p.getStringList('$_prefix$key');
    if (stored == null) {
      _p.setStringList('$_prefix$key', ids.toList());
      return 0;
    }
    final seen = stored.toSet();
    return ids.where((id) => !seen.contains(id)).length;
  }

  /// Marque [ids] comme vus dans la section [key].
  Future<void> markSeen(String key, Iterable<String> ids) async {
    final list = <String>{...?_p.getStringList('$_prefix$key'), ...ids}.toList();
    await _p.setStringList(
      '$_prefix$key',
      list.length > _maxIds ? list.sublist(list.length - _maxIds) : list,
    );
  }
}

final seenStoreProvider = FutureProvider<SeenStore>(
  (ref) async => SeenStore(await SharedPreferences.getInstance()),
);