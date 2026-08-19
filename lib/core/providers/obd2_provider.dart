import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import '../../obd2_elm327.dart';
import '../../obd2_transport.dart';

enum Obd2ConnectionState { disconnected, connecting, connected }

class Obd2SensorData {
  final int rpm;
  final int speed;
  final String coolantTemp;
  final String engineLoad;
  final String throttle;
  final String map;
  final String iat;
  final String timing;
  final String maf;
  final String fuelLevel;
  final String baro;
  final String stft1;
  final String ltft1;
  final String stft2;
  final String ltft2;

  const Obd2SensorData({
    this.rpm = 0,
    this.speed = 0,
    this.coolantTemp = '--',
    this.engineLoad = '--',
    this.throttle = '--',
    this.map = '--',
    this.iat = '--',
    this.timing = '--',
    this.maf = '--',
    this.fuelLevel = '--',
    this.baro = '--',
    this.stft1 = '--',
    this.ltft1 = '--',
    this.stft2 = '--',
    this.ltft2 = '--',
  });

  Obd2SensorData copyWith({
    int? rpm,
    int? speed,
    String? coolantTemp,
    String? engineLoad,
    String? throttle,
    String? map,
    String? iat,
    String? timing,
    String? maf,
    String? fuelLevel,
    String? baro,
    String? stft1,
    String? ltft1,
    String? stft2,
    String? ltft2,
  }) {
    return Obd2SensorData(
      rpm: rpm ?? this.rpm,
      speed: speed ?? this.speed,
      coolantTemp: coolantTemp ?? this.coolantTemp,
      engineLoad: engineLoad ?? this.engineLoad,
      throttle: throttle ?? this.throttle,
      map: map ?? this.map,
      iat: iat ?? this.iat,
      timing: timing ?? this.timing,
      maf: maf ?? this.maf,
      fuelLevel: fuelLevel ?? this.fuelLevel,
      baro: baro ?? this.baro,
      stft1: stft1 ?? this.stft1,
      ltft1: ltft1 ?? this.ltft1,
      stft2: stft2 ?? this.stft2,
      ltft2: ltft2 ?? this.ltft2,
    );
  }
}

class Obd2State {
  final Obd2ConnectionState connectionState;
  final BluetoothDevice? device;
  final Obd2SensorData sensorData;
  final List<DTCCode> dtcs;
  final String protocol;
  final String vin;
  final bool mil;
  final String log;
  final List<String> availablePids;
  final String error;

  const Obd2State({
    this.connectionState = Obd2ConnectionState.disconnected,
    this.device,
    this.sensorData = const Obd2SensorData(),
    this.dtcs = const [],
    this.protocol = '',
    this.vin = '',
    this.mil = false,
    this.log = '',
    this.availablePids = const [],
    this.error = '',
  });

  Obd2State copyWith({
    Obd2ConnectionState? connectionState,
    BluetoothDevice? device,
    Obd2SensorData? sensorData,
    List<DTCCode>? dtcs,
    String? protocol,
    String? vin,
    bool? mil,
    String? log,
    List<String>? availablePids,
    String? error,
  }) {
    return Obd2State(
      connectionState: connectionState ?? this.connectionState,
      device: device ?? this.device,
      sensorData: sensorData ?? this.sensorData,
      dtcs: dtcs ?? this.dtcs,
      protocol: protocol ?? this.protocol,
      vin: vin ?? this.vin,
      mil: mil ?? this.mil,
      log: log ?? this.log,
      availablePids: availablePids ?? this.availablePids,
      error: error ?? this.error,
    );
  }
}

final obd2Provider = NotifierProvider<Obd2Notifier, Obd2State>(Obd2Notifier.new);

class Obd2Notifier extends Notifier<Obd2State> {
  final Obd2Elm327 _obd = Obd2Elm327();
  Timer? _refreshTimer;
  Timer? _keepAliveTimer;
  StreamSubscription<String>? _responseSub;
  bool _isRefreshing = false;
  DateTime? _refreshStarted;
  int _keepAliveFailures = 0;

  @override
  Obd2State build() {
    ref.onDispose(() {
      _refreshTimer?.cancel();
      _keepAliveTimer?.cancel();
      _responseSub?.cancel();
      _obd.disconnect();
    });
    return const Obd2State();
  }

  Future<void> connect(BluetoothDevice device) async {
    state = state.copyWith(connectionState: Obd2ConnectionState.connecting, device: device, log: '', error: '');

    _responseSub?.cancel();
    _responseSub = _obd.responseStream.listen((data) {
      state = state.copyWith(log: state.log + data);
    });

    var success = await _obd.connect(device.address);

    if (!success) {
      state = state.copyWith(log: state.log + '\nℹ️ SPP falló, probando BLE...\n');
      _obd.switchTransport(BleTransport(deviceId: device.address));
      success = await _obd.connect(device.address);
    }

    if (success) {
      state = state.copyWith(connectionState: Obd2ConnectionState.connected);
      _startRefresh();
      _startKeepAlive();
      _loadVehicleInfo();
    } else {
      state = state.copyWith(
        connectionState: Obd2ConnectionState.disconnected,
        error: 'Error de conexion',
      );
    }
  }

  Future<void> disconnect() async {
    _refreshTimer?.cancel();
    _keepAliveTimer?.cancel();
    await _responseSub?.cancel();
    await _obd.disconnect();
    _keepAliveFailures = 0;
    state = const Obd2State(log: 'Desconectado\n');
  }

  void _startRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) => _refreshSensors());
  }

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _checkKeepAlive());
  }

  Future<void> _checkKeepAlive() async {
    if (!_obd.isConnected) {
      await disconnect();
      return;
    }
    final ok = await _obd.keepAlive(timeout: const Duration(seconds: 4));
    if (ok) {
      _keepAliveFailures = 0;
    } else {
      _keepAliveFailures += 1;
      if (_keepAliveFailures >= 2) {
        await disconnect();
        state = state.copyWith(
          connectionState: Obd2ConnectionState.disconnected,
          error: 'Conexión perdida con el adaptador',
        );
      }
    }
  }
  Future<void> _refreshSensors() async {
    if (_isRefreshing) {
      if (_refreshStarted != null &&
          DateTime.now().difference(_refreshStarted!).inSeconds > 20) {
        _isRefreshing = false;
      } else {
        return;
      }
    }
    if (!_obd.isConnected) return;
    _isRefreshing = true;
    _refreshStarted = DateTime.now();
    try {
      Future<void> read<T>(
        Future<T> Function() fn,
        Obd2SensorData Function(Obd2SensorData, T) apply,
      ) async {
        try {
          final v = await fn();
          state = state.copyWith(sensorData: apply(state.sensorData, v));
        } catch (_) {}
      }

      await read(_obd.getRpm, (s, v) => s.copyWith(rpm: v));
      await read(_obd.getSpeed, (s, v) => s.copyWith(speed: v));
      await read(_obd.getCoolantTemp, (s, v) => s.copyWith(coolantTemp: '$v°C'));
      await read(_obd.getEngineLoad, (s, v) => s.copyWith(engineLoad: '$v%'));
      await read(_obd.getThrottlePosition, (s, v) => s.copyWith(throttle: '${v.toStringAsFixed(1)}%'));
      await read(_obd.getIntakePressure, (s, v) => s.copyWith(map: '${v}kPa'));
      await read(_obd.getIntakeTemp, (s, v) => s.copyWith(iat: '$v°C'));
      await read(_obd.getMAF, (s, v) => s.copyWith(maf: '${v.toStringAsFixed(2)} g/s'));
      await read(_obd.getFuelLevel, (s, v) => s.copyWith(fuelLevel: '${v.toStringAsFixed(0)}%'));
      await read(_obd.getBarometricPressure, (s, v) => s.copyWith(baro: '${v}kPa'));
      await read(_obd.getShortTermTrimBank1, (s, v) => s.copyWith(stft1: '${v.toStringAsFixed(1)}%'));
      await read(_obd.getLongTermTrimBank1, (s, v) => s.copyWith(ltft1: '${v.toStringAsFixed(1)}%'));
      await read(_obd.getShortTermTrimBank2, (s, v) => s.copyWith(stft2: '${v.toStringAsFixed(1)}%'));
      await read(_obd.getLongTermTrimBank2, (s, v) => s.copyWith(ltft2: '${v.toStringAsFixed(1)}%'));
      await read(_obd.getTimingAdvance, (s, v) => s.copyWith(timing: '${v.toStringAsFixed(1)}°'));
    } finally {
      _isRefreshing = false;
      _refreshStarted = null;
    }
  }

  Future<void> _loadVehicleInfo() async {
    try {
      final protocol = await _obd.getProtocol();
      state = state.copyWith(protocol: protocol);
    } catch (_) {}
    try {
      final mil = await _obd.isMILActive();
      state = state.copyWith(mil: mil);
    } catch (_) {}
    try {
      final vin = await _obd.getVIN();
      state = state.copyWith(vin: vin);
    } catch (_) {}
    try {
      final pids = await _obd.getSupportedPIDs();
      state = state.copyWith(
        availablePids: pids
            .map((p) => p.toRadixString(16).toUpperCase().padLeft(2, '0'))
            .toList(),
      );
    } catch (_) {}
  }

  Future<void> loadDTCs() async {
    try {
      final dtcs = <DTCCode>[];
      final stored = await _obd.getDTCs();
      dtcs.addAll(stored);
      final pending = await _obd.getPendingDTCs();
      for (final d in pending) {
        if (d.code != 'NONE' && !dtcs.any((e) => e.code == d.code)) {
          dtcs.add(d);
        }
      }
      final permanent = await _obd.getPermanentDTCs();
      for (final d in permanent) {
        if (d.code != 'NONE' && !dtcs.any((e) => e.code == d.code)) {
          dtcs.add(d);
        }
      }
      if (dtcs.isEmpty) {
        dtcs.add(const DTCCode(code: 'NONE', description: 'No hay codigos almacenados'));
      }
      state = state.copyWith(dtcs: dtcs);
    } catch (_) {}
  }

  Future<bool> clearDTCs() async {
    final ok = await _obd.clearDTCs();
    if (ok) await loadDTCs();
    return ok;
  }

  Future<void> sendCommand(String cmd) async {
    try {
      await _obd.sendCommand(cmd);
      state = state.copyWith(log: '${state.log}> $cmd\n');
    } catch (e) {
      state = state.copyWith(log: '${state.log}Error: $e\n');
    }
  }

  void clearTerminal() {
    state = state.copyWith(log: '');
  }

  Future<List<OxygenSensor>> getOxygenSensors() => _obd.getOxygenSensors();
}
