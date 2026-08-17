# OBD2 Flutter / ELM327 Skill

Conocimiento operativo para trabajar en `obd2_scanner_flt`: arquitectura real del proyecto, diferencias SPP/BLE, cómo diagnosticar y cómo extender el cliente ELM327 sin romper el flujo existente.

## Proyecto

- `lib/obd2_elm327.dart`: cliente monolítico `Obd2Elm327`. Toda la lógica OBD2 (AT init, comandos modo 1/2/3/7/9, parsing, DTCs, keepalive, polling) vive aquí.
- `lib/core/providers/obd2_provider.dart`: `Obd2Notifier` (Riverpod) que envuelve `Obd2Elm327`, maneja timers de refresh/keepalive y expone estado a UI.
- `lib/presentation/screens/obd2_dashboard_screen.dart`: UI nueva (Riverpod + GoRouter).
- `lib/obd2_screen.dart`: UI legacy monolítica. No está en el router actual, pero sigue existiendo.
- `android/app/src/main/AndroidManifest.xml`: permisos Bluetooth clásico + `ACCESS_FINE_LOCATION`.
- `pubspec.yaml`: usa `flutter_bluetooth_serial_plus: ^0.5.1` (SPP/RFCOMM). Hay `flutter_blue_plus: ^2.3.12` declarado pero **no implementado** (solo un TODO).

## Hardware real: ELM327 y clones

- ELM327 original expone SPP/RFCOMM clásico.
- Clones muy comunes ("v1.5 truchos") exponen **BLE únicamente**, a pesar de venderse como "SPP".
- Si Car Scanner también tira timeout en el mismo adaptador, es señal de problema de transporte/hardware, no solo del código.

## Diagnóstico rápido

1. Si el adaptador aparece en `Ajustes → Bluetooth` del sistema y se puede emparejar manualmente → probablemente SPP.
2. Si no aparece en Bluetooth clásico, pero sí en un escáner BLE (nRF Connect) → es BLE-only.
3. Si es BLE-only, `flutter_bluetooth_serial_plus` **no puede conectar**; hace falta `flutter_blue_plus`.

## Limitaciones actuales del código

- `Obd2Elm327.connect` hace RFCOMM directo con `BluetoothConnection.toAddress(mac)`.
- No hay fallback a BLE.
- Si el adaptador es BLE-only, el flujo actual siempre falla con timeout.
- Bonding/pairing previo es mandatorio en Android antes de RFCOMM; si no está emparejado, el connect cuelga hasta timeout.

## Cómo agregar BLE sin reescribir todo

### 1. Interfaz de transporte

```dart
abstract class Elm327Transport {
  Future<void> connect(String deviceId);
  Future<void> disconnect();
  Future<void> write(String data);
  Stream<String> get responseStream;
  bool get isConnected;
  void Function(String log)? onLog;
}
```

### 2. ClassicSppTransport

Refactor de la lógica actual de `Obd2Elm327` hacia esta clase:
- Verificar BT disponible y encendido.
- Request/verify permisos runtime (`BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN`, `location`).
- Verificar bonded devices.
- Intentar bonding si no está emparejado (`bondDeviceAtAddress`).
- Conectar RFCOMM con reintentos (ej: 4 intentos, 25s cada uno).
- Escuchar `connection.input` y emitir texto decodificado por `responseStream`.
- `write`: agregar `\r` si falta y enviar por `conn.output`.

### 3. BleTransport

Usa `flutter_blue_plus`:

```dart
class BleTransport implements Elm327Transport {
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
  // ...
}
```

Flujo:
1. Verificar `FlutterBluePlus.isSupported` y BT encendido.
2. Scan BLE por `deviceId` (MAC o remoteId).
3. Conectar al device (`device.connect`).
4. `discoverServices()`.
5. Buscar service por UUIDs candidatos.
6. Dentro del service, buscar characteristic de escritura (`write` o `writeWithoutResponse`) y de notificación (`notify`).
7. `setNotifyValue(true)` en la characteristic de notify.
8. Escuchar `lastValueStream` y emitir por `responseStream`.
9. `write`: codificar comando + `\r` y escribir en characteristic.

Si no encuentra servicios/características compatibles, tirar excepción clara pidiendo verificar con nRF Connect.

### 4. Cliente ELM327 sobre transporte

```dart
class Elm327Client {
  final Elm327Transport transport;
  // _buffer, _sub, etc.
  Future<void> connect() async {
    await transport.connect(deviceId);
    _sub = transport.responseStream.listen((chunk) => _buffer.write(chunk));
  }
  Future<String> sendCommand(String command, {Duration timeout = ...}) async {
    _buffer.clear();
    await transport.write(command);
    final completer = Completer<String>();
    Timer.periodic(...) check for '>' prompt ...
    return completer.future.timeout(timeout, onTimeout: () => 'TIMEOUT');
  }
  // initialize, getRPM, getSpeed, parseo, etc.
}
```

Mantener **toda la lógica de protocolo/parsing** intacta; solo cambia la capa de E/S.

## Integración en la app existente

### Opción A: reemplazo total (recomendado a mediano plazo)

- Crear `lib/obd2_transport.dart` con la interfaz y ambos transportes.
- Reescribir `Obd2Elm327` para que internamente use un `Elm327Transport` (SPP por default).
- `Obd2Notifier.connect`: intentar SPP; si falla por timeout/excepción, caer a BLE automáticamente.
- `Obd2DashboardScreen`: si el usuario elige un device y SPP falla, mostrar opción de reintentar con BLE.

### Opción B: parche rápido

- Agregar un método alternativo en `Obd2Elm327` que reciba un flag `forceBle`.
- Si `forceBle == true`, usar `BleTransport` en vez de `BluetoothConnection`.
- Mantener `connect(mac)` actual como SPP para no romper nada.

## Permisos Android

Ya declarados en `AndroidManifest.xml`:
- `BLUETOOTH` / `BLUETOOTH_ADMIN` (maxSdkVersion 30)
- `BLUETOOTH_SCAN`
- `BLUETOOTH_CONNECT`
- `ACCESS_FINE_LOCATION` (necesario para scan en Android < 12)

Para BLE alcanza con estos; si se agrega advertising, sumar `BLUETOOTH_ADVERTISE`.

## Errores comunes y soluciones

| Síntoma | Causa probable | Solución |
|---|---|---|
| Timeout 25s en `BluetoothConnection.toAddress` | No emparejado / BLE-only / socket ocupado | Verificar bonding, chequear si es BLE, cerrar apps que usen BT |
| No aparece en discovery SPP | Es BLE-only o muy lejos | Escanear con nRF Connect para confirmar |
| `bondDeviceAtAddress` devuelve `false` | Android no permite pairing programático en algunos OEM | Pedir pairing manual desde Ajustes Bluetooth |
| `ATSP0` no responde | Adaptador en modo BLE o cableado suelto | Cambiar a BLE o revisar alimentación del ELM327 |
| `>` no aparece | ELM327 no inicializado / protocolo incompatible | Revisar logs de init, probar `ATZ` manual |

## Notas de versión

- v2.0.8 → v2.0.9: mejoras en guidance de pairing y sugerencias de error.
- Próximo salto esperado: soporte BLE con fallback automático.

## Archivos clave a tocar

- `lib/obd2_elm327.dart`: núcleo OBD2, evitar editar si no es protocolo.
- `lib/core/providers/obd2_provider.dart`: estado y timers.
- `lib/presentation/screens/obd2_dashboard_screen.dart`: UI conexión/dashboard.
- `android/app/src/main/AndroidManifest.xml`: permisos.
- `pubspec.yaml`: dependencias Bluetooth.

## Comandos útiles

```bash
flutter analyze
flutter build apk --debug
```
