/// Config globale. Change SEULEMENT ici l'URL de l'API.
class AppConfig {
  AppConfig._();

  // ⚠️ À CONFIRMER : ton API prod. Le web utilise VITE_API_URL + '/api'.
  // Mets ici l'URL complète jusqu'à /api inclus.
  static const String apiBaseUrl = 'https://api.groshop.tn/api';
}