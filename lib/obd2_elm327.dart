import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';

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

  DTCCode({required this.code, required this.description});
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

class Obd2Elm327 {
  BluetoothConnection? _connection;
  bool _isConnected = false;
  final StreamController<String> _responseController =
      StreamController<String>.broadcast();
  StreamSubscription<Uint8List>? _inputSubscription;

  Stream<String> get responseStream => _responseController.stream;
  bool get isConnected => _isConnected;

  Future<bool> connect(String targetMacAddress) async {
    try {
      await disconnect();
      _responseController.add("Verificando Bluetooth...\n");
      bool? isAvailable = await FlutterBluetoothSerial.instance.isAvailable;
      if (isAvailable != true) {
        throw Exception("Bluetooth no soportado en este dispositivo.");
      }
      _responseController.add("✓ Bluetooth disponible\n");

      bool? isEnabled = await FlutterBluetoothSerial.instance.isEnabled;
      if (isEnabled != true) {
        throw Exception("Bluetooth no encendido. Actívalo desde Ajustes.");
      }
      _responseController.add("✓ Bluetooth encendido\n");

      // Intentar emparejar si no lo está
      _responseController.add("Verificando emparejamiento...\n");
      try {
        final bondState = await FlutterBluetoothSerial.instance.getBondStateForAddress(targetMacAddress);
        if (!bondState.isBonded) {
          _responseController.add("Dispositivo no emparejado. Intentando emparejar...\n");
          bool? bonded = await FlutterBluetoothSerial.instance.bondDeviceAtAddress(targetMacAddress);
          if (bonded != true) {
            _responseController.add("⚠️ No se pudo emparejar automáticamente. Verifica en Ajustes Bluetooth.\n");
          } else {
            _responseController.add("✓ Emparejado correctamente\n");
          }
        } else {
          _responseController.add("✓ Dispositivo ya emparejado\n");
        }
      } catch (e) {
        _responseController.add("⚠️ Error al verificar emparejamiento: $e\n");
      }

      // Conectar RFCOMM al ELM327 (con reintento)
      _responseController.add("Conectando RFCOMM con $targetMacAddress...\n");
      const maxAttempts = 2;
      bool connected = false;
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          if (attempt > 1) {
            _responseController.add("Reintento $attempt de $maxAttempts...\n");
            await Future.delayed(const Duration(seconds: 1));
          }
          _connection = await BluetoothConnection.toAddress(targetMacAddress)
              .timeout(const Duration(seconds: 10), onTimeout: () {
            throw Exception("Timeout al conectar (10s). Verifica que el ELM327 esté encendido y cerca.");
          });
          connected = true;
          break;
        } catch (e) {
          if (attempt == maxAttempts) rethrow;
          _responseController.add("  Falló intento $attempt, reintentando...\n");
          try { await _connection?.close(); } catch (_) {}
          _connection = null;
        }
      }

      _isConnected = true;
      _responseController.add("✓ Conexión RFCOMM establecida\n");

      await Future.delayed(const Duration(milliseconds: 500));

      _inputSubscription = _connection!.input!.listen((Uint8List data) {
        String response = utf8.decode(data, allowMalformed: true);
        _responseController.add(response);
      });

      _responseController.add("Inicializando ELM327...\n");
      await _initializeElm327();
      return true;
    } catch (e, st) {
      _isConnected = false;
      await _inputSubscription?.cancel();
      _inputSubscription = null;
      try { await _connection?.close(); } catch (_) {}
      _connection = null;
      _responseController.add("\n=== ERROR DE CONEXIÓN ===\n");
      _responseController.add("Tipo: ${e.runtimeType}\n");
      _responseController.add("Mensaje: $e\n");
      final stack = st.toString().split("\n");
      final limit = stack.length > 6 ? 6 : stack.length;
      for (int i = 0; i < limit; i++) {
        if (stack[i].contains("package:flutter_bluetooth_serial_plus") ||
            stack[i].contains("BluetoothConnection") ||
            stack[i].contains(".connect(")) {
          _responseController.add("  ${stack[i]}\n");
        }
      }
      _responseController.add("========================\n");
      _responseController.add("\n💡 SUGERENCIAS:\n");
      _responseController.add("  1. Verifica que el auto esté en ACC o encendido\n");
      _responseController.add("  2. El ELM327 debe tener luz LED fija (no parpadeando)\n");
      _responseController.add("  3. Ve a Ajustes → Bluetooth → empareja \"OBDII\" manualmente\n");
      _responseController.add("  4. Apaga y enciende Bluetooth del móvil\n");
      _responseController.add("  5. Desconecta la batería del ELM327 10s y reconecta\n");
      return false;
    }
  }

  Future<void> sendCommand(String command) async {
    if (!_isConnected || _connection == null) {
      throw Exception("No conectado.");
    }
    String cmd = command.trim();
    if (!cmd.endsWith("\r")) cmd += "\r";
    _connection!.output.add(Uint8List.fromList(utf8.encode(cmd)));
    await _connection!.output.allSent;
  }

  /// Envía un comando y espera a recibir el prompt ">" del ELM327
  /// para asegurar que el dispositivo está listo para el siguiente comando.
  Future<String> sendCommandWithResponse(String command,
      {Duration timeout = const Duration(seconds: 4)}) async {
    if (!_isConnected) throw Exception("No conectado.");
    final completer = Completer<String>();
    final buffer = StringBuffer();
    StreamSubscription? sub;

    try {
      sub = responseStream.listen((data) {
        buffer.write(data);
        // Verificar el buffer ACUMULADO, no solo el chunk actual
        if (buffer.toString().contains(">") && !completer.isCompleted) {
          completer.complete(buffer.toString());
          sub?.cancel();
        }
      });

      await sendCommand(command);

      final result = await completer.future.timeout(
        timeout,
        onTimeout: () {
          sub?.cancel();
          if (buffer.isNotEmpty) {
            return buffer.toString();
          }
          throw TimeoutException("Sin respuesta del ELM327 para: $command ($timeout)");
        },
      );

      return result;
    } catch (_) {
      // Asegurar limpieza de la suscripción en cualquier error
      sub?.cancel();
      rethrow;
    }
  }

  /// Envía un comando AT y verifica que la respuesta contenga "OK".
  /// Si no obtiene "OK", reintenta una vez.
  Future<bool> _sendATCommand(String command,
      {Duration timeout = const Duration(seconds: 3)}) async {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final resp = await sendCommandWithResponse(command, timeout: timeout);
        if (resp.contains("OK") || resp.contains(">")) {
          return true;
        }
      } catch (_) {
        // Si falla, reintenta
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  Future<void> _initializeElm327() async {
    _responseController.add("Inicializando ELM327...\n");

    // ATZ - Reset ELM327, esperar respuesta (puede tardar hasta 3s)
    try {
      final atzResp = await sendCommandWithResponse("ATZ",
          timeout: const Duration(seconds: 5));
      _responseController.add("ATZ: ${_truncateResponse(atzResp)}\n");
    } catch (e) {
      _responseController.add("ATZ timeout (esperando 3s)...\n");
      await Future.delayed(const Duration(seconds: 3));
    }

    // ATE0 - Echo OFF
    await _sendATCommand("ATE0");
    await Future.delayed(const Duration(milliseconds: 200));

    // ATL0 - Linefeeds OFF
    await _sendATCommand("ATL0");
    await Future.delayed(const Duration(milliseconds: 200));

    // ATS0 - Spaces OFF (como en la implementación C++ que funciona)
    // Las respuestas serán continuas sin espacios: "410C0A0A>"
    await _sendATCommand("ATS0");
    await Future.delayed(const Duration(milliseconds: 200));

    // NOTA: NO enviamos ATH0 (headers off) porque _parseResponse()
    // necesita el prefijo "41" en las respuestas de los PIDs.

    // ATSP0 - Protocolo automático
    await _sendATCommand("ATSP0", timeout: const Duration(seconds: 4));
    await Future.delayed(const Duration(milliseconds: 200));

    // ATAT1 - Adaptor timeout mínimo
    await _sendATCommand("ATAT1");
    await Future.delayed(const Duration(milliseconds: 200));

    // ATST20 - Search timeout 200ms
    await _sendATCommand("ATST20");
    await Future.delayed(const Duration(milliseconds: 200));

    _responseController.add("✓ ELM327 inicializado correctamente\n");
  }

  /// Trunca respuestas largas para el log
  String _truncateResponse(String resp) {
    final clean = resp.replaceAll("\r", "").replaceAll("\n", "").trim();
    if (clean.length > 60) return "${clean.substring(0, 60)}...";
    return clean;
  }

  /// Parsea la respuesta del ELM327.
  /// Soporta formatos CON espacios ("41 0C 0A 0A") y SIN espacios ("410C0A0A").
  /// Devuelve una lista de strings hexadecimales: ["41", "0C", "0A", "0A"]
  List<String> _parseResponse(String response, String expectedPid) {
    // Limpiar saltos de línea y prompt
    var clean = response
        .replaceAll("\r", "")
        .replaceAll("\n", "");
    if (clean.contains(">")) {
      clean = clean.substring(0, clean.indexOf(">"));
    }
    clean = clean.trim();

    // Buscar "41XX" (modo 41 + PID esperado) en el string limpio
    // Puede ser "41 0C" (con espacios) o "410C" (sin espacios)
    final searchStr = "41${expectedPid}";
    final searchStrSpaced = "41 $expectedPid";

    int idx = -1;
    if (clean.contains(searchStrSpaced)) {
      // Formato con espacios
      idx = clean.indexOf(searchStrSpaced);
      if (idx >= 0) {
        final data = clean.substring(idx);
        return data.split(RegExp(r"\s+"));
      }
    }

    if (clean.contains(searchStr)) {
      // Formato sin espacios (ATS0 activo)
      idx = clean.indexOf(searchStr);
      if (idx >= 0) {
        final data = clean.substring(idx); // ej: "410C0A0A"
        final parts = <String>[];
        for (int i = 0; i + 1 < data.length; i += 2) {
          parts.add(data.substring(i, i + 2));
        }
        return parts;
      }
    }

    return [];
  }

  int? _parseInt(String s) => int.tryParse(s, radix: 16);

  Future<int> getRpm() async {
    final resp = await sendCommandWithResponse("010C");
    final parts = _parseResponse(resp, "0C");
    if (parts.length >= 4) {
      final a = _parseInt(parts[2]);
      final b = _parseInt(parts[3]);
      if (a != null && b != null) return ((a * 256) + b) ~/ 4;
    }
    throw Exception("Formato RPM inválido: $resp");
  }

  Future<int> getSpeed() async {
    final resp = await sendCommandWithResponse("010D");
    final parts = _parseResponse(resp, "0D");
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return v;
    }
    throw Exception("Formato velocidad inválido: $resp");
  }

  Future<int> getCoolantTemp() async {
    final resp = await sendCommandWithResponse("0105");
    final parts = _parseResponse(resp, "05");
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return v - 40;
    }
    throw Exception("Formato temp inválido: $resp");
  }

  Future<int> getEngineLoad() async {
    final resp = await sendCommandWithResponse("0104");
    final parts = _parseResponse(resp, "04");
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return (v * 100) ~/ 255;
    }
    throw Exception("Formato carga inválido: $resp");
  }

  Future<double> getThrottlePosition() async {
    final resp = await sendCommandWithResponse("0111");
    final parts = _parseResponse(resp, "11");
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return (v * 100.0) / 255.0;
    }
    throw Exception("Formato TPS inválido: $resp");
  }

  Future<int> getIntakePressure() async {
    final resp = await sendCommandWithResponse("010B");
    final parts = _parseResponse(resp, "0B");
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return v;
    }
    throw Exception("Formato MAP inválido: $resp");
  }

  Future<int> getIntakeTemp() async {
    final resp = await sendCommandWithResponse("010F");
    final parts = _parseResponse(resp, "0F");
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return v - 40;
    }
    throw Exception("Formato IAT inválido: $resp");
  }

  Future<double> getTimingAdvance() async {
    final resp = await sendCommandWithResponse("010E");
    final parts = _parseResponse(resp, "0E");
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return (v / 2.0) - 64;
    }
    throw Exception("Formato avance inválido: $resp");
  }

  Future<double> getFuelPressure() async {
    final resp = await sendCommandWithResponse("010A");
    final parts = _parseResponse(resp, "0A");
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return v * 3.0;
    }
    throw Exception("Formato fuel pressure inválido: $resp");
  }

  Future<double> getMAF() async {
    final resp = await sendCommandWithResponse("0110");
    final parts = _parseResponse(resp, "10");
    if (parts.length >= 4) {
      final a = _parseInt(parts[2]);
      final b = _parseInt(parts[3]);
      if (a != null && b != null) return (a * 256 + b) / 100.0;
    }
    throw Exception("Formato MAF inválido: $resp");
  }

  Future<double> getFuelLevel() async {
    final resp = await sendCommandWithResponse("012F");
    final parts = _parseResponse(resp, "2F");
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return (v * 100.0) / 255.0;
    }
    throw Exception("Formato fuel level inválido: $resp");
  }

  Future<int> getBarometricPressure() async {
    final resp = await sendCommandWithResponse("0133");
    final parts = _parseResponse(resp, "33");
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return v;
    }
    throw Exception("Formato baro inválido: $resp");
  }

  Future<double> getShortTermTrimBank1() async {
    final resp = await sendCommandWithResponse("0106");
    final parts = _parseResponse(resp, "06");
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return ((v - 128) * 100.0) / 128.0;
    }
    throw Exception("STFT B1 inválido: $resp");
  }

  Future<double> getShortTermTrimBank2() async {
    final resp = await sendCommandWithResponse("0108");
    final parts = _parseResponse(resp, "08");
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return ((v - 128) * 100.0) / 128.0;
    }
    throw Exception("STFT B2 inválido: $resp");
  }

  Future<double> getLongTermTrimBank1() async {
    final resp = await sendCommandWithResponse("0107");
    final parts = _parseResponse(resp, "07");
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return ((v - 128) * 100.0) / 128.0;
    }
    throw Exception("LTFT B1 inválido: $resp");
  }

  Future<double> getLongTermTrimBank2() async {
    final resp = await sendCommandWithResponse("0109");
    final parts = _parseResponse(resp, "09");
    if (parts.length >= 3) {
      final v = _parseInt(parts[2]);
      if (v != null) return ((v - 128) * 100.0) / 128.0;
    }
    throw Exception("LTFT B2 inválido: $resp");
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
      if (sensor < 1 || sensor > 4) throw Exception("Sensor inválido");
      pidBase = 0x14 + (sensor - 1);
    } else if (bank == 2) {
      if (sensor < 1 || sensor > 4) throw Exception("Sensor inválido");
      pidBase = 0x18 + (sensor - 1);
    } else {
      throw Exception("Bank inválido");
    }
    final pidStr = "01${pidBase.toRadixString(16).toUpperCase().padLeft(2, '0')}";
    final pidHex = pidBase.toRadixString(16).toUpperCase().padLeft(2, '0');
    final resp = await sendCommandWithResponse(pidStr);
    final parts = _parseResponse(resp, pidHex);
    if (parts.length >= 4) {
      final vByte = _parseInt(parts[2]);
      final tByte = _parseInt(parts[3]);
      if (vByte != null && tByte != null) {
        if (vByte == 0xFF && tByte == 0xFF) {
          throw Exception("Sensor no presente");
        }
        return OxygenSensor(
          bank: bank,
          sensor: sensor,
          voltage: vByte * 0.005,
          shortTermTrim: ((tByte - 128) * 100.0) / 128.0,
        );
      }
    }
    throw Exception("Formato O2 inválido: $resp");
  }

  Future<List<OxygenSensor>> getOxygenSensors() async {
    final sensors = <OxygenSensor>[];
    final pids = [
      (0x14, 1, 1),
      (0x15, 1, 2),
      (0x16, 1, 3),
      (0x17, 1, 4),
      (0x18, 2, 1),
      (0x19, 2, 2),
      (0x1A, 2, 3),
      (0x1B, 2, 4),
    ];
    for (final (_, bank, sensor) in pids) {
      try {
        sensors.add(await getO2Sensor(bank, sensor));
      } catch (_) {}
    }
    return sensors;
  }

  Future<List<DTCCode>> getDTCs() async {
    final dtcs = <DTCCode>[];
    try {
      final resp = await sendCommandWithResponse("03",
          timeout: const Duration(seconds: 5));
      var clean = resp
          .replaceAll("\r", "")
          .replaceAll("\n", "")
          .replaceAll(">", "")
          .replaceAll(" ", "")  // quitar espacios por si ATS0 no está activo
          .trim();
      // Con ATS0 el formato es "4301XXXXXX"
      // Sin ATS0 el formato es "43 01 XX XX XX XX"
      if (clean.startsWith("43") && clean.length >= 4) {
        // Parsear en chunks de 2 caracteres
        final hexParts = <String>[];
        for (int i = 0; i + 1 < clean.length; i += 2) {
          hexParts.add(clean.substring(i, i + 2));
        }
        if (hexParts.length >= 2) {
          final numCodes = _parseInt(hexParts[1]);
          if (numCodes != null && numCodes > 0) {
            for (int i = 0; i < numCodes && (2 + i * 2 + 1) < hexParts.length; i++) {
              final code = hexParts[2 + i * 2] + hexParts[2 + i * 2 + 1];
              if (code != "0000") {
                dtcs.add(DTCCode(
                    code: code, description: _decodeDTCCode(code)));
              }
            }
          }
        }
      }
    } catch (_) {}
    if (dtcs.isEmpty) {
      dtcs.add(DTCCode(
          code: "NONE", description: "No hay códigos de error almacenados"));
    }
    return dtcs;
  }

  Future<bool> clearDTCs() async {
    try {
      await sendCommand("ATZ");
      await Future.delayed(const Duration(milliseconds: 2000));
      await sendCommand("ATE0");
      await Future.delayed(const Duration(milliseconds: 200));
      await sendCommand("ATL0");
      await Future.delayed(const Duration(milliseconds: 200));
      // NOTA: No enviamos ATH0 (headers off) porque _parseResponse()
      // espera el prefijo "41" en las respuestas.
      await sendCommand("ATSP0");
      await Future.delayed(const Duration(milliseconds: 500));

      for (int i = 0; i < 3; i++) {
        try {
          final resp = await sendCommandWithResponse("04",
              timeout: const Duration(seconds: 3));
          if (resp.contains("44") || resp.contains("OK")) {
            return true;
          }
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 500));
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isMILActive() async {
    try {
      final resp = await sendCommandWithResponse("0101");
      final parts = _parseResponse(resp, "01");
      if (parts.length >= 3) {
        final v = _parseInt(parts[2]);
        if (v != null) return (v & 0x80) != 0;
      }
    } catch (_) {}
    return false;
  }

  Future<String> getProtocol() async {
    try {
      final resp = await sendCommandWithResponse("ATDP",
          timeout: const Duration(seconds: 2));
      return resp.replaceAll("\r", "").replaceAll("\n", "").replaceAll(">", "").trim();
    } catch (_) {
      return "Desconocido";
    }
  }

  Future<String> getVIN() async {
    try {
      final resp = await sendCommandWithResponse("0902",
          timeout: const Duration(seconds: 5));
      // Limpiar la respuesta: eliminar \r\n, \t, espacios, y el prompt >
      var clean = resp
          .replaceAll("\r", "")
          .replaceAll("\n", "")
          .replaceAll("\t", "")
          .replaceAll(" ", "");
      final idx = clean.indexOf("4902");
      if (idx >= 0) {
        final data = clean.substring(idx + 4);
        final bytes = <int>[];
        for (int i = 0; i + 1 < data.length; i += 2) {
          final byteStr = data.substring(i, i + 2);
          final v = _parseInt(byteStr);
          if (v == null) break;
          bytes.add(v);
        }
        final vin = String.fromCharCodes(
            bytes.where((b) => b >= 32 && b <= 126));
        if (vin.isNotEmpty) return vin;
      }
      return "No disponible";
    } catch (_) {
      return "No disponible";
    }
  }

  String _decodeDTCCode(String code) {
    const types = {
      "P0": "Powertrain - Genérico",
      "P1": "Powertrain - Fabricante",
      "P2": "Powertrain - Genérico",
      "P3": "Powertrain - Genérico",
      "C0": "Chasis - Genérico",
      "C1": "Chasis - Fabricante",
      "C2": "Chasis - Genérico",
      "C3": "Chasis - Genérico",
      "B0": "Carrocería - Genérico",
      "B1": "Carrocería - Fabricante",
      "B2": "Carrocería - Genérico",
      "B3": "Carrocería - Genérico",
      "U0": "Red - Genérico",
      "U1": "Red - Fabricante",
      "U2": "Red - Genérico",
      "U3": "Red - Genérico",
    };
    final prefix = code.length >= 2 ? code.substring(0, 2) : "";
    return types[prefix] ?? code;
  }

  Future<List<int>> getSupportedPIDs() async {
    final pids = <int>[];
    final ranges = ["0100", "0120", "0140", "0160"];
    for (final range in ranges) {
      try {
        final resp = await sendCommandWithResponse(range);
        final parts = _parseResponse(resp, range.substring(2));
        if (parts.length >= 6) {
          final mode = range.substring(0, 2);
          final pidRange = range.substring(2);
          for (int j = 0; j < 4; j++) {
            final v = _parseInt(parts[2 + j]);
            if (v != null) {
              for (int bit = 0; bit < 8; bit++) {
                if ((v & (1 << (7 - bit))) != 0) {
                  final base =
                      int.parse(pidRange, radix: 16) + (j * 8) + bit;
                  if (base <= 0x60) {
                    pids.add(base);
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

  Future<void> disconnect() async {
    _isConnected = false;
    await _inputSubscription?.cancel();
    _inputSubscription = null;
    try {
      await _connection?.close();
    } catch (_) {}
    _connection = null;
  }
}
