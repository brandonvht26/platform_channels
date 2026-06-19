# Skill: Interfaz de Usuario (UI) y Patrones de Diseño

Este documento define el patrón de diseño visual que seguirá la aplicación.

## 1. Concepto General
**Tema:** Burbujas - Marino Caribe.
El diseño debe evocar el mar caribe, transmitiendo frescura y tranquilidad, acompañado de la suavidad de las burbujas. La mayor carga de la aplicación está en la lógica, por lo que la UI no debe estar sobrecargada, sino ser un complemento limpio y estético.

## 2. Paleta de Colores
- **Fondos principales:** Blanco puro.
- **Colores Primarios:** 
  - Celeste clarito.
  - Verde clarito.
- **Gradientes:** Para evitar monotonía, se recomienda utilizar gradientes sutiles transicionando entre el celeste y el verde clarito, respetando el concepto marítimo.

## 3. Tipografía
- **Fuente Principal:** `Nunito` (Ubicada en `assets/fonts`).
- Asegurarse de utilizar los pesos correctos (`Light`, `Regular`, `Bold`) dependiendo de la jerarquía (títulos vs cuerpos de texto).

## 4. Formas y Bordes
- **Bordes:** Redonditos (Rounded Corners). Evitar por completo bordes afilados o cuadrados. Usar `BorderRadius.circular(16)` o mayor, y formas completamente circulares para avatares o botones de acción (`FloatingActionButton`), para simular la suavidad de las burbujas.

## 5. Fluidez y Animaciones
- **Animaciones Interactivas:** La aplicación debe sentirse viva pero con interacciones **no abusivas**.
- **Feedback:** Botones y tarjetas deben tener pequeñas interacciones de escala al ser presionados.
- **Transiciones:** Transiciones de pantalla y modales fluidas que no entorpezcan el flujo del usuario.
