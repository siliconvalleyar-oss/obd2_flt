import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart' as bt;
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as ble;
import 'package:permission_handler/permission_handler.dart';

abstract class Elm327Transport {
  Future<void> connect(String deviceId);
  Future<void> disconnect();
  Future<void> write(String command);
  Stream<String> get responseStream;
  bool get isConnected;
  void Function(String log)? onLog;
}

class ClassicSppTransport implements Elm327Transport {
  bt.BluetoothConnection? _connection;
  bool _isConnected = false;
  final StreamController<String> _responseController = StreamController<String>.broadcast();
  StreamSubscription<Uint8List>? _inputSubscription;

  @override
  Stream<String> get responseStream => _responseController.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  void Function(String log)? onLog;

  @override
  Future<void> connect(String targetMacAddress) async {
    onLog?.call('Verificando Bluetooth...\n');
    final isAvailable = await bt.FlutterBluetoothSerial.instance.isAvailable;
    if (isAvailable != true) {
      throw Exception('Bluetooth no soportado en este dispositivo.');
    }
    onLog?.call('✓ Bluetooth disponible\n');

    final isEnabled = await bt.FlutterBluetoothSerial.instance.isEnabled;
    if (isEnabled != true) {
      throw Exception('Bluetooth no encendido. Actívalo desde Ajustes.');
    }
    onLog?.call('✓ Bluetooth encendido\n');

    onLog?.call('Verificando permisos Bluetooth...\n');
    final btConnect = await Permission.bluetoothConnect.status;
    final btScan = await Permission.bluetoothScan.status;
    final location = await Permission.location.status;
    if (!btConnect.isGranted || !btScan.isGranted || !location.isGranted) {
      onLog?.call('Permisos Bluetooth incompletos. Se solicitarán de nuevo.\n');
      final results = await [
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.location,
      ].request();
      final allGranted = results.values.every((s) => s.isGranted);
      if (!allGranted) {
        throw Exception('Se necesitan permisos Bluetooth y ubicación para conectar.');
      }
    }
    onLog?.call('✓ Permisos Bluetooth OK\n');

    onLog?.call('Verificando dispositivos emparejados...\n');
    final bonded = await bt.FlutterBluetoothSerial.instance.getBondedDevices();
    final targetDevice = bonded.firstWhere(
      (d) => d.address == targetMacAddress,
      orElse: () => throw Exception(
          'Dispositivo no encontrado en emparejados. Empareja "$targetMacAddress" desde Ajustes Bluetooth.'),
    );
    onLog?.call('✓ Dispositivo encontrado: ${targetDevice.name ?? targetDevice.address}\n');

    onLog?.call('Verificando emparejamiento...\n');
    try {
      final bondState = await bt.FlutterBluetoothSerial.instance.getBondStateForAddress(targetMacAddress);
      if (!bondState.isBonded) {
        onLog?.call('Dispositivo no emparejado. Intentando emparejar...\n');
        onLog?.call('💡 Abrí Ajustes > Bluetooth y empareja "OBDII" con PIN 1234 o 0000.\n');
        final paired = await bt.FlutterBluetoothSerial.instance.bondDeviceAtAddress(targetMacAddress);
        if (paired != true) {
          onLog?.call('⚠️ No se pudo emparejar automáticamente. Hacelo manualmente desde Ajustes Bluetooth.\n');
        } else {
          onLog?.call('✓ Emparejado correctamente\n');
          await Future.delayed(const Duration(milliseconds: 2500));
        }
      } else {
        onLog?.call('✓ Dispositivo ya emparejado\n');
        await Future.delayed(const Duration(milliseconds: 2000));
      }
    } catch (e) {
      onLog?.call('⚠️ Error al verificar emparejamiento: $e\n');
    }

    onLog?.call('Conectando RFCOMM con $targetMacAddress...\n');
    const maxAttempts = 4;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        if (attempt > 1) {
          onLog?.call('Reintento $attempt de $maxAttempts...\n');
          await Future.delayed(const Duration(seconds: 3));
        }
        _connection = await bt.BluetoothConnection.toAddress(targetMacAddress)
            .timeout(const Duration(seconds: 25), onTimeout: () {
          throw Exception('Timeout al conectar (25s). Verifica que el ELM327 esté encendido y en modo SPP (no BLE).');
        });
        break;
      } catch (e) {
        if (attempt == maxAttempts) rethrow;
        onLog?.call('  Falló intento $attempt: $e\n');
        try { await _connection?.close(); } catch (_) {}
        _connection = null;
      }
    }

    _isConnected = true;
    onLog?.call('✓ Conexión RFCOMM establecida\n');

    // Iniciar listener ANTES de cualquier retardo para no perder datos
    _inputSubscription = _connection!.input!.listen(
      _onData,
      onError: (Object _) => _handleRemoteClose(),
      onDone: _handleRemoteClose,
    );

    // Wake-up: enviar \r\n vacío para "despertar" clones ELM327
    // que no responden al primer ATZ después de RFCOMM.
    await Future.delayed(const Duration(milliseconds: 500));
    for (int i = 0; i < 3; i++) {
      try {
        final conn = _connection;
        if (conn != null) {
          conn.output.add(Uint8List.fromList(utf8.encode('\r')));
          await conn.output.allSent;
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 150));
    }
    onLog?.call('✓ ELM327 wake-up enviado\n');
  }

  void _onData(Uint8List data) {
    final text = utf8.decode(data, allowMalformed: true);
    _responseController.add(text);
  }

  void _handleRemoteClose() {
    if (_isConnected) {
      _isConnected = false;
    }
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    await _inputSubscription?.cancel();
    _inputSubscription = null;
    try { await _connection?.close(); } catch (_) {}
    _connection = null;
  }

  @override
  Future<void> write(String command) async {
    final conn = _connection;
    if (conn == null) throw StateError('No conectado.');
    String cmd = command.trim();
    if (!cmd.endsWith('\r')) cmd += '\r';
    conn.output.add(Uint8List.fromList(utf8.encode(cmd)));
    await conn.output.allSent;
  }
}

