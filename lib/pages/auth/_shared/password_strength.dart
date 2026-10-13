// lib/pages/auth/_shared/password_strength.dart
//
// Portage direct de PasswordStrength.jsx (web). Pas utilisé par login_screen
// (pas de champ mot de passe à évaluer là) — pensé pour être glissé sous le
// champ mot de passe de signup_screen.dart :
//
//   W.field(controller: _pass, ...),
//   PasswordStrength(password: _pass.text),   // ⭐ ajouter ceci
//
// (nécessite de passer onChanged: (_) => setState((){}) sur ce champ pour
// que la barre se mette à jour à chaque frappe)

import 'package:flutter/material.dart';

class PasswordStrength extends StatelessWidget {
  final String password;
  const PasswordStrength({super.key, required this.password});

  int get _score {
    var score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(password) && RegExp(r'[a-z]').hasMatch(password)) score++;
    if (RegExp(r'\d').hasMatch(password)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;
    return score;
  }

  static const List<({String label, Color color, double fraction})> _levels = [
    (label: 'Très faible', color: Color(0xFFEF4444), fraction: 0.2),
    (label: 'Faible', color: Color(0xFFF97316), fraction: 0.4),
    (label: 'Moyen', color: Color(0xFFEAB308), fraction: 0.6),
    (label: 'Bon', color: Color(0xFF84CC16), fraction: 0.8),
    (label: 'Fort', color: Color(0xFF22C55E), fraction: 1.0),
  ];

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();
    final level = _levels[_score.clamp(0, 4)];

    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Container(
                height: 3,
                color: const Color(0xFFF3F4F6),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: level.fraction,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    color: level.color,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text(
              level.label,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: level.color),
            ),
          ),
        ],
      ),
    );
  }
}