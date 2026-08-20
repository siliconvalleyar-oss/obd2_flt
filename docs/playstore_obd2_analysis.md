# Análisis: Secuencia OBD2 de App Play Store

## Resumen
Análisis de la secuencia de comandos enviados por una app profesional de Play Store
para entender su estrategia de monitoreo, discovery de PIDs, y lectura de datos.

---

## FASE 1: Discovery de PIDs Soportados

```
req 01 00 -> 41 00 BE 3F B8 13   (PIDs 01-20 soportados)
req 01 20 -> 41 20 80 06 80 00   (PIDs 21-40 soportados)
```

### Decodificación del bitmap `01 00` → `BE 3F B8 13`:
```
Bit 31 (PID 01): 1 → Monitor Status
Bit 30 (PID 02): 1 → Freeze DTC
Bit 29 (PID 03): 1 → Fuel System Status
Bit 28 (PID 04): 1 → Calculated Engine Load
Bit 27 (PID 05): 1 → Coolant Temperature
Bit 26 (PID 06): 1 → Short Term Fuel Trim Bank 1
Bit 25 (PID 07): 1 → Long Term Fuel Trim Bank 1
Bit 24 (PID 08): 1 → Short Term Fuel Trim Bank 2
Bit 23 (PID 09): 0 → Long Term Fuel Trim Bank 2 (NO)
Bit 22 (PID 0A): 1 → Fuel Pressure
Bit 21 (PID 0B): 1 → Intake Manifold Pressure
Bit 20 (PID 0C): 1 → Engine RPM
Bit 19 (PID 0D): 1 → Vehicle Speed
Bit 18 (PID 0E): 0 → Timing Advance (NO)
Bit 17 (PID 0F): 1 → Intake Air Temperature
Bit 16 (PID 10): 1 → MAF Air Flow Rate
Bit 15 (PID 11): 1 → Throttle Position
Bit 14 (PID 12): 0 → Commanded O2 Sensor 1 (NO)
Bit 13 (PID 13): 0 → O2 Sensor 1 Voltage (NO)
Bit 12 (PID 14): 1 → O2 Sensor 2 Voltage
Bit 11 (PID 15): 1 → O2 Sensor 3 Voltage
Bit 10 (PID 16): 0 → O2 Sensor 4 (NO)
Bit 09 (PID 17): 0 → O2 Sensor 5 (NO)
Bit 08 (PID 18): 0 → O2 Sensor 6 (NO)
Bit 07 (PID 19): 0 → O2 Sensor 7 (NO)
Bit 06 (PID 1A): 0 → O2 Sensor 8 (NO)
Bit 05 (PID 1B): 0 → OBD Standard (NO)
Bit 04 (PID 1C): 1 → OBD Type
Bit 03 (PID 1D): 0 → O2 Sensors Aux (NO)
Bit 02 (PID 1E): 0 → (NO)
Bit 01 (PID 1F): 1 → Runtime Since Start
Bit 00 (PID 20): 1 → PIDs 21-40 supported
```

### Decodificación del bitmap `01 20` → `80 06 80 00`:
```
Bit 31 (PID 21): 0 → Distance with MIL (NO)
Bit 30 (PID 22): 0 → Fuel Rail Pressure (NO)
Bit 29 (PID 23): 0 → Fuel Rail Gauge Pressure (NO)
Bit 28 (PID 24): 1 → O2 Sensor 1 (4 bytes)
Bit 27 (PID 25): 0 → O2 Sensor 2 (NO)
Bit 26 (PID 26): 0 → O2 Sensor 3 (NO)
Bit 25 (PID 27): 0 → O2 Sensor 4 (NO)
Bit 24 (PID 28): 0 → O2 Sensor 5 (NO)
Bit 23 (PID 29): 0 → O2 Sensor 6 (NO)
Bit 22 (PID 2A): 0 → Commanded O2 (NO)
Bit 21 (PID 2B): 0 → (NO)
Bit 20 (PID 2C): 1 → Commanded EGR
Bit 19 (PID 2D): 0 → EGR Error (NO)
Bit 18 (PID 2E): 1 → Commanded Evap Purge
Bit 17 (PID 2F): 1 → Fuel Tank Level
Bit 16 (PID 30): 0 → Warm-ups Since Clear (NO)
Bit 15 (PID 31): 1 → Distance Since Clear
Bit 14 (PID 32): 0 → Evap Pressure (NO)
Bit 13 (PID 33): 0 → Barometric Pressure (NO)
Bit 12 (PID 34): 1 → O2 Sensor 1 (4 bytes)
Bit 11 (PID 35): 0 → O2 Sensor 2 (NO)
Bit 10 (PID 36): 0 → O2 Sensor 3 (NO)
Bit 09 (PID 37): 0 → O2 Sensor 4 (NO)
Bit 08 (PID 38): 0 → O2 Sensor 5 (NO)
Bit 07 (PID 39): 0 → O2 Sensor 6 (NO)
Bit 06 (PID 3A): 0 → O2 Sensor 7 (NO)
Bit 05 (PID 3B): 0 → O2 Sensor 8 (NO)
Bit 04 (PID 3C): 1 → Catalyst Temperature Bank 1
Bit 03 (PID 3D): 0 → Catalyst Temperature Bank 2 (NO)
Bit 02 (PID 3E): 0 → (NO)
Bit 01 (PID 3F): 0 → (NO)
Bit 00 (PID 40): 0 → PIDs 41-60 supported (NO)
```

### PIDs relevantes para dashboard:
| PID | Nombre | Formato |
|-----|--------|---------|
| 01 | Monitor Status / DTC Count | 4 bytes |
| 03 | Fuel System Status | 2 bytes |
| 04 | Calculated Engine Load | 1 byte (0-100%) |
| 05 | Coolant Temperature | 1 byte (°C = raw - 40) |
| 06 | Short Term Fuel Trim Bank 1 | 1 byte (% = raw/1.28 - 100) |
| 07 | Long Term Fuel Trim Bank 1 | 1 byte |
| 0B | Intake Manifold Pressure | 1 byte (kPa) |
| 0C | Engine RPM | 2 bytes (RPM = raw/4) |
| 0D | Vehicle Speed | 1 byte (km/h) |
| 0F | Intake Air Temperature | 1 byte (°C = raw - 40) |
| 10 | MAF Air Flow Rate | 2 bytes (g/s = raw/100) |
| 11 | Throttle Position | 1 byte (% = raw*100/255) |
| 14 | O2 Sensor 2 Voltage | 2 bytes |
| 15 | O2 Sensor 3 Voltage | 2 bytes |
| 1C | OBD Type | 1 byte |
| 1F | Runtime Since Start | 2 bytes (segundos) |
| 24 | O2 Sensor 1 (4 bytes) | 4 bytes |
| 2C | Commanded EGR | 1 byte |
| 2E | Commanded Evap Purge | 1 byte |
| 2F | Fuel Tank Level | 1 byte (% = raw*100/255) |
| 31 | Distance Since Clear | 2 bytes (km) |
| 34 | O2 Sensor 1 (4 bytes) | 4 bytes |
| 3C | Catalyst Temperature Bank 1 | 2 bytes |

---

## FASE 2: Identificación del Vehículo

```
req 09 02 -> 49 02 01 39 42 47 4B 4C 34 38 54 30 48 42 31 33 30 37 36 33
req 09 04 -> 49 04 02 31 35 30 35 37 30 38 00 35 32 31 32 34 34 30 34 00
req 09 0A -> 49 0A 01 54 43 4D 2D 45 6E 67 69 6E 65 20 43 6F 6E 74 72 6F 6C 00 00
```

### Mode 09 (Vehicle Information):
| Sub | Nombre | Datos |
|-----|--------|-------|
| 02 | VIN | `9BGKL48T0HB130763` (Chevrolet Onix/Spin) |
| 04 | Calibration ID | `1505708` / `52124404` |
| 0A | ECU Name | `TCM-Engine Control` |

**VIN decodificado:**
- `9BG` → General Motors (Brasil)
- `KL48T` → Chevrolet Onix (código de modelo)
- `0H` → Año 2017
- `B130763` → Serial

---

## FASE 3: Intermedio (Discovery Adicional)

```
req 01 20 -> 41 20 80 06 80 00   (confirma PIDs 21-40)
req 22 F500 -> 7F 22 F5 00 31     (UDS: requestOutOfRange)
```

La app intenta leer un PID del fabricante `F500` vía UDS (Service 22 = ReadDataByIdentifier).
El `7F` = Negative Response Code, `31` = requestOutOfRange (ese PID no existe).

---

## FASE 4: Dashboard - Ciclo Principal

### Patrón de lectura en reposo (sin RPM):
La app lee repetidamente `01 00` (13 veces) como "heartbeat" mientras espera
el motor o verifica conexión. Luego entra en un ciclo de:

```
01 01 → Monitor Status / DTC count
01 03 → Fuel System Status
01 04 → Engine Load
01 05 → Coolant Temp (cada ~2 ciclos)
```

**Observación:** Cuando el motor está frío, la app NO lee RPM, velocidad, etc.
Solo lee load y temp para detectar cuándo el motor arranca.

### Patrón completo (motor funcionando):
Cuando detecta RPM > 0, expande el ciclo a:

```
01 01 → Monitor Status
01 03 → Fuel System Status
01 04 → Engine Load
01 05 → Coolant Temp
01 06 → STFT Bank 1
01 07 → LTFT Bank 1
01 0B → Intake Manifold Pressure (MAP)
01 0C → Engine RPM
01 01 → Monitor Status (verifica cada ~7 reads)
01 03 → Fuel System Status
01 04 → Engine Load
...
```

### Ciclo extendido (modo completo):
```
01 14 → O2 Sensor 2 Voltage
01 15 → O2 Sensor 3 Voltage
01 1C → OBD Type
01 1F → Runtime Since Start
01 21 → Distance with MIL
01 2E → Commanded Evap Purge
01 2F → Fuel Tank Level
01 31 → Distance Since Clear
01 0D → Vehicle Speed
01 03 → Fuel System Status
01 11 → Throttle Position
01 10 → MAF Air Flow Rate
```

**Secuencia completa del ciclo extendido:**
1. O2 sensors + catalizador
2. Runtime, distance
3. Evap purge, fuel level
4. Distance since clear
5. Vehicle speed
6. Fuel system status
7. Throttle + MAF

---

## FASE 5: PIDs del Fabricante (UDS Mode 22)

La app prueba 12 PIDs específicos del fabricante en cada ciclo:

```
22 199A → 7F 22 19 9A 31  (NRC: requestOutOfRange)
22 3201 → 7F 22 32 01 31  (NRC: requestOutOfRange)
22 1192 → 7F 22 11 92 31  (NRC: requestOutOfRange)
22 0052 → 7F 22 00 52 31  (NRC: requestOutOfRange)
22 1171 → 7F 22 11 71 31  (NRC: requestOutOfRange)
22 114B → 7F 22 11 4B 31  (NRC: requestOutOfRange)
22 11A1 → 62 11 A1 XX XX  (OK! Variable datos)
22 1470 → 7F 22 14 70 31  (NRC: requestOutOfRange)
22 2344 → 7F 22 23 44 31  (NRC: requestOutOfRange)
22 2345 → 62 23 45 00      (OK! Respuesta válida)
22 1154 → 7F 22 11 54 31  (NRC: requestOutOfRange)
22 19DE → 62 19 DE XX      (OK! Variable datos)
22 1170 → 7F 22 11 70 31  (NRC: requestOutOfRange)
```

### PIDs del fabricante que RESPONDEN:

| DID | Respuesta | Posible significado |
|-----|-----------|---------------------|
| `11A1` | `62 11 A1 00 3X` (X cambia: 0,1,2,3,4,5,6,7,8,9) | **Contador incremental** - probablemente PID counter o distance trip |
| `2345` | `62 23 45 00` (constante) | **Dato estático** - quizás config o status |
| `19DE` | `62 19 DE XX` (cambia: 30,23,1D,1B,21,30,40,29,2C,29,29) | **Valor dinámico** - probablemente presión de turbo, TPS real, o temp |

### Análisis del DID `11A1`:
Valores observados: `00 30`, `00 31`, `00 32`, `00 33`, `00 34`, `00 35`, `00 36`, `00 37`, `00 38`, `00 39`
→ Byte bajo incrementa de 0x30 a 0x39 = contador de 0 a 9
→ Es un **trip counter** o **sample counter** del ECU

### Análisis del DID `19DE`:
Valores: 0x30(48), 0x23(35), 0x1D(29), 0x1B(27), 0x21(33), 0x30(48), 0x40(64), 0x29(41), 0x2C(44), 0x29(41), 0x29(41)
→ Rango: 27-64 → puede ser temperatura (°C) o presión (kPa/2)
→ Los valores bajan y suben → **dinámico, probablemente temperatura de algún componente**

---

## FASE 6: TCM (Transmission Control Module)

```
TCM req 22 199A → 7F 22 19 9A 31  (NRC)
TCM req 22 280D → 7F 22 28 0D 31  (NRC)
TCM req 22 1940 → 62 19 40 BA     (OK!)
TCM req 22 210A → 7F 22 21 0A 31  (NRC)
```

La app cambia el header a `7E1` (TCM) y prueba 4 PIDs del fabricante:
- `1940` responde con `BA` (186 decimal) → **Temperatura del aceite de transmisión** (°C)

---

## Estrategia de la App - Resumen

### 1. Inicialización:
1. Leer `01 00` y `01 20` para descubrir PIDs soportados
2. Leer VIN (09 02), Calibration ID (09 04), ECU Name (09 0A)
3. Intentar PIDs del fabricante (F500) para detectar soporte UDS

### 2. Espera de arranque:
- Lee `01 00` repetidamente (13 veces) como heartbeat
- Detecta motor encendido cuando RPM > 0

### 3. Dashboard rápido (reposo):
- Ciclo cada ~1-2 segundos
- Lee: Monitor Status → Fuel System → Engine Load → Coolant Temp
- Cada 2 ciclos lee coolant temp

### 4. Dashboard completo (motor funcionando):
- Ciclo cada ~2-3 segundos
- Lee ~15-20 PIDs por ciclo
- Incluye: RPM, speed, load, temp, fuel trims, MAP, throttle, MAF, O2, fuel level, distance, runtime
- Lee PIDs del fabricante en cada ciclo

### 5. PIDs del fabricante:
- Intenta 12 PIDs UDS en cada ciclo
- Solo 3 responden para este ECU (GM/Onix)
- Los que responden: counter, config, valor dinámico
- Lee TCM por separado (header 7E1)

---

## Lecciones para Nuestra App

### 1. Discovery de PIDs:
- **Siempre** leer `01 00` y `01 20` al conectar
- Construir bitmap de PIDs soportados
- Solo intentar PIDs que existen
- Guardar resultado para usarlo en el dashboard

### 2. Identificación:
- Leer VIN, Calibration ID, ECU Name
- Decodificar VIN para detectar marca/modelo
- Usar para personalizar UI y PID display

### 3. Estrategia de lectura:
- **No leer todos los PIDs en cada ciclo** - la app profesional solo lee ~5 en reposo
- Detectar si el motor está encendido (RPM > 0)
- En reposo: solo load + temp + fuel system
- En funcionamiento: ciclo completo
- Los O2 sensors se leen con menos frecuencia

### 4. PIDs del fabricante:
- Probar UDS Mode 22 con headers del fabricante (7E0, 7E1)
- No todos los PIDs funcionan → manejar NRC gracefully
- Leer TCM por separado con header 7E1
- Los PIDs útiles varían por marca/modelo

### 5. Optimización:
- Usar `01 00` como heartbeat/market check
- Leer `01 01` antes de cada ciclo para verificar DTCs
- Los fuel trims (06, 07) solo leerlos cada ~5 ciclos
- Los O2 sensors solo cada ~10 ciclos

---

## Comparación con Nuestra App

| Característica | App Play Store | Nuestra App (v2.4.1) |
|----------------|----------------|----------------------|
| Discovery de PIDs | Lee 01 00 y 01 20 | Lee 01 00 una vez |
| Identificación | VIN + CalID + ECU | No lee |
| Heartbeat | 01 00 repetido | No tiene |
| Ciclo reposo | 4 sensores | Ciclo rápido (5 sensores) |
| Ciclo completo | ~15-20 PIDs | Ciclo lento (12+ sensores) |
| PIDs fabricante | Sí (UDS 22) | No |
| TCM separado | Sí (header 7E1) | Sí (DTC reading) |
| O2 sensors | En ciclo completo | En ciclo lento |
| Fuel level | Sí | No |
| Runtime | Sí | No |
| Distance | Sí | No |

---

## Próximos Pasos (Prioridad)

1. **Discovery automático de PIDs** → Usar 01 00 para saber qué leer
2. **Heartbeat con 01 00** → Mantener conexión activa
3. **Leer VIN** → Identificar el vehículo
4. **Ciclo inteligente** → Reposo vs funcionamiento
5. **PIDs del fabricante** → Probar UDS para datos extra
6. **Fuel level + Runtime** → Agregar al dashboard
