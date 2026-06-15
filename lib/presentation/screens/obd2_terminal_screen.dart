import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/obd2_provider.dart';
import '../widgets/glassmorphism_widget.dart';

class Obd2TerminalScreen extends ConsumerStatefulWidget {
  const Obd2TerminalScreen({super.key});

  @override
  ConsumerState<Obd2TerminalScreen> createState() => _Obd2TerminalScreenState();
}

class _Obd2TerminalScreenState extends ConsumerState<Obd2TerminalScreen> {
  final TextEditingController _cmdController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<String> _history = [];
  int _historyIndex = -1;

  @override
  void dispose() {
    _cmdController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendCommand() {
    final cmd = _cmdController.text.trim();
    if (cmd.isEmpty) return;
    _history.add(cmd);
    _historyIndex = _history.length;
    ref.read(obd2Provider.notifier).sendCommand(cmd);
    _cmdController.clear();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final obd2 = ref.watch(obd2Provider);
    final connected = obd2.connectionState == Obd2ConnectionState.connected;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Terminal', style: Theme.of(context).textTheme.headlineLarge)
                  .animate().fadeIn(duration: 400.ms).slideX(begin: -0.1, end: 0, duration: 400.ms),
              const SizedBox(height: 4),
              Text('Comandos OBD2 en bruto', style: Theme.of(context).textTheme.bodyMedium)
                  .animate().fadeIn(duration: 400.ms, delay: 200.ms),
              const SizedBox(height: 16),

              if (connected)
                GlassCard(
                  borderRadius: 16, blur: 8, borderWidth: 1,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  gradientColors: [Colors.white.withValues(alpha: 0.08), Colors.white.withValues(alpha: 0.02)],
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _cmdController,
                          style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Ej: 010C, ATZ, AT RV',
                            hintStyle: TextStyle(color: Colors.white24, fontFamily: 'monospace'),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _sendCommand(),
                        ),
                      ),
                      GlassButton(
                        label: 'Enviar', icon: Icons.send,
                        onTap: _sendCommand,
                        borderRadius: 12,
                        backgroundColor: AppTheme.primaryColor,
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 400.ms, delay: 300.ms),

              const SizedBox(height: 12),

              Expanded(
                child: GlassCard(
                  borderRadius: 16, blur: 8, borderWidth: 1,
                  padding: const EdgeInsets.all(12),
                  gradientColors: [Colors.white.withValues(alpha: 0.05), Colors.white.withValues(alpha: 0.01)],
                  child: obd2.log.isEmpty
                      ? Center(
                          child: Text(
                            connected ? 'Esperando datos...' : 'Conectate al ELM327',
                            style: TextStyle(color: Colors.white24),
                          ),
                        )
                      : SingleChildScrollView(
                          controller: _scrollController,
                          reverse: true,
                          child: SelectableText(
                            obd2.log,
                            style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 12, height: 1.5),
                          ),
                        ),
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 400.ms),
            ],
          ),
        ),
      ),
    );
  }
}
