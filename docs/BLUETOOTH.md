ATZ           → Resetea ELM327, devuelve "ELM327 v1.5"
ATE0          → Desactiva eco (no repetir comandos)
STI / VTI     → No soportados (responde "?")
ATD           → Restaura valores por defecto
ATD0          → Configuración adicional
ATE0          → (repite)
ATH1          → Activa cabeceras en respuestas
ATSP0         → Auto‑detección de protocolo
ATM0          → Desactiva monitoreo
ATS0          → Desactiva espacios en respuestas
ATAT1         → Ajusta tiempo de espera
ATAL          → Ajusta longitud de línea
ATST64        → Aumenta timeout a 640 ms

--- COMUNICACIÓN BLUETOOTH APP <-> ELM327 ---

1. Conexión física:
   - La aplicación escanea dispositivos Bluetooth, encuentra el ELM327 (nombre OBDII, MAC 00:1D:A5:07:23:6E).
   - Intenta conectar usando diferentes métodos (Method=1,3,4). A menudo falla con timeout o error de lectura.
   - Cuando tiene éxito, establece un socket y obtiene flujos de datos.

2. Inicialización del ELM327:
   - Envía "ATZ" (reset) y recibe "ELM327 v1.5".
   - Envía "ATE0" para desactivar eco.
   - Intenta "STI" y "VTI" pero no soportados.
   - Envía "ATD" (reset defaults) y configura parámetros: ATD0, ATE0, ATH1, ATSP0, ATM0, ATS0, ATAT1, ATAL, ATST64.

3. Detección de protocolo:
   - Envía "0100" (petición de PID de soporte). Recibe respuesta tipo "7E8064100BE3FB813".
   - Lee "ATDPN" para obtener protocolo (A6 = CAN 11 bit).
   - Decodifica.

4. Lectura de datos:
   - Pide PIDs como 0100, 0120, 0140, etc.
   - Pide información del vehículo con 0902, 0904, 090A.
   - Lee valores de sensores (RPM, velocidad, carga, etc.) con comandos como 010C, 010D, etc.
   - También usa comandos 22 (modo 22) para PIDs específicos de Chevrolet (ej. 221564, 221940, etc.) pero a menudo recibe "NO DATA".

5. Escaneo de ECUs:
   - Intenta leer DTCs y comunicarse con distintas unidades de control (motor, transmisión, BCM, ABS, etc.) cambiando cabeceras (ATSH) y filtros.
   - Usa comandos como 3E, 1800FF00, 1902AC, 19D2FF00, 03A981..., etc.

6. Errores comunes:
   - Timeouts en conexión (Arg_TimeoutException).
   - "read failed, socket might closed or timeout".
   - "NO DATA" para muchos PIDs.
   - "UNABLE TO CONNECT" al intentar restablecer conexión.
   - "Broken pipe" al escribir, indicando que el socket se cerró.

7. Desconexión:
   - Envía "Stop" y cierra la conexión.


App → Bluetooth (conectar) → ELM327
App → ATZ, ATE0, ATD, ... (inicializar)
App → 0100, ATDPN (detectar protocolo)
App → 0101, 010C, 0902, ... (leer datos)
App → ATSH7E0, 221564, ... (comandos específicos)
App → ATSH7E1, 3E, 1800FF00, ... (escaneo ECUs)
App → 04, 14FFFFFF (borrar DTCs)
App → Stop (desconectar)


La comunicacion Bluetooth entre la aplicacion (Car Scanner) y el adaptador OBD-II ELM327 se establece a traves de un perfil RFCOMM, donde la aplicacion actua como cliente y el adaptador como servidor, identificado por la direccion MAC 00:1D:A5:07:23:6E y el nombre "OBDII". El proceso de conexion se intenta mediante tres metodos internos distintos (Method=1, Method=3 y Method=4), siendo el ultimo el que generalmente logra establecer el enlace exitosamente, reportando en el log "[BTConnectionEstablished, Method=4] got streams from client"; sin embargo, es comun encontrar fallos previos debido a excepciones de timeout (Arg_TimeoutException) o errores de lectura que indican que el socket se ha cerrado o el tiempo de espera ha expirado ("read failed, socket might closed or timeout, read ret: -1").

