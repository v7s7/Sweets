import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/config/app_config.dart';
import 'features/sweets/widgets/sweets_viewport.dart';

class SweetsApp extends StatelessWidget {
  const SweetsApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sweets',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        backgroundColor: const Color(0xFFF9EFF3),
        appBar: const _AppBarLogo(),
        body: _GradientShell(
          child: SweetsViewport(), // leave non-const unless its ctor is const
        ),
      ),
    );
  }
}

class _AppBarLogo extends ConsumerWidget implements PreferredSizeWidget {
  const _AppBarLogo({Key? key}) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(appConfigProvider);
    // Helpful during development; won't spam in release.
    debugPrint('AppConfig => $cfg');

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
  const _GradientShell({required this.child, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF9EFF3), Color(0xFFFFF5F8)],
        ),
      ),
      child: SafeArea(top: false, child: child),
    );
  }
}
