import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/config/app_config.dart'; // <-- ensure this import exists
import 'features/sweets/widgets/sweets_viewport.dart';

class SweetsApp extends StatelessWidget {
  const SweetsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sweets',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const Scaffold(
        backgroundColor: Color(0xFFF9EFF3),
        appBar: _AppBarLogo(),
        body: _GradientShell(child: SweetsViewport()),
      ),
    );
  }
}

class _AppBarLogo extends ConsumerWidget implements PreferredSizeWidget {
  const _AppBarLogo({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // This will print on first build (and when config changes).
    final cfg = ref.watch(appConfigProvider);
    // Safe: just logs to the debug console
    // Example: AppConfig(merchantId=..., branchId=..., apiBase=..., ...)
    // ignore: avoid_print
    print('AppConfig => $cfg');

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      centerTitle: true,
      title: Text('Craveable', style: AppTheme.scriptTitle),
    );
  }
}

class _GradientShell extends StatelessWidget {
  final Widget child;
  const _GradientShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [ Color(0xFFF9EFF3), Color(0xFFFFF5F8) ],
        ),
      ),
      child: SafeArea(top: false, child: child),
    );
  }
}
