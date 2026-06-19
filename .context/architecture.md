# Arquitectura del Proyecto

Este documento describe rígidamente la arquitectura del proyecto. **NO puede ser eliminado ni actualizado**.

## 1. Patrón Arquitectónico Principal
El proyecto utiliza una combinación de **Clean Architecture** y **Vertical Slicing**.

### Clean Architecture (Capas por Feature)
Cada funcionalidad de la aplicación se divide en las siguientes capas para garantizar el desacoplamiento:
- **Presentation (UI & State):** Contiene los Widgets de Flutter y los manejadores de estado (BLoC). Esta capa no tiene lógica de negocio.
- **Domain (Lógica de Negocio):** Contiene las Entities (modelos de datos puros) y los Use Cases. No tiene dependencias de Flutter ni librerías externas (solo Dart puro).
- **Data (Fuentes de Datos y Repositorios):** Contiene las implementaciones de los repositorios, DataSources (remotos, locales, y Platform Channels) y DTOs (Modelos de datos con serialización).

### Vertical Slicing (Modularización por Funcionalidad)
En lugar de agrupar por tipo (todas las vistas juntas, todos los repositorios juntos), el proyecto se agrupa por funcionalidad (feature).
Ejemplo de estructura:
```text
lib/
  features/
    auth/
      presentation/
      domain/
      data/
    steps/
      presentation/
      domain/
      data/
    tracking/
      presentation/
      domain/
      data/
```

## 2. Interacción Nativa (Platform Channels)
Dado que la aplicación requiere interacción profunda con el hardware de Android:
- **MethodChannel:** Para peticiones de una sola vez (ej. Solicitar autenticación biométrica, comprobar estado de GPS).
- **EventChannel:** Para escuchar flujos constantes de datos desde sensores (ej. Streaming del acelerómetro para contar pasos, coordenadas GPS en tiempo real).
El código nativo reside estrictamente en el directorio de Android nativo siguiendo las mejores prácticas.
