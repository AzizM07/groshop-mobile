import 'package:flutter/material.dart';

const _kOrange = Color(0xFFFF7A00); // orange marque mobile
const _kDark = Color(0xFF3B2A2A);

/// Écran « Pas de connexion Internet » (icône Wi-Fi + X orange).
class NoConnectionView extends StatelessWidget {
  const NoConnectionView({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 110,
              height: 90,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Center(
                    child: Icon(Icons.wifi_rounded, size: 96, color: _kDark),
                  ),
                  Positioned(
                    right: -2,
                    top: 8,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: _kOrange,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: const Icon(Icons.close_rounded,
                          size: 18, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Pas de connexion Internet',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _kOrange,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Vérifiez votre connexion et réessayez.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF555555), fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 160,
              height: 44,
              child: FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: _kDark,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('Réessayer',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Écran pour les autres erreurs (serveur, 500...) — sans code brut.
class GenericErrorView extends StatelessWidget {
  const GenericErrorView({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 72, color: _kDark),
            const SizedBox(height: 16),
            const Text(
              'Une erreur est survenue',
              style: TextStyle(
                  color: _kOrange, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Réessayez dans un instant.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF555555), fontSize: 14),
            ),
            const SizedBox(height: 24),
            OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}

/// Bandeau fin affiché au-dessus des données déjà chargées.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kDark,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(
          children: [
            const Icon(Icons.wifi_off_rounded, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Hors ligne — dernières données chargées',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: _kOrange),
              child: const Text('Réessayer',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}