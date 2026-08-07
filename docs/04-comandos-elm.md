# 04 — Catálogo de comandos ELM327 / CAN

> Comandos que la app envía (o expone) al adaptador ELM327. Basado en el catálogo documentado del
> proyecto hermano `car_scanner/docs/19-comandos.md` (análisis del código descompilado de Car Scanner),
> adaptado a la arquitectura Flutter.

## 4.1 Modelo de envío

Todo comando se envía como `comando + "\r"` y se espera el prompt `>`:

- Comandos **AT**: `ATZ`, `ATE0`, `ATSP5`, `ATFCSH7E0`, …
- Comandos **de datos**: `010C`, `03`, `0902`, `221201`, `3E00`, `10C0`, …

La respuesta se valida según tipo:

| Respuesta | Interpretación |
|---|---|
| `OK` | Comando AT aceptado |
| `?` | Comando no soportado por el ELM327 |
| `NO DATA` | ECU sin datos para el PID |
| `SEARCHING...` / `BUS INIT: ...` | El adaptador está buscando protocolo (previo a la respuesta real) |
| `ERROR` / `UNABLE TO CONNECT` | Fallo de bus o comando rechazado |
| `7F` + servicio | NRC UDS (no soportado / condición incorrecta) |

## 4.2 Secuencias de init

### Init por defecto — `default_init`

```
ATD → ATD0 → ATE0 → ATH1
```

### Post-init — `post_init`

```
ATE0 → ATH1 → ATM0 → ATS0 → ATAT{AdaptiveTimings} → ATAL
```

### Init NC2 (Nissan Consult 2) — `nc2_init`

```
ATD → ATD0 → ATE0 → ATH1 → ATM0 → ATS0 → ATAT1 → ATSP5
→ ATAL → ATIB10 → ATSH8110FC → ATST20 → ATSW05
→ 2212010401 → 221201 → ATSW05 → ATWM221201
```

KWP fast init (protocolo 5) hacia la cabecera `81 10 FC`, con wake-up y dos peticiones KWP
(modo `0x22`, DID `0x1201`).

### Init usado por la app al conectar

La app usa una secuencia propia (más robusta para clónicos):

```
ATZ → ATE0 → ATL0 → ATM0 → ATS0 → ATH0 → ATAL → ATAT1 → ATSP0 → ATST32 → ATDPN
```

> `ATZ` se tolera sin respuesta (algunos clónicos tardan o reinician el puerto). `ATH0` (headers
> off) es explícito para que el parseo no dependa de cabeceras; el parser igualmente soporta
> cabeceras on (ver `02-motor-obd2.md` §2.6). Cada comando se envía con `_safeCommand`, que
> **tolera fallos** (timeout, `?`, `ERROR`) y continúa con el siguiente; los comandos opcionales
> (`ATM0`, `ATS0`, `ATAT1`) no abortan el init. `ATDPN` se usa para detectar el protocolo activo
> y mapearlo a `ElmFormat` (§4.7). Para el reintento de comandos AT genéricos (2 intentos con
> 250 ms de espera) ver `_sendAt`.

## 4.3 Init por protocolo — tabla 12–45 (`GetAdditionalInit`)

Car Scanner usa **números de protocolo propios 12–45**, cada uno mapeado a comandos ELM reales.
La app expone `initProtocol(n)` con esta tabla:

| # | Comandos | ELM protocolo |
|---|---|---|
| 12 | `ATSP5` `ATIB96` | KWP fast (ISO14230) |
| 13 | `ATSP5` `ATIB48` | KWP fast |
| 14 | `ATSP5` `ATIB48` `ATIIA7A` | KWP fast + ISO9141 5-baud |
| 15 | `ATSP5` `ATIB48` `ATIIA13` | KWP fast + ISO9141 |
| 16 | `ATSP5` `ATIB48` `ATIIA33` | KWP fast + ISO9141 |
| 17 | `ATSP4` `ATIB96` | KWP 5-baud |
| 18 | `ATSP4` `ATIB48` | KWP 5-baud |
| 19 | `ATSP4` `ATIB48` `ATIIA7A` | KWP 5-baud + ISO9141 |
| 20 | `ATSP4` `ATIB48` `ATIIA13` | KWP 5-baud + ISO9141 |
| 21 | `ATSP4` `ATIB48` `ATIIA33` | KWP 5-baud + ISO9141 |
| 22 | `ATSP3` `ATIB96` | ISO9141-2 |
| 23 | `ATSP3` `ATIB48` | ISO9141-2 |
| 24 | `ATSP3` `ATIB48` `ATIIA7A` | ISO9141-2 |
| 25 | `ATSP3` `ATIB48` `ATIIA13` | ISO9141-2 |
| 26 | `ATSP3` `ATIB48` `ATIIA33` | ISO9141-2 |
| 27 | `ATSP5` `ATSH8013F1` `ATIB10` `ATIIA13` | KWP fast, cabecera 8013F1 (Renault/PSA) |
| 28 | `ATSP5` `ATSH8013F0` `ATIB96` `ATIIA13` | KWP fast, cabecera 8013F0 |
| 29 | `ATSP5` `ATSH8213F0` `ATIB96` `ATIIA13` | KWP fast, cabecera 8213F0 |
| 30 | `ATSP5` `ATSH8013FC` `ATIB10` `ATIIA10` | KWP fast, cabecera 8013FC |
| 31 | `ATSP5` `ATSH8013FC` `ATIB96` `ATIIA10` | KWP fast, cabecera 8013FC |
| 32 | `ATSP4` `ATSH8013F1` `ATIB10` `ATIIA13` | KWP 5-baud, cabecera 8013F1 |
| 33 | `ATSP4` `ATSH8013F0` `ATIB96` `ATIIA13` | KWP 5-baud, cabecera 8013F0 |
| 34 | `ATSP4` `ATSH8213F0` `ATIB96` `ATIIA13` | KWP 5-baud, cabecera 8213F0 |
| 35 | `ATSP4` `ATSH8013FC` `ATIB10` `ATIIA13` | KWP 5-baud, cabecera 8013FC |
| 36 | `ATSP4` `ATSH8013F1` `ATIB96` `ATIIA13` | KWP 5-baud, cabecera 8013F1 |
| 37 | `ATSP4` `ATSH8113F1` `ATIB96` `ATIIA13` | KWP 5-baud, cabecera 8113F1 |
| 38 | `ATSP5` `ATSH8110FC` `ATIB10` `ATIIA10` | KWP fast, cabecera 8110FC |
| 39 | `ATSP4` `ATSH8013F1` `ATIB10` `ATIIA13` | KWP 5-baud, cabecera 8013F1 |
| 40 | `ATSP5` `ATSH8113F1` `ATIB96` `ATIIA13` | KWP fast, cabecera 8113F1 |
| 41 | `ATSP5` `ATSH8213F1` `ATIB96` `ATIIA13` | KWP fast, cabecera 8213F1 |
| 42 | `ATSP3` `ATSH686AF1` `ATIB10` `ATIIA33` | ISO9141-2, cabecera 686AF1 |
| 43 | `ATSP6` `ATSH7E0` `10C0` | CAN 11-bit + inicio de sesión 0x10/0xC0 |
| 44 | `ATSP5` `ATSH8110F1` `ATIB10` `ATST20` | KWP fast, cabecera 8110F1, timeout 0x20 |
| 45 | `ATSP6` `ATFCSH7E0` `ATFCSD30000000` `ATFCSM1` | CAN con flow control definido |

Los comandos de **datos** dentro de la tabla (`10C0`, `2212010401`) se envían como comandos
normales (con espera de prompt); el resto son AT de configuración.

## 4.4 Config CAN por petición — `sendCanRequest()`

Modelado sobre `BaseCAN11bitECU.GetRequestForCommand` / `BaseCAN29bitECU`:

### 11-bit (protocolo 6 u 8)

```
1. ATSP{protocolo:X1}                     fijar protocolo de la ECU
2. AdditionalPreInit
3. Flow control:
   - con RequestHeader ≠ "7DF":
       - con ExtendedAddress: ATFCSH{hdr}; ATFCSD{EA}300005; ATFCSM1;
       - sin ExtendedAddress: ATFCSH{hdr}; ATFCSD300005; ATFCSM1;
   - sin RequestHeader o "7DF": ATFCSM0;   (auto)
4. Recepción:
   - sin ResponseHeader o RequestHeader=="7DF": ATAR;
   - si no: ATCRA{ResponseHeader};
5. Con ExtendedAddress: ATCEA{EA};
6. Con TesterAddress: ATTA{TesterAddress};
7. Comando de datos (p. ej. 010C)
8. Restauración (opcional): ATAR; ATFCSM0; ATCEA; ATSTDEF; ATSP0
```

`ATFCSD{EA}300005` = FC con dirección extendida destino + `30 00 05` (FS=0, BS=5).

### 29-bit (protocolo 7 o 9)

Igual que 11-bit pero añadiendo `ATCP{CANPriority}` antes de `ATSP`, y la cabecera de flow
control incluye la prioridad: `ATFCSH{prioridad}{RequestHeader};`.

## 4.5 Tabla maestra de comandos AT

| Comando | Parámetro | Significado | Uso |
|---|---|---|---|
| `ATZ` | — | Reset del adaptador | init |
| `ATD` / `ATD0` | — | Restaurar defaults (con/sin auto-connect) | init |
| `ATE0` | — | Echo OFF | init |
| `ATH0` / `ATH1` | — | Headers OFF/ON | init; el parser tolera ambos |
| `ATL0` | — | Linefeeds OFF | init |
| `ATM0` | — | Memory OFF | init |
| `ATS0` | — | Spaces OFF (compacto) | init |
| `ATAT0/1` | — | Adaptive timing | init |
| `ATAL` | — | Allow long messages (multiframe) | init, lecturas CAN |
| `ATSP` | hex 0–B | Fijar protocolo (0=auto, 3=ISO9141, 4=KWP 5-baud, 5=KWP fast, 6=CAN 11-bit 500k, 7=CAN 29-bit 500k, 8=CAN 11-bit 250k, 9=CAN 29-bit 250k) | init, `initProtocol`, `sendCanRequest` |
| `ATSPA` / `ATSPB` | — | Protocolo auto / otro | detección |
| `ATDPN` | — | Leer número de protocolo | detección → `ELMFormat` |
| `ATDP` | — | Leer descripción del protocolo | `getProtocol()` |
| `ATST` | hex (ms×4) | Timeout de respuesta | `ATST32` por defecto; `ATST20`/`ATST96` selectivos |
| `ATSTDEF` | — | Restaurar timeout por defecto | afterCommands CAN29 |
| `ATIB` | hex | Byte de init ISO14230 (fast) | `GetAdditionalInit` |
| `ATIIA` | hex | Byte de init ISO9141-2 (5-baud) | `GetAdditionalInit` |
| `ATSW05` | — | Wake-up KWP (0x05) | `nc2_init` |
| `ATSH` | cabecera (6 hex) | Fijar cabecera Rx | `GetAdditionalInit` |
| `ATWM` | dato (6 hex) | Wake-up message (KWP/NC2) | `nc2_init` |
| `ATFCSM` | 0/1/2 | Flow control CAN: auto/definido/definido-datos | `sendCanRequest` |
| `ATFCSH` | cabecera (6 hex) | Cabecera Tx de la trama FC | `sendCanRequest`, protocolo 45 |
| `ATFCSD` | datos (6+ hex) | Datos de la trama FC (`300005`, `300800`, …) | `sendCanRequest` |
| `ATCAF` | 0/1 | CAN auto-format OFF/ON | lecturas CAN largas |
| `ATCFC` | 0/1 | Flow control automático OFF/ON | lecturas CAN largas |
| `ATCRA` | cabecera (3/8 hex) | Dirección de recepción | `sendCanRequest` |
| `ATAR` | — | Auto receive | por defecto y restauración |
| `ATCEA` | dir (2 hex) / vacío | Direccionamiento extendido ON/OFF | `sendCanRequest` |
| `ATTA` | dir (2 hex) | Dirección del tester (Tx) | `sendCanRequest` |
| `ATCP` | 2 hex | Prioridad CAN 29-bit | `sendCanRequest` |
| `ATRV` | — | Leer voltaje de alimentación | `getVoltage()` |
| `STI` / `VTI` | — | Identificar chip STN1110 / Voltect | extensión (futuro) |
| `STP` | 2 dígitos | Fijar protocolo (STN) | extensión (futuro) |

### Comandos de datos

| Comando | Significado |
|---|---|
| `01xx` | Modo 1, PID `xx` (datos en vivo) |
| `02xx` | Modo 2 (freeze frame) |
| `03`, `07`, `0A` | DTC almacenados / pendientes / permanentes |
| `04` | Borrar DTC |
| `06` | Test de monitor ON-Board |
| `09` | Info del vehículo (`0902` VIN, `0900` PIDs soportados, `090A` nombre ECU) |
| `22xxxx` | UDS ReadDataByIdentifier (DID `xxxx`) |
| `3E` / `3E00` | UDS TesterPresent |
| `10C0` | Inicio de sesión de diagnóstico UDS (sesión 0xC0) |
| `2212010401` | Petición KWP de init NC2 (Nissan Consult 2) |

## 4.6 Optimización de comandos (deduplicación)

Al igual que `ELMState.UpdateStatusFromCommand` en Car Scanner, se evita reenviar comandos AT
redundantes:

- `ATSPx` solo se envía si el protocolo cambió.
- `ATFCSH`/`ATFCSD`/`ATFCSM0/1/2` se omiten si ya están activos.
- `ATCRA`, `ATCEA`, `ATTA`, `ATCP`, `ATST` se omiten si el valor coincide.
- `ATAR`/`ATCAF0/1`/`ATCFC0/1` se omiten si el estado ya es el solicitado.

El estado se limpia al iniciar una operación compuesta (`initProtocol`, `sendCanRequest`) y tras
`ATZ`, para no deduplicar sobre configuraciones desactualizadas.

## 4.7 Detección de protocolo — `ATDPN` → `ELMFormat`

| `ATDPN` | Protocolo | Formato |
|---|---|---|
| 0 | Auto | `auto` |
| 1 | SAE J1850 PWM | `j1850Pwm` |
| 2 | SAE J1850 VPW | `j1850Vpw` |
| 3 | ISO 9141-2 | `iso9141` |
| 4 | ISO 14230-4 KWP (5-baud) | `kwp5Baud` |
| 5 | ISO 14230-4 KWP (fast) | `kwpFast` |
| 6 | ISO 15765-4 CAN (11-bit, 500k) | `can11bit500` |
| 7 | ISO 15765-4 CAN (29-bit, 500k) | `can29bit500` |
| 8 | ISO 15765-4 CAN (11-bit, 250k) | `can11bit250` |
| 9 | ISO 15765-4 CAN (29-bit, 250k) | `can29bit250` |
| A | SAE J1939 (CAN 29-bit) | `j1939` |
| B | CAN 11-bit, 125k | `can11bit125` |
| C | CAN 29-bit, 125k | `can29bit125` |

## 4.8 Referencias

- `car_scanner/docs/19-comandos.md` — catálogo original completo (fuente de esta tabla).
- `car_scanner/docs/03-motor-obd2.md` §3.4 — detección `ELMFormat`.
- `BaseCAN11bitECU.cs:494` / `BaseCAN29bitECU.cs:103` — construcción de `beforeCommands`/`afterCommands`.
- `ELMState.cs:479` — `UpdateStatusFromCommand` (deduplicación).
- `OBDDataReader.cs:11500`/`:15040` — lectura CAN con flow control manual y `SendLongCanRequest`.
