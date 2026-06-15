import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import '../../obd2_elm327.dart';

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
  StreamSubscription<String>? _responseSub;

  @override
  Obd2State build() {
    ref.onDispose(() {
      _refreshTimer?.cancel();
      _responseSub?.cancel();
      _obd.disconnect();
    });
    return const Obd2State();
  }

  Future<void> connect(BluetoothDevice device) async {
    state = state.copyWith(connectionState: Obd2ConnectionState.connecting, device: device, log: '');

    _responseSub?.cancel();
    _responseSub = _obd.responseStream.listen((data) {
      state = state.copyWith(log: state.log + data);
    });

    final success = await _obd.connect(device.address);

    if (success) {
      state = state.copyWith(connectionState: Obd2ConnectionState.connected);
      _startRefresh();
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
    await _responseSub?.cancel();
    await _obd.disconnect();
    state = const Obd2State(log: 'Desconectado\n');
  }

  void _startRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) => _refreshSensors());
  }

  Future<void> _refreshSensors() async {
    try {
      final rpm = await _obd.getRpm();
      state = state.copyWith(sensorData: state.sensorData.copyWith(rpm: rpm));
    } catch (_) {}
    try {
      final speed = await _obd.getSpeed();
      state = state.copyWith(sensorData: state.sensorData.copyWith(speed: speed));
    } catch (_) {}
    try {
      final temp = await _obd.getCoolantTemp();
      state = state.copyWith(sensorData: state.sensorData.copyWith(coolantTemp: '$temp°C'));
    } catch (_) {}
    try {
      final load = await _obd.getEngineLoad();
      state = state.copyWith(sensorData: state.sensorData.copyWith(engineLoad: '$load%'));
    } catch (_) {}
    try {
      final tps = await _obd.getThrottlePosition();
      state = state.copyWith(sensorData: state.sensorData.copyWith(throttle: '${tps.toStringAsFixed(1)}%'));
    } catch (_) {}
    try {
      final map = await _obd.getIntakePressure();
      state = state.copyWith(sensorData: state.sensorData.copyWith(map: '${map}kPa'));
    } catch (_) {}
    try {
      final iat = await _obd.getIntakeTemp();
      state = state.copyWith(sensorData: state.sensorData.copyWith(iat: '$iat°C'));
    } catch (_) {}
    try {
      final timing = await _obd.getTimingAdvance();
      state = state.copyWith(sensorData: state.sensorData.copyWith(timing: '${timing.toStringAsFixed(1)}°'));
    } catch (_) {}
    try {
      final maf = await _obd.getMAF();
      state = state.copyWith(sensorData: state.sensorData.copyWith(maf: '${maf.toStringAsFixed(2)} g/s'));
    } catch (_) {}
    try {
      final fuel = await _obd.getFuelLevel();
      state = state.copyWith(sensorData: state.sensorData.copyWith(fuelLevel: '${fuel.toStringAsFixed(0)}%'));
    } catch (_) {}
    try {
      final baro = await _obd.getBarometricPressure();
      state = state.copyWith(sensorData: state.sensorData.copyWith(baro: '${baro}kPa'));
    } catch (_) {}
    try {
      final stft1 = await _obd.getShortTermTrimBank1();
      state = state.copyWith(sensorData: state.sensorData.copyWith(stft1: '${stft1.toStringAsFixed(1)}%'));
    } catch (_) {}
    try {
      final ltft1 = await _obd.getLongTermTrimBank1();
      state = state.copyWith(sensorData: state.sensorData.copyWith(ltft1: '${ltft1.toStringAsFixed(1)}%'));
    } catch (_) {}
    try {
      final stft2 = await _obd.getShortTermTrimBank2();
      state = state.copyWith(sensorData: state.sensorData.copyWith(stft2: '${stft2.toStringAsFixed(1)}%'));
    } catch (_) {}
    try {
      final ltft2 = await _obd.getLongTermTrimBank2();
      state = state.copyWith(sensorData: state.sensorData.copyWith(ltft2: '${ltft2.toStringAsFixed(1)}%'));
    } catch (_) {}
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
  }

  Future<void> loadDTCs() async {
    try {
      final dtcs = await _obd.getDTCs();
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
      state = state.copyWith(log: state.log + '> $cmd\n');
    } catch (e) {
      state = state.copyWith(log: state.log + 'Error: $e\n');
    }
  }

  Future<List<OxygenSensor>> getOxygenSensors() => _obd.getOxygenSensors();
}
