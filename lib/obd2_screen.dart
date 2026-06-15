import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import 'obd2_elm327.dart';

class Obd2Screen extends StatefulWidget {
  const Obd2Screen({super.key});

  @override
  State<Obd2Screen> createState() => _Obd2ScreenState();
}

class _Obd2ScreenState extends State<Obd2Screen> with WidgetsBindingObserver {
  final Obd2Elm327 _obd = Obd2Elm327();
  bool _connecting = false;
  bool _connected = false;
  int _currentTab = 0;

  List<BluetoothDevice> _availableDevices = [];
  BluetoothDevice? _selectedDevice;
  bool _scanning = false;
  StreamSubscription<BluetoothDiscoveryResult>? _discoverySub;

  String _rpm = "--";
  String _speed = "--";
  String _coolantTemp = "--";
  String _engineLoad = "--";
  String _throttle = "--";
  String _map = "--";
  String _iat = "--";
  String _timing = "--";
  String _maf = "--";
  String _fuelLevel = "--";
  String _baro = "--";
  String _stft1 = "--";
  String _ltft1 = "--";
  String _stft2 = "--";
  String _ltft2 = "--";

  List<DTCCode> _dtcs = [];
  String _protocol = "";
  String _vin = "";
  bool _mil = false;
  String _log = "";

  Timer? _refreshTimer;
  final TextEditingController _commandController = TextEditingController();
  StreamSubscription<String>? _responseSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestPermissions();
    _loadPairedDevices();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _responseSub?.cancel();
    _commandController.dispose();
    _obd.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel();
    } else if (state == AppLifecycleState.resumed && _connected) {
      _startAutoRefresh();
    }
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();
  }

  Future<void> _loadPairedDevices() async {
    try {
      if (!mounted) return;
      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      if (mounted) {
        setState(() {
          _availableDevices = devices;
        });
      }
    } catch (_) {}
  }

  Future<void> _scanDevices() async {
    if (_scanning) return;
    setState(() => _scanning = true);

    try {
      _discoverySub =
          FlutterBluetoothSerial.instance.startDiscovery().listen((result) {
        if (mounted) {
          setState(() {
            if (!_availableDevices.any((d) => d.address == result.device.address)) {
              _availableDevices.add(result.device);
            }
          });
        }
      });

      await Future.delayed(const Duration(seconds: 6));
      await FlutterBluetoothSerial.instance.cancelDiscovery();

      final bonded = await FlutterBluetoothSerial.instance.getBondedDevices();
      for (final d in bonded) {
        if (!_availableDevices.any((ad) => ad.address == d.address)) {
          _availableDevices.add(d);
        }
      }

      if (mounted) {
        setState(() => _scanning = false);
      }
    } catch (e) {
      if (mounted) setState(() => _scanning = false);
    } finally {
      await _discoverySub?.cancel();
      _discoverySub = null;
    }
  }

  Future<void> _connect() async {
    if (_selectedDevice == null) return;
    setState(() {
      _connecting = true;
      final name = _selectedDevice!.name ?? _selectedDevice!.address;
      _log = "Iniciando conexión a $name...\n"
          "─────────────────────────────────\n";
    });

    // Escuchar respuestas del ELM327 en tiempo real
    _responseSub?.cancel();
    _responseSub = _obd.responseStream.listen((data) {
      if (mounted) setState(() => _log += "$data");
    });

    // Intentar conectar (con timeout y logging detallado)
    final success = await _obd.connect(_selectedDevice!.address);

    if (!mounted) return;
    setState(() {
      _connecting = false;
      _connected = success;
      _log += success
          ? "\n✅ CONECTADO\n"
          : "\n❌ FALLO CONEXIÓN\n";
    });

    if (success) {
      _startAutoRefresh();
      _loadVehicleInfo();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ Conectado al ELM327"),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      // Mostrar error visible al usuario
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("❌ Falló la conexión. Revisa la Terminal para más detalles."),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: "Ver Terminal",
            textColor: Colors.white,
            onPressed: () => _showTerminalDialog(context),
          ),
        ),
      );
    }
  }

  /// Muestra un diálogo con los logs completos (útil cuando no se está conectado)
  void _showTerminalDialog(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.terminal, size: 20),
            SizedBox(width: 8),
            Text("Terminal - Logs"),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            reverse: true,
            child: SelectableText(
              _log,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text("Cerrar"),
          ),
        ],
      ),
    );
  }

  Future<void> _disconnect() async {
    _refreshTimer?.cancel();
    await _responseSub?.cancel();
    await _obd.disconnect();
    if (mounted) {
      setState(() {
        _connected = false;
        _log += "Desconectado\n";
      });
    }
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshSensors();
    });
  }

  Future<void> _refreshSensors() async {
    if (!mounted || !_connected) return;
    try {
      final rpm = await _obd.getRpm();
      if (mounted) setState(() => _rpm = rpm.toString());
    } catch (_) {}
    try {
      final speed = await _obd.getSpeed();
      if (mounted) setState(() => _speed = speed.toString());
    } catch (_) {}
    try {
      final temp = await _obd.getCoolantTemp();
      if (mounted) setState(() => _coolantTemp = "$temp°C");
    } catch (_) {}
    try {
      final load = await _obd.getEngineLoad();
      if (mounted) setState(() => _engineLoad = "$load%");
    } catch (_) {}
    try {
      final tps = await _obd.getThrottlePosition();
      if (mounted) setState(() => _throttle = "${tps.toStringAsFixed(1)}%");
    } catch (_) {}
    try {
      final map = await _obd.getIntakePressure();
      if (mounted) setState(() => _map = "${map}kPa");
    } catch (_) {}
    try {
      final iat = await _obd.getIntakeTemp();
      if (mounted) setState(() => _iat = "$iat°C");
    } catch (_) {}
    try {
      final timing = await _obd.getTimingAdvance();
      if (mounted) {
        setState(() => _timing = "${timing.toStringAsFixed(1)}°");
      }
    } catch (_) {}
    try {
      final maf = await _obd.getMAF();
      if (mounted) setState(() => _maf = "${maf.toStringAsFixed(2)} g/s");
    } catch (_) {}
    try {
      final fuel = await _obd.getFuelLevel();
      if (mounted) setState(() => _fuelLevel = "${fuel.toStringAsFixed(0)}%");
    } catch (_) {}
    try {
      final baro = await _obd.getBarometricPressure();
      if (mounted) setState(() => _baro = "${baro}kPa");
    } catch (_) {}
    try {
      final stft1 = await _obd.getShortTermTrimBank1();
      if (mounted) {
        setState(() =>
            _stft1 = "${stft1.toStringAsFixed(1)}%");
      }
    } catch (_) {}
    try {
      final ltft1 = await _obd.getLongTermTrimBank1();
      if (mounted) {
        setState(() =>
            _ltft1 = "${ltft1.toStringAsFixed(1)}%");
      }
    } catch (_) {}
    try {
      final stft2 = await _obd.getShortTermTrimBank2();
      if (mounted) {
        setState(() =>
            _stft2 = "${stft2.toStringAsFixed(1)}%");
      }
    } catch (_) {}
    try {
      final ltft2 = await _obd.getLongTermTrimBank2();
      if (mounted) {
        setState(() =>
            _ltft2 = "${ltft2.toStringAsFixed(1)}%");
      }
    } catch (_) {}
  }

  Future<void> _loadVehicleInfo() async {
    try {
      final protocol = await _obd.getProtocol();
      if (mounted) setState(() => _protocol = protocol);
    } catch (_) {}
    try {
      final mil = await _obd.isMILActive();
      if (mounted) setState(() => _mil = mil);
    } catch (_) {}
    try {
      final vin = await _obd.getVIN();
      if (mounted) setState(() => _vin = vin);
    } catch (_) {}
  }

  Future<void> _loadDTCs() async {
    if (!_connected) return;
    try {
      final dtcs = await _obd.getDTCs();
      if (mounted) setState(() => _dtcs = dtcs);
    } catch (_) {}
  }

  Future<void> _clearDTCs() async {
    if (!_connected) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Borrar DTCs"),
        content: const Text("¿Está seguro de borrar todos los códigos de error?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Borrar")),
        ],
      ),
    );
    if (confirm == true) {
      final ok = await _obd.clearDTCs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? "DTCs borrados" : "Error al borrar DTCs")),
        );
        await _loadDTCs();
      }
    }
  }

  Future<void> _sendCustomCommand() async {
    final cmd = _commandController.text.trim();
    if (cmd.isEmpty) return;
    try {
      await _obd.sendCommand(cmd);
      if (mounted) {
        setState(() => _log += "📤 $cmd\n");
        _commandController.clear();
      }
    } catch (e) {
      if (mounted) setState(() => _log += "Error: $e\n");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_connected ? "OBD2 - ${_selectedDevice?.name ?? ""}" : "OBD2 Scanner"),
        actions: [
          if (_connected)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshSensors,
            ),
        ],
      ),
      body: _connected ? _buildMainBody() : _buildConnectScreen(),
      bottomNavigationBar: _connected
          ? NavigationBar(
              selectedIndex: _currentTab,
              onDestinationSelected: (i) {
                setState(() => _currentTab = i);
                if (i == 1) _loadDTCs();
              },
              destinations: const [
                NavigationDestination(icon: Icon(Icons.dashboard), label: "Dashboard"),
                NavigationDestination(icon: Icon(Icons.error_outline), label: "DTCs"),
                NavigationDestination(icon: Icon(Icons.terminal), label: "Terminal"),
                NavigationDestination(icon: Icon(Icons.info_outline), label: "Info"),
              ],
            )
          : null,
    );
  }

  Widget _buildConnectScreen() {
    final hasRecentLogs = _log.contains("FALLO") || _log.contains("CONECTADO");
    final logLines = _log.split("\n").where((l) => l.isNotEmpty).toList();
    final lastLogLines = logLines.length > 4
        ? logLines.sublist(logLines.length - 4)
        : logLines;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          const SizedBox(height: 12),
          const Icon(Icons.bluetooth_searching, size: 56, color: Colors.blue),
          const SizedBox(height: 8),
          const Text("Conectar ELM327", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text("Selecciona tu dispositivo ELM327 de la lista:",
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 10),
          // Lista de dispositivos con altura limitada
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: _availableDevices.isEmpty
                ? Center(
                    child: _scanning
                        ? const CircularProgressIndicator()
                        : const Text("Presiona 'Escanear' para buscar dispositivos",
                            style: TextStyle(fontSize: 13)),
                  )
                : ListView.builder(
                    itemCount: _availableDevices.length,
                    itemBuilder: (ctx, i) {
                      final device = _availableDevices[i];
                      final selected = _selectedDevice?.address == device.address;
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        color: selected ? Colors.blue.shade50 : null,
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.bluetooth, size: 20),
                          title: Text(
                            (device.name != null && device.name!.isNotEmpty) ? device.name! : "Sin nombre",
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Row(
                            children: [
                              Text(device.address, style: const TextStyle(fontSize: 11)),
                              if (device.isBonded) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.link, size: 12, color: Colors.grey),
                                const Text(" emparejado", style: TextStyle(fontSize: 11)),
                              ],
                            ],
                          ),
                          trailing: selected
                              ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                              : null,
                          onTap: () => setState(() => _selectedDevice = device),
                        ),
                      );
                    },
                  ),
          ),
          // Botones (justo debajo de la lista)
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _scanning ? null : _scanDevices,
                  icon: _scanning
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh, size: 18),
                  label: Text(_scanning ? "Escaneando..." : "Escanear"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_selectedDevice == null || _connecting) ? null : _connect,
                  icon: _connecting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.link, size: 18),
                  label: Text(_connecting ? "Conectando..." : "Conectar"),
                ),
              ),
            ],
          ),
          // Preview de logs recientes (abajo de los botones)
          if (hasRecentLogs) ...[
            const SizedBox(height: 6),
            _buildLogPreviewCardCompact(lastLogLines),
          ],
        ],
      ),
    );
  }

  Widget _buildLogPreviewCardCompact(List<String> lines) {
    return Card(
      clipBehavior: Clip.antiAlias,
      color: _log.contains("FALLO") ? Colors.red.shade50 : Colors.green.shade50,
      child: InkWell(
        onTap: () => _showTerminalDialog(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    _log.contains("FALLO") ? Icons.error_outline : Icons.check_circle,
                    size: 16,
                    color: _log.contains("FALLO") ? Colors.red : Colors.green,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _log.contains("FALLO") ? "Error de conexión" : "Conexión exitosa",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _log.contains("FALLO") ? Colors.red.shade700 : Colors.green.shade700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    "Ver detalles >",
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Últimas líneas del log
              ...lines.map((line) => Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  line.length > 55 ? "${line.substring(0, 55)}..." : line,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: line.contains("✗") || line.contains("Error") || line.contains("FALLO")
                        ? Colors.red.shade700
                        : line.contains("✓") || line.contains("CONECTADO")
                            ? Colors.green.shade700
                            : Colors.grey.shade600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainBody() {
    switch (_currentTab) {
      case 0:
        return _buildDashboard();
      case 1:
        return _buildDTCTab();
      case 2:
        return _buildTerminal();
      case 3:
        return _buildInfoTab();
      default:
        return _buildDashboard();
    }
  }

  Widget _buildDashboard() {
    return RefreshIndicator(
      onRefresh: _refreshSensors,
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          _buildConnectionBar(),
          const SizedBox(height: 8),
          _buildLogPreviewCard(),
          const SizedBox(height: 8),
          _buildSensorGrid(),
        ],
      ),
    );
  }

  Widget _buildLogPreviewCard() {
    // Mostrar últimas líneas del log, o un mensaje si está vacío
    final previewLines = _log.isNotEmpty
        ? _log.split("\n").where((l) => l.isNotEmpty).toList()
        : <String>[];
    final lastLines = previewLines.length > 4
        ? previewLines.sublist(previewLines.length - 4)
        : previewLines;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _currentTab = 2),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Preview de logs
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.terminal, size: 16, color: Colors.grey.shade700),
                        const SizedBox(width: 6),
                        Text(
                          "Terminal",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                    if (lastLines.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _connected
                              ? "Esperando datos..."
                              : "Conéctate al ELM327 para ver los logs",
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                      )
                    else ...lastLines.map((line) => Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        line.length > 60 ? "${line.substring(0, 60)}..." : line,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: line.contains("✗") ||
                                      line.contains("Error") ||
                                      line.contains("Falló")
                              ? Colors.red.shade700
                              : line.contains("✓")
                                  ? Colors.green.shade700
                                  : Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )),
                  ],
                ),
              ),
              // Flecha para ir a Terminal
              Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionBar() {
    return Card(
      color: _connected ? Colors.green.shade50 : Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Icon(Icons.bluetooth_connected, color: _connected ? Colors.green : Colors.red),
            const SizedBox(width: 8),
            Text(_connected
                ? "Conectado a ${_selectedDevice?.name ?? ""}"
                : "Desconectado"),
            const Spacer(),
            if (_connected)
              TextButton(
                onPressed: _disconnect,
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text("Desconectar"),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.6,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        _sensorCard("RPM", _rpm, Icons.speed, Colors.red),
        _sensorCard("Velocidad", "$_speed km/h", Icons.directions_car, Colors.blue),
        _sensorCard("Temp. Motor", _coolantTemp, Icons.thermostat, Colors.orange),
        _sensorCard("Carga Motor", _engineLoad, Icons.power, Colors.purple),
        _sensorCard("Acelerador", _throttle, Icons.tune, Colors.teal),
        _sensorCard("MAP", _map, Icons.air, Colors.cyan),
        _sensorCard("IAT", _iat, Icons.ac_unit, Colors.lightBlue),
        _sensorCard("Avance", _timing, Icons.timer, Colors.brown),
        _sensorCard("MAF", _maf, Icons.wind_power, Colors.indigo),
        _sensorCard("Combustible", _fuelLevel, Icons.local_gas_station, Colors.green),
        _sensorCard("Baro", _baro, Icons.compress, Colors.grey),
        _sensorCard("STFT B1", _stft1, Icons.balance, Colors.amber),
        _sensorCard("LTFT B1", _ltft1, Icons.balance, Colors.deepOrange),
        _sensorCard("STFT B2", _stft2, Icons.balance, Colors.lime),
        _sensorCard("LTFT B2", _ltft2, Icons.balance, Colors.pink),
      ],
    );
  }

  Widget _sensorCard(String label, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDTCTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: _loadDTCs,
                icon: const Icon(Icons.refresh),
                label: const Text("Leer DTCs"),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _clearDTCs,
                icon: const Icon(Icons.delete),
                label: const Text("Borrar"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              ),
            ],
          ),
        ),
        Expanded(
          child: _dtcs.isEmpty
              ? const Center(child: Text("Presiona 'Leer DTCs' para buscar códigos"))
              : ListView.builder(
                  itemCount: _dtcs.length,
                  itemBuilder: (ctx, i) {
                    final dtc = _dtcs[i];
                    final isError = dtc.code != "NONE";
                    return Card(
                      color: isError ? Colors.red.shade50 : Colors.green.shade50,
                      child: ListTile(
                        leading: Icon(
                          isError ? Icons.error : Icons.check_circle,
                          color: isError ? Colors.red : Colors.green,
                        ),
                        title: Text(dtc.code),
                        subtitle: Text(dtc.description),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTerminal() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commandController,
                  decoration: const InputDecoration(
                    labelText: "Comando OBD (ej: 010C, ATZ)",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _sendCustomCommand(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _sendCustomCommand,
                child: const Text("Enviar"),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              reverse: true,
              padding: const EdgeInsets.all(8),
              child: SelectableText(
                _log,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Información del Vehículo",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Divider(),
                _infoRow("Protocolo", _protocol),
                _infoRow("VIN", _vin),
                _infoRow("MIL", _mil ? "ACTIVA ⚠️" : "Inactiva ✓"),
                _infoRow("Dispositivo", _selectedDevice?.name ?? ""),
                _infoRow("MAC", _selectedDevice?.address ?? ""),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Sensores de Oxígeno",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Divider(),
                FutureBuilder<List<OxygenSensor>>(
                  future: _obd.getOxygenSensors(),
                  builder: (ctx, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError || !snap.hasData || snap.data!.isEmpty) {
                      return const Text("No se detectaron sensores O2");
                    }
                    return Column(
                      children: snap.data!.map((s) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Text("B${s.bank}S${s.sensor}: "),
                              Text("${s.voltage.toStringAsFixed(3)}V",
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text(" / ${s.shortTermTrim.toStringAsFixed(1)}%"),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text("$label:", style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(value.isEmpty ? "--" : value)),
        ],
      ),
    );
  }
}
