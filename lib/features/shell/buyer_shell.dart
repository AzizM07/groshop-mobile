import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../state/cart_provider.dart';

const _idle = Color(0xFF6B7785);

class BuyerShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const BuyerShell({super.key, required this.shell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE8EAED), width: 0.5)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                _Tab(icon: Icons.home_outlined, label: 'Accueil', index: 0, shell: shell),
                _Tab(icon: Icons.grid_view_outlined, label: 'Catégories', index: 1, shell: shell),
                _Tab(icon: Icons.chat_bubble_outline, label: 'Messages', index: 2, shell: shell),
                _Tab(icon: Icons.shopping_cart_outlined, label: 'Panier', index: 3, shell: shell, showCartBadge: true),
                _Tab(icon: Icons.person_outline, label: 'Compte', index: 4, shell: shell),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends ConsumerWidget {
  final IconData icon;
  final String label;
  final int index;
  final StatefulNavigationShell shell;
  final bool showCartBadge;
  const _Tab({
    required this.icon,
    required this.label,
    required this.index,
    required this.shell,
    this.showCartBadge = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = shell.currentIndex == index;
    final color = active ? AppColors.primary : _idle;
    final count = showCartBadge ? ref.watch(cartProvider).count : 0;

    return Expanded(
      child: InkWell(
        onTap: () => shell.goBranch(index, initialLocation: index == shell.currentIndex),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 23, color: color),
                if (count > 0)
                  Positioned(
                    top: -5, right: -8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      constraints: const BoxConstraints(minWidth: 16),
                      height: 16,
                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
                      alignment: Alignment.center,
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        style: AppTheme.body(size: 10, weight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(label, style: AppTheme.body(size: 10, weight: active ? FontWeight.w700 : FontWeight.w500, color: color)),
          ],
        ),
      ),
    );
  }
}