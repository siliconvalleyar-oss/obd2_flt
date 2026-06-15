# OBD2 Scanner — ELM327

App Flutter para diagnóstico vehicular OBD-II vía adaptador ELM327 Bluetooth. UI moderna con **glassmorphism**, **liquid swipe** y animaciones fluidas.

## Capturas

| Onboarding | Dashboard | DTCs | Terminal |
|------------|-----------|------|----------|
| LiquidSwipe con 3 páginas | Sensores en tiempo real | Códigos de error | Comandos AT/pid |

## Stack

| Capa | Tecnología |
|------|-----------|
| UI | Flutter + Material 3 |
| Estado | Riverpod (Notifier) |
| Rutas | GoRouter + StatefulShellRoute |
| Bluetooth | `flutter_bluetooth_serial_plus` |
| Animaciones | `flutter_animate`, `liquid_swipe`, `animations` |
| Efectos | Glassmorphism (BackdropFilter), LiquidBar (CustomPaint) |
| Persistencia | SharedPreferences (tema) |

## Funcionalidades

- **Dashboard** — RPM (barra líquida animada), velocidad, temp. motor, carga, TPS, MAP, IAT, avance, MAF, combustible, presión barométrica
- **Fuel Trim** — STFT/LTFT Banco 1 y 2 en tiempo real
- **Sensores de oxígeno** — Voltaje y trim por banco/sensor
- **Códigos DTC** — Lectura (Modo 03) y borrado (Modo 04) con glassmorphism
- **Info vehículo** — VIN, protocolo OBD, estado MIL, sensores O2
- **Terminal OBD** — Comandos raw AT y pid
- **Bluetooth** — Escaneo, selección y conexión a dispositivos emparejados
- **Tema** — Oscuro/Claro/Sistema con transición radial reveal
- **Onboarding** — LiquidSwipe con 3 pantallas introductorias
- **Navegación** — Bottom nav glassmorphism con badges

## Requisitos

- Android 8.0+ (API 26+)
- Adaptador ELM327 Bluetooth
- Flutter SDK 3.11.4+ ([Instalar](https://docs.flutter.dev/get-started/install/linux/android))

## Compilar

```bash
flutter pub get
flutter build apk --debug
# APK en: build/app/outputs/flutter-apk/app-debug.apk
```

## Instalar

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

## PIDs OBD-II Soportados

| PID | Sensor | Fórmula |
|-----|--------|---------|
| 0104 | Carga motor | `A × 100 / 255` |
| 0105 | Temperatura refrigerante | `A − 40` |
| 0106-09 | Fuel Trim ST/LT B1/B2 | `(A − 128) / 1.28` |
| 010A | Presión combustible | `A × 3` |
| 010B | Presión MAP | `A kPa` |
| 010C | RPM | `(256A + B) / 4` |
| 010D | Velocidad | `A km/h` |
| 010E | Avance encendido | `A/2 − 64` |
| 010F | IAT | `A − 40` |
| 0110 | MAF | `(256A + B) / 100 g/s` |
| 0111 | TPS | `A × 100 / 255` |
| 012F | Nivel combustible | `A × 100 / 255` |
| 0133 | Presión barométrica | `A kPa` |
| 0114-1B | Sensores O2 | `A × 0.005V / (B − 128) / 1.28` |
| 0902 | VIN | 17 caracteres ASCII |
| 03 | Códigos DTC | — |
| 04 | Borrar DTCs | — |

## Estructura

```
lib/
├── main.dart                         # Entry point, ProviderScope, router
├── obd2_elm327.dart                  # Motor OBD2 (Bluetooth + PIDs)
├── core/
│   ├── theme/app_theme.dart          # Colores, gradientes, dark/light theme
│   └── providers/
│       ├── obd2_provider.dart        # Estado reactivo de sensores y conexión
│       └── theme_provider.dart       # ThemeMode con persistencia
└── presentation/
    ├── router/app_router.dart        # GoRouter + StatefulShellRoute
    ├── screens/
    │   ├── onboarding_screen.dart    # LiquidSwipe intro
    │   ├── shell_screen.dart         # Bottom nav shell
    │   ├── obd2_dashboard_screen.dart# Dashboard + conexión Bluetooth
    │   ├── obd2_dtc_screen.dart      # Códigos DTC
    │   ├── obd2_terminal_screen.dart # Terminal de comandos raw
    │   └── obd2_info_screen.dart     # Info vehículo + sensores O2
    └── widgets/
        ├── glassmorphism_widget.dart # GlassCard + GlassButton
        ├── liquid_bar.dart           # Barra de progreso con ondas
        ├── liquid_glass_bottom_bar.dart # Bottom nav glassmorphism
        └── theme_transition_overlay.dart # Transición radial de tema
```

