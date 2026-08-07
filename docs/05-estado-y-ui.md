# 05 — Estado y UI (Riverpod)

> Estado reactivo de la app: `obd2Provider`, `Obd2State`, pantallas y bucle de refresco.

## 5.1 Estado — `Obd2State`

```dart
enum Obd2ConnectionState { disconnected, connecting, connected }

class Obd2State {
  final Obd2ConnectionState connectionState;
  final BluetoothDevice? device;        // dispositivo BT conectado
  final Obd2SensorData sensorData;      // RPM, velocidad, temp, trims, …
  final List<DTCCode> dtcs;             // códigos de error
  final String protocol;                // descripción ATDP
  final String vin;                     // VIN del vehículo
  final bool mil;                       // MIL encendida
  final String log;                     // log de bytes (terminal/debug)
  final List<String> availablePids;     // PIDs soportados (formateados)
  final String error;                   // último error de conexión
}
```

`Obd2SensorData` conserva el último valor leído; los campos no leídos todavía valen `'--'`:

```dart
rpm, speed, coolantTemp, engineLoad, throttle, map, iat,
timing, maf, fuelLevel, baro, stft1, ltft1, stft2, ltft2
```

## 5.2 Notifier — `Obd2Notifier`

- `connect(device)` → estado `connecting` → `_obd.connect(address)` → suscribe `responseStream`
  al `log` → si OK: estado `connected`, arranca `_startRefresh()` y `_loadVehicleInfo()`.
- `disconnect()` → cancela timer y suscripción, cierra el motor, estado `disconnected`.
- `_refreshSensors()` → lee los 15 sensores de forma **secuencial y await** (Timer 1s).
- `_loadVehicleInfo()` → protocolo (`ATDP`), MIL (`0101`) y VIN (`0902`).
- `loadDTCs()` / `clearDTCs()` → modo 03 / 04.
- `sendCommand(cmd)` → terminal: envía raw y registra `> cmd` en el log.
- `getOxygenSensors()` → delega en el motor.

## 5.3 Bucle de refresco

```
_startRefresh() → Timer.periodic(1s, (_) => _refreshSensors())
```

`_refreshSensors` ejecuta, uno tras otro y con `await`:

```
getRpm → getSpeed → getCoolantTemp → getEngineLoad → getThrottlePosition
→ getIntakePressure → getIntakeTemp → getTimingAdvance → getMAF
→ getFuelLevel → getBarometricPressure → STFT1 → LTFT1 → STFT2 → LTFT2
```

Cada lectura está envuelta en `try/catch` individual: si un PID falla (NO DATA, timeout, comando
no soportado), el sensor conserva el valor anterior y el resto continúa.

### Problema conocido (a corregir)

Con la implementación actual, si una vuelta de refresco tarda más de 1s (15 lecturas × ~200 ms en
un ELM327 lento ≈ 3 s), **los timers se solapan** y lanzan varias vueltas en paralelo. La corrección
es añadir un guard `_isRefreshing` que salte el tick si ya hay una vuelta en curso y, opcionalmente,
aumentar el intervalo (p. ej. 1.5–2 s) para lecturas sobre protocolos lentos (ISO/KWP).

## 5.4 Pantallas

### Onboarding (`onboarding_screen.dart`)
`LiquidSwipe` con 3 páginas introductorias. Permite saltar al home.

### Shell + bottom nav (`shell_screen.dart`, `liquid_glass_bottom_bar.dart`)
`StatefulShellRoute` de go_router con 4 destinos: Dashboard, DTC, Terminal, Info. Barra inferior
glassmorphism con badges.

### Dashboard (`obd2_dashboard_screen.dart`)
- Lista de dispositivos BT emparejados (`FlutterBluetoothSerial.instance.getBondedDevices()`).
- Botón conectar/desconectar.
- Sensores en tiempo real: RPM (barra líquida `liquid_bar.dart`), velocidad, temp. motor, carga,
  TPS, MAP, IAT, avance, MAF, combustible, barométrica + Fuel Trim (STFT/LTFT B1/B2).
- Log de conexión/errores en tarjetas glass.

### DTC (`obd2_dtc_screen.dart`)
- Lista de códigos (modo 03) en tarjetas glass con su descripción.
- Botón "Borrar códigos" (modo 04) con confirmación.

### Terminal (`obd2_terminal_screen.dart`)
- Campo de texto + botón enviar → `obd2Provider.notifier.sendCommand(cmd)`.
- El output se muestra vía `state.log` (alimentado por `responseStream`).
- Permite probar cualquier comando AT/PID.

### Info (`obd2_info_screen.dart`)
- VIN, protocolo (ATDP), estado MIL.
- Sensores O2 (voltaje y trim por banco/sensor) vía `getOxygenSensors()`.
- PIDs soportados.

## 5.5 Tema y persistencia

`theme_provider.dart` mantiene `ThemeMode` (system/light/dark) con `shared_preferences`;
`app_theme.dart` define colores/gradientes y los `ThemeData` Material 3. El cambio de tema usa
`theme_transition_overlay.dart` (reveal radial).

## 5.6 Correcciones recomendadas de estado

| # | Problema | Corrección |
|---|---|---|
| 1 | Refresco solapado (timer 1s < duración de vuelta). | Guard `_isRefreshing`; intervalo configurable. |
| 2 | `_loadVehicleInfo()` corre en paralelo con el primer refresco (ambos usan el motor). | Con la cola FIFO del motor ya no corrompen datos; opcionalmente esperar al primer refresco. |
| 3 | `availablePids` se define pero nunca se rellena. | Llamar `getSupportedPIDs()` tras conectar y volcar a `availablePids`. |
| 4 | Errores de lectura no distinguen "NO DATA" de "timeout". | Motor debe exponer excepciones tipadas (`Obd2NoDataException`, `Obd2TimeoutException`) para que la UI muestre mensajes precisos. |