class BleTransport implements Elm327Transport {
  final String deviceId;
  ble.BluetoothDevice? _device;
  ble.BluetoothCharacteristic? _writeChar;
  ble.BluetoothCharacteristic? _notifyChar;
  bool _isConnected = false;
  final StreamController<String> _responseController = StreamController<String>.broadcast();
  StreamSubscription<List<int>>? _notificationSub;

  static const _candidateServiceUuids = [
    '0000fff0-0000-1000-8000-00805f9b34fb',
    '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
  ];
  static const _candidateTxUuids = [
    '0000fff1-0000-1000-8000-00805f9b34fb',
    '6e400003-b5a3-f393-e0a9-e50e24dcca9e',
  ];
  static const _candidateRxUuids = [
    '0000fff2-0000-1000-8000-00805f9b34fb',
    '6e400002-b5a3-f393-e0a9-e50e24dcca9e',
  ];

  BleTransport({required this.deviceId});

  @override
  Stream<String> get responseStream => _responseController.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  void Function(String log)? onLog;

  @override
  Future<void> connect(String targetDeviceId) async {
    onLog?.call('Verificando BLE...\n');
    if (!await ble.FlutterBluePlus.isSupported) {
      throw Exception('BLE no soportado en este dispositivo.');
    }

    final state = await ble.FlutterBluePlus.adapterState.first;
    if (state != ble.BluetoothAdapterState.on) {
      onLog?.call('Activando Bluetooth...\n');
      await ble.FlutterBluePlus.turnOn();
      await Future.delayed(const Duration(seconds: 2));
    }

    onLog?.call('Verificando permisos BLE...\n');
    final btScan = await Permission.bluetoothScan.status;
    final btConnect = await Permission.bluetoothConnect.status;
    final location = await Permission.location.status;
    if (!btScan.isGranted || !btConnect.isGranted || !location.isGranted) {
      final results = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
      if (!results.values.every((s) => s.isGranted)) {
        throw Exception('Se necesitan permisos Bluetooth y ubicación para escanear BLE.');
      }
    }
    onLog?.call('✓ Permisos BLE OK\n');

    onLog?.call('Escaneando BLE para $targetDeviceId...\n');
    final device = await _findDeviceById(targetDeviceId);
    if (device == null) {
      throw Exception(
        'Dispositivo BLE no encontrado: $targetDeviceId.\n'
        'Verifica que esté encendido, en modo BLE, y dentro del alcance.\n'
        'Si persiste, verificá con nRF Connect los servicios GATT disponibles.'
      );
    }
    onLog?.call('✓ Dispositivo BLE encontrado: ${device.platformName}\n');

    onLog?.call('Conectando BLE...\n');
    await device.connect(license: ble.License.nonprofit);
    onLog?.call('✓ Conectado al dispositivo BLE\n');

    onLog?.call('Descubriendo servicios GATT...\n');
    final services = await device.discoverServices();
    onLog?.call('✓ ${services.length} servicios descubiertos\n');

    ble.BluetoothService? targetService;
    for (final service in services) {
      final serviceUuid = service.uuid.toString().toLowerCase();
      if (_candidateServiceUuids.contains(serviceUuid)) {
        targetService = service;
        break;
      }
    }

    if (targetService == null) {
      await device.disconnect();
      throw Exception(
        'No se encontraron servicios ELM327 conocidos.\n'
        'UUIDs buscados: ${_candidateServiceUuids.join(", ")}\n'
        'Usá nRF Connect para ver los servicios reales y pasámelos.'
      );
    }
    onLog?.call('✓ Servicio ELM327 encontrado: ${targetService.uuid.toString()}\n');

    for (final c in targetService.characteristics) {
      final uuid = c.uuid.toString().toLowerCase();
      if (_candidateRxUuids.contains(uuid) && (c.properties.write || c.properties.writeWithoutResponse)) {
        _writeChar = c;
      }
      if (_candidateTxUuids.contains(uuid) && c.properties.notify) {
        _notifyChar = c;
      }
    }

    if (_writeChar == null || _notifyChar == null) {
      await device.disconnect();
      throw Exception(
        'No se encontraron characteristics de escritura/notificación.\n'
        'Verificá con nRF Connect los UUIDs exactos.'
      );
    }
    onLog?.call('✓ Characteristics encontradas\n');

    await _notifyChar!.setNotifyValue(true);
    _notificationSub = _notifyChar!.lastValueStream.listen((value) {
      _responseController.add(utf8.decode(value, allowMalformed: true));
    });

    _device = device;
    _isConnected = true;
    onLog?.call('✓ BLE listo para comandos\n');
  }

  Future<ble.BluetoothDevice?> _findDeviceById(String targetId) async {
    final completer = Completer<ble.BluetoothDevice?>();
    final found = <ble.BluetoothDevice>[];
    final sub = ble.FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final id = r.device.remoteId.str.toLowerCase();
        final name = (r.device.platformName).toLowerCase();
        onLog?.call('  BLE encontrado: ${r.device.platformName} [$id] RSSI: ${r.rssi}\n');
        found.add(r.device);
        if (id == targetId.toLowerCase() || name.contains('elm327') || name.contains('obd')) {
          if (!completer.isCompleted) {
            completer.complete(r.device);
          }
        }
      }
    });

    onLog?.call('Escaneando BLE por 10s...\n');
    await ble.FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    await Future.delayed(const Duration(seconds: 10));
    await ble.FlutterBluePlus.stopScan();
    await sub.cancel();

    if (!completer.isCompleted) {
      onLog?.call('BLE: no se encontró coincidencia exacta para $targetId\n');
      onLog?.call('BLE: dispositivos encontrados: ${found.length}\n');
      return null;
    }
    return completer.future;
  }

  @override
  Future<void> disconnect() async {
    await _notificationSub?.cancel();
    _notificationSub = null;
    await _device?.disconnect();
    _device = null;
    _writeChar = null;
    _notifyChar = null;
    _isConnected = false;
  }

  @override
  Future<void> write(String command) async {
    if (_writeChar == null) throw StateError('BLE no conectado.');
    final bytes = utf8.encode('$command\r');
    final withoutResponse = _writeChar!.properties.writeWithoutResponse;
    await _writeChar!.write(bytes, withoutResponse: withoutResponse);
  }
}
