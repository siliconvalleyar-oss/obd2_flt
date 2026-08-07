# 08 — Limitaciones y hoja de ruta

> Limitaciones conocidas de la implementación actual y mejoras planificadas, en orden de impacto.

## 8.1 Limitaciones conocidas

### Comunicación

- **Solo Bluetooth clásico (SPP)**. Los adaptadores BLE (p. ej. chips CC2541 "BLE Mini", o ELM327
  BLE que expone GATT) **no funcionan** con esta app. Car Scanner usa GATT con servicios
  configurables (`BTLEServiceID`/`BTLEInputID`/`BTLEOutputID`), suscripción `notify` y escritura
  con respuesta (ver `car_scanner/docs/05-transportes-conexion.md` §5.3).
- **Sin WiFi/TCP**: no hay soporte para adaptadores tipo ELM327 WiFi.
- **Sin detección automática de STN/VT**: los comandos `STI`/`VTI`/`STP`/`STCFCPA`/`VTFCTRA`
  están documentados (ver `04-comandos-elm.md` §4.5) pero no se explotan para optimizar el acceso
  a ECUs STN-only.

### Motor OBD2

- **Sin batching de PIDs**: cada lectura de modo 1 es un round-trip. Car Scanner agrupa varios PIDs
  en una sola trama CAN (`OBDMultiRequest`) para reducir latencia; aquí el refresco de 15 sensores
  cuesta 15 round-trips (~1–3 s en adaptadores lentos).
- **Refresco fijo a 1 s**: no hay control de frecuencia por protocolo ni pausa de refresco cuando
  se leen DTC/UDS simultáneamente (se corrige con la cola FIFO + guard `_isRefreshing`).
- **Sin deduplicación completa de AT**: el estado ELM se modela parcialmente; algunos comandos
  redundantes podrían reenviarse en `sendCanRequest` cuando la tabla no registra el valor.
- **Paridad del flujo de datos**: con `ATH1` + `ATS0` simultáneos el formato es ambiguo (cabecera
  de 3 dígitos mezclada con datos) — el parser no lo soporta. La app usa `ATH0` + `ATS0`.
- **UDS limitado**: se soporta el envío genérico de `22xxxx`/`3E00`/`10C0` y `sendUDS`, pero no hay
  decodificación de DIDs, ni `2E`/`31`/`2F`, ni seed/key, ni sesiones de diagnóstico completas.
- **Sin DTC modos 07/0A en UI**: el motor puede leerlos (`47`/`4A`) pero la pantalla DTC solo usa
  el modo 03.
- **Sin soporte de tramas CAN largas con flow control manual** (`SendLongCanRequest`,
  `ATCFC`/`ATCAF` manual): los comandos están en el catálogo pero no hay API específica aún.

### Estado/UI

- `availablePids` se define en `Obd2State` pero nunca se rellena.
- El parser y las fórmulas viven dentro de `Obd2Elm327` (depende de `dart:io`/Bluetooth) → no son
  testeables de forma unitaria aislada.
- La pantalla legacy `obd2_screen.dart` duplica lógica del dashboard; mantenerla al día es costoso.

## 8.2 Hoja de ruta

### Fase 1 — Robustez del motor (prioridad alta)
1. **Cola FIFO** de comandos + buffer único por conexión (elimina lecturas corruptas).
2. **Init robusto**: `ATH0`, `ATM0`, `ATAL` explícitos, tolerancia a `?` en opcionales, timeout
   configurable, `ATDPN` → `ELMFormat`.
3. **Parseo unificado** tolerante a espacios y cabeceras, reensamblaje multiframe para VIN.
4. `clearDTCs` directo (sin `ATZ` intermedio).
5. Guard `_isRefreshing` en el provider.

### Fase 2 — Catálogo completo (ver `04-comandos-elm.md`)
6. `initProtocol(n)` con tabla 12–45.
7. `sendCanRequest()` con `beforeCommands`/`afterCommands` y deduplicación de AT.
8. `getVoltage()`, `testerPresent()`, `getProtocolNumber()`/`getProtocolInfo()`, freeze frame,
   modos 07/0A de DTC.
9. Detección STN/VT (`STI`/`VTI`) y comandos `ST*`.

### Fase 3 — Rendimiento y UDS
10. **Batching de PIDs** (modo 1 en una trama CAN cuando el protocolo lo permita).
11. Refresco adaptativo: intervalo por formato (CAN rápido vs ISO/KWP lento).
12. UDS: tabla de DIDs, `2E`/`31`/`2F`, sesiones de diagnóstico y seed/key.
13. Lectura CAN larga con flow control manual (ATCFC/ATCAF, `SendLongCanRequest`).

### Fase 4 — Transportes y calidad
14. **BLE/GATT** (servicios configurables, notify + write-with-response) como transporte alternativo.
15. Tests de unidad: extraer parser/fórmulas a `lib/core/obd/` y cubrir con `flutter test`
    (plan en `07-validacion.md` §7.5).
16. Retirar la pantalla legacy (`obd2_screen.dart`) una vez el dashboard cubra todas sus funciones.

## 8.3 Referencias al proyecto hermano

| Tema | Documento fuente |
|---|---|
| Motor OBD2 / reimplementación | `car_scanner/docs/03-motor-obd2.md` |
| Catálogo de comandos | `car_scanner/docs/19-comandos.md` |
| BLE / SPP / transporte | `car_scanner/docs/05-transportes-conexion.md` |
| Optimización de la cola | `OBDRequestQueueOptimizer` (§3.6 de `03-motor-obd2.md`) |
