import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../state/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _fadeOut = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await Future.wait([
      Future.delayed(const Duration(milliseconds: 800)),
      _waitAuthReady(),
    ]);
    if (!mounted) return;
    setState(() => _fadeOut = true);
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    final auth = ref.read(authProvider).valueOrNull;
    final dest = (auth?.isSupplier ?? false) ? '/supplier' : '/';
    context.go(dest);
  }

  Future<void> _waitAuthReady() async {
    if (!ref.read(authProvider).isLoading) return;
    final c = Completer<void>();
    final sub = ref.listenManual(authProvider, (_, next) {
      if (!next.isLoading && !c.isCompleted) c.complete();
    });
    await c.future;
    sub.close();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: AnimatedOpacity(
          opacity: _fadeOut ? 0 : 1,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.92, end: 1),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28), // ⬅️ cadre arrondi
              child: Image.asset(
                'assets/images/logo.png',
                width: 130,
                height: 130,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Text(
                  'GROSHOP',
                  style: AppTheme.display(size: 34, color: AppColors.primary),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}