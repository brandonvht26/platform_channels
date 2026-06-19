# Decisiones Técnicas - Mega Reto: Detector de Actividad y Caídas

Este documento sustenta las decisiones arquitectónicas y de librerías tomadas para la implementación del detector de actividad física con aviso por voz, cumpliendo con los requerimientos del Mega Reto.

## 1. Detección de Actividad (Caminar/Correr/Quieto)
**Decisión:** Uso exclusivo de `sensors_plus` (Datos Crudos del Acelerómetro).
**Justificación:**
A pesar de que existen alternativas nativas más eficientes energéticamente (como `activity_recognition_flutter`), se optó por construir la lógica matemática manualmente usando los datos crudos de `sensors_plus`. 
- *El Porqué:* Dado que el reto exige obligatoriamente detectar caídas (lo cual requiere sí o sí leer el acelerómetro en bruto para buscar los picos de impacto), utilizar un segundo plugin para la actividad sería redundante y sumaría dependencias innecesarias al proyecto.
- *Gestión de Desventajas (Batería):* Somos conscientes de que procesar el acelerómetro en Dart genera un mayor consumo en el procesador (especialmente en equipos como el Galaxy A54). Para mitigar esto, aplicaremos un muestreo controlado y optimizaremos las fórmulas matemáticas de los umbrales para que el impacto en el CPU sea el mínimo indispensable.

## 2. Detección de Caída
**Decisión:** Algoritmo propio de umbrales basado en `sensors_plus`.
**Justificación:**
Una caída humana tiene una firma física inconfundible. Se implementará una máquina de estados para detectar esta firma en tres fases:
1. **Caída libre:** La magnitud resultante del vector 3D (X, Y, Z) cae abruptamente por debajo de la gravedad estándar (acercándose a 0).
2. **Impacto:** Un pico violento donde la magnitud supera los 30-40 m/s².
3. **Inmovilidad:** La magnitud se estabiliza de nuevo en ~9.8 m/s² sin variaciones (el usuario está en el suelo).
- *Control de Falsos Positivos:* Tras el impacto, el sistema evaluará una "ventana de gracia" de 2 a 3 segundos. Si la varianza de la aceleración demuestra movimiento (el usuario siguió caminando), la caída se descarta (fue solo un tropiezo o el celular rebotó). Si hay inmovilidad total, se asume caída grave y se dispara el diálogo de emergencia de 15 segundos.

## 3. Síntesis de Voz (Avisos de Estado)
**Decisión:** Uso del paquete `flutter_tts`.
**Justificación:**
Se descartaron soluciones basadas en la nube (Cloud TTS) porque una aplicación de fitness y monitoreo de emergencias debe funcionar **100% offline**. 
- *El Porqué:* Si el usuario sufre una caída corriendo en un bosque o en una zona sin cobertura celular, depender de una API web para la síntesis de voz retrasaría o anularía las notificaciones de emergencia. `flutter_tts` utiliza el motor de voz integrado del dispositivo (Android TTS), garantizando ejecución instantánea y sin consumo de datos, aunque la voz pueda percibirse ligeramente menos natural.

## 4. Control de Ruido del Sensor (Debounce)
**Decisión:** Uso del paquete `rxdart` con `.debounceTime(Duration(seconds: 3))`.
**Justificación:**
Los sensores de movimiento en bruto generan muchísimo ruido (jitter). Si conectamos el TTS directamente al stream, la aplicación saturaría al usuario con mensajes cada segundo ante mínimos cambios de ritmo.
- *El Porqué (3 Segundos):* Se determinó que 3 segundos es el "sweet spot" (punto de equilibrio) humano. Si una persona que va corriendo frena para esquivar un obstáculo o mirar a ambos lados de la calle, le toma entre 1 y 2 segundos reanudar la marcha. Al establecer el debounce en 3 segundos, filtramos estas micro-pausas. La aplicación solo anunciará "Te detuviste" si el usuario genuinamente dejó de moverse de forma sostenida. 

## 5. Permisos
**Decisión:** Manejo híbrido (Manifiesto + Runtime).
**Justificación:**
Para poder acceder a los datos del hardware, declararemos explícitamente `HIGH_SAMPLING_RATE_SENSORS` en el `AndroidManifest.xml` (necesario en Android 12+ para leer el acelerómetro a alta frecuencia) y solicitaremos los permisos de actividad en tiempo de ejecución para cumplir con las políticas modernas de privacidad del sistema operativo.
