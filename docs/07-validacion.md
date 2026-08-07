# 07 — Validación

> Cómo probar la app, checklist de verificación, comportamiento esperado según el tipo de adaptador
> y resolución de problemas.

## 7.1 Preparación del entorno

1. **Vehículo en ACC o motor encendido** (el ELM327 se alimenta del puerto OBD-II).
2. **ELM327 conectado** y con LED fijo (no parpadeando).
3. Emparejar el adaptador desde **Ajustes → Bluetooth** (p. ej. "OBDII") y anotar su MAC.
4. Compilar e instalar:

```bash
flutter pub get
flutter analyze          # sin errores ni warnings
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

## 7.2 Checklist de conexión

| Paso | Acción | Resultado esperado |
|---|---|---|
| 1 | Abrir app → Dashboard | La lista muestra los dispositivos BT emparejados |
| 2 | Pulsar "Conectar" sobre el ELM327 | Log: Bluetooth disponible → encendido → emparejado → conexión RFCOMM → "Inicializando ELM327…" |
| 3 | Esperar init | Log: protocolo detectado (p. ej. `ISO 15765-4 (CAN 11/500)`); estado "Conectado" |
| 4 | Observar Dashboard 5 s | RPM/velocidad/temp se actualizan cada segundo; el resto de sensores muestran valores o `--` |
| 5 | Ir a DTC | Lista de códigos o "No hay códigos de error almacenados" |
| 6 | Ir a Info | VIN de 17 caracteres, protocolo y estado MIL |
| 7 | Ir a Terminal | Enviar `ATRV` → voltaje; `ATDP` → protocolo; `010C` → `41 0C ...` |
| 8 | Desconectar | Timer detenido, estado "Desconectado" |

## 7.3 Prueba manual con terminal (validación del motor)

| Comando | Respuesta esperada | Qué valida |
|---|---|---|
| `ATZ` | `ELM327 v1.5` (o versión del chip) | Reset + identificación |
| `ATE0` | `OK` | Echo OFF |
| `ATH0` | `OK` | Headers OFF |
| `ATS0` | `OK` (puede responder `?` en clónicos viejos) | Spaces OFF |
| `ATSP0` | `OK` (con `SEARCHING...` en algunos) | Protocolo automático |
| `ATDPN` | `06`, `07`, `03`, … | Número de protocolo |
| `ATDP` | `ISO 15765-4 (CAN 11/500)` | Descripción |
| `ATRV` | `12.3V` | Voltaje de alimentación |
| `0100` | `41 00 <4 bytes>` | Mapa de PIDs (comunicación OK) |
| `010C` | `41 0C <2 bytes>` | RPM |
| `0902` | `49 02 01 <VIN>` | VIN (incluye multiframe) |
| `03` | `43 <nº> <códigos>` | DTC |
| `04` | `OK` | Borrado de DTC (¡usar con cuidado!) |
| `221201` | `62 12 01 <datos>` (solo en UDS) | UDS ReadDataByIdentifier |
| `3E00` | `7E 00` (solo en UDS) | TesterPresent |

## 7.4 Casos límite a probar

| Escenario | Comportamiento esperado |
|---|---|
| Respuestas con espacios on (clónico sin `ATS0`) | Los PIDs se parsean igual (`41 0C 0A 0A`) |
| Cabeceras on (`ATH1`) | El parser quita `7E8 <len>` y sigue leyendo `41 0C …` |
| `NO DATA` (PID no soportado) | El sensor conserva el valor anterior / `--`; sin crash |
| `SEARCHING...` lento al conectar | La init tolera la espera (timeouts generosos) |
| Desconexión del adaptador a mitad de lectura | La app marca desconexión y detiene el refresco |
| 2+ ECUs respondiendo (broadcast `7DF`) | Se usa la primera respuesta que contenga el marcador |
| Multiframe CAN para VIN con headers on | Las tramas se reensamblan y el VIN se lee completo |
| Comandos concurrentes (refresco + DTC + terminal) | La cola FIFO serializa; ninguna respuesta se corrompe |

## 7.5 Pruebas automatizadas

La app no incluye aún un suite de tests de unidad para el motor. Plan sugerido:

```
test/
├── elm_parser_test.dart     # _parseResponse con/ sin espacios, con/ sin cabeceras, NO DATA, multiframe
├── dtc_decoder_test.dart    # _decodeDTCCode (P0100, C0032, U0100, …)
├── formulas_test.dart       # RPM, MAF, trims, O2 con bytes conocidos
├── protocol_table_test.dart # tabla 12–45 → comandos generados
└── can_request_test.dart    # sendCanRequest → beforeCommands/afterCommands correctos
```

Ejecutar con `flutter test`.

> Nota: `_parseResponse`, `_decodeDTCCode` y las fórmulas están como métodos de `Obd2Elm327`;
> para testearlas conviene extraerlas a un módulo puro (p. ej. `lib/core/obd/parser.dart`) — ver
> roadmap `08-limitaciones-roadmap.md`.

## 7.6 Adaptadores clónicos — comportamiento conocido

| Comando | Clónicos v1.5 genéricos | STN1170/STN1110 |
|---|---|---|
| `ATZ` | `ELM327 v1.5` (a veces tarda 1–2 s) | `STN1170 v4.x` |
| `ATL0`/`ATM0`/`ATS0` | Suele responder `OK`; algunos ignoran | `OK` |
| `ATAT1` | Puede responder `?` | `OK` |
| `ATAL` | `OK` | `OK` |
| Respuestas | Con/sin espacios según soporte | Compactas y fiables |
| `STI`/`VTI` | `?` | Identifican el chip |

El motor **tolera** `?` en comandos opcionales (ATS0, ATAT1, ATM0) y ajusta el parseo según el
formato real de las respuestas.

## 7.7 Resolución de problemas

| Síntoma | Causa probable | Solución |
|---|---|---|
| No aparece el dispositivo en la lista | Permiso BT/locación no concedido; BT apagado | Conceder permisos; encender BT; re-escaneo |
| "Bluetooth no soportado" | Dispositivo sin BT clásico o emulador | Usar un móvil físico con BT |
| Fallo de conexión RFCOMM | ELM327 apagado, fuera de alcance, o MAC incorrecta | Verificar LED; acercar; re-emparejar |
| Init se queda en `SEARCHING...` | Protocolo lento (ISO/KWP) o ECU no compatible | Aumentar timeouts de init/lectura |
| RPM no sube al acelerar | PID no soportado por la ECU, o protocolo mal detectado | Terminal: `ATDP`/`0100`; fijar protocolo con `initProtocol(n)` |
| VIN vacío o corto | Multiframe mal reensamblado o ECU sin PID 09 | Comprobar `0902` en terminal |
| Valores congelados tras un error | `--` persistente porque la lectura falla siempre | Revisar `NO DATA`; el sensor conserva el último valor válido |
| Terminal no responde | Comando quedó atrapado en la cola (timeout previo) | Enviar `ATZ` para resetear el adaptador |

## 7.8 Criterios de aceptación (definición de "hecho")

- [ ] `flutter analyze` sin errores ni warnings.
- [ ] Conexión a un ELM327 real en 3 intentos o menos.
- [ ] Dashboard muestra RPM y velocidad estables a 1 Hz.
- [ ] DTC se leen y borran correctamente (modo 03/04).
- [ ] VIN de 17 caracteres se lee en CAN (incluye multiframe).
- [ ] El terminal responde a AT y PID sin corromper lecturas concurrentes.
- [ ] Desconexión del adaptador se detecta y la UI vuelve a "Desconectado".
