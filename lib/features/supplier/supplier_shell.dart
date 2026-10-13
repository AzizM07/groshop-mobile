import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';

const _orange = Color(0xFFFF8A00); // même orange que le dashboard
const _idle = Color(0xFF9AA3AE);

/// Coque fournisseur : contenu + barre du bas (Dashboard / Commandes /
/// Produits / Messages / Réglages). Chaque page passe `index`.
class SupplierShell extends StatelessWidget {
  final int index;
  final Widget child;
  const SupplierShell({super.key, required this.index, required this.child});

  static const _tabs = <({IconData icon, String label, String route})>[
    (icon: Icons.dashboard_outlined, label: 'Dashboard', route: '/supplier'),
    (icon: Icons.receipt_long_outlined, label: 'Commandes', route: '/supplier/orders'),
    (icon: Icons.inventory_2_outlined, label: 'Produits', route: '/supplier/products'),
    (icon: Icons.chat_bubble_outline, label: 'Messages', route: '/supplier/messages'),
    (icon: Icons.settings_outlined, label: 'Réglages', route: '/supplier/settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F5),
      body: SafeArea(bottom: false, child: child),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE8EAED), width: 0.5)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 58,
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  _Tab(
                    icon: _tabs[i].icon,
                    label: _tabs[i].label,
                    active: i == index,
                    onTap: () {
                      if (i == index) return;
                      context.go(_tabs[i].route);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Tab({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = active ? _orange : _idle;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 3),
            Text(label,
                style: AppTheme.body(size: 9.5, weight: active ? FontWeight.w700 : FontWeight.w500, color: color)),
          ],
        ),
      ),
    );
  }
}