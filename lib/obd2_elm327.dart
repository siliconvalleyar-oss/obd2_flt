import 'dart:async';
import 'core/obd/elm_parser.dart' as parser;
import 'obd2_transport.dart';

/// Excepciones del dominio OBD2.
class Obd2Exception implements Exception {
  final String message;
  const Obd2Exception(this.message);
  @override
  String toString() => message;
}

class Obd2TimeoutException extends Obd2Exception {
  const Obd2TimeoutException(super.message);
}

class Obd2NoDataException extends Obd2Exception {
  const Obd2NoDataException(super.message);
}

/// Formato del protocolo detectado (deducido del número de protocolo de ATDPN).
/// Ver docs/04-comandos-elm.md §4.7.
enum ElmFormat {
  auto,
  j1850Pwm,
  j1850Vpw,
  iso9141,
  kwp5Baud,
  kwpFast,
  can11bit500,
  can29bit500,
  can11bit250,
  can29bit250,
  j1939,
  can11bit125,
  can29bit125,
  unknown;

  bool get isCan =>
      this == can11bit500 ||
      this == can29bit500 ||
      this == can11bit250 ||
      this == can29bit250 ||
      this == can11bit125 ||
      this == can29bit125 ||
      this == j1939;

  static ElmFormat fromProtocolNumber(int n) {
    switch (n) {
      case 0:
        return auto;
      case 1:
        return j1850Pwm;
      case 2:
        return j1850Vpw;
      case 3:
        return iso9141;
      case 4:
        return kwp5Baud;
      case 5:
        return kwpFast;
      case 6:
        return can11bit500;
      case 7:
        return can29bit500;
      case 8:
        return can11bit250;
      case 9:
        return can29bit250;
      case 10:
        return j1939;
      case 11:
        return can11bit125;
      case 12:
        return can29bit125;
      default:
        return unknown;
    }
  }
}

class OxygenSensor {
  final int bank;
  final int sensor;
  final double voltage;
  final double shortTermTrim;

  OxygenSensor({
    required this.bank,
    required this.sensor,
    required this.voltage,
    required this.shortTermTrim,
  });
}

class DTCCode {
  final String code;
  final String description;
  final String source;

  const DTCCode({required this.code, required this.description, this.source = ''});
}

class FuelTrim {
  final double shortTermBank1;
  final double shortTermBank2;
  final double longTermBank1;
  final double longTermBank2;
  final bool available;

  FuelTrim({
    required this.shortTermBank1,
    required this.shortTermBank2,
    required this.longTermBank1,
    required this.longTermBank2,
    required this.available,
  });
}

/// Configuración CAN por petición (ver docs/04-comandos-elm.md §4.4).
/// Modelado sobre `BaseCAN11bitECU.GetRequestForCommand` / `BaseCAN29bitECU`.
class CanRequestConfig {
  final int protocol; // 6 (CAN 11/500), 7 (CAN 29/500), 8, 9...
  final String? requestHeader; // p. ej. '7E0', '7DF' (broadcast)
  final String? responseHeader; // p. ej. '7E8'
  final String? extendedAddress; // 2 hex
  final String? testerAddress; // 2 hex
  final String? canPriority; // 2 hex (CAN 29-bit)
  final bool restoreAfter; // restaurar ATAR/ATFCSM0/ATCEA/ATSTDEF/ATSP0

  const CanRequestConfig({
    required this.protocol,
    this.requestHeader,
    this.responseHeader,
    this.extendedAddress,
    this.testerAddress,
    this.canPriority,
    this.restoreAfter = true,
  });
}

class Obd2Elm327 {
  static const version = '2.4.1';
  Elm327Transport _transport;
  bool _isConnected = false;

  final StreamController<String> _responseController = StreamController<String>.broadcast();
  StreamSubscription<String>? _inputSubscription;

  Stream<String> get responseStream => _responseController.stream;
  bool get isConnected => _isConnected;

  Obd2Elm327() : _transport = ClassicSppTransport() {
    _inputSubscription = _transport.responseStream.listen(_onTransportData);
  }

  Obd2Elm327.transport(this._transport) {
    _inputSubscription = _transport.responseStream.listen(_onTransportData);
  }

  void switchTransport(Elm327Transport transport) {
    _transport = transport;
    _inputSubscription?.cancel();
    _inputSubscription = _transport.responseStream.listen(_onTransportData);
  }

  // ---------------------------------------------------------------
  // Serialización: cola FIFO de comandos.
  // ---------------------------------------------------------------
  Future<void> _queue = Future.value();
  bool _inQueueTask = false;

  /// Encadena [task] en la cola FIFO. Las llamadas anidadas dentro de una
  /// tarea en ejecución se ejecutan en línea (evita esperas innecesarias).
  Future<T> _run<T>(Future<T> Function() task) {
    if (_inQueueTask) return task();
    return _enqueue(task);
  }

  Future<T> _enqueue<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      _inQueueTask = true;
      try {
        final result = await task();
        if (!completer.isCompleted) completer.complete(result);
      } catch (e, st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      } finally {
        _inQueueTask = false;
      }
    });
    return completer.future;
  }

  // ---------------------------------------------------------------
  // Framing de respuestas: el ELM327 termina cada respuesta con '>'.
  // ---------------------------------------------------------------
  final StringBuffer _responseBuffer = StringBuffer();
  Completer<String>? _responseCompleter;
  Timer? _responseTimer;

  Completer<String> _waitForResponse(Duration timeout) {
    _responseBuffer.clear();
    final completer = Completer<String>();
    _responseCompleter = completer;
    _responseTimer?.cancel();
    _responseTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        if (_responseBuffer.isNotEmpty) {
          completer.complete(_responseBuffer.toString());
        } else {
          completer.completeError(
            Obd2TimeoutException(
                'Sin respuesta del ELM327 (${timeout.inMilliseconds} ms)'),
          );
        }
      }
    });
    return completer;
  }

  void _cancelResponseWait({Object? error}) {
    final completer = _responseCompleter;
    _responseTimer?.cancel();
    _responseTimer = null;
    _responseCompleter = null;
    if (completer != null && !completer.isCompleted) {
      if (error != null) {
        completer.completeError(error);
      } else {
        completer.complete('');
      }
    }
  }

  void _onTransportData(String text) {
    _responseBuffer.write(text);
    _responseController.add(text);
    final completer = _responseCompleter;
    if (completer != null && !completer.isCompleted) {
      if (_responseBuffer.toString().contains('>')) {
        completer.complete(_responseBuffer.toString());
        _responseTimer?.cancel();
        _responseTimer = null;
        _responseCompleter = null;
      }
    }
  }

  // ---------------------------------------------------------------
  // Envío de comandos.
  // ---------------------------------------------------------------

  Future<String> _sendAndWait(String command,
      {Duration timeout = const Duration(seconds: 4)}) {
    return _run(() => _sendAndWaitCore(command, timeout));
  }

  Future<String> _sendAndWaitCore(String command, Duration timeout) async {
    if (!_isConnected || !_transport.isConnected) {
      throw StateError('No conectado.');
    }
    final completer = _waitForResponse(timeout);
    Timer? hardTimer;
    try {
      // Safety net: if the normal response path fails, force-complete
      // after 3× the timeout so the queue never stalls permanently.
      hardTimer = Timer(timeout * 3, () {
        if (!completer.isCompleted) {
          completer.completeError(
            Obd2TimeoutException('Hard timeout para "$command"'),
          );
        }
      });
      await _transport.write(command);
    } catch (e) {
      _cancelResponseWait();
      rethrow;
    }
    try {
      return await completer.future;
    } finally {
      hardTimer?.cancel();
    }
  }

  /// Envía [command] y espera la respuesta completa (hasta el prompt `>`).
  /// Si el comando es AT, invalida el estado deduplicado (no sabemos qué cambió).
  Future<String> sendCommandWithResponse(String command,
      {Duration timeout = const Duration(seconds: 4)}) {
    if (_isAtCommand(command)) _elmState.clear();
    return _sendAndWait(command, timeout: timeout);
  }

  /// Envía [command] sin esperar su respuesta (fire-and-forget).
  Future<void> sendCommand(String command) {
    if (_isAtCommand(command)) _elmState.clear();
    return _sendAndWait(command).then((_) {});
  }

  bool _isAtCommand(String command) =>
      command.trim().toUpperCase().startsWith('AT');

  // ---------------------------------------------------------------
  // Comandos AT (validación + deduplicación).
  // ---------------------------------------------------------------

  /// Estado del ELM327 para deduplicar comandos redundantes
  /// (ver docs/04-comandos-elm.md §4.6).
  final Map<String, String> _elmState = {};

  bool _isOkResponse(String resp) => parser.isOkResponse(resp);

  bool _isElmError(String resp) => parser.isElmError(resp);

  bool _isNoData(String resp) => parser.isNoData(resp);

  /// Envía un comando AT y verifica `OK` (reintenta una vez).
  Future<bool> _sendAt(String command,
      {Duration timeout = const Duration(seconds: 3)}) async {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final resp = await _sendAndWait(command, timeout: timeout);
        if (_isOkResponse(resp)) return true;
        if (_isElmError(resp)) return false; // '?' / ERROR → no reintentar
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  (String, String) _splitAtCommand(String command) {
    final m = RegExp(r'^AT([A-Za-z]+)([0-9A-Fa-f]*)$').firstMatch(command.trim());
    if (m == null) return (command.trim(), '');
    return (m.group(1)!.toUpperCase(), m.group(2)!);
  }

  /// Envía un comando AT solo si su valor no está ya activo (deduplicación).
  Future<bool> _sendAtDedup(String command,
      {bool force = false, Duration timeout = const Duration(seconds: 3)}) async {
    final (key, value) = _splitAtCommand(command);
    if (!force && key.isNotEmpty && _elmState[key] == value) return true;
    final ok = await _sendAt(command, timeout: timeout);
    if (ok && key.isNotEmpty) _elmState[key] = value;
    return ok;
  }

  /// Envía un comando y tolera su fallo (para init). Devuelve la respuesta o ''.
  Future<String> _safeCommand(String cmd,
      {Duration timeout = const Duration(seconds: 2), String tag = ''}) async {
    try {
      final resp = await sendCommandWithResponse(cmd, timeout: timeout);
      _responseController.add('$tag: ${_truncateResponse(resp)}\n');
      return resp;
    } catch (e) {
      _responseController.add('$tag: ${e.runtimeType} (se continúa)\n');
      return '';
    }
  }

  // ---------------------------------------------------------------
  // Conexión.
  // ---------------------------------------------------------------

  // ---------------------------------------------------------------
  // Conexión.
  // ---------------------------------------------------------------

  Future<bool> _connectInternal(String deviceId) async {
    try {
      await disconnect();
      _responseController.add('Reconectando v$version con $deviceId...\n');
      const maxAttempts = 4;
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          if (attempt > 1) {
            _responseController.add('Reintento reconexión $attempt de $maxAttempts...\n');
            await Future.delayed(const Duration(seconds: 3));
          }
          await _transport.connect(deviceId);
          _subscribeToTransport();
          break;
        } catch (e) {
          if (attempt == maxAttempts) rethrow;
          _responseController.add('  Falló reconexión intento $attempt: $e\n');
          await _transport.disconnect();
        }
      }
      _isConnected = true;
      _responseController.add('✓ Reconexión establecida\n');
      await Future.delayed(const Duration(milliseconds: 500));
      _responseController.add('Reinicializando ELM327...\n');
      final initOk = await _initializeElm327();
      if (!initOk) throw Exception('Inicialización ELM327 falló');
      final ok = await keepAlive(timeout: const Duration(seconds: 5));
      if (!ok) throw Exception('Keepalive post-reconexión falló');
      return true;
    } catch (e, st) {
      _isConnected = false;
      await _transport.disconnect();
      _responseController.add('\n=== ERROR DE RECONEXIÓN ===\n');
      _responseController.add('Tipo: ${e.runtimeType}\n');
      _responseController.add('Mensaje: $e\n');
      final stack = st.toString().split('\n');
      final limit = stack.length > 6 ? 6 : stack.length;
      for (int i = 0; i < limit; i++) {
        if (stack[i].contains('package:flutter_bluetooth_serial_plus') ||
            stack[i].contains('BluetoothConnection') ||
            stack[i].contains('.connect(')) {
          _responseController.add('  ${stack[i]}\n');
        }
      }
      _responseController.add('========================\n');
      _responseController.add('\n💡 SUGERENCIAS:\n');
      _responseController.add('  1. Verificá que el auto esté en ACC o encendido\n');
      _responseController.add('  2. Verificá que el ELM327 tenga luz LED fija (no parpadeando)\n');
      _responseController.add('  3. Confirmá que esté emparejado en Ajustes > Bluetooth (nombre OBDII, MAC $deviceId)\n');
      _responseController.add('  4. Confirmá que el adaptador sea SPP (no BLE); este flujo no soporta BLE\n');
      _responseController.add('  5. Apaga y enciende Bluetooth del móvil\n');
      _responseController.add('  6. Desconectá la batería del ELM327 10s y reconectá\n');
      _responseController.add('  7. Si usas Xiaomi, revisá si la app tiene permiso de ubicación/ubicación aproximada activo\n');
      _responseController.add('  8. Si otra app queda conectada, el socket RFCOMM queda ocupado y esta conexión falla\n');
      return false;
    }
  }

  Future<bool> connect(String targetMacAddress) async {
    try {
      await disconnect();
      _responseController.add('=== OBD2 Scanner v$version ===\n');
      _responseController.add('MAC: $targetMacAddress\n');
      const maxAttempts = 4;
      var connected = false;
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          if (attempt > 1) {
            _responseController.add('Reintento $attempt de $maxAttempts...\n');
            await Future.delayed(const Duration(seconds: 3));
          }
          await _transport.connect(targetMacAddress);
          _subscribeToTransport();
          connected = true;
          break;
        } catch (e) {
          if (attempt == maxAttempts) rethrow;
          _responseController.add('  Falló intento $attempt: $e\n');
          await _transport.disconnect();
        }
      }
      if (!connected) throw Exception('No se pudo conectar.');

      _isConnected = true;
      _responseController.add('✓ Conexión establecida\n');

      await Future.delayed(const Duration(milliseconds: 500));

      _responseController.add('Inicializando ELM327...\n');
      final initOk = await _initializeElm327();
      if (!initOk) {
        throw Exception('Inicialización ELM327 falló. Verificá que el adaptador esté encendido y en modo SPP.');
      }

      try {
        final alive = await keepAlive(timeout: const Duration(seconds: 5));
        if (!alive) {
          _responseController.add('⚠️ Keepalive inicial falló, reintentando...\n');
          await disconnect();
          await Future.delayed(const Duration(seconds: 2));
          return await _connectInternal(targetMacAddress);
        }
      } catch (_) {
        await disconnect();
        return await _connectInternal(targetMacAddress);
      }

      return true;
    } catch (e, st) {
      _isConnected = false;
      await _transport.disconnect();
      _responseController.add('\n=== ERROR DE CONEXIÓN ===\n');
      _responseController.add('Tipo: ${e.runtimeType}\n');
      _responseController.add('Mensaje: $e\n');
      final stack = st.toString().split('\n');
      final limit = stack.length > 6 ? 6 : stack.length;
      for (int i = 0; i < limit; i++) {
        if (stack[i].contains('package:flutter_bluetooth_serial_plus') ||
            stack[i].contains('BluetoothConnection') ||
            stack[i].contains('.connect(')) {
          _responseController.add('  ${stack[i]}\n');
        }
      }
      _responseController.add('========================\n');
      _responseController.add('\n💡 SUGERENCIAS:\n');
      _responseController.add('  1. Verificá que el auto esté en ACC o encendido\n');
      _responseController.add('  2. Verificá que el ELM327 tenga luz LED fija (no parpadeando)\n');
      _responseController.add('  3. Confirmá que esté emparejado en Ajustes > Bluetooth (nombre OBDII, MAC $targetMacAddress)\n');
      _responseController.add('  4. Confirmá que el adaptador sea SPP (no BLE); este flujo no soporta BLE\n');
      _responseController.add('  5. Apaga y enciende Bluetooth del móvil\n');
      _responseController.add('  6. Desconectá la batería del ELM327 10s y reconectá\n');
      _responseController.add('  7. Si usas Xiaomi, revisá si la app tiene permiso de ubicación/ubicación aproximada activo\n');
      _responseController.add('  8. Si otra app queda conectada, el socket RFCOMM queda ocupado y esta conexión falla\n');
      return false;
    }
  }

  void _subscribeToTransport() {
    _inputSubscription?.cancel();
    _inputSubscription = _transport.responseStream.listen(_onTransportData);
  }

  Future<void> disconnect() async {
    _isConnected = false;
    _cancelResponseWait(error: StateError('Desconectado'));
    await _inputSubscription?.cancel();
    _inputSubscription = null;
    await _transport.disconnect();
    _responseBuffer.clear();
    _elmState.clear();
    _protocolNumber = null;
  }

  // ---------------------------------------------------------------
  // Init ELM327.
  // ---------------------------------------------------------------

  int? _protocolNumber;
  ElmFormat _elmFormat = ElmFormat.unknown;

  Future<bool> _initializeElm327() async {
    _responseController.add('Inicializando ELM327...\n');
    _elmState.clear();

    // Enviar TODOS los comandos para dar oportunidad al ELM327 de
    // responder y mantener actividad en los LEDs. Se evalúa al final.

    // 1. ATZ — reset del módulo (timeout largo 6s)
    final azResponse = await _safeCommand('ATZ',
        timeout: const Duration(seconds: 6), tag: 'ATZ');
    final elmDetected = azResponse.toUpperCase().contains('ELM327');
    if (!elmDetected) {
      _responseController.add(
          'ATZ: ${_truncateResponse(azResponse)} (reintentando...)\n');
    }

    // 2. Configuración base — se envían siempre
    await _safeCommand('ATE0', tag: 'ATE0');
    await _safeCommand('ATD', tag: 'ATD');
    await _safeCommand('ATD0', tag: 'ATD0');
    await _safeCommand('ATL0', tag: 'ATL0');
    await _safeCommand('ATM0', tag: 'ATM0');
    await _safeCommand('ATS0', tag: 'ATS0');
    await _safeCommand('ATH1', tag: 'ATH1');
    await _safeCommand('ATAL', tag: 'ATAL');
    await _safeCommand('ATAT1', tag: 'ATAT1');

    // 3. Si ATZ no respondió, reintentar una vez después de la config
    if (!elmDetected) {
      _responseController.add('Reintentando ATZ...\n');
      final retry = await _safeCommand('ATZ',
          timeout: const Duration(seconds: 6), tag: 'ATZ-2');
      if (!retry.toUpperCase().contains('ELM327')) {
        _responseController.add('ATZ no respondió tras reintentos\n');
        return false;
      }
    }

    // 4. Protocolo automático
    await _safeCommand('ATSP0', timeout: const Duration(seconds: 4), tag: 'ATSP0');
    await _safeCommand('ATST64', tag: 'ATST64');

    // 5. Detectar protocolo
    try {
      final dpn = await sendCommandWithResponse('ATDPN',
          timeout: const Duration(seconds: 2));
      _protocolNumber = parser.parseProtocolNumber(dpn);
      _elmFormat = ElmFormat.fromProtocolNumber(_protocolNumber ?? 0);
      _responseController.add('Protocolo: $_protocolLabel\n');
    } catch (_) {
      _responseController.add('No se pudo detectar el protocolo (ATDPN)\n');
    }

    // 6. Handshake OBD — verificar que la ECU responde (no falla init,
    //    porque el auto puede estar apagado)
    try {
      final handshake = await sendCommandWithResponse('0100',
          timeout: const Duration(seconds: 8));
      if (!handshake.toUpperCase().contains('UNABLE TO CONNECT') &&
          !handshake.toUpperCase().contains('NO DATA')) {
        _responseController.add('Handshake OBD OK\n');
      } else {
        _responseController.add('ECU sin respuesta (auto apagado?)\n');
      }
    } catch (_) {
      _responseController.add('Handshake OBD sin respuesta\n');
    }

    _responseController.add('✓ ELM327 inicializado\n');
    return true;
  }

  String get _protocolLabel {
    switch (_protocolNumber) {
      case null:
        return 'Desconocido';
      case 0:
        return 'Automático';
      case 1:
        return 'SAE J1850 PWM (41.6 kbaud)';
      case 2:
        return 'SAE J1850 VPW (10.4 kbaud)';
      case 3:
        return 'ISO 9141-2 (5 baud)';
      case 4:
        return 'ISO 14230-4 KWP (5 baud)';
      case 5:
        return 'ISO 14230-4 KWP (fast)';
      case 6:
        return 'ISO 15765-4 CAN (11 bit, 500 kbaud)';
      case 7:
        return 'ISO 15765-4 CAN (29 bit, 500 kbaud)';
      case 8:
        return 'ISO 15765-4 CAN (11 bit, 250 kbaud)';
      case 9:
        return 'ISO 15765-4 CAN (29 bit, 250 kbaud)';
      case 10:
        return 'SAE J1939 (CAN 29 bit)';
      case 11:
        return 'CAN (11 bit, 125 kbaud)';
      case 12:
        return 'CAN (29 bit, 125 kbaud)';
      default:
        return 'Protocolo $_protocolNumber';
    }
  }

  // ---------------------------------------------------------------
  // Parseo de respuestas.
  // ---------------------------------------------------------------

  String _truncateResponse(String resp) {
    final clean = resp.replaceAll('\r', '').replaceAll('\n', '').trim();
    if (clean.length > 60) return '${clean.substring(0, 60)}...';
    return clean;
  }

  /// Igual que `parser.extractPayload` para PIDs de modo 1 (`01xx` → `41xx`).
  /// Devuelve los tokens desde el marcador, p. ej. ['41','0C','0A','0A'].
  Future<List<String>> _readPidTokens(String pidHex,
      {Duration timeout = const Duration(seconds: 4)}) async {
    final resp = await sendCommandWithResponse('01$pidHex', timeout: timeout);
    if (_isNoData(resp)) {
      throw Obd2NoDataException('NO DATA para 01$pidHex');
    }
    if (_isElmError(resp)) {
      throw Obd2Exception('ELM error: ${_truncateResponse(resp)}');
    }
    final tokens = parser.extractPayload(resp, '41$pidHex');
    if (tokens.isEmpty) {
      throw Obd2Exception('Formato inválido para 01$pidHex: ${_truncateResponse(resp)}');
    }
    return tokens;
  }

  int? _parseInt(String s) => int.tryParse(s, radix: 16);

  List<int> _toBytes(List<String> tokens) {
    final bytes = <int>[];
    for (final t in tokens) {
      final v = int.tryParse(t, radix: 16);
      if (v != null) bytes.add(v);
    }
    return bytes;
  }

  // ---------------------------------------------------------------
  // Sensores (modo 1).
  // ---------------------------------------------------------------

  static const _fastTimeout = Duration(seconds: 1);
  static const _normalTimeout = Duration(seconds: 4);

  Future<int> getRpm({Duration? timeout}) async {
    final parts = await _readPidTokens('0C', timeout: timeout ?? _normalTimeout);
    if (parts.length >= 4) {
      final a = _parseInt(parts[2]);
      final b = _parseInt(parts[3]);
      if (a != null && b != null) return ((a * 256) + b) ~/ 4;
    }
    throw Obd2Exception('Formato RPM inválido');
  }

  Future<int> getSpeed({Duration? timeout}) async {
    final parts = await _readPidTokens('0D', timeout: timeout ?? _normalTimeout);
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return v;
    }
    throw Obd2Exception('Formato velocidad inválido');
  }

  Future<int> getCoolantTemp({Duration? timeout}) async {
    final parts = await _readPidTokens('05', timeout: timeout ?? _normalTimeout);
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return v - 40;
    }
    throw Obd2Exception('Formato temp inválido');
  }

  Future<int> getEngineLoad({Duration? timeout}) async {
    final parts = await _readPidTokens('04', timeout: timeout ?? _normalTimeout);
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return (v * 100) ~/ 255;
    }
    throw Obd2Exception('Formato carga inválido');
  }

  Future<double> getThrottlePosition({Duration? timeout}) async {
    final parts = await _readPidTokens('11', timeout: timeout ?? _normalTimeout);
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return (v * 100.0) / 255.0;
    }
    throw Obd2Exception('Formato TPS inválido');
  }

  Future<int> getIntakePressure() async {
    final parts = await _readPidTokens('0B');
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return v;
    }
    throw Obd2Exception('Formato MAP inválido');
  }

  Future<int> getIntakeTemp() async {
    final parts = await _readPidTokens('0F');
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return v - 40;
    }
    throw Obd2Exception('Formato IAT inválido');
  }

  Future<double> getTimingAdvance() async {
    final parts = await _readPidTokens('0E');
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return (v / 2.0) - 64;
    }
    throw Obd2Exception('Formato avance inválido');
  }

  Future<double> getFuelPressure() async {
    final parts = await _readPidTokens('0A');
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return v * 3.0;
    }
    throw Obd2Exception('Formato fuel pressure inválido');
  }

  Future<double> getMAF() async {
    final parts = await _readPidTokens('10');
    if (parts.length >= 4) {
      final a = _parseInt(parts[2]);
      final b = _parseInt(parts[3]);
      if (a != null && b != null) return (a * 256 + b) / 100.0;
    }
    throw Obd2Exception('Formato MAF inválido');
  }

  Future<double> getFuelLevel() async {
    final parts = await _readPidTokens('2F');
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return (v * 100.0) / 255.0;
    }
    throw Obd2Exception('Formato fuel level inválido');
  }

  Future<int> getBarometricPressure() async {
    final parts = await _readPidTokens('33');
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return v;
    }
    throw Obd2Exception('Formato baro inválido');
  }

  Future<double> getShortTermTrimBank1() async {
    final parts = await _readPidTokens('06');
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return ((v - 128) * 100.0) / 128.0;
    }
    throw Obd2Exception('STFT B1 inválido');
  }

  Future<double> getShortTermTrimBank2() async {
    final parts = await _readPidTokens('08');
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return ((v - 128) * 100.0) / 128.0;
    }
    throw Obd2Exception('STFT B2 inválido');
  }

  Future<double> getLongTermTrimBank1() async {
    final parts = await _readPidTokens('07');
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return ((v - 128) * 100.0) / 128.0;
    }
    throw Obd2Exception('LTFT B1 inválido');
  }

  Future<double> getLongTermTrimBank2() async {
    final parts = await _readPidTokens('09');
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return ((v - 128) * 100.0) / 128.0;
    }
    throw Obd2Exception('LTFT B2 inválido');
  }

  Future<FuelTrim> getAllFuelTrims() async {
    try {
      final stft1 = await getShortTermTrimBank1();
      final stft2 = await getShortTermTrimBank2();
      final ltft1 = await getLongTermTrimBank1();
      final ltft2 = await getLongTermTrimBank2();
      return FuelTrim(
        shortTermBank1: stft1,
        shortTermBank2: stft2,
        longTermBank1: ltft1,
        longTermBank2: ltft2,
        available: true,
      );
    } catch (_) {
      return FuelTrim(
        shortTermBank1: -999,
        shortTermBank2: -999,
        longTermBank1: -999,
        longTermBank2: -999,
        available: false,
      );
    }
  }

  Future<OxygenSensor> getO2Sensor(int bank, int sensor) async {
    int pidBase;
    if (bank == 1) {
      if (sensor < 1 || sensor > 4) throw Exception('Sensor inválido');
      pidBase = 0x14 + (sensor - 1);
    } else if (bank == 2) {
      if (sensor < 1 || sensor > 4) throw Exception('Sensor inválido');
      pidBase = 0x18 + (sensor - 1);
    } else {
      throw Exception('Bank inválido');
    }
    final pidHex = pidBase.toRadixString(16).toUpperCase().padLeft(2, '0');
    final parts = await _readPidTokens(pidHex);
    if (parts.length >= 4) {
      final vByte = _parseInt(parts[2]);
      final tByte = _parseInt(parts[3]);
      if (vByte != null && tByte != null) {
        if (vByte == 0xFF && tByte == 0xFF) {
          throw const Obd2NoDataException('Sensor no presente');
        }
        return OxygenSensor(
          bank: bank,
          sensor: sensor,
          voltage: vByte * 0.005,
          shortTermTrim: ((tByte - 128) * 100.0) / 128.0,
        );
      }
    }
    throw Obd2Exception('Formato O2 inválido');
  }

  Future<List<OxygenSensor>> getOxygenSensors() async {
    final sensors = <OxygenSensor>[];
    for (int b = 1; b <= 2; b++) {
      for (int s = 1; s <= 4; s++) {
        try {
          sensors.add(await getO2Sensor(b, s));
        } catch (_) {}
      }
    }
    return sensors;
  }

  // ---------------------------------------------------------------
  // DTC (modos 03 / 07 / 0A / UDS 19).
  // ---------------------------------------------------------------

  Future<List<DTCCode>> _readDTCs(String command, String marker,
      {Duration timeout = const Duration(seconds: 6)}) async {
    final dtcs = <DTCCode>[];
    try {
      final resp = await sendCommandWithResponse(command, timeout: timeout);
      if (_isNoData(resp)) return dtcs;
      final tokens = parser.extractPayload(resp, marker);
      if (tokens.length >= 2 && tokens[0].toUpperCase() == marker) {
        final count = _parseInt(tokens[1]) ?? 0;
        final codes = <String>[];
        for (int i = 2; i + 1 < tokens.length; i += 2) {
          final hex4 = tokens[i].toUpperCase() + tokens[i + 1].toUpperCase();
          if (hex4 == '0000') continue;
          final dtcCode = parser.decodeDtcBytes(hex4);
          codes.add(dtcCode);
        }
        final n = count == 0
            ? codes.length
            : (count > codes.length ? codes.length : count);
        for (int i = 0; i < n; i++) {
          dtcs.add(DTCCode(
              code: codes[i],
              description: parser.describeDtc(codes[i])));
        }
      }
    } catch (_) {}
    return dtcs;
  }

  Future<List<DTCCode>> _readDTCsFromEcu(String ecuHeader, String command,
      String marker, {Duration timeout = const Duration(seconds: 5)}) async {
    final dtcs = <DTCCode>[];
    try {
      await sendCommandWithResponse('ATSH $ecuHeader', timeout: const Duration(seconds: 2));
      dtcs.addAll(await _readDTCs(command, marker, timeout: timeout));
    } catch (_) {}
    try {
      await sendCommandWithResponse('ATSH 7DF', timeout: const Duration(seconds: 2));
    } catch (_) {}
    return dtcs;
  }

  /// Lee DTCs via UDS servicio 19.
  /// [statusMask] = 0xFF (todos) o 0x09 (confirmed+testFailed).
  Future<List<DTCCode>> _readDtcUds(String ecuHeader, int subFunc,
      {int statusMask = 0xFF, Duration timeout = const Duration(seconds: 5)}) async {
    final dtcs = <DTCCode>[];
    try {
      await sendCommandWithResponse('ATSH $ecuHeader', timeout: const Duration(seconds: 2));
      final subHex = subFunc.toRadixString(16).toUpperCase().padLeft(2, '0');
      final maskHex = statusMask.toRadixString(16).toUpperCase().padLeft(2, '0');
      final cmd = '19$subHex$maskHex';
      final resp = await sendCommandWithResponse(cmd, timeout: timeout);
      if (_isNoData(resp)) return dtcs;
      final tokens = parser.hexTokens(
          parser.normalizeLines(resp).where((l) => l.isNotEmpty).join(' '));
      if (tokens.isEmpty) return dtcs;
      int startIdx = -1;
      for (int i = 0; i < tokens.length; i++) {
        if (tokens[i].toUpperCase() == '59') { startIdx = i + 2; break; }
      }
      if (startIdx < 0 || startIdx >= tokens.length) return dtcs;
      for (int i = startIdx; i + 3 <= tokens.length; i += 4) {
        final b0 = tokens[i];
        final b1 = tokens[i + 1];
        final hex4 = b0.toUpperCase() + b1.toUpperCase();
        if (hex4 == '0000') continue;
        final fullHex = b0 + b1 + (i + 2 < tokens.length ? tokens[i + 2] : '00');
        if (fullHex.toUpperCase() == '000000') continue;
        final dtcCode = parser.decodeDtcBytes(hex4);
        dtcs.add(DTCCode(
            code: dtcCode,
            description: parser.describeDtc(dtcCode)));
      }
    } catch (_) {}
    try {
      await sendCommandWithResponse('ATSH 7DF', timeout: const Duration(seconds: 2));
    } catch (_) {}
    return dtcs;
  }

  /// Lee DTCs via UDS servicio 19 sub-función 06 (DTCExtDataByDTCNumber).
  Future<List<DTCCode>> _readDtcExtData(String ecuHeader,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final dtcs = <DTCCode>[];
    try {
      await sendCommandWithResponse('ATSH $ecuHeader', timeout: const Duration(seconds: 2));
      // 19 06 FF FF 09 → all DTCs, all ext data records, confirmed mask
      final resp = await sendCommandWithResponse('1906FFFF09', timeout: timeout);
      if (_isNoData(resp)) return dtcs;
      final tokens = parser.hexTokens(
          parser.normalizeLines(resp).where((l) => l.isNotEmpty).join(' '));
      if (tokens.isEmpty) return dtcs;
      int startIdx = -1;
      for (int i = 0; i < tokens.length; i++) {
        if (tokens[i].toUpperCase() == '59' && tokens[i + 1].toUpperCase() == '06') {
          startIdx = i + 2; break;
        }
      }
      if (startIdx < 0 || startIdx >= tokens.length) return dtcs;
      // Format: DTC_hi DTC_lo status [extData...] DTC_hi DTC_lo status ...
      for (int i = startIdx; i + 2 <= tokens.length; i += 3) {
        final hex4 = tokens[i].toUpperCase() + tokens[i + 1].toUpperCase();
        if (hex4 == '0000') continue;
        final fullHex = tokens[i] + tokens[i + 1] + tokens[i + 2];
        if (fullHex.toUpperCase() == '000000') continue;
        final dtcCode = parser.decodeDtcBytes(hex4);
        dtcs.add(DTCCode(
            code: dtcCode,
            description: parser.describeDtc(dtcCode)));
      }
    } catch (_) {}
    try {
      await sendCommandWithResponse('ATSH 7DF', timeout: const Duration(seconds: 2));
    } catch (_) {}
    return dtcs;
  }

  Future<List<DTCCode>> getDTCs() async {
    final dtcs = <DTCCode>[];
    final seen = <String>{};

    void addUnique(List<DTCCode> list, {String source = ''}) {
      for (final d in list) {
        if (d.code != 'NONE' && !seen.contains(d.code)) {
          seen.add(d.code);
          if (source.isNotEmpty) {
            dtcs.add(DTCCode(code: d.code, description: d.description, source: source));
          } else {
            dtcs.add(d);
          }
        }
      }
    }

    const ecuHeaders = ['7E0', '7E1', '7E2', '7E3'];
    const ecuNames = ['Motor', 'Transmisión', 'ABS/Frenos', 'Airbag'];

    // 1. Broadcast estándar OBD-II modo 03
    addUnique(await _readDTCs('03', '43'));

    // 2. OBD-II modo 03 por headers CAN específicos
    for (int i = 0; i < ecuHeaders.length; i++) {
      addUnique(await _readDTCsFromEcu(ecuHeaders[i], '03', '43'), source: ecuNames[i]);
    }

    // 3. UDS 19 02 (reportDTCByStatusMask) — status 0xFF = todos los DTCs
    for (int i = 0; i < ecuHeaders.length; i++) {
      addUnique(await _readDtcUds(ecuHeaders[i], 2, statusMask: 0xFF), source: ecuNames[i]);
    }

    // 4. UDS 19 06 (DTCExtDataByDTCNumber) — extiende cobertura
    for (int i = 0; i < ecuHeaders.length; i++) {
      addUnique(await _readDtcExtData(ecuHeaders[i]), source: ecuNames[i]);
    }

    // 5. UDS 19 17 (reportDTCBySeverityMaskRecord) — severidad
    for (int i = 0; i < ecuHeaders.length; i++) {
      try {
        await sendCommandWithResponse('ATSH ${ecuHeaders[i]}', timeout: const Duration(seconds: 2));
        final resp = await sendCommandWithResponse('1917FF', timeout: const Duration(seconds: 5));
        if (!_isNoData(resp)) {
          final tokens = parser.hexTokens(
              parser.normalizeLines(resp).where((l) => l.isNotEmpty).join(' '));
          for (int j = 0; j < tokens.length; j++) {
            if (tokens[j].toUpperCase() == '59' && j + 4 <= tokens.length) {
              // 59 17 severity DTC_hi DTC_lo status
              final hex4 = tokens[j + 2].toUpperCase() + tokens[j + 3].toUpperCase();
              if (hex4 != '0000') {
                addUnique([DTCCode(code: parser.decodeDtcBytes(hex4), description: parser.describeDtc(parser.decodeDtcBytes(hex4)))], source: ecuNames[i]);
              }
              j += 4;
            }
          }
        }
      } catch (_) {}
    }

    try {
      await sendCommandWithResponse('ATSH 7DF', timeout: const Duration(seconds: 2));
    } catch (_) {}

    if (dtcs.isEmpty) {
      dtcs.add(const DTCCode(
          code: 'NONE', description: 'No hay códigos de error almacenados'));
    }
    return dtcs;
  }

  Future<List<DTCCode>> getPendingDTCs() async {
    final dtcs = <DTCCode>[];
    final seen = <String>{};

    void addUnique(List<DTCCode> list, {String source = ''}) {
      for (final d in list) {
        if (d.code != 'NONE' && !seen.contains(d.code)) {
          seen.add(d.code);
          if (source.isNotEmpty) {
            dtcs.add(DTCCode(code: d.code, description: d.description, source: source));
          } else {
            dtcs.add(d);
          }
        }
      }
    }

    const ecuHeaders = ['7E0', '7E1', '7E2', '7E3'];
    const ecuNames = ['Motor', 'Transmisión', 'ABS/Frenos', 'Airbag'];

    // 1. Broadcast OBD-II modo 07
    addUnique(await _readDTCs('07', '47'));

    // 2. Headers CAN específicos
    for (int i = 0; i < ecuHeaders.length; i++) {
      addUnique(await _readDTCsFromEcu(ecuHeaders[i], '07', '47'), source: ecuNames[i]);
    }

    // 3. UDS 19 12 (reportDTCSnapshotIdentification) — pending via UDS
    for (int i = 0; i < ecuHeaders.length; i++) {
      addUnique(await _readDtcUds(ecuHeaders[i], 12, statusMask: 0xFF), source: ecuNames[i]);
    }

    // 4. UDS 19 18 (reportDTCBySeverityMaskRecord) — pending + severity
    for (int i = 0; i < ecuHeaders.length; i++) {
      addUnique(await _readDtcUds(ecuHeaders[i], 18, statusMask: 0x09), source: ecuNames[i]);
    }

    if (dtcs.isEmpty) {
      dtcs.add(const DTCCode(code: 'NONE', description: 'No hay códigos pendientes'));
    }
    return dtcs;
  }

  Future<List<DTCCode>> getPermanentDTCs() async {
    final dtcs = <DTCCode>[];
    final seen = <String>{};

    void addUnique(List<DTCCode> list, {String source = ''}) {
      for (final d in list) {
        if (d.code != 'NONE' && !seen.contains(d.code)) {
          seen.add(d.code);
          if (source.isNotEmpty) {
            dtcs.add(DTCCode(code: d.code, description: d.description, source: source));
          } else {
            dtcs.add(d);
          }
        }
      }
    }

    const ecuHeaders = ['7E0', '7E1', '7E2', '7E3'];
    const ecuNames = ['Motor', 'Transmisión', 'ABS/Frenos', 'Airbag'];

    // 1. Broadcast OBD-II modo 0A
    addUnique(await _readDTCs('0A', '4A'));

    // 2. Headers CAN específicos
    for (int i = 0; i < ecuHeaders.length; i++) {
      addUnique(await _readDTCsFromEcu(ecuHeaders[i], '0A', '4A'), source: ecuNames[i]);
    }

    // 3. UDS 19 13 (reportSupportedDTCs) — algunos ECUs reportan permanentes aquí
    for (int i = 0; i < ecuHeaders.length; i++) {
      addUnique(await _readDtcUds(ecuHeaders[i], 13, statusMask: 0xFF), source: ecuNames[i]);
    }

    if (dtcs.isEmpty) {
      dtcs.add(const DTCCode(code: 'NONE', description: 'No hay códigos permanentes'));
    }
    return dtcs;
  }

  Future<bool> clearDTCs() async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final resp = await sendCommandWithResponse('04',
            timeout: const Duration(seconds: 4));
        final u = resp.toUpperCase();
        if (u.contains('OK') || u.contains('44')) return true;
        if (_isElmError(resp)) return false;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));
    }
    // Fallback: reinicializar y reintentar una vez.
    try {
      await _initializeElm327();
      final resp = await sendCommandWithResponse('04',
          timeout: const Duration(seconds: 4));
      final u = resp.toUpperCase();
      return u.contains('OK') || u.contains('44');
    } catch (_) {
      return false;
    }
  }

  Future<bool> isMILActive() async {
    try {
      final parts = await _readPidTokens('01');
      if (parts.length >= 3) {
        final v = _parseInt(parts[2]);
        if (v != null) return (v & 0x80) != 0;
      }
    } catch (_) {}
    return false;
  }

  static String _decodeDTCCode(String code) => parser.decodeDTCCode(code);

  // ---------------------------------------------------------------
  // Info del vehículo (modo 09).
  // ---------------------------------------------------------------

  Future<String> getVIN() async {
    try {
      final resp = await sendCommandWithResponse('0902',
          timeout: const Duration(seconds: 6));
      if (_isNoData(resp)) return 'No disponible';
      final tokens = parser.extractPayload(resp, '4902');
      if (tokens.length < 3) return 'No disponible';
      final bytes = _toBytes(tokens.sublist(3));
      final vin = String.fromCharCodes(bytes.where((b) => b >= 32 && b <= 126));
      if (vin.length >= 11) return vin;
    } catch (_) {}
    return 'No disponible';
  }

  // ---------------------------------------------------------------
  // Protocolo.
  // ---------------------------------------------------------------

  Future<String> getProtocol() async {
    try {
      final resp = await sendCommandWithResponse('ATDP',
          timeout: const Duration(seconds: 2));
      final clean = resp
          .replaceAll('\r', '')
          .replaceAll('\n', '')
          .replaceAll('>', '')
          .trim();
      if (clean.isNotEmpty) return clean;
    } catch (_) {}
    return _protocolLabel;
  }

  Future<int?> getProtocolNumber(
      {Duration timeout = const Duration(seconds: 2)}) async {
    try {
      final resp = await sendCommandWithResponse('ATDPN', timeout: timeout);
      _protocolNumber = parser.parseProtocolNumber(resp);
      _elmFormat = ElmFormat.fromProtocolNumber(_protocolNumber ?? 0);
    } catch (_) {}
    return _protocolNumber;
  }

  Future<ElmFormat> getProtocolInfo() async {
    if (_protocolNumber == null) await getProtocolNumber();
    _elmFormat = ElmFormat.fromProtocolNumber(_protocolNumber ?? 0);
    return _elmFormat;
  }

  String get protocolLabel => _protocolLabel;
  int? get protocolNumber => _protocolNumber;
  ElmFormat get elmFormat => _elmFormat;

  // ---------------------------------------------------------------
  // Keepalive / comprobación rápida de conexión.
  // ---------------------------------------------------------------

  Future<bool> keepAlive({Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final resp = await sendCommandWithResponse('0100', timeout: timeout);
      return !_isElmError(resp) && !_isNoData(resp);
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------
  // PIDs soportados.
  // ---------------------------------------------------------------

  Future<List<int>> getSupportedPIDs() async {
    final pids = <int>[];
    const ranges = [
      ('00', 0x00),
      ('20', 0x20),
      ('40', 0x40),
      ('60', 0x60),
    ];
    for (final (pidRange, base) in ranges) {
      try {
        final parts = await _readPidTokens(pidRange);
        if (parts.length >= 6) {
          for (int j = 0; j < 4; j++) {
            final v = _parseInt(parts[2 + j]);
            if (v != null) {
              for (int bit = 0; bit < 8; bit++) {
                if ((v & (1 << (7 - bit))) != 0) {
                  final pid = base + (j * 8) + bit + 1;
                  if (pid <= 0x60 || pid > 0x60) {
                    pids.add(pid);
                  }
                }
              }
            }
          }
        }
      } catch (_) {}
    }
    return pids;
  }

  // ---------------------------------------------------------------
  // Modo 2 (freeze frame), UDS y utilidades.
  // ---------------------------------------------------------------

  /// Lee un PID de freeze frame (modo 02). Devuelve los bytes de datos
  /// (tras el marcador `42xx`).
  Future<List<int>> getFreezeFrame(int pid,
      {Duration timeout = const Duration(seconds: 4)}) async {
    final pidHex = pid.toRadixString(16).toUpperCase().padLeft(2, '0');
    final resp = await sendCommandWithResponse('02$pidHex', timeout: timeout);
    if (_isNoData(resp)) {
      throw Obd2NoDataException('NO DATA freeze frame 02$pidHex');
    }
    final tokens = parser.extractPayload(resp, '42$pidHex');
    final bytes = _toBytes(tokens);
    if (bytes.length < 3) {
      throw Obd2Exception('Formato freeze frame inválido');
    }
    return bytes.sublist(2);
  }

  /// Lee el voltaje de alimentación del adaptador (`ATRV`).
  Future<double?> getVoltage({Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final resp = await sendCommandWithResponse('ATRV', timeout: timeout);
      final m = RegExp(r'(\d+\.?\d*)').firstMatch(resp);
      if (m != null) return double.tryParse(m.group(1)!);
    } catch (_) {}
    return null;
  }

  /// Envía un comando UDS (p. ej. `3E00`) y comprueba que no hay error.
  Future<bool> testerPresent({String command = '3E00', Duration timeout = const Duration(seconds: 4)}) async {
    try {
      final resp = await sendCommandWithResponse(command, timeout: timeout);
      return !_isElmError(resp) && !_isNoData(resp);
    } catch (_) {
      return false;
    }
  }

  /// Envía un comando UDS genérico (p. ej. `22xxxx`) y devuelve la respuesta.
  Future<String> sendUDS(String command,
      {Duration timeout = const Duration(seconds: 4)}) {
    return sendCommandWithResponse(command, timeout: timeout);
  }

  String _deriveMarker(String command) {
    final c = command.trim();
    if (c.length >= 4 && c.startsWith('01')) return '41${c.substring(2, 4)}';
    if (c.length >= 4 && c.startsWith('02')) return '42${c.substring(2, 4)}';
    if (c.startsWith('0902')) return '4902';
    if (c.startsWith('09')) return '49';
    if (c.startsWith('03')) return '43';
    if (c.startsWith('07')) return '47';
    if (c.startsWith('0A')) return '4A';
    if (c.startsWith('06')) return '46';
    if (c.length >= 6 && c.startsWith('22')) return '62';
    if (c.startsWith('3E')) return '7E';
    return '';
  }

  /// Envía un comando de datos y devuelve los bytes del payload decodificados.
  Future<List<int>> sendDataCommand(String command,
      {String? expectedService, Duration timeout = const Duration(seconds: 4)}) async {
    final resp = await sendCommandWithResponse(command, timeout: timeout);
    if (_isElmError(resp)) {
      throw Obd2Exception('ELM: ${_truncateResponse(resp)}');
    }
    if (_isNoData(resp)) {
      throw Obd2NoDataException('NO DATA para $command');
    }
    final marker = (expectedService ?? _deriveMarker(command)).toUpperCase();
    if (marker.isEmpty) {
      throw Obd2Exception('No se puede deducir el marcador de $command');
    }
    final tokens = parser.extractPayload(resp, marker);
    final bytes = _toBytes(tokens);
    if (bytes.isEmpty) {
      throw Obd2Exception('Formato inválido para $command');
    }
    return bytes;
  }

  // ---------------------------------------------------------------
  // Catálogo de comandos (ver docs/04-comandos-elm.md).
  // ---------------------------------------------------------------

  static const List<String> defaultInitCommands = ['ATD', 'ATD0', 'ATE0', 'ATH1'];

  static const List<String> postInitCommands = [
    'ATE0', 'ATH1', 'ATM0', 'ATS0', 'ATAT1', 'ATAL',
  ];

  static const List<String> nc2InitCommands = [
    'ATD', 'ATD0', 'ATE0', 'ATH1', 'ATM0', 'ATS0', 'ATAT1', 'ATSP5',
    'ATAL', 'ATIB10', 'ATSH8110FC', 'ATST20', 'ATSW05',
    '2212010401', '221201', 'ATSW05', 'ATWM221201',
  ];

  /// Tabla de init por protocolo (GetAdditionalInit, números 12–45).
  static const Map<int, List<String>> protocolInitCommands = {
    12: ['ATSP5', 'ATIB96'],
    13: ['ATSP5', 'ATIB48'],
    14: ['ATSP5', 'ATIB48', 'ATIIA7A'],
    15: ['ATSP5', 'ATIB48', 'ATIIA13'],
    16: ['ATSP5', 'ATIB48', 'ATIIA33'],
    17: ['ATSP4', 'ATIB96'],
    18: ['ATSP4', 'ATIB48'],
    19: ['ATSP4', 'ATIB48', 'ATIIA7A'],
    20: ['ATSP4', 'ATIB48', 'ATIIA13'],
    21: ['ATSP4', 'ATIB48', 'ATIIA33'],
    22: ['ATSP3', 'ATIB96'],
    23: ['ATSP3', 'ATIB48'],
    24: ['ATSP3', 'ATIB48', 'ATIIA7A'],
    25: ['ATSP3', 'ATIB48', 'ATIIA13'],
    26: ['ATSP3', 'ATIB48', 'ATIIA33'],
    27: ['ATSP5', 'ATSH8013F1', 'ATIB10', 'ATIIA13'],
    28: ['ATSP5', 'ATSH8013F0', 'ATIB96', 'ATIIA13'],
    29: ['ATSP5', 'ATSH8213F0', 'ATIB96', 'ATIIA13'],
    30: ['ATSP5', 'ATSH8013FC', 'ATIB10', 'ATIIA10'],
    31: ['ATSP5', 'ATSH8013FC', 'ATIB96', 'ATIIA10'],
    32: ['ATSP4', 'ATSH8013F1', 'ATIB10', 'ATIIA13'],
    33: ['ATSP4', 'ATSH8013F0', 'ATIB96', 'ATIIA13'],
    34: ['ATSP4', 'ATSH8213F0', 'ATIB96', 'ATIIA13'],
    35: ['ATSP4', 'ATSH8013FC', 'ATIB10', 'ATIIA13'],
    36: ['ATSP4', 'ATSH8013F1', 'ATIB96', 'ATIIA13'],
    37: ['ATSP4', 'ATSH8113F1', 'ATIB96', 'ATIIA13'],
    38: ['ATSP5', 'ATSH8110FC', 'ATIB10', 'ATIIA10'],
    39: ['ATSP4', 'ATSH8013F1', 'ATIB10', 'ATIIA13'],
    40: ['ATSP5', 'ATSH8113F1', 'ATIB96', 'ATIIA13'],
    41: ['ATSP5', 'ATSH8213F1', 'ATIB96', 'ATIIA13'],
    42: ['ATSP3', 'ATSH686AF1', 'ATIB10', 'ATIIA33'],
    43: ['ATSP6', 'ATSH7E0', '10C0'],
    44: ['ATSP5', 'ATSH8110F1', 'ATIB10', 'ATST20'],
    45: ['ATSP6', 'ATFCSH7E0', 'ATFCSD30000000', 'ATFCSM1'],
  };

  /// Ejecuta la secuencia de init por protocolo (tabla 12–45).
  Future<bool> initProtocol(int protocolNumber,
      {Duration timeout = const Duration(seconds: 4)}) async {
    final commands = protocolInitCommands[protocolNumber];
    if (commands == null) return false;
    _elmState.clear();
    var ok = true;
    for (final c in commands) {
      if (c.startsWith('AT')) {
        if (!await _sendAt(c, timeout: timeout)) ok = false;
      } else {
        try {
          await sendCommandWithResponse(c, timeout: timeout);
        } catch (_) {
          ok = false;
        }
      }
    }
    return ok;
  }

  /// Ejecuta la secuencia `default_init` documentada.
  Future<bool> runDefaultInit() async {
    _elmState.clear();
    for (final c in defaultInitCommands) {
      if (!await _sendAt(c, timeout: const Duration(seconds: 4))) return false;
    }
    return true;
  }

  /// Ejecuta la secuencia `post_init` documentada.
  Future<bool> runPostInit() async {
    _elmState.clear();
    for (final c in postInitCommands) {
      if (!await _sendAt(c, timeout: const Duration(seconds: 4))) return false;
    }
    return true;
  }

  /// Ejecuta la secuencia `nc2_init` (Nissan Consult 2).
  Future<bool> runNC2Init() async {
    _elmState.clear();
    for (final c in nc2InitCommands) {
      if (c.startsWith('AT')) {
        if (!await _sendAt(c, timeout: const Duration(seconds: 4))) return false;
      } else {
        try {
          await sendCommandWithResponse(c, timeout: const Duration(seconds: 5));
        } catch (_) {
          return false;
        }
      }
    }
    return true;
  }

  /// Configuración CAN por petición (ver docs/04-comandos-elm.md §4.4).
  /// Si [config] es null, se envía el comando sin configuración previa.
  Future<String> sendCanRequest(String command,
      {CanRequestConfig? config, Duration timeout = const Duration(seconds: 5)}) {
    if (config == null) {
      return sendCommandWithResponse(command, timeout: timeout);
    }
    return _run(() async {
      final before = <String>[];
      final after = <String>[];

      if (config.canPriority != null) before.add('ATCP${config.canPriority}');
      before.add('ATSP${config.protocol.toRadixString(16).toUpperCase()}');

      final rh = config.requestHeader?.toUpperCase();
      if (rh != null && rh != '7DF') {
        before.add('ATFCSH${config.requestHeader}');
        before.add(config.extendedAddress != null
            ? 'ATFCSD${config.extendedAddress}300005'
            : 'ATFCSD300005');
        before.add('ATFCSM1');
      } else {
        before.add('ATFCSM0');
      }

      if (config.responseHeader == null || rh == '7DF') {
        before.add('ATAR');
      } else {
        before.add('ATCRA${config.responseHeader}');
      }

      if (config.extendedAddress != null) {
        before.add('ATCEA${config.extendedAddress}');
      }
      if (config.testerAddress != null) {
        before.add('ATTA${config.testerAddress}');
      }

      if (config.restoreAfter) {
        after.addAll(['ATAR', 'ATFCSM0', 'ATCEA', 'ATSTDEF', 'ATSP0']);
      }

      for (final c in before) {
        await _sendAtDedup(c);
      }
      final resp = await _sendAndWait(command, timeout: timeout);
      for (final c in after) {
        await _sendAtDedup(c, force: true);
      }
      return resp;
    });
  }
}
