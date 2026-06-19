# Project Rules (Reglas de Oro)

Este archivo actúa como el índice y la constitución del directorio `.context`. Las reglas definidas aquí tienen prioridad sobre cualquier otro archivo de contexto.

## 1. Stack Tecnológico
- **Framework:** Flutter.
- **Lenguaje de Desarrollo:** Dart (para lógica de app) y Kotlin/Java (para implementaciones nativas en Android).
- **Arquitectura Base:** Clean Architecture combinada con Vertical Slicing.
- **Gestión de Estado:** BLoC.
- **Inyección de Dependencias:** GetIt (u otra solución estándar).

## 2. Idiomas
- **Documentación y Comunicación (Texto):** Español.
- **Código (Nombres de variables, clases, métodos, comentarios técnicos):** Inglés.

## 3. Manejo de Archivos de Contexto (`.context/`)
- **`rules.md`:** Índice y constitución. Modificación/eliminación **solo con autorización explícita del usuario**.
- **`architecture.md`:** Definición estricta de la arquitectura. **NO se puede eliminar ni actualizar**.
- **`roadmap.md`:** Archivo volátil para planeación. Se actualiza con autorización del usuario para planificar sprints. NO se elimina.
- **`session.md`:** Archivo volátil. Registra el trabajo de la jornada. Se reescribe. NO se elimina.
- **`skills/`:** Directorio para directrices específicas (ej. UI/UX).

## 4. Flujo de Trabajo
- Todo plan importante o modificación al Roadmap debe ser consultado y autorizado por el usuario.
- Siempre priorizar implementaciones eficientes y respetar el patrón de diseño acordado en la interfaz.

## 5. Hardware Target y Optimización
- **Dispositivo Principal:** Samsung Galaxy A54.
- **Manejo de Sensores:** Considerar el nivel de ruido específico del acelerómetro de este dispositivo. Las lecturas de datos deben ser filtradas y suavizadas meticulosamente para evitar lecturas erradas.
- **Rendimiento Térmico:** Optimizar los streams (EventChannels) y polling del GPS para evitar sobrecalentamientos agresivos. Asegurar de cerrar o pausar las escuchas del hardware (acelerómetro/GPS) cuando no estén en uso.
