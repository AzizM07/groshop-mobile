import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Site web public GROSHOP. Surchargeable au build :
/// flutter run --dart-define=WEB_URL=http://192.168.1.10:5173
const kWebBaseUrl = String.fromEnvironment('WEB_URL', defaultValue: 'https://groshop.tn');

/// Ouvre une page du site (chemin relatif `/devenir-fournisseur`) ou une URL
/// absolue dans le navigateur du téléphone.
Future<void> openExternal(BuildContext context, String pathOrUrl) async {
  final uri = Uri.parse(pathOrUrl.startsWith('http') ? pathOrUrl : '$kWebBaseUrl$pathOrUrl');
  bool ok;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("Impossible d'ouvrir la page.")));
  }
}