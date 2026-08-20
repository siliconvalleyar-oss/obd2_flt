import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  final List<double> o2Voltages;
  final int runtime;
  final String fuelSystem;

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
    this.o2Voltages = const [],
    this.runtime = 0,
    this.fuelSystem = '--',
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
    List<double>? o2Voltages,
    int? runtime,
    String? fuelSystem,
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
      o2Voltages: o2Voltages ?? this.o2Voltages,
      runtime: runtime ?? this.runtime,
      fuelSystem: fuelSystem ?? this.fuelSystem,
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
  final int refreshIntervalMs;
  final bool isEngineRunning;

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
    this.refreshIntervalMs = 1000,
    this.isEngineRunning = false,
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
    int? refreshIntervalMs,
    bool? isEngineRunning,
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
      refreshIntervalMs: refreshIntervalMs ?? this.refreshIntervalMs,
      isEngineRunning: isEngineRunning ?? this.isEngineRunning,
    );
  }
}

final obd2Provider = NotifierProvider<Obd2Notifier, Obd2State>(Obd2Notifier.new);

class Obd2Notifier extends Notifier<Obd2State> {
  final Obd2Elm327 _obd = Obd2Elm327();
  Timer? _refreshTimer;
  Timer? _keepAliveTimer;
  StreamSubscription<String>? _responseSub;
  bool _refreshRunning = false;
  int _keepAliveFailures = 0;
  int _slowCycleCount = 0;
  int _slowSubCycle = 0;

  static const _prefKey = 'refresh_interval_ms';

  @override
  Obd2State build() {
    ref.onDispose(() {
      _refreshTimer?.cancel();
      _keepAliveTimer?.cancel();
      _responseSub?.cancel();
      _obd.disconnect();
    });
    _loadRefreshInterval();
    return const Obd2State();
  }

  Future<void> _loadRefreshInterval() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_prefKey) ?? 1000;
      state = state.copyWith(refreshIntervalMs: ms);
    } catch (_) {}
  }

  Future<void> setRefreshInterval(int ms) async {
    state = state.copyWith(refreshIntervalMs: ms);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefKey, ms);
    } catch (_) {}
    // Restart timer with new interval
    if (state.connectionState == Obd2ConnectionState.connected) {
      _startRefresh();
    }
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
    _slowCycleCount = 0;
    _slowSubCycle = 0;
    state = const Obd2State(log: 'Desconectado\n');
  }

  void _startRefresh() {
    _refreshTimer?.cancel();
    _scheduleNextRefresh();
  }

  void _scheduleNextRefresh() {
    _refreshTimer?.cancel();
    final ms = state.refreshIntervalMs;
    _refreshTimer = Timer(Duration(milliseconds: ms), () => _refreshSensors());
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

  /// Ciclo de lectura auto-programado: el siguiente arranca cuando termina el actual.
  /// Elimina el lock _isRefreshing que causaba saltos de ciclo.
  Future<void> _refreshSensors() async {
    if (!_obd.isConnected) return;
    if (_refreshRunning) {
      _scheduleNextRefresh();
      return;
    }
    _refreshRunning = true;
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

      const fast = Duration(milliseconds: 600);

      // === SIEMPRE: RPM + speed + temp (3 comandos, ~1-2s) ===
      int currentRpm = 0;
      try {
        currentRpm = await _obd.getRpm(timeout: fast);
        state = state.copyWith(sensorData: state.sensorData.copyWith(rpm: currentRpm));
      } catch (_) {}

      final engineRunning = currentRpm > 0;
      if (engineRunning != state.isEngineRunning) {
        state = state.copyWith(isEngineRunning: engineRunning);
      }

      await read(() => _obd.getSpeed(timeout: fast), (s, v) => s.copyWith(speed: v));
      await read(() => _obd.getCoolantTemp(timeout: fast), (s, v) => s.copyWith(coolantTemp: '$v°C'));

      if (!engineRunning) {
        // REPOSO: solo load + temp (2 comandos extra)
        await read(() => _obd.getEngineLoad(timeout: fast), (s, v) => s.copyWith(engineLoad: '$v%'));
      } else {
        // FUNCIONAMIENTO: load + throttle (2 comandos extra)
        await read(() => _obd.getEngineLoad(timeout: fast), (s, v) => s.copyWith(engineLoad: '$v%'));
        await read(() => _obd.getThrottlePosition(timeout: fast), (s, v) => s.copyWith(throttle: '${v.toStringAsFixed(1)}%'));

        // === CICLO LENTO: cada 3 ticks, dividido en 2 mitades ===
        _slowCycleCount++;
        if (_slowCycleCount >= 3) {
          _slowCycleCount = 0;
          _slowSubCycle = (_slowSubCycle + 1) % 2;

          if (_slowSubCycle == 0) {
            // Mitad A: MAP, IAT, MAF, fuel, baro, runtime
            await read(() => _obd.getIntakePressure(timeout: fast), (s, v) => s.copyWith(map: '${v}kPa'));
            await read(() => _obd.getIntakeTemp(timeout: fast), (s, v) => s.copyWith(iat: '$v°C'));
            await read(() => _obd.getMAF(timeout: fast), (s, v) => s.copyWith(maf: '${v.toStringAsFixed(2)} g/s'));
            await read(() => _obd.getFuelLevel(timeout: fast), (s, v) => s.copyWith(fuelLevel: '${v.toStringAsFixed(0)}%'));
            await read(() => _obd.getBarometricPressure(timeout: fast), (s, v) => s.copyWith(baro: '${v}kPa'));
            await read(() => _obd.getRuntime(timeout: fast), (s, v) => s.copyWith(runtime: v));
          } else {
            // Mitad B: fuel trims + O2 (solo 2 sensores por bank)
            await read(() => _obd.getShortTermTrimBank1(timeout: fast), (s, v) => s.copyWith(stft1: '${v.toStringAsFixed(1)}%'));
            await read(() => _obd.getLongTermTrimBank1(timeout: fast), (s, v) => s.copyWith(ltft1: '${v.toStringAsFixed(1)}%'));
            await read(() => _obd.getShortTermTrimBank2(timeout: fast), (s, v) => s.copyWith(stft2: '${v.toStringAsFixed(1)}%'));
            await read(() => _obd.getLongTermTrimBank2(timeout: fast), (s, v) => s.copyWith(ltft2: '${v.toStringAsFixed(1)}%'));
            await read(() => _obd.getTimingAdvance(timeout: fast), (s, v) => s.copyWith(timing: '${v.toStringAsFixed(1)}°'));

            // O2: solo sensores 1 y 2 por bank (mayoría de autos)
            try {
              final voltages = <double>[];
              for (int bank = 1; bank <= 2; bank++) {
                for (int s = 1; s <= 2; s++) {
                  try {
                    final o2 = await _obd.getO2Sensor(bank, s, timeout: fast);
                    voltages.add(o2.voltage);
                  } catch (_) {
                    voltages.add(-1.0);
                  }
                }
              }
              state = state.copyWith(sensorData: state.sensorData.copyWith(o2Voltages: voltages));
            } catch (_) {}
          }
        }
      }
    } finally {
      _refreshRunning = false;
      _scheduleNextRefresh();
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
