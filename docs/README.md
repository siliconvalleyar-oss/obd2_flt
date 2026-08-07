# OBD2 Scanner Flutter — Documentación

> Documentación técnica de la app Flutter **"OBD2 Scanner con ELM327 — Liquid Glass UI"** (v2.0.1+1).
> Aplicación de diagnóstico vehicular OBD-II que se comunica con un adaptador **ELM327 por Bluetooth clásico (SPP/RFCOMM)**.

## Índice

| Doc | Contenido |
|-----|-----------|
| [01-arquitectura.md](01-arquitectura.md) | Estructura del proyecto, capas, router y flujo de datos |
| [02-motor-obd2.md](02-motor-obd2.md) | El motor `Obd2Elm327`: ciclo de conexión, framing por prompt `>`, parseo y API |
| [03-comunicacion-bluetooth.md](03-comunicacion-bluetooth.md) | Transporte SPP con `flutter_bluetooth_serial_plus`, permisos Android, flujo y correcciones |
| [04-comandos-elm.md](04-comandos-elm.md) | Catálogo de comandos ELM327/CAN implementado (init, protocolos 12–45, config CAN por petición, UDS) |
| [05-estado-y-ui.md](05-estado-y-ui.md) | Estado reactivo Riverpod, pantallas, refresco de sensores y terminal |
| [06-pids-soportados.md](06-pids-soportados.md) | PIDs OBD-II soportados, modos de servicio y fórmulas de conversión |
| [07-validacion.md](07-validacion.md) | Pruebas, checklist de verificación, adaptadores clónicos y resolución de problemas |
| [08-limitaciones-roadmap.md](08-limitaciones-roadmap.md) | Limitaciones conocidas y hoja de ruta (BLE, batching de PIDs, UDS avanzado) |

## Stack resumido

| Capa | Tecnología |
|------|-----------|
| UI | Flutter + Material 3, glassmorphism, liquid swipe |
| Estado | `flutter_riverpod` (Notifier/NotifierProvider) |
| Rutas | `go_router` (StatefulShellRoute) |
| Bluetooth | `flutter_bluetooth_serial_plus` (SPP, BT clásico) |
| Animaciones | `flutter_animate`, `liquid_swipe`, `animations` |
| Persistencia | `shared_preferences` (tema) |

## Ruta principal del flujo

```
UI (Dashboard) → obd2Provider (Riverpod) → Obd2Elm327 (lib/obd2_elm327.dart)
                                                     │
                                              BluetoothConnection (SPP)
                                                     │
                                              ELM327 → ECU del vehículo
```

## Comandos rápidos

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug   # build/app/outputs/flutter-apk/app-debug.apk
```

## Referencias cruzadas

El motor y el catálogo de comandos se basan en la documentación del proyecto hermano de escritorio
`car_scanner` (`docs/19-comandos.md`, `docs/03-motor-obd2.md`, `docs/05-transportes-conexion.md`),
que a su vez proviene del análisis del código de **Car Scanner (MAUI)** descompilado.
