import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_swipe/liquid_swipe.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../widgets/glassmorphism_widget.dart';
import '../../core/theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final LiquidController _liquidController = LiquidController();
  int _currentPage = 0;

  final List<_OnboardingPage> _pages = const [
    _OnboardingPage(
      title: 'OBD2 Scanner',
      subtitle: 'Diagnostico vehicular profesional\ncon diseno glassmorphism',
      icon: Icons.directions_car,
      gradientStart: Color(0xFF6C63FF),
      gradientEnd: Color(0xFF3F3D9E),
    ),
    _OnboardingPage(
      title: 'Bluetooth ELM327',
      subtitle: 'Conectate al puerto OBD de tu auto\nvia Bluetooth en segundos',
      icon: Icons.bluetooth,
      gradientStart: Color(0xFFFF6584),
      gradientEnd: Color(0xFFCC3355),
    ),
    _OnboardingPage(
      title: 'Diagnostico Tiempo Real',
      subtitle: 'RPM, velocidad, temperatura, DTCs\ny mas sensores en vivo',
      icon: Icons.speed,
      gradientStart: Color(0xFF00D9FF),
      gradientEnd: Color(0xFF0099CC),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          LiquidSwipe(
            pages: _pages.map((page) => _buildPage(page)).toList(),
            liquidController: _liquidController,
            waveType: WaveType.liquidReveal,
            enableLoop: false,
            fullTransitionValue: 500,
            onPageChangeCallback: (page) => setState(() => _currentPage = page),
            slideIconWidget: const Icon(Icons.arrow_back_ios_new, color: Colors.white54, size: 20),
            positionSlideIcon: 0.85,
          ),
          Positioned(
            bottom: 60, left: 0, right: 0,
            child: Column(
              children: [
                AnimatedSmoothIndicator(
                  activeIndex: _currentPage,
                  count: _pages.length,
                  effect: const ExpandingDotsEffect(
                    dotWidth: 8, dotHeight: 8, spacing: 8, expansionFactor: 3,
                    activeDotColor: Colors.white, dotColor: Color(0x4DFFFFFF),
                  ),
                ),
                const SizedBox(height: 24),
                _currentPage < _pages.length - 1
                    ? GestureDetector(
                        onTap: () => _liquidController.animateToPage(page: _currentPage + 1),
                        child: Text('Saltar', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 16, fontWeight: FontWeight.w500)),
                      )
                        : GlassButton(
                        label: 'Comenzar',
                        icon: Icons.arrow_forward,
                        onTap: () => context.go('/home/dashboard'),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(_OnboardingPage page) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [page.gradientStart, page.gradientEnd, page.gradientStart.withValues(alpha: 0.8)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                GlassCard(
                  width: 120, height: 120, borderRadius: 30, blur: 10, borderWidth: 1,
                  gradientColors: [Colors.white.withValues(alpha: 0.2), Colors.white.withValues(alpha: 0.05)],
                  padding: const EdgeInsets.all(0),
                  child: Center(child: Icon(page.icon, color: Colors.white, size: 56)),
                ).animate().scale(duration: 600.ms, curve: Curves.elasticOut).fadeIn(duration: 500.ms),
                const SizedBox(height: 48),
                Text(page.title, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.5), textAlign: TextAlign.center)
                    .animate().fadeIn(duration: 600.ms, delay: 300.ms).slideY(begin: 0.3, end: 0, duration: 600.ms),
                const SizedBox(height: 16),
                Text(page.subtitle, style: TextStyle(fontSize: 16, color: Colors.white.withValues(alpha: 0.7), height: 1.5), textAlign: TextAlign.center)
                    .animate().fadeIn(duration: 600.ms, delay: 500.ms).slideY(begin: 0.3, end: 0, duration: 600.ms),
                const Spacer(flex: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingPage {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color gradientStart;
  final Color gradientEnd;

  const _OnboardingPage({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradientStart,
    required this.gradientEnd,
  });
}
