# OBD2 Scanner - ELM327 v1.5

App Flutter para diagnóstico vehicular OBD-II mediante adaptador ELM327 Bluetooth.

## Funcionalidades

- **Dashboard en tiempo real**: RPM, velocidad, temperatura motor, carga, TPS, MAP, IAT, avance, MAF, combustible, presión barométrica
- **Fuel Trim**: STFT/LTFT Banco 1 y 2
- **Sensores de oxígeno**: Voltaje y trim corto plazo B1S1-B2S4
- **Códigos DTC**: Lectura (Modo 03) y borrado (Modo 04)
- **Información vehículo**: VIN, protocolo OBD, estado MIL
- **Terminal OBD**: Comandos personalizados AT y pid
- **Escaneo Bluetooth**: Selección dinámica de dispositivos emparejados

## Requisitos

- Android 8.0+ (API 26+)
- Adaptador ELM327 Bluetooth emparejado
- Flutter SDK 3.11.4+ ([Instalar](https://docs.flutter.dev/get-started/install/linux/android))

## Compilar APK

```bash
# 1. Verificar entorno
flutter doctor

# 2. Obtener dependencias
flutter pub get

# 3. Compilar APK de depuración
flutter build apk --debug

# 4. Compilar APK de release (requiere keystore)
# flutter build apk --release
```

El APK generado estará en:

```
build/app/outputs/flutter-apk/app-debug.apk
```

## Instalar en el móvil

### Opción 1 - ADB (USB debugging)

```bash
# Conectar el móvil por USB con debugging activado
flutter install
# o directamente:
adb install build/app/outputs/flutter-apk/app-debug.apk
```

### Opción 2 - Transferir archivo

1. Copiar `app-debug.apk` al móvil
2. En el móvil, abrir el archivo APK
3. Permitir instalación de orígenes desconocidos
4. Instalar

### Opción 3 - Google Drive / WhatsApp

1. Subir el APK a Drive o enviar por WhatsApp
2. Abrir desde el móvil e instalar

## Uso

1. Abrir la app
2. Seleccionar el dispositivo ELM327 de la lista de emparejados
3. Presionar "Conectar"
4. El dashboard mostrará los sensores en tiempo real
5. Usar las pestañas inferiores para DTCs, Terminal OBD e Info

## PIDs OBD-II Soportados

| PID | Sensor | Fórmula |
|-----|--------|---------|
| 0104 | Carga motor | A × 100 / 255 |
| 0105 | Temperatura refrigerante | A − 40 |
| 0106-09 | Fuel Trim ST/LT B1/B2 | (A − 128) / 1.28 |
| 010B | Presión MAP | A kPa |
| 010C | RPM | (256A + B) / 4 |
| 010D | Velocidad | A km/h |
| 010E | Avance encendido | A/2 − 64 |
| 010F | IAT | A − 40 |
| 0110 | MAF | (256A + B) / 100 g/s |
| 0111 | TPS | A × 100 / 255 |
| 012F | Nivel combustible | A × 100 / 255 |
| 0133 | Presión barométrica | A kPa |
| 0114-1B | Sensores O2 | A × 0.005V / (B − 128) / 1.28 |
| 03 | Códigos DTC | — |
| 04 | Borrar DTCs | — |
| 0902 | VIN | 17 caracteres ASCII |
