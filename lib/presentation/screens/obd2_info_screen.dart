import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/obd2_provider.dart';
import '../widgets/glassmorphism_widget.dart';

class Obd2InfoScreen extends ConsumerWidget {
  const Obd2InfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final obd2 = ref.watch(obd2Provider);
    final connected = obd2.connectionState == Obd2ConnectionState.connected;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Info del Vehiculo', style: Theme.of(context).textTheme.headlineLarge)
                  .animate().fadeIn(duration: 400.ms).slideX(begin: -0.1, end: 0, duration: 400.ms),
              const SizedBox(height: 4),
              Text('Protocolo, VIN, sensores', style: Theme.of(context).textTheme.bodyMedium)
                  .animate().fadeIn(duration: 400.ms, delay: 200.ms),
              const SizedBox(height: 20),

              if (!connected)
                Center(
                  child: Column(
                    children: [
                      const SizedBox(height: 60),
                      Icon(Icons.bluetooth_disabled, size: 48, color: Colors.white24),
                      const SizedBox(height: 16),
                      Text('Conectate al ELM327 primero', style: TextStyle(color: Colors.white38)),
                    ],
                  ),
                )
              else ...[
                _buildInfoGlassCard(context, 'Protocolo', obd2.protocol, Icons.settings_ethernet, AppTheme.primaryColor, 300),
                const SizedBox(height: 10),
                _buildInfoGlassCard(context, 'VIN', obd2.vin, Icons.qr_code, AppTheme.accentColor, 350),
                const SizedBox(height: 10),
                _buildInfoGlassCard(context, 'MIL', obd2.mil ? 'ACTIVA' : 'Inactiva', Icons.warning, obd2.mil ? AppTheme.errorColor : AppTheme.successColor, 400),
                const SizedBox(height: 10),
                _buildInfoGlassCard(context, 'Dispositivo', obd2.device?.name ?? '--', Icons.bluetooth, AppTheme.primaryColor, 450),
                const SizedBox(height: 10),
                _buildInfoGlassCard(context, 'MAC', obd2.device?.address ?? '--', Icons.memory, AppTheme.secondaryColor, 500),

                const SizedBox(height: 24),
                Text('Sensores de Oxigeno', style: Theme.of(context).textTheme.titleLarge)
                    .animate().fadeIn(duration: 400.ms, delay: 550.ms),
                const SizedBox(height: 12),
                _buildO2Sensors(context, ref, 600),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoGlassCard(BuildContext context, String label, String value, IconData icon, Color color, int delay) {
    return GlassCard(
      borderRadius: 16, blur: 8, borderWidth: 1,
      padding: const EdgeInsets.all(16),
      gradientColors: [color.withValues(alpha: 0.1), Colors.white.withValues(alpha: 0.03)],
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: Colors.white38, fontSize: 11)),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: delay.ms).slideX(begin: -0.1, end: 0, duration: 400.ms);
  }

  Widget _buildO2Sensors(BuildContext context, WidgetRef ref, int delay) {
    return FutureBuilder<List>(
      future: ref.read(obd2Provider.notifier).getOxygenSensors(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError || !snap.hasData || snap.data!.isEmpty) {
          return GlassCard(
            borderRadius: 16, blur: 8, borderWidth: 1,
            padding: const EdgeInsets.all(20),
            gradientColors: [Colors.white.withValues(alpha: 0.05), Colors.white.withValues(alpha: 0.01)],
            child: Center(child: Text('No se detectaron sensores O2', style: TextStyle(color: Colors.white38))),
          ).animate().fadeIn(duration: 400.ms, delay: delay.ms);
        }
        return Column(
          children: snap.data!.map((s) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                borderRadius: 12, blur: 6, borderWidth: 1,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                gradientColors: [Colors.white.withValues(alpha: 0.08), Colors.white.withValues(alpha: 0.02)],
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('B${s.bank}S${s.sensor}', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    Text('${s.voltage.toStringAsFixed(3)}V', style: TextStyle(color: AppTheme.accentColor, fontWeight: FontWeight.bold)),
                    Text('${s.shortTermTrim.toStringAsFixed(1)}%', style: TextStyle(color: AppTheme.warningColor)),
                  ],
                ),
              ),
            );
          }).toList(),
        ).animate().fadeIn(duration: 400.ms, delay: delay.ms);
      },
    );
  }
}