Una vez que la conexion fisica de Bluetooth esta activa, la aplicacion procede a inicializar el adaptador ELM327 enviando una secuencia de comandos AT (Attention Commands). Primero envia "ATZ" para realizar un reinicio completo del chip, a lo que el adaptador responde con su identificador, tipicamente "ELM327 v1.5". Luego se desactiva el eco de los comandos con "ATE0" para evitar que el adaptador devuelva lo que se escribe, y se prueban comandos como "STI" y "VTI" para detectar funciones avanzadas, aunque en estos logs siempre responden con "?" indicando que no estan soportados. Posteriormente, se envia "ATD" para restaurar los valores por defecto, seguido de "ATD0", "ATH1" para activar la visualizacion de cabeceras en las respuestas, "ATSP0" para habilitar la autodeteccion del protocolo del vehiculo, "ATM0" para desactivar el monitoreo, "ATS0" para suprimir espacios en las tramas, "ATAT1" y "ATAL" para ajustar los tiempos de espera y longitudes de linea, y finalmente "ATST64" para aumentar el timeout a 640 milisegundos, buscando una comunicacion mas estable.

Con el adaptador ya configurado, la aplicacion inicia el handshake OBD-II enviando el comando "0100", que solicita los PIDs (Paramater IDs) soportados por la Unidad de Control del Motor (ECU). La respuesta obtenida, como "7E8064100BE3FB813", es decodificada y confirma que el vehiculo utiliza el protocolo CAN de 11 bits. Para verificar este hallazgo, se envia "ATDPN", que devuelve "A6", correspondiente al estandar ISO 15765-4 (CAN 11 bit), estableciendo asi el perfil de comunicacion definitivo.

A partir de este punto, la aplicacion comienza el ciclo de lectura de datos en tiempo real. Para ello, enviamos comandos estandar del modo 01, como "0101" (estado del sistema de monitoreo), "0103" (sistema de combustible), "0104" (carga del motor calculada), "0105" (temperatura del refrigerante), "0106" (ajuste de la mezcla de combustible a corto plazo), "0107" (ajuste a largo plazo), "010C" (revoluciones del motor, RPM), "010D" (velocidad del vehiculo, VSS) y "010E" (avance de encendido). Las respuestas tipicas tienen formatos como "7E806410182000000", "7E80441030200" o "7E803410438", donde cada par de digitos representa un byte de informacion especifica segun la norma SAE J1979. Muchos de estos PIDs devuelven "NO DATA" si la ECU del vehiculo no los soporta, lo cual es comun en modelos especificos.

Ademas de los datos de rendimiento, la aplicacion recupera la informacion de identidad del vehiculo mediante comandos del modo 09. Envia "0902" para solicitar el VIN (Vehicle Identification Number), "0904" para obtener la informacion de calibracion y "090A" para el nombre del fabricante. Estas respuestas son largas y se devuelven fragmentadas en varias lineas (por ejemplo, "7E81014490201394247" seguido de mas lineas), que la aplicacion ensambla para formar la cadena de texto completa del VIN y los datos del motor.

Para acceder a informacion mas profunda y especifica del fabricante (Chevrolet), la aplicacion utiliza comandos del modo 22 (servicio de datos por identificador). Antes de enviarlos, cambia la cabecera de comunicacion con "ATSH7E0" para dirigirse a la ECU del motor. Luego envia multiples solicitudes como "221564", "221940", "221997", "221993", "221998", "221994", "221999", "221995", "22119E", "22162F", "221630", "221631", "221632", "221633", "221634", "221635", "221636", "221251", "22119D", "22199A", "223201", "221192", "220052", "221171", "22114B", "2211A1", "221470", "222344", "222345", "221154", "2219DE", "221170", "22F432", "221145", "221172", "221141", "221193", "221194", "221195", "221196", "221197", "221198", "221199", "22129A", "221538", "2211A6", "22125D", "22125E", "221992", "221205", "221201", "221206", "221202", "221207", "221203", "221208", "221204", "2211EA", "2211F8", "2211EB", "2211F9", "2211EC", "2211FA", "2211ED", "2211FB", "1ADF", "221161", "22199E", "22199F", "22119F", "221991". En la mayoria de los casos, estas peticiones devuelven "NO DATA" porque la ECU del motor no implementa esos identificadores especificos o porque requieren una cabecera diferente, aunque en algunas ocasiones se obtienen respuestas positivas como "7E80462156429" que contienen informacion interna sobre parametros de inyeccion o transmision.

