import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/obd2_provider.dart';
import '../widgets/glassmorphism_widget.dart';
import '../widgets/liquid_bar.dart';

const _kPrefFavoriteDevice = 'favorite_device_mac';
const _kPrefPermissionRequested = 'permission_location_requested';

class Obd2DashboardScreen extends ConsumerStatefulWidget {
  const Obd2DashboardScreen({super.key});

  @override
  ConsumerState<Obd2DashboardScreen> createState() => _Obd2DashboardScreenState();
}

class _Obd2DashboardScreenState extends ConsumerState<Obd2DashboardScreen> {
  final List<BluetoothDevice> _devices = [];
  BluetoothDevice? _selectedDevice;
  String? _favoriteMac;
  bool _scanning = false;
  bool _loadingDevices = true;
  StreamSubscription<BluetoothDiscoveryResult>? _discoverySub;

  // Expanded sensor overlay state
  String? _expandedKey;
  String? _expandedLabel;
  IconData? _expandedIcon;
  Color? _expandedColor;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _discoverySub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    await _requestPermissionsIfNeeded();
    await _loadFavorite();
    await _loadBondedDevices();
  }

  Future<void> _requestPermissionsIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyRequested = prefs.getBool(_kPrefPermissionRequested) ?? false;

    if (alreadyRequested) {
      // Ya pidió antes — solo verificar que siga concedido, no volver a preguntar
      return;
    }

    // Primera vez: pedir permisos necesarios
    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();

    // Para ubicación solo pedir si no está concedido aún (Android <12)
    final locationStatus = await Permission.location.status;
    if (!locationStatus.isGranted && !locationStatus.isPermanentlyDenied) {
      await Permission.location.request();
    }

    // Marcar que ya se pidió
    await prefs.setBool(_kPrefPermissionRequested, true);
  }

  Future<void> _loadFavorite() async {
    final prefs = await SharedPreferences.getInstance();
    _favoriteMac = prefs.getString(_kPrefFavoriteDevice);
  }

  Future<void> _saveFavorite(String mac) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefFavoriteDevice, mac);
    setState(() => _favoriteMac = mac);
  }

  Future<void> _clearFavorite() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefFavoriteDevice);
    setState(() => _favoriteMac = null);
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
        _sortDevices();
        _autoSelectFavorite();
      }
    } catch (_) {
      if (mounted) setState(() => _loadingDevices = false);
    }
  }

  void _sortDevices() {
    if (_favoriteMac == null || _devices.isEmpty) return;
    _devices.sort((a, b) {
      if (a.address == _favoriteMac) return -1;
      if (b.address == _favoriteMac) return 1;
      return 0;
    });
  }

  void _autoSelectFavorite() {
    if (_favoriteMac == null) return;
    final fav = _devices.where((d) => d.address == _favoriteMac).firstOrNull;
    if (fav != null && _selectedDevice == null) {
      setState(() => _selectedDevice = fav);
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
        _sortDevices();
        _autoSelectFavorite();
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

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
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

                  _buildRpmCard(context, sensors, 200),

                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: _buildSensorCard(context, 'speed', 'Velocidad', '${sensors.speed} km/h', Icons.speed, AppTheme.accentColor, 300)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildSensorCard(context, 'coolantTemp', 'Temp. Motor', sensors.coolantTemp, Icons.thermostat, AppTheme.secondaryColor, 350)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildSensorCard(context, 'engineLoad', 'Carga', sensors.engineLoad, Icons.power, AppTheme.warningColor, 400)),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _buildSensorCard(context, 'throttle', 'Acelerador', sensors.throttle, Icons.tune, AppTheme.primaryColor, 420)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildSensorCard(context, 'map', 'MAP', sensors.map, Icons.air, AppTheme.accentColor, 440)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildSensorCard(context, 'iat', 'IAT', sensors.iat, Icons.ac_unit, const Color(0xFF4ECDC4), 460)),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _buildSensorCard(context, 'maf', 'MAF', sensors.maf, Icons.wind_power, const Color(0xFFE040FB), 480)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildSensorCard(context, 'fuelLevel', 'Combustible', sensors.fuelLevel, Icons.local_gas_station, AppTheme.successColor, 500)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildSensorCard(context, 'baro', 'Baro', sensors.baro, Icons.compress, Colors.grey, 520)),
                  ]),
                  const SizedBox(height: 16),
                  Text('Fuel Trim', style: Theme.of(context).textTheme.titleLarge)
                      .animate().fadeIn(duration: 400.ms, delay: 540.ms),
                  const SizedBox(height: 8),
                  _buildFuelTrimRow(context, sensors, 560),
                  const SizedBox(height: 20),
                  if (sensors.o2Voltages.isNotEmpty) ...[
                    Text('Sensores O2', style: Theme.of(context).textTheme.titleLarge)
                        .animate().fadeIn(duration: 400.ms, delay: 600.ms),
                    const SizedBox(height: 8),
                    _buildO2Grid(context, sensors.o2Voltages, 620),
                    const SizedBox(height: 20),
                  ],
                ],
              ),
            ),
            if (_expandedLabel != null) _buildExpandedOverlay(sensors),
          ],
        ),
      ),
    );
  }

  Widget _buildRpmCard(BuildContext context, Obd2SensorData sensors, int delay) {
    final rpmFraction = (sensors.rpm / 8000.0).clamp(0.0, 1.0);
    return GestureDetector(
      onTap: () => _showExpanded('rpm', 'RPM', Icons.speed, AppTheme.accentColor),
      child: GlassCard(
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
      ),
    ).animate().fadeIn(duration: 500.ms, delay: delay.ms).slideY(begin: 0.2, end: 0, duration: 500.ms, delay: delay.ms);
  }

  void _showExpanded(String key, String label, IconData icon, Color color) {
    setState(() {
      _expandedKey = key;
      _expandedLabel = label;
      _expandedIcon = icon;
      _expandedColor = color;
    });
  }

  void _dismissExpanded() {
    setState(() {
      _expandedKey = null;
      _expandedLabel = null;
      _expandedIcon = null;
      _expandedColor = null;
    });
  }

  String _liveValue(String key, Obd2SensorData s) {
    switch (key) {
      case 'rpm': return '${s.rpm}';
      case 'speed': return '${s.speed} km/h';
      case 'coolantTemp': return s.coolantTemp;
      case 'engineLoad': return s.engineLoad;
      case 'throttle': return s.throttle;
      case 'map': return s.map;
      case 'iat': return s.iat;
      case 'maf': return s.maf;
      case 'fuelLevel': return s.fuelLevel;
      case 'baro': return s.baro;
      case 'timing': return s.timing;
      case 'stft1': return s.stft1;
      case 'ltft1': return s.ltft1;
      case 'stft2': return s.stft2;
      case 'ltft2': return s.ltft2;
      default: return '--';
    }
  }

  Widget _buildExpandedOverlay(Obd2SensorData sensors) {
    final value = _expandedKey != null ? _liveValue(_expandedKey!, sensors) : '--';
    return GestureDetector(
      onTap: _dismissExpanded,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        color: Colors.black87,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_expandedIcon, color: _expandedColor, size: 64),
              const SizedBox(height: 20),
              Text(_expandedLabel!, style: TextStyle(color: Colors.white54, fontSize: 20, fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              Text(value, style: TextStyle(color: _expandedColor, fontSize: 56, fontWeight: FontWeight.bold)),
              const SizedBox(height: 32),
              Text('Toca para cerrar', style: TextStyle(color: Colors.white24, fontSize: 13)),
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
              const SizedBox(height: 4),
              Text('v2.3.1', style: TextStyle(color: Colors.white24, fontSize: 12))
                  .animate().fadeIn(duration: 600.ms, delay: 250.ms),
              const SizedBox(height: 4),
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
                              final isFav = device.address == _favoriteMac;
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
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            (device.name?.isNotEmpty == true) ? device.name! : 'Sin nombre',
                                            style: TextStyle(color: Colors.white, fontSize: 14),
                                          ),
                                        ),
                                        if (isFav)
                                          Icon(Icons.star, color: Colors.amber, size: 18),
                                      ],
                                    ),
                                    subtitle: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            device.address,
                                            style: TextStyle(color: Colors.white38, fontSize: 11),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (device.isBonded) ...[
                                          const SizedBox(width: 6),
                                          Icon(Icons.link, size: 12, color: Colors.white38),
                                          Text(' emp', style: TextStyle(color: Colors.white38, fontSize: 11)),
                                        ],
                                      ],
                                    ),
                                    trailing: SizedBox(
                                      width: 72,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          GestureDetector(
                                            onTap: () {
                                              if (isFav) {
                                                _clearFavorite();
                                              } else {
                                                _saveFavorite(device.address);
                                              }
                                            },
                                            child: Icon(
                                              isFav ? Icons.star : Icons.star_border,
                                              color: isFav ? Colors.amber : Colors.white38,
                                              size: 20,
                                            ),
                                          ),
                                          if (selected) ...[
                                            const SizedBox(width: 4),
                                            Icon(Icons.check_circle, color: AppTheme.accentColor, size: 18),
                                          ],
                                        ],
                                      ),
                                    ),
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
                      onTap: (connecting || _selectedDevice == null) ? null : () async {
                        final device = _selectedDevice!;
                        await ref.read(obd2Provider.notifier).connect(device);
                        // Si la conexión fue exitosa, guardar como favorito
                        if (ref.read(obd2Provider).connectionState == Obd2ConnectionState.connected) {
                          await _saveFavorite(device.address);
                        }
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

  Widget _buildSensorCard(BuildContext context, String key, String label, String value, IconData icon, Color color, int delay) {
    return GestureDetector(
      onTap: () => _showExpanded(key, label, icon, color),
      child: GlassCard(
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

  Widget _buildO2Grid(BuildContext context, List<double> voltages, int delay) {
    final labels = ['B1S1', 'B1S2', 'B1S3', 'B1S4', 'B2S1', 'B2S2', 'B2S3', 'B2S4'];
    return GlassCard(
      borderRadius: 16, blur: 8, borderWidth: 1,
      padding: const EdgeInsets.all(12),
      gradientColors: [Colors.white.withValues(alpha: 0.08), Colors.white.withValues(alpha: 0.02)],
      child: Column(
        children: [
          for (int row = 0; row < 2; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (int col = 0; col < 4; col++)
                    _buildO2Chip(labels[row * 4 + col],
                        voltages[row * 4 + col], AppTheme.accentColor),
                ],
              ),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: delay.ms);
  }

  Widget _buildO2Chip(String label, double voltage, Color color) {
    final isNoData = voltage < 0;
    final display = isNoData ? '--' : '${voltage.toStringAsFixed(3)}V';
    final vColor = isNoData
        ? Colors.white24
        : (voltage < 0.1 ? Colors.red : (voltage > 0.9 ? Colors.amber : color));
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.white38, fontSize: 10)),
        const SizedBox(height: 2),
        Text(display, style: TextStyle(color: vColor, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
