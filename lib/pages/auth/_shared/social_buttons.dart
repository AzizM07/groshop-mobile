// lib/pages/auth/_shared/social_buttons.dart
//
// Portage de SocialButtons.jsx (web) — 2 cartes carrées : Google / Facebook.
// (LinkedIn retiré.)

import 'package:flutter/material.dart';
import 'social_icons.dart';

class SocialButtons extends StatelessWidget {
  /// Appelé avec 'google' | 'facebook'.
  final ValueChanged<String> onSelect;
  final double height;
  const SocialButtons({super.key, required this.onSelect, this.height = 46});

  static final List<_SocialSpec> _specs = [
    _SocialSpec('google', 'Continuer avec Google', (size) => GoogleIcon(size: size)),
    _SocialSpec('facebook', 'Continuer avec Facebook', (size) => FacebookIcon(size: size)),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _specs.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == _specs.length - 1 ? 0 : 8),
              child: _SocialCard(
                height: height,
                tooltip: _specs[i].tooltip,
                onTap: () => onSelect(_specs[i].provider),
                icon: _specs[i].iconBuilder(22),
              ),
            ),
          ),
      ],
    );
  }
}

class _SocialSpec {
  final String provider;
  final String tooltip;
  final Widget Function(double size) iconBuilder;
  _SocialSpec(this.provider, this.tooltip, this.iconBuilder);
}

class _SocialCard extends StatelessWidget {
  final double height;
  final String tooltip;
  final VoidCallback onTap;
  final Widget icon;
  const _SocialCard({
    required this.height,
    required this.tooltip,
    required this.onTap,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}