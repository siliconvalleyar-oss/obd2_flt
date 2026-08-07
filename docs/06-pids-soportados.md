# 06 — PIDs OBD-II soportados

> Modos de servicio OBD y PIDs que la app lee, con sus fórmulas de conversión. Implementado en
> `lib/obd2_elm327.dart`. Los PIDs de modo 1 se consultan con `01xx` y responden `41xx`.

## 6.1 Modos de servicio

| Modo | Uso | Comando | Respuesta |
|---|---|---|---|
| 01 | Datos en vivo | `01xx` | `41xx <datos>` |
| 02 | Freeze frame | `02xx` | `42xx <datos>` |
| 03 | DTC almacenados | `03` | `43 <nº> <códigos...>` |
| 04 | Borrar DTC | `04` | `OK` / `44...` |
| 07 | DTC pendientes | `07` | `47 ...` |
| 09 | Info del vehículo | `09 02` | `49 02 <VIN>` |
| 22 | UDS ReadDataByIdentifier | `22xxxx` | `62xxxx <datos>` |
| 3E | UDS TesterPresent | `3E00` | `7E00` |

## 6.2 PIDs de modo 1 soportados

| PID | Sensor | Fórmula |
|-----|--------|---------|
| 0100/20/40/60 | Mapa de PIDs soportados | bits 0–31 por rango |
| 0101 | Estado MIL + nº de DTC | bit 7 del byte A |
| 0104 | Carga del motor | `A × 100 / 255` |
| 0105 | Temperatura refrigerante | `A − 40` °C |
| 0106 | STFT Banco 1 | `(A − 128) × 100 / 128` |
| 0107 | LTFT Banco 1 | `(A − 128) × 100 / 128` |
| 0108 | STFT Banco 2 | `(A − 128) × 100 / 128` |
| 0109 | LTFT Banco 2 | `(A − 128) × 100 / 128` |
| 010A | Presión de combustible | `A × 3` kPa |
| 010B | Presión MAP (manifold) | `A` kPa |
| 010C | RPM | `(256·A + B) / 4` |
| 010D | Velocidad | `A` km/h |
| 010E | Avance de encendido | `A / 2 − 64` ° |
| 010F | Temperatura aire (IAT) | `A − 40` °C |
| 0110 | Flujo MAF | `(256·A + B) / 100` g/s |
| 0111 | TPS (posición mariposa) | `A × 100 / 255` % |
| 0114–0117 | Sensores O2 B1 S1–S4 | voltaje `A × 0.005` V; trim `(B − 128) × 100 / 128` |
| 0118–011B | Sensores O2 B2 S1–S4 | ídem |
| 012F | Nivel de combustible | `A × 100 / 255` % |
| 0133 | Presión barométrica | `A` kPa |

## 6.3 Freeze frame (modo 02)

El motor expone `getFreezeFrame(pid)` que envía `02xx` y devuelve los bytes crudos de `42xx`.
La decodificación por PID reutiliza las mismas fórmulas del modo 1 (los PIDs de modo 2 comparten
semántica con el modo 1).

## 6.4 DTC (modos 03/07/0A)

Respuesta típica del modo 03 con `ATS0` (sin espacios):

```
4301010002100315
     │ │  └───────► códigos DTC (2 bytes cada uno)
     │ └──────────► nº de códigos (byte B)
     └────────────► servicio 43
```

- `01 00` → `P0100`, `02 10` → `P0210`, `03 15` → `P0315`, …
- `0000` se ignora (ECU sin código en esa posición).
- Con cabeceras/espacios on el parseo es equivalente (el motor normaliza y busca el marcador `43`).
- La descripción se decodifica con `_decodeDTCCode` según el primer carácter y el siguiente:
  - `P0/P2/P3` → Powertrain genérico; `P1` → Powertrain fabricante; ídem C (Chasis), B (Carrocería),
    U (Red).

## 6.5 Borrar DTC (modo 04)

`clearDTCs()` envía `04` hasta 3 veces aceptando `OK` o `44...` como éxito. Algunos clónicos no
responden nada: en ese caso se asume éxito tras `OK` implícito en el prompt.

> ⚠️ El borrado es definitivo. La UI pide confirmación antes de llamar a este método.

## 6.6 VIN (modo 09, PID 02)

`getVIN()` envía `0902`. El parseo soporta dos formas:

- **Línea única (merged, headers OFF)**: `49 02 01 <17 bytes ASCII>`.
- **Multiframe (headers ON)**: una trama por línea
  (`7E8 10 14 49 02 01 …`, `7E8 21 …`, `7E8 22 …`), reensambladas quitando cabecera + byte de
  longitud/secuencia en cada trama de continuación.

Se validan ≥ 11 caracteres ASCII (17 típicos) para aceptar el VIN.

## 6.7 PIDs soportados (`getSupportedPIDs`)

Consulta los rangos `0100`, `0120`, `0140`, `0160` y decodifica el mapa de 4 bytes por rango:

```
0100 → 41 00 BE 1E B8 13
            │  │  │  │
            │  └──┴──┴──► bytes B,C,D,E (32 PIDs: 0x01–0x20)
            └────────────► servicio + PID
```

Cada bit a 1 indica que el PID está soportado (bit más significativo = PID base del rango).

## 6.8 Modo 09 adicional

| PID | Dato | Nota |
|---|---|---|
| 09 00 | PIDs de modo 9 soportados | mapa de bits |
| 09 02 | VIN | implementado (`getVIN`) |
| 09 0A | Nombre de la ECU (calibración) | disponible vía terminal |
| 09 04 | ID de calibración | vía terminal |
