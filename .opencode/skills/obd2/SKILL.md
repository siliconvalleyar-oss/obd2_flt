---
name: obd2
description: Use when working on the OBD-II Flutter plugin (ELM327 over Bluetooth). Covers plugin architecture, Bluetooth discovery/pairing/connection, command execution pipeline, PID parameter parsing, DTC decoding, JSON configuration format, and math formula evaluation.
---

# OBD-II Flutter Plugin

Flutter plugin for connecting to ECU cars via OBD port and ELM327 dongle over Bluetooth.

## Project Structure

```
obd2_plugin/
├── lib/obd2_plugin.dart     # Main plugin class (~660 lines)
├── example/                  # Flutter example app
├── android/                  # Android platform code
├── ios/                      # iOS platform code
├── test/                     # Tests
└── pubspec.yaml              # Dependencies: flutter_bluetooth_serial, math_expressions
```

## Core Architecture

### Enum `Mode`

```dart
enum Mode { parameter, config, dtc, at }
```

Tracks the current operation mode. Routes incoming serial responses to the correct handler.

### Class `Obd2Plugin`

**Key properties:**
- `connection` — `BluetoothConnection?`, active Bluetooth serial connection
- `onResponse` — callback `Function(String command, String response, int requestCode)?`
- `commandMode` — current `Mode`
- `requestCode` — user-assigned int to correlate requests with responses
- `_bluetooth` — `FlutterBluetoothSerial` instance (lib `flutter_bluetooth_serial`)
- `lastetCommand` — last sent command string (used for echo stripping)
- `runningService` — current PID config being processed
- `parameterResponse` / `dtcCodesResponse` — accumulated response buffers

---

## 1. Discovery y Sincronización del Dispositivo

El plugin usa `flutter_bluetooth_serial` para interactuar con el Bluetooth del sistema. No hay sincronización automática — el usuario debe llamar los métodos explícitamente.

### 1.1 Inicializar y verificar Bluetooth

```dart
Obd2Plugin obd2 = Obd2Plugin();

// Obtener estado actual del Bluetooth
BluetoothState state = await obd2.initBluetooth;

// Activar Bluetooth (pide al usuario si está apagado)
bool enabled = await obd2.enableBluetooth;

// Verificar si está habilitado
bool isOn = await obd2.isBluetoothEnable;

// Desactivar Bluetooth
bool disabled = await obd2.disableBluetooth;
```

**Internamente** (`lib/obd2_plugin.dart:42-87`):
- `initBluetooth` consulta `FlutterBluetoothSerial.instance.state`
- `enableBluetooth` llama `requestEnable()` si el estado es `STATE_OFF`
- `isBluetoothEnable` tiene recursión: si el estado es `UNKNOWN`, llama `initBluetooth` y se reevalúa

### 1.2 Obtener dispositivos emparejados (paired/bonded)

```dart
List<BluetoothDevice> paired = await obd2.getPairedDevices;
```

**Internamente** (`lib/obd2_plugin.dart:89-91`): llama `_bluetooth.getBondedDevices()` — retorna los dispositivos previamente emparejados con el sistema Android/iOS.

### 1.3 Escanear dispositivos cercanos (discovery)

```dart
List<BluetoothDevice> nearby = await obd2.getNearbyDevices;
```

**Internamente** (`lib/obd2_plugin.dart:93-105`):
```dart
// Pseudo-código de lo que hace:
List<BluetoothDevice> discoveryDevices = [];
await _bluetooth.startDiscovery().listen((event) {
  // Si ya existe por dirección, actualiza; si no, agrega (solo si name != null)
  int idx = discoveryDevices.indexWhere((e) => e.address == event.device.address);
  if (idx >= 0) {
    discoveryDevices[idx] = event.device;
  } else if (event.device.name != null) {
    discoveryDevices.add(event.device);
  }
}).asFuture(discoveryDevices);  // <-- Convierte el Stream en Future
```

Usa `startDiscovery()` que emite eventos `BluetoothDiscoveryResult` vía Stream. El `.listen()` recolecta dispositivos en una lista, y `.asFuture()` convierte el Stream en un Future que se completa cuando el discovery termina.

### 1.4 Combinar emparejados + cercanos

```dart
// Solo cercanos que ya están emparejados
List<BluetoothDevice> nearbyPaired = await obd2.getNearbyPairedDevices;

// Emparejados + cercanos (todo junto)
List<BluetoothDevice> all = await obd2.getNearbyAndPairedDevices;
```

**`getNearbyAndPairedDevices`** (`lib/obd2_plugin.dart:123-136`): primero obtiene los emparejados con `getBondedDevices()`, luego hace discovery y agrega/actualiza los encontrados.

### 1.5 Emparejar/desemparejar

```dart
// Vincular (pair) con un dispositivo
bool paired = await obd2.pairWithDevice(device);

// Desvincular
bool unpaired = await obd2.unpairWithDevice(device);

// Verificar si está emparejado
bool isBonded = await obd2.isPaired(device);
```

**Internamente** (`lib/obd2_plugin.dart:267-293`):
- `pairWithDevice`: llama `_bluetooth.bondDeviceAtAddress(address)`
- `unpairWithDevice`: llama `_bluetooth.removeDeviceBondWithAddress(address)`
- `isPaired`: consulta `getBondStateForAddress(address)` y retorna `state.isBonded`

---

## 2. Conexión Bluetooth al ELM327

### 2.1 Conectar

```dart
await obd2.getConnection(
  bluetoothDevice,
  (connection) {
    print("Conectado al ELM327");
  },
  (message) {
    print("Error conectando: $message");
  }
);
```

**Internamente** (`lib/obd2_plugin.dart:139-150`):
1. Si `connection` ya existe (no es null), llama `onConnected` inmediatamente y retorna
2. Si no, crea una conexión nueva: `BluetoothConnection.toAddress(device.address)`
3. Si `connection` no es null, llama `onConnected`; si falla, lanza Exception

### 2.2 Desconectar

```dart
await obd2.disconnect();
```

Cierra `connection?.close()` y establece `connection = null`.

### 2.3 Verificar conexión activa

```dart
bool connected = await obd2.hasConnection;
```

Solo verifica `connection != null` (`lib/obd2_plugin.dart:294-296`). **No verifica si el socket sigue abierto** — es un chequeo débil.

---

## 3. Pipeline de Comunicación: Enviar Comandos y Recibir Respuestas

### 3.1 Registro del callback de datos (IMPORTANTE: hacer primero)

```dart
await obd2.setOnDataReceived((command, response, requestCode) {
  print("$command => $response");
});
```

**Solo se puede llamar UNA VEZ.** Si ya está inicializado, lanza Exception.

**Internamente** (`lib/obd2_plugin.dart:329-426`):
1. Verifica que `onResponse` sea null (si no, lanza error)
2. Escucha el stream `connection?.input?.listen(...)`
3. Acumula datos en `response` hasta que llega el carácter `>` (prompt de ELM327)
4. Cuando recibe `>`, enruta según `commandMode`:
   - **Mode.config / Mode.at** → callback directo con la respuesta limpia
   - **Mode.parameter** → decodifica PID con fórmula
   - **Mode.dtc** → decodifica códigos de diagnóstico
5. Limpia `\n`, `\r`, `>`, `SEARCHING...` de la respuesta

### 3.2 Envío de comandos raw

```dart
// Método privado _write (lib/obd2_plugin.dart:298-303):
// connection?.output.add(Uint8List.fromList(utf8.encode("$command\r\n")))
// await connection?.output.allSent;
```

Todos los comandos se envían como texto ASCII terminado en `\r\n` al puerto serial Bluetooth del ELM327.

### 3.3 Flujo completo de configuración (AT commands)

```dart
String configJson = '''[
  {"command": "AT Z",    "description": "Reset",       "status": true},
  {"command": "AT E0",   "description": "Echo off",    "status": true},
  {"command": "AT SP 0", "description": "Auto protocol","status": true},
  {"command": "AT H1",   "description": "Headers on",  "status": true},
  {"command": "AT S0",   "description": "Print spaces","status": true},
  {"command": "AT AT 1", "description": "Adaptive timing","status": true},
  {"command": "01 00",   "description": "Check PIDs",  "status": true}
]''';

int waitMs = await obd2.configObdWithJSON(configJson);
await Future.delayed(Duration(milliseconds: waitMs));
// Después de esto, el ELM327 ya está configurado y listo
```

**Internamente** (`lib/obd2_plugin.dart:236-262`):
1. Parsea el JSON
2. Toma el primer comando, lo envía con `_write()`
3. Programa el siguiente envío con `Future.delayed`:
   - Si el comando es `AT Z` o `ATZ` → espera 1000ms (el reset tarda)
   - Si no → espera 100ms
4. Repite hasta recorrer todo el array
5. Retorna el tiempo total estimado: `(length * 150) + 1500` ms

### 3.4 Lectura de parámetros (PIDs)

```dart
String paramJson = '''[
  {
    "PID": "01 0C",
    "length": 2,
    "title": "Engine RPM",
    "unit": "RPM",
    "description": "<double>, (( [0] * 256) + [1] ) / 4",
    "status": true
  }
]''';

int waitMs = await obd2.getParamsFromJSON(paramJson);
await Future.delayed(Duration(milliseconds: waitMs));
// Las respuestas llegan al callback de setOnDataReceived con command="PARAMETER"
```

**Pipeline de decodificación** (`lib/obd2_plugin.dart:343-381`):
1. El callback recibe la respuesta cruda
2. Limpia la respuesta (quita `\n`, `\r`, `>`, `SEARCHING...`, la unidad)
3. Extrae los bytes usando `_calculateParameterFrames()`:
   - Calcula el PID esperado + 4 en el primer byte (para quitar el echo)
   - Busca ese patrón en la respuesta
   - Retorna los bytes subsiguientes como array de hex strings
4. Si `description` contiene `, ` → tiene fórmula:
   - Reemplaza `[i]` con el valor decimal de cada byte
   - Evalúa la expresión con `math_expressions` (`Parser` + `Expression.evaluate`)
5. Si no tiene fórmula → usa la respuesta como string directo
6. Acumula en `parameterResponse`
7. Cuando se procesa el último parámetro (`sendDTCToResponse = true`), envía todo como JSON al callback con command `"PARAMETER"`

### 3.5 Lectura de DTCs (Diagnostic Trouble Codes)

```dart
String dtcJson = '''[
  {"id": 1, "command": "03", "response": "6", "status": true}
]''';

int waitMs = await obd2.getDTCFromJSON(dtcJson);
await Future.delayed(Duration(milliseconds: waitMs));
// Las respuestas llegan con command="DTC"
```

**Decodificación** (`lib/obd2_plugin.dart:442-536`):
1. Quita el echo (primeros 2 bytes del comando + 4)
2. Agrupa bytes restantes en frames de 3 bytes
3. Cada frame de 24 bits se convierte a DTC:
   - Bits 0-1: sistema → `_initialDataOne()` → P, C, B, U
   - Bits 2-3: primer dígito → `_initialDataTwo()` → 0-3
   - Bits 4-15: 3 dígitos hex → `_initialDTC()` → 0-F
4. Ejemplo: `0104` + `0F` + `A0` en binario → `P010F` + `A0?` → código `P010F`
5. Evita duplicados con `.toSet().toList()`

### 3.6 Envío de tiempo real

Entre comandos, el plugin usa `Future.delayed` con tiempos fijos para esperar la respuesta del ELM327:
- Config normal: 100ms entre comandos
- Config `AT Z`: 1000ms
- Parámetros: 350ms entre cada PID
- DTCs: 1000ms entre cada comando

---

## PIDs Integrados en el Código

| PID | Título | Fórmula | Unidad |
|---|---|---|---|
| `AT RV` | Battery Voltage | raw string | V |
| `01 0C` | Engine RPM | `(([0]*256)+[1])/4` | RPM |
| `01 0D` | Speed | `[0]` | km/h |
| `01 05` | Engine Temp | `[0] - 40` | °C |
| `01 0B` | Manifold Abs Pressure | `[0]` | kPa |

### Fórmulas auxiliares (cálculos derivados)

```dart
fMaf(rpm, pressMbar, tempC)  // Mass Air Flow (g/s)
fFuel(rpm, pressMbar, tempC) // Fuel consumption (L/h)
```

---

## Request Codes

```dart
// Usar enteros >= 5 (1-4 reservados)
await obd2.configObdWithJSON(json, requestCode: 42);
await obd2.getParamsFromJSON(paramJson, requestCode: 99);
await obd2.getDTCFromJSON(dtcJson, requestCode: 77);
```

El `requestCode` se pasa al callback en `setOnDataReceived` para correlacionar qué operación generó cada respuesta.

---

## Diagrama del Flujo Completo

```
[App] → enableBluetooth → (BT ON)
[App] → getPairedDevices | getNearbyDevices → (lista dispositivos)
[App] → getConnection(device) → BluetoothConnection.toAddress()
[App] → setOnDataReceived(callback) → escucha connection.input
[App] → configObdWithJSON(config) → envía AT commands → ELM327 configurado
[App] → getParamsFromJSON(params) → envía PIDs → respuestas decodificadas → callback
[App] → getDTCFromJSON(dtcs) → envía comandos DTC → códigos decodificados → callback
```

## Patrón Completo Recomendado

```dart
Obd2Plugin obd2 = Obd2Plugin();

// 1. Registrar callback (SIEMPRE PRIMERO)
await obd2.setOnDataReceived((cmd, res, code) {
  if (cmd == "PARAMETER") {
    List params = json.decode(res);
    print("Parámetros: $params");
  } else if (cmd == "DTC") {
    List dtcs = json.decode(res);
    print("Códigos DTC: $dtcs");
  } else {
    print("[$cmd] => $res (código $code)");
  }
});

// 2. Activar Bluetooth
await obd2.enableBluetooth;

// 3. Obtener dispositivos
List<BluetoothDevice> devices = await obd2.getNearbyAndPairedDevices;
BluetoothDevice elmDevice = devices.firstWhere((d) => d.name?.contains("OBD") ?? false);

// 4. Conectar
await obd2.getConnection(elmDevice, (conn) {}, (msg) {});

// 5. Configurar ELM327
await Future.delayed(Duration(
  milliseconds: await obd2.configObdWithJSON(configJson)
));

// 6. Leer parámetros en vivo
await obd2.getParamsFromJSON(paramJson);

// 7. Leer DTCs
await obd2.getDTCFromJSON(dtcJson);
```

## Notas Importantes

- **Orden estricto**: `setOnDataReceived` → Bluetooth → conexión → comandos
- **No ejecutar múltiples funciones de comando simultáneamente** — causan errores
- **requestCode**: usar valores ≥ 5 (1-4 reservados internamente)
- **`setOnDataReceived`** solo se puede llamar una vez
- `SEARCHING...` en respuestas se elimina automáticamente
- `hasConnection` solo verifica `connection != null`, no si el socket está abierto
- Los métodos de "envío" (`configObdWithJSON`, `getParamsFromJSON`, `getDTCFromJSON`) son asíncronos con `Future.delayed` — **no bloquean**; solo inician la secuencia y retornan el tiempo estimado