La aplicacion tambien realiza un barrido exhaustivo de todas las Unidades de Control Electronicas (ECUs) presentes en el bus CAN, incluyendo el motor (7E0), la transmision #1 (7E1), transmision #2 (7E2), el modulo de carroceria BCM (241), la direccion asistida EPS/TDM (242), el sistema de frenos ABS/EBCM/ESC (243), la unidad de entretenimiento EHU (244), el SIC (246), el modulo de airbags SDC/SRS (247), las luces AHL/AFL (249), el control de amortiguacion (24B), el tablero de instrumentos (24C), el climatizador HVAC (251) y el freno de estacionamiento (254). Para cada una de estas, la aplicacion cambia la cabecera activa usando "ATSH" seguido del identificador correspondiente y envia el comando "3E" (Tester Present) para mantener la sesion activa y evitar timeouts, seguido de solicitudes de codigos de diagnostico (DTC) como "1800FF00", "1902AC", "19D2FF00" y "03A98102F". Las ECUs que responden devuelven tramas como "7E8017E" para el tester present, o "7E8037F1811" y "5E881000000FF000000" para los codigos de fallo. En los logs, solo el Motor (7E0), el BCM (241) y el ABS (243) responden activamente, mientras que el resto de ECUs devuelven "NO DATA" o no contestan, indicando que no estan presentes en este modelo de Chevrolet o que requieren procedimientos de activacion previa.

Cuando se detectan codigos de fallo, la aplicacion puede intentar borrarlos. Un ejemplo claro es el borrado de DTCs en el modulo BCM: se selecciona la cabecera "ATSH241", se envia "04" (comando de borrado de codigos de diagnostico del modo 01) y posteriormente "14FFFFFF" para un borrado ampliado segun el estandar ISO 14230, recibiendo la confirmacion "6410144" y finalizando el proceso con exito.

Durante toda esta comunicacion, es frecuente que se produzcan errores. El mas comun es el agotamiento del limite de datos nulos, que ocurre cuando el adaptador deja de responder a las solicitudes, activando el evento "SetRunning(False, LOOPV3_NO_DATA_LIMIT_REACHED)", lo que obliga a la aplicacion a reiniciar el adaptador mediante "ReinitializeConnectionToECU". Este reinicio repite la secuencia de inicializacion (ATZ, ATE0, ATD, etc.) para intentar recuperar la sincronia. Cuando la situacion persiste, pueden aparecer errores graves de escritura en el socket, como "System.IO.IOException: Broken pipe", que indican que la conexion fisica Bluetooth se ha interrumpido abruptamente, imposibilitando la escritura de datos. En estos casos, los comandos posteriores devuelven "SEARCHING... UNABLE TO CONNECT", evidenciando que el ELM327 ha quedado bloqueado y no responde a ningun comando.

Finalmente, ya sea por finalizacion normal de la sesion o por deteccion de fallos criticos, la aplicacion ejecuta la rutina de desconexion "Stop(Disconnect:OBDHelper->Disconnect)", que cierra los flujos de entrada y salida, libera el socket Bluetooth y registra el estado "Stopped" junto con "SetRunning(False, From Stop #3640)". La aplicacion cuenta con un sistema robusto de reintentos, configurado para intentar hasta 34 conexiones en caso de fallos, con un tiempo de espera entre intentos y un limite de 25 minutos antes de detener los intentos automaticos. Este comportamiento asegura que, a pesar de las caidas de comunicacion y los timeouts, el usuario tenga una alta probabilidad de restablecer la conexion con el adaptador OBD-II simplemente reintentando la operacion.

