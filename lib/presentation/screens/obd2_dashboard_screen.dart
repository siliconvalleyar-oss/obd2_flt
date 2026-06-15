import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/obd2_provider.dart';
import '../widgets/glassmorphism_widget.dart';
import '../widgets/liquid_bar.dart';

class Obd2DashboardScreen extends ConsumerStatefulWidget {
  const Obd2DashboardScreen({super.key});

  @override
  ConsumerState<Obd2DashboardScreen> createState() => _Obd2DashboardScreenState();
}

class _Obd2DashboardScreenState extends ConsumerState<Obd2DashboardScreen> {
  final List<BluetoothDevice> _devices = [];
  BluetoothDevice? _selectedDevice;
  bool _scanning = false;
  bool _loadingDevices = true;
  StreamSubscription<BluetoothDiscoveryResult>? _discoverySub;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadBondedDevices();
  }

  @override
  void dispose() {
    _discoverySub?.cancel();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();
  }

  Future<void> _loadBondedDevices() async {
    setState(() => _loadingDevices = true);
    try {
      final bonded = await FlutterBluetoothSerial.instance.getBondedDevices();
      if (mounted) {
        setState(() {
          _devices.clear();
          _devices.addAll(bonded);
          _loadingDevices = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingDevices = false);
    }
  }

  Future<void> _scanDevices() async {
    if (_scanning) return;
    setState(() => _scanning = true);

    try {
      _discoverySub = FlutterBluetoothSerial.instance.startDiscovery().listen((result) {
        if (mounted) {
          setState(() {
            if (!_devices.any((d) => d.address == result.device.address)) {
              _devices.add(result.device);
            }
          });
        }
      });

      await Future.delayed(const Duration(seconds: 6));
      await FlutterBluetoothSerial.instance.cancelDiscovery();

      final bonded = await FlutterBluetoothSerial.instance.getBondedDevices();
      if (mounted) {
        for (final d in bonded) {
          if (!_devices.any((ad) => ad.address == d.address)) {
            _devices.add(d);
          }
        }
      }
    } catch (_) {}

    if (mounted) setState(() => _scanning = false);
  }

  @override
  Widget build(BuildContext context) {
    final obd2 = ref.watch(obd2Provider);
    final sensors = obd2.sensorData;

    if (obd2.connectionState != Obd2ConnectionState.connected) {
      return _buildConnectScreen(obd2);
    }

    final rpmFraction = (sensors.rpm / 8000.0).clamp(0.0, 1.0);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dashboard', style: Theme.of(context).textTheme.headlineLarge)
                          .animate().fadeIn(duration: 400.ms).slideX(begin: -0.1, end: 0, duration: 400.ms),
                      const SizedBox(height: 4),
                      Text('Datos en tiempo real', style: Theme.of(context).textTheme.bodyMedium)
                          .animate().fadeIn(duration: 400.ms, delay: 200.ms),
                    ],
                  ),
                  GlassCard(
                    width: 52, height: 52, borderRadius: 16, blur: 8, borderWidth: 1, padding: const EdgeInsets.all(0),
                    gradientColors: [AppTheme.successColor.withValues(alpha: 0.3), AppTheme.successColor.withValues(alpha: 0.1)],
                    child: Center(child: Icon(Icons.bluetooth_connected, color: AppTheme.successColor, size: 28)),
                  ).animate().scale(duration: 500.ms, curve: Curves.elasticOut, delay: 350.ms),
                ],
              ),
              const SizedBox(height: 16),

              GlassCard(
                width: double.infinity, height: 80, borderRadius: 20, blur: 12, borderWidth: 1, padding: const EdgeInsets.all(16),
                gradientColors: [Colors.white.withValues(alpha: 0.1), Colors.white.withValues(alpha: 0.03)],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('RPM', style: Theme.of(context).textTheme.titleMedium),
                        Text('${sensors.rpm}', style: TextStyle(color: AppTheme.accentColor, fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LiquidBar(progress: rpmFraction, height: 6, colors: const [Color(0xFF6C63FF), Color(0xFF00D9FF)]),
                  ],
                ),
              ).animate().fadeIn(duration: 500.ms, delay: 200.ms).slideY(begin: 0.2, end: 0, duration: 500.ms, delay: 200.ms),

              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: _buildSensorCard(context, 'Velocidad', '${sensors.speed} km/h', Icons.speed, AppTheme.accentColor, 300)),
                const SizedBox(width: 10),
                Expanded(child: _buildSensorCard(context, 'Temp. Motor', sensors.coolantTemp, Icons.thermostat, AppTheme.secondaryColor, 350)),
                const SizedBox(width: 10),
                Expanded(child: _buildSensorCard(context, 'Carga', sensors.engineLoad, Icons.power, AppTheme.warningColor, 400)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _buildSensorCard(context, 'Acelerador', sensors.throttle, Icons.tune, AppTheme.primaryColor, 420)),
                const SizedBox(width: 10),
                Expanded(child: _buildSensorCard(context, 'MAP', sensors.map, Icons.air, AppTheme.accentColor, 440)),
                const SizedBox(width: 10),
                Expanded(child: _buildSensorCard(context, 'IAT', sensors.iat, Icons.ac_unit, const Color(0xFF4ECDC4), 460)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _buildSensorCard(context, 'MAF', sensors.maf, Icons.wind_power, const Color(0xFFE040FB), 480)),
                const SizedBox(width: 10),
                Expanded(child: _buildSensorCard(context, 'Combustible', sensors.fuelLevel, Icons.local_gas_station, AppTheme.successColor, 500)),
                const SizedBox(width: 10),
                Expanded(child: _buildSensorCard(context, 'Baro', sensors.baro, Icons.compress, Colors.grey, 520)),
              ]),
              const SizedBox(height: 16),
              Text('Fuel Trim', style: Theme.of(context).textTheme.titleLarge)
                  .animate().fadeIn(duration: 400.ms, delay: 540.ms),
              const SizedBox(height: 8),
              _buildFuelTrimRow(context, sensors, 560),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectScreen(Obd2State obd2) {
    final connecting = obd2.connectionState == Obd2ConnectionState.connecting;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 40, 20, 16),
          child: Column(
            children: [
              const Spacer(flex: 1),
              GlassCard(
                width: 100, height: 100, borderRadius: 30, blur: 10, borderWidth: 1,
                gradientColors: [AppTheme.primaryColor.withValues(alpha: 0.3), AppTheme.secondaryColor.withValues(alpha: 0.1)],
                padding: const EdgeInsets.all(0),
                child: Center(child: Icon(Icons.bluetooth_searching, color: Colors.white, size: 48)),
              ).animate().scale(duration: 600.ms, curve: Curves.elasticOut).fadeIn(duration: 500.ms),
              const SizedBox(height: 32),
              Text('Conectar ELM327', style: Theme.of(context).textTheme.headlineLarge)
                  .animate().fadeIn(duration: 600.ms, delay: 200.ms).slideY(begin: 0.3, end: 0, duration: 600.ms),
              const SizedBox(height: 8),
              Text('Selecciona tu dispositivo OBD2 Bluetooth', style: Theme.of(context).textTheme.bodyMedium)
                  .animate().fadeIn(duration: 600.ms, delay: 300.ms),
              const SizedBox(height: 24),

              Expanded(
                child: _loadingDevices
                    ? const Center(child: CircularProgressIndicator())
                    : _devices.isEmpty && !_scanning
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.bluetooth_disabled, size: 48, color: Colors.white38),
                                const SizedBox(height: 16),
                                Text('No hay dispositivos', style: TextStyle(color: Colors.white54)),
                                const SizedBox(height: 8),
                                Text('Presiona "Escanear" para buscar', style: TextStyle(color: Colors.white38, fontSize: 12)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _scanning ? _devices.length + 1 : _devices.length,
                            itemBuilder: (ctx, i) {
                              if (_scanning && i == _devices.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                );
                              }
                              final device = _devices[i];
                              final selected = _selectedDevice?.address == device.address;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: GlassCard(
                                  borderRadius: 16, blur: 8, borderWidth: 1,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  gradientColors: selected
                                      ? [AppTheme.primaryColor.withValues(alpha: 0.3), AppTheme.primaryColor.withValues(alpha: 0.1)]
                                      : [Colors.white.withValues(alpha: 0.1), Colors.white.withValues(alpha: 0.03)],
                                  child: ListTile(
                                    leading: Icon(Icons.bluetooth, color: selected ? AppTheme.primaryColor : Colors.white54),
                                    title: Text(
                                      (device.name?.isNotEmpty == true) ? device.name! : 'Sin nombre',
                                      style: TextStyle(color: Colors.white, fontSize: 14),
                                    ),
                                    subtitle: Row(
                                      children: [
                                        Text(device.address, style: TextStyle(color: Colors.white38, fontSize: 11)),
                                        if (device.isBonded) ...[
                                          const SizedBox(width: 6),
                                          Icon(Icons.link, size: 12, color: Colors.white38),
                                          Text(' emparejado', style: TextStyle(color: Colors.white38, fontSize: 11)),
                                        ],
                                      ],
                                    ),
                                    trailing: selected
                                        ? Icon(Icons.check_circle, color: AppTheme.accentColor, size: 20)
                                        : null,
                                    onTap: () => setState(() => _selectedDevice = device),
                                  ),
                                ),
                              );
                            },
                          ),
              ),

              if (obd2.error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(obd2.error, style: TextStyle(color: AppTheme.errorColor, fontSize: 13)),
                ),

              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      label: _scanning ? 'Buscando...' : 'Escanear',
                      icon: _scanning ? null : Icons.refresh,
                      onTap: _scanning ? null : _scanDevices,
                      backgroundColor: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassButton(
                      label: connecting ? 'Conectando...' : 'Conectar',
                      icon: Icons.link,
                      onTap: (connecting || _selectedDevice == null) ? null : () {
                        ref.read(obd2Provider.notifier).connect(_selectedDevice!);
                      },
                      backgroundColor: AppTheme.accentColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSensorCard(BuildContext context, String label, String value, IconData icon, Color color, int delay) {
    return GlassCard(
      borderRadius: 16, blur: 8, borderWidth: 1,
      padding: const EdgeInsets.all(12),
      gradientColors: [color.withValues(alpha: 0.1), Colors.white.withValues(alpha: 0.03)],
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: delay.ms).slideY(begin: 0.1, end: 0, duration: 400.ms);
  }

  Widget _buildFuelTrimRow(BuildContext context, Obd2SensorData sensors, int delay) {
    return GlassCard(
      borderRadius: 16, blur: 8, borderWidth: 1,
      padding: const EdgeInsets.all(12),
      gradientColors: [Colors.white.withValues(alpha: 0.08), Colors.white.withValues(alpha: 0.02)],
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _buildFuelTrimChip('STFT B1', sensors.stft1, AppTheme.warningColor),
            _buildFuelTrimChip('LTFT B1', sensors.ltft1, const Color(0xFFE040FB)),
          ]),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _buildFuelTrimChip('STFT B2', sensors.stft2, AppTheme.secondaryColor),
            _buildFuelTrimChip('LTFT B2', sensors.ltft2, AppTheme.primaryColor),
          ]),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: delay.ms);
  }

  Widget _buildFuelTrimChip(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.white38, fontSize: 10)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
