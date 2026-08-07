# 01 — Arquitectura

> Estructura del proyecto, capas, router y flujo de datos de la app Flutter.

## 1.1 Estructura de carpetas

```
lib/
├── main.dart                          # Entry point: ProviderScope, MaterialApp.router, prefs de tema
├── obd2_elm327.dart                   # Motor OBD2: conexión Bluetooth SPP + comandos ELM + parseo
├── obd2_screen.dart                   # Pantalla legacy (pre-Riverpod), usa el mismo motor
├── core/
│   ├── providers/
│   │   ├── obd2_provider.dart         # Estado reactivo de conexión, sensores, DTC, protocolo, log
│   │   └── theme_provider.dart        # ThemeMode (claro/oscuro/sistema) persistido
│   └── theme/
│       └── app_theme.dart             # Colores, gradientes y temas Material 3
└── presentation/
    ├── router/
    │   └── app_router.dart            # go_router + StatefulShellRoute
    ├── screens/
    │   ├── onboarding_screen.dart     # LiquidSwipe intro (3 páginas)
    │   ├── shell_screen.dart          # Bottom nav shell
    │   ├── obd2_dashboard_screen.dart # Dashboard + conexión Bluetooth
    │   ├── obd2_dtc_screen.dart       # Códigos DTC (leer/borrar)
    │   ├── obd2_terminal_screen.dart  # Terminal de comandos AT/PID
    │   └── obd2_info_screen.dart      # Info vehículo (VIN, protocolo, MIL, O2)
    └── widgets/
        ├── glassmorphism_widget.dart  # GlassCard + GlassButton (BackdropFilter)
        ├── liquid_bar.dart            # Barra de progreso con ondas (CustomPaint)
        ├── liquid_glass_bottom_bar.dart # Bottom nav glassmorphism
        └── theme_transition_overlay.dart # Transición radial de tema
```

## 1.2 Capas y responsabilidades

| Capa | Archivos | Responsabilidad |
|---|---|---|
| **Motor OBD2** | `lib/obd2_elm327.dart` | Todo lo relacionado con el ELM327: conexión RFCOMM, serialización de comandos, espera del prompt `>`, parseo de respuestas, init, PIDs, DTC, VIN. |
| **Estado** | `lib/core/providers/obd2_provider.dart` | Expone `obd2Provider` con `Obd2State`; orquesta refrescos periódicos; traduce excepciones del motor a campos del estado. |
| **Tema** | `lib/core/providers/theme_provider.dart`, `lib/core/theme/app_theme.dart` | ThemeMode persistido y temas. |
| **Rutas** | `lib/presentation/router/app_router.dart` | Navegación con `StatefulShellRoute` (bottom nav persistente). |
| **UI** | `lib/presentation/screens/*`, `lib/presentation/widgets/*` | Pantallas y widgets de glassmorphism/liquid. |
| **Legacy** | `lib/obd2_screen.dart` | Pantalla antigua autónoma (usa `Obd2Elm327` directamente, no Riverpod). |

## 1.3 Router (go_router)

`app_router.dart` define las rutas:

| Ruta | Pantalla | Notas |
|---|---|---|
| `/onboarding` | `OnboardingScreen` | LiquidSwipe introductorio |
| `/home` | `ShellScreen` (StatefulShellRoute) | Bottom nav con sub-rutas |
| `/home/dashboard` | `Obd2DashboardScreen` | Sensores en tiempo real + conexión BT |
| `/home/dtc` | `Obd2DtcScreen` | Códigos de error |
| `/home/terminal` | `Obd2TerminalScreen` | Comandos raw |
| `/home/info` | `Obd2InfoScreen` | Info vehículo + sensores O2 |

El tema se aplica con `MaterialApp.router(theme: ..., darkTheme: ..., themeMode: ...)` y una
`ThemeTransitionOverlay` para la transición radial al cambiar de tema.

## 1.4 Flujo de datos de sensores

```
Timer.periodic(1s)                      obd2_provider._refreshSensors()
        │                                        │
        ▼                                        ▼
Obd2Elm327.getRpm()/getSpeed()/...  →  sendCommandWithResponse('01xx')
        │                                        │
        ▼                                        ▼
   BluetoothConnection.output.add(bytes)   →   ELM327  →  ECU
        │
        ▼
BluetoothConnection.input (Stream<Uint8List>)
        │
        ▼
Obd2Elm327._responseController (broadcast, log)
        │
        ├─► obd2_provider._responseSub → state.log  (terminal + debug)
        └─► buffer interno → detección de prompt ">" → completa el Future de la lectura
```

Cada sensor se lee de forma **secuencial y await** dentro de `_refreshSensors()`; los errores
individuales se ignoran y el campo correspondiente conserva su valor anterior (`--` la primera vez).

## 1.5 Dependencias relevantes (pubspec.yaml)

| Paquete | Versión | Uso |
|---|---|---|
| `flutter_bluetooth_serial_plus` | ^0.5.1 | Conexión Bluetooth SPP/RFCOMM |
| `permission_handler` | — | Permisos de Bluetooth/ubicación en Android 12+ |
| `flutter_riverpod` | — | Estado reactivo |
| `go_router` | — | Navegación |
| `liquid_swipe`, `flutter_animate`, `glassmorphism`, `smooth_page_indicator` | — | UI/animaciones |
| `shared_preferences` | — | Persistencia del tema |
