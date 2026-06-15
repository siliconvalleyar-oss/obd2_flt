import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/obd2_provider.dart';
import '../widgets/glassmorphism_widget.dart';

class Obd2DtcScreen extends ConsumerWidget {
  const Obd2DtcScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final obd2 = ref.watch(obd2Provider);
    final dtcs = obd2.dtcs;
    final connected = obd2.connectionState == Obd2ConnectionState.connected;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Codigos DTC', style: Theme.of(context).textTheme.headlineLarge)
                          .animate().fadeIn(duration: 400.ms).slideX(begin: -0.1, end: 0, duration: 400.ms),
                      const SizedBox(height: 4),
                      Text('Codigos de diagnostico', style: Theme.of(context).textTheme.bodyMedium)
                          .animate().fadeIn(duration: 400.ms, delay: 200.ms),
                    ],
                  ),
                  Row(
                    children: [
                      GlassButton(
                        label: 'Leer', icon: Icons.refresh,
                        onTap: connected ? () => ref.read(obd2Provider.notifier).loadDTCs() : null,
                        backgroundColor: AppTheme.primaryColor,
                        borderRadius: 12,
                      ),
                      const SizedBox(width: 8),
                      GlassButton(
                        label: 'Borrar', icon: Icons.delete,
                        onTap: connected ? () async {
                          final ok = await ref.read(obd2Provider.notifier).clearDTCs();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(ok ? 'DTCs borrados' : 'Error al borrar DTCs'),
                            ));
                          }
                        } : null,
                        backgroundColor: AppTheme.errorColor,
                        borderRadius: 12,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (!connected)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bluetooth_disabled, size: 48, color: Colors.white24),
                        const SizedBox(height: 16),
                        Text('Conectate al ELM327 primero', style: TextStyle(color: Colors.white38)),
                      ],
                    ),
                  ),
                )
              else if (dtcs.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline, size: 48, color: AppTheme.successColor),
                        const SizedBox(height: 16),
                        Text('No hay codigos almacenados', style: TextStyle(color: Colors.white54)),
                        const SizedBox(height: 4),
                        Text('Presiona "Leer" para buscar', style: TextStyle(color: Colors.white38, fontSize: 12)),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: dtcs.length,
                    itemBuilder: (ctx, i) {
                      final dtc = dtcs[i];
                      final isError = dtc.code != 'NONE';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GlassCard(
                          borderRadius: 16, blur: 8, borderWidth: 1,
                          padding: const EdgeInsets.all(16),
                          gradientColors: isError
                              ? [AppTheme.errorColor.withValues(alpha: 0.15), Colors.white.withValues(alpha: 0.03)]
                              : [AppTheme.successColor.withValues(alpha: 0.1), Colors.white.withValues(alpha: 0.03)],
                          child: Row(
                            children: [
                              Icon(
                                isError ? Icons.error : Icons.check_circle,
                                color: isError ? AppTheme.errorColor : AppTheme.successColor,
                                size: 28,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(dtc.code, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Text(dtc.description, style: TextStyle(color: Colors.white54, fontSize: 13)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ).animate().fadeIn(duration: 300.ms, delay: (i * 100).ms).slideX(begin: 0.1, end: 0, duration: 300.ms);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
