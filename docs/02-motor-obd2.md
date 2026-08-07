# 02 — Motor OBD2 (`Obd2Elm327`)

> Núcleo de la app: `lib/obd2_elm327.dart`. Conexión Bluetooth SPP, serialización de comandos,
> espera del prompt `>`, parseo de respuestas y API pública. Referencia del catálogo en `04-comandos-elm.md`.

## 2.1 Responsabilidades

1. **Conexión**: RFCOMM al adaptador ELM327 con verificación de disponibilidad/encendido Bluetooth,
   emparejamiento y reintentos.
2. **Serialización**: los comandos viajan uno a uno (FIFO); nunca se mezclan respuestas de lecturas concurrentes.
3. **Framing por prompt**: cada respuesta se considera completa cuando el ELM327 envía su prompt `>`.
4. **Init ELM327**: secuencia AT de arranque (ATZ, ATE0, ATL0, ATS0, ATH0, ATM0, ATAL, ATAT, ATSP0, ATST).
5. **Parseo**: extrae los bytes del payload a partir del marcador de servicio (`41XX`, `43`, `49 02`, …),
   tolerando espacios on/off y cabeceras on/off.
6. **API de diagnóstico**: RPM, velocidad, temperaturas, trims, O2, DTC, VIN, protocolo, PIDs soportados, etc.

## 2.2 Ciclo de conexión (`connect`)

```
connect(mac)
 ├─ disconnect() previo
 ├─ FlutterBluetoothSerial.isAvailable            → "Bluetooth no soportado"
 ├─ FlutterBluetoothSerial.isEnabled             → "Bluetooth no encendido"
 ├─ getBondStateForAddress / bondDeviceAtAddress  → emparejar si no lo está
 ├─ BluetoothConnection.toAddress(mac)            → RFCOMM (2 intentos, timeout 10s)
 ├─ input!.listen(...)                            → re-emite bytes a responseStream y buffer interno
 └─ _initializeElm327()                           → secuencia AT
```

En cualquier fallo se cierra la conexión y se publica en `responseStream` un resumen de error
con sugerencias (auto en ACC, LED del ELM327, emparejamiento manual, etc.).

## 2.3 Framing: espera del prompt `>`

El protocolo ELM327 es **line-oriented** y termina cada respuesta con el carácter prompt `>`.
El motor acumula los bytes entrantes en un buffer y completa la lectura en curso al ver `>`:

```
comando: 010C\r
respuesta: 41 0C 0A 0A\r\r>   ← el ">" cierra la respuesta
```

Consideraciones de diseño:

- El buffer se limpia al iniciar cada lectura (los comandos están serializados, así que no hay
  datos pendientes de una respuesta anterior, salvo en caso de timeout previo).
- Si no llega `>` antes del timeout, se devuelve lo acumulado (o se lanza `TimeoutException`
  si no hubo nada).
- Mensajes tipo `SEARCHING...`, `BUS INIT: ...` pueden aparecer antes de la respuesta real;
  el parseo los ignora buscando el marcador de servicio.

## 2.4 Serialización de comandos (cola FIFO)

Todas las escrituras pasan por una **cola encadenada de futures** para garantizar que una
respuesta nunca se atribuya a otro comando. Esto es crítico porque la app puede lanzar lecturas
concurrentes (refresco de sensores + carga de DTC + terminal).

```
sendCommandWithResponse('010C')  ┐
getDTCs() ('03')                  ├─► cola FIFO ► rawSend ► wait ">"
sendCommand('ATRV')               ┘
```

## 2.5 Secuencia de init

Estado del código actual (ver correcciones propuestas en §2.7):

```
ATZ   → reset (tolerante, timeout 5s)
ATE0  → echo OFF
ATL0  → linefeeds OFF
ATS0  → spaces OFF (compacto)
ATSP0 → protocolo automático
ATAT1 → adaptive timing
ATST20→ search timeout
```

> Nota: la implementación actual **no** envía `ATH0`. El ELM327 vuelve a headers OFF por defecto
> tras `ATZ`, y `_parseResponse` busca el prefijo `41` sin cabeceras. Para robustez conviene
> explicitar `ATH0` y hacer el parseo tolerante a cabeceras (ver §2.7).

## 2.6 Estrategia de parseo

1. Se normaliza la respuesta: se eliminan `\r`, `\n` y el prompt `>`, y se divide en líneas.
2. Se busca el **marcador de servicio** (`41 0C`, `43`, `49 02`, `42 xx`, …) en cada línea.
3. A partir del marcador se extraen los bytes (tokenización por pares hex).
4. Si una línea no contiene el marcador y empieza por una cabecera (p. ej. `7E8` en CAN), se
   interpreta como trama de continuación y se le quitan cabecera + byte de longitud/secuencia.

Esto permite leer respuestas con **espacios on/off** (`41 0C 0A 0A` vs `410C0A0A`) y con
**cabeceras on/off** (`7E8 06 41 0C 0A 0A` vs `41 0C 0A 0A`).

Casos especiales:

- `NO DATA` → el comando se considera sin datos (DTC → "NONE", sensores → valor anterior).
- `?` / `ERROR` / `UNABLE TO CONNECT` → comando no soportado o bus no disponible.
- `SEARCHING...` → se ignora en el parseo.

## 2.7 Correcciones recomendadas (análisis)

Problemas detectados en el código actual y su solución documentada:

| # | Problema | Corrección |
|---|---|---|
| 1 | `sendCommandWithResponse` crea una suscripción a `responseStream` por comando; con lecturas concurrentes, **varias suscripciones capturan los mismos datos** y las respuestas se corrompen. | Cola FIFO global + un único buffer gestionado por la conexión (ver §2.4). |
| 2 | `_sendATCommand` valida con `resp.contains("OK") || resp.contains(">")`; como `>` siempre está presente, **nunca detecta fallos**. | Validar `OK` y rechazar `?`/`ERROR`; `ATZ` se valida aparte (versión del ELM, sin `OK`). |
| 3 | `clearDTCs` re-inicializa con `ATZ` + delays manuales (lento y frágil). | Enviar `04` directamente con reintentos; solo re-init si falla. |
| 4 | Init sin `ATH0` explícito ni `ATAL` ni `ATM0`; VIN con CAN multiframe puede truncarse. | Añadir `ATH0`, `ATM0`, `ATAL`; parsear VIN con reensamblaje (ver `06-pids-soportados.md` §6.6). |
| 5 | Sin detección de protocolo (`ATDPN` → `ELMFormat`). | Añadir `getProtocolNumber()`/`getProtocolInfo()` y mapear a `ELMFormat`. |
| 6 | Sin catálogo de protocolos 12–45 ni config CAN por petición. | Añadir `initProtocol(n)` y `sendCanRequest()` (ver `04-comandos-elm.md`). |
| 7 | `getVIN` asume respuesta de una sola línea; falla en CAN con múltiples tramas. | Reensamblar tramas con índice de secuencia. |

## 2.8 API pública

| Método | Comando | Devuelve |
|---|---|---|
| `connect(mac)` / `disconnect()` | — | `bool` / `void` |
| `sendCommand(cmd)` | raw | envía y espera prompt |
| `sendCommandWithResponse(cmd, timeout)` | raw | respuesta completa hasta `>` |
| `getRpm()` | `010C` | `int` RPM |
| `getSpeed()` | `010D` | `int` km/h |
| `getCoolantTemp()` | `0105` | `int` °C |
| `getEngineLoad()` | `0104` | `int` % |
| `getThrottlePosition()` | `0111` | `double` % |
| `getIntakePressure()` | `010B` | `int` kPa |
| `getIntakeTemp()` | `010F` | `int` °C |
| `getTimingAdvance()` | `010E` | `double` ° |
| `getFuelPressure()` | `010A` | `double` kPa |
| `getMAF()` | `0110` | `double` g/s |
| `getFuelLevel()` | `012F` | `double` % |
| `getBarometricPressure()` | `0133` | `int` kPa |
| `getShortTermTrimBank1/2()` | `0106`/`0108` | `double` % |
| `getLongTermTrimBank1/2()` | `0107`/`0109` | `double` % |
| `getAllFuelTrims()` | 4 PIDs | `FuelTrim` |
| `getO2Sensor(bank, sensor)` | `0114–011B` | `OxygenSensor` |
| `getOxygenSensors()` | 8 PIDs | `List<OxygenSensor>` |
| `getDTCs()` | `03` | `List<DTCCode>` |
| `clearDTCs()` | `04` | `bool` |
| `isMILActive()` | `0101` | `bool` |
| `getProtocol()` | `ATDP` | `String` |
| `getVIN()` | `0902` | `String` |
| `getSupportedPIDs()` | `0100/20/40/60` | `List<int>` |
| `getFreezeFrame(pid)` | `02xx` | `List<int>` bytes |
| `getVoltage()` | `ATRV` | `double?` V |
| `testerPresent()` | `3E00` | `bool` |
| `sendUDS(cmd)` | `22xxxx`… | `String` |
| `initProtocol(n)` | tabla 12–45 | `bool` |
| `sendCanRequest(cmd, config)` | config CAN | `String` |
| `responseStream` | — | log de bytes entrantes (broadcast) |

Los modelos de datos expuestos: `OxygenSensor` (bank, sensor, voltage, shortTermTrim),
`DTCCode` (code, description), `FuelTrim` (STFT/LTFT B1/B2 + available).
