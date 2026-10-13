import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Instance préchargée dans main() avant runApp() et injectée via
/// ProviderScope(overrides: [...]) — permet une lecture SYNCHRONE
/// (ref.read) partout dans l'app, ex. pour peindre un cache au premier
/// rendu sans flash (voir MobileHeroGrid).
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider doit être overridé dans main() avec '
    'l\'instance résolue par SharedPreferences.getInstance()',
  );
});