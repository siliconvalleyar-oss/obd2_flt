# 03 — Comunicación Bluetooth (SPP)

> Cómo habla la app con el adaptador ELM327: Bluetooth clásico **SPP/RFCOMM** vía
> `flutter_bluetooth_serial_plus`. Permisos, flujo de conexión, streams y correcciones aplicadas.
> Referencia del transporte BLE del proyecto hermano: `car_scanner/docs/05-transportes-conexion.md` §5.3.

## 3.1 Transporte elegido: SPP (BT clásico)

La app usa **Bluetooth clásico (SPP/RFCOMM)** mediante `flutter_bluetooth_serial_plus: ^0.5.1`.

- **No** usa BLE/GATT: no hay servicios `FFE0/FFE1`, ni `WriteCharacteristic`, ni
  `notifyCharacteristic`. El adaptador ELM327 SPP se comporta como un puerto serie.
- La mayoría de los adaptadores ELM327 económicos (tipo "OBDII Bluetooth", chip genérico o
  STN1170 en modo SPP) exponen este perfil y funcionan con esta app.
- El paquete `flutter_bluetooth_serial_plus` es un fork del clásico `flutter_bluetooth_serial`
  con mantenimiento activo y soporte de null-safety.

## 3.2 Permisos Android

`android/app/src/main/AndroidManifest.xml`:

```xml
<!-- BT clásico: máxSdk 30 (Android 11-) -->
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<!-- Android 12+ (API 31+) -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<!-- Localización (requerida para escaneo en Android <12) -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

La app pide permisos en tiempo de ejecución con `permission_handler` antes de escanear/conectar.
En Android 12+ `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` son permisos `normal`/`dangerous` que el usuario
concede; en Android ≤11 se usa `ACCESS_FINE_LOCATION`.

## 3.3 Flujo de conexión

Verificado en `connect()` de `lib/obd2_elm327.dart`:

```
1. FlutterBluetoothSerial.isAvailable     → ¿chip BT presente?
2. FlutterBluetoothSerial.isEnabled       → ¿BT encendido?
3. getBondStateForAddress(mac)            → ¿emparejado?
      └─ si no: bondDeviceAtAddress(mac)  → intenta emparejar
4. BluetoothConnection.toAddress(mac)     → abre socket RFCOMM (10s de timeout, 2 intentos)
5. connection.input!.listen(...)          → stream de bytes entrantes (Uint8List)
6. connection.output.add(bytes)           → escritura
7. await connection.output.allSent        → asegura que los bytes salieron
8. _initializeElm327()                    → secuencia AT
```

El emparejamiento en caliente es una heurística: si falla, la app avisa al usuario para que
empareje manualmente desde Ajustes → Bluetooth.

## 3.4 Streams de lectura/escritura

### Lectura

```dart
_inputSubscription = _connection!.input!.listen((Uint8List data) {
  String text = utf8.decode(data, allowMalformed: true);
  _responseController.add(text);       // log (broadcast) → UI
  // ... y también se acumula en el buffer interno para el framing ">"
});
```

El ELM327 responde en **ASCII**; los chunks pueden llegar divididos, por eso se acumula el
texto y se decide "respuesta completa" cuando aparece el prompt `>`.

### Escritura

```dart
String cmd = command.trim();
if (!cmd.endsWith("\r")) cmd += "\r";
_connection!.output.add(Uint8List.fromList(utf8.encode(cmd)));
await _connection!.output.allSent;
```

Todos los comandos OBD/AT terminan con `\r` (CR). El `allSent` del paquete garantiza que los
bytes se escribieron en el socket antes de esperar la respuesta.

## 3.5 Problemas encontrados y correcciones

| # | Problema | Impacto | Corrección |
|---|---|---|---|
| 1 | Cada `sendCommandWithResponse` escucha el `responseStream` compartido (broadcast). Con lecturas concurrentes (refresco 1s + DTC + terminal), **múltiples suscriptores reciben los mismos bytes** y pueden completar con datos de otro comando. | Lecturas corruptas, RPM/velocidad erráticos, DTC mal parseados. | **Cola FIFO de comandos** + un único buffer de respuesta por conexión (ver `02-motor-obd2.md` §2.4). |
| 2 | El framing por `>` depende de que ningún comando quede pendiente al enviar el siguiente. | Respuestas desplazadas. | Resuelto con la serialización (punto 1). |
| 3 | `utf8.decode(data, allowMalformed: true)` — el ELM envía ASCII puro, pero `allowMalformed` evita que un byte raro rompa el stream. | — | Mantener (comportamiento correcto). |
| 4 | No se hace `flush` ni drenado de datos residuales tras un timeout. | El siguiente comando puede "heredar" datos viejos. | Limpiar el buffer al iniciar cada lectura. |
| 5 | La conexión no detecta el cierre remoto del socket más allá del `onDone` interno del paquete. | Estado "conectado" fantasma. | Comprobar `connection.isConnected` antes de cada envío y al detectar `onError`/`onDone` del stream marcar desconexión. |
| 6 | Permisos: en Android 12+ hay que pedir `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` **antes** de `getBondedDevices`/`connect`. | Fallo de permiso silencioso. | Verificar con `permission_handler` y pedirlos en el dashboard. |

## 3.6 Compatibilidad con adaptadores

| Adaptador | Perfil | Observaciones |
|---|---|---|
| ELM327 v1.5 clón (SPP, "OBDII") | SPP | El más común; puede ignorar `ATL0`/`ATS0`/`ATM0` — el parseo tolera espacios on. |
| ELM327 original / STN1170 | SPP | Responde `ATZ` con versión (`ELM327 v1.5` / `STN1170`). |
| STN1110/VT (chip STN) | SPP | Soporta `STI`, `STP` — extensión opcional (ver `04-comandos-elm.md` §4.5). |
| Adaptadores BLE (chip CC2541/BLE Mini) | **BLE/GATT** | **No soportados** por esta app (solo SPP). Ver roadmap `08-limitaciones-roadmap.md`. |
| Adaptadores WiFi (TCP) | — | No soportados (la app no incluye `ITCPConnection`). |

## 3.7 Terminología y referencias

- **SPP**: Serial Port Profile (perfil de puerto serie de BT clásico).
- **RFCOMM**: transporte serie sobre L2CAP; es el canal que abre `BluetoothConnection.toAddress`.
- **UUID de SPP**: el paquete usa el UUID estándar de SPP
  (`00001101-0000-1000-8000-00805F9B34FB`) para el servicio de descubrimiento en Android.
- Contraste BLE (referencia): Car Scanner usa servicios GATT configurables
  (`BTLEServiceID`, `BTLEInputID`/`BTLEOutputID`), suscripción `notify` y escritura con respuesta
  (ver `car_scanner/docs/05-transportes-conexion.md` §5.3).
