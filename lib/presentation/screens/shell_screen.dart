import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../widgets/liquid_glass_bottom_bar.dart';

class ShellScreen extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const ShellScreen({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = navigationShell.currentIndex;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: SafeArea(
        top: false, bottom: true,
        child: LiquidGlassBottomBar(
          currentIndex: currentIndex,
          onTap: (index) {
            HapticFeedback.lightImpact();
            navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
          },
          items: const [
            LiquidGlassBottomBarItem(label: 'Dashboard', icon: Icons.speed_outlined, activeIcon: Icons.speed),
            LiquidGlassBottomBarItem(label: 'DTCs', icon: Icons.error_outline, activeIcon: Icons.error),
            LiquidGlassBottomBarItem(label: 'Terminal', icon: Icons.terminal_outlined, activeIcon: Icons.terminal),
            LiquidGlassBottomBarItem(label: 'Info', icon: Icons.info_outline, activeIcon: Icons.info),
          ],
        ),
      ),
    );
  }
}
