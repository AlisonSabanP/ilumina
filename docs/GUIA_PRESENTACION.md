# Lumina — Guía para la presentación

Todo lo que sigue está comprobado en el repositorio: los textos, los nombres de
los botones y las cifras salen del código y de compilaciones reales, no de
suposiciones.

---

## 1. El discurso de apertura (30 segundos)

> Lumina acerca la impresión 3D a quien más la necesita: personas con
> discapacidad motriz, visual o cognitiva, y profesionales de la salud y la
> ortopedia.
>
> El problema es que hoy, para imprimir un objeto adaptado, hay que saber
> manejar un programa de diseño 3D. Lumina quita esa barrera: el usuario
> responde unas preguntas, mide su mano con la cámara y la app le entrega un
> archivo listo para imprimir.
>
> Y lo hace accesible de verdad: la propia app se adapta a la persona, no al
> contrario.

---

## 2. El problema y la solución

| El problema | Lo que hace Lumina |
|---|---|
| Diseñar en 3D exige formación técnica | Un formulario de preguntas cortas que recomienda el objeto |
| Cada mano y cada cuerpo son distintos | Medición con cámara (21 puntos de la mano) o con regla |
| Muchas apps no son usables por quien las necesita | Cinco modos de accesibilidad conmutables en caliente |
| El software de diseño 3D es caro | Generación en el propio dispositivo, gratis y sin conexión |

---

## 3. Las tres ideas que deben quedarse en la cabeza

1. **La app se adapta a la persona.** Botones grandes, pictogramas, fuente para
   dislexia, alto contraste y reducir movimiento. Se activan en cualquier
   pantalla y se aplican al instante.
2. **Genera el modelo sin coste.** La pieza se construye en el propio móvil con
   geometría paramétrica real y sale en STL, el formato que abren todos los
   laminadores. No necesita internet ni cuenta de pago.
3. **Mide de verdad.** Con la cámara detecta los 21 puntos de la mano y calcula
   el ancho de palma, la envergadura y la apertura de agarre.

---

## 4. Guion de la demo en vivo (5 minutos)

Sigue este orden. Es el camino más corto que enseña todo sin callejones.

### Paso 1 — La accesibilidad (1 min)

1. Abre la app. En la pantalla de inicio verás la tarjeta **"Empieza ajustando
   la accesibilidad"**.
2. Pulsa **"Abrir el panel de accesibilidad"**.
3. Pulsa el perfil rápido **"Cognitiva / Sensibilidad"**. Fíjate en cómo cambia
   la letra a Andika y desaparecen las animaciones, sin reiniciar nada.
4. Activa **"Alto contraste"** y enséñalo.
5. Pulsa **"Sin ajustes"** para volver a la normalidad antes de seguir.

> **Frase para decir:** "Ninguno de estos cambios necesita reiniciar la app. Y
> se guardan: si cierro Lumina y la vuelvo a abrir, siguen puestos."

### Paso 2 — El formulario (1,5 min)

1. Vuelve al inicio y entra en **"Formulario inteligente"**.
2. Elige **"Motriz"**.
3. Responde las preguntas. Señala en voz alta que **el árbol se ramifica**: la
   pregunta siguiente depende de lo que acabas de contestar.
4. Cuando te pregunte la herramienta, elige **"Martillo"**.
5. Llega a la recomendación: **"Adaptador de agarre para martillo"**.

> **Frase para decir:** "No le pido al usuario que diseñe nada. Le hago las
> preguntas que haría un terapeuta ocupacional."

### Paso 3 — Medir con la cámara (1 min)

1. En el formulario, baja hasta la tarjeta de medidas y pulsa **"Medir con la
   cámara"** (si ya hay medidas, el botón dice **"Añadir o revisar medidas"**).
2. En la pantalla "Medir", abre **"Mano con 21 puntos"**. Pon la mano frente
   a la cámara: verás los 21 puntos superpuestos sobre la imagen en directo.
3. Menciona la **calibración**: sin indicar el ancho real de la palma, las
   medidas salen en unidades relativas. Es honesto y conviene decirlo.
4. Guarda las medidas.

> **Aviso:** esto **solo funciona en Android**. Si presentas desde un iPhone,
> salta este paso y usa **"Medida a mano"**, que siempre está disponible.

### Paso 4 — Generar y ver el modelo (1,5 min)

1. Pulsa **"Generar modelo 3D"**.
2. Verás la descripción de la pieza y la ficha con las cotas finales.
3. Pulsa **"Ver el modelo en 3D"**.
4. Gira la pieza con el dedo. Pulsa **"Rotar"** para la rotación automática.
5. Pulsa **"Bloquear"**: ahora la pieza ya no se puede mover por accidente.
6. Pulsa **"Descargar STL"** y luego **"Compartir STL"**.

> **Frase para decir:** "El botón de bloquear parece una tontería, pero para
> alguien con temblor esencial, perder la pieza fuera de la pantalla es motivo
> para dejar de usar la app."

### Paso 5 — La etiqueta en Braille (30 s)

1. Vuelve al formulario y elige el perfil **"Visual"**.
2. Responde hasta llegar a la recomendación **"Etiqueta en braille con
   relieve"**.
3. En el formulario aparece la tarjeta **"Etiqueta en Braille (opcional)"**.
   Pulsa **"Crear etiqueta en Braille"**.
4. Escribe un texto. Ajusta el tamaño con el deslizador.
5. Desliza el dedo por encima: **el móvil vibra** por cada carácter.
6. Vuelve y genera la etiqueta.

> **Frase para decir:** "La etiqueta no es decoración: es la pieza. Quien no ve
> el objeto no necesita un objeto grande, necesita saber qué es."

---

## 5. Tecnologías utilizadas

Versión sencilla, para poner en una diapositiva.

### Base

| Tecnología | Para qué |
|---|---|
| **Flutter + Dart** | Un solo código para Android e iOS |
| **provider** | Guarda el estado de la app (formulario, accesibilidad, generación) |
| **shared_preferences** | Recuerda los ajustes al cerrar la app |
| **path_provider** | Guarda los archivos generados en el móvil |

### Accesibilidad

| Tecnología | Para qué |
|---|---|
| **accessibility_widget** | Ajustes de accesibilidad según el estándar WCAG |
| **braille_text** | Convierte texto a Braille y lo dibuja con vibración |
| **Fuente Andika** | Tipografía diseñada para lectores con dislexia |
| **Fuente BraillePoints** | Dibuja los puntos Braille (el paquete no trae fuente) |
| **Semantics de Flutter** | Compatibilidad con TalkBack y VoiceOver |

### Medición

| Tecnología | Para qué |
|---|---|
| **camera** | Enciende la cámara |
| **hand_landmarker (MediaPipe)** | Detecta los 21 puntos de la mano. **Solo Android** |
| **Medida manual** | Alternativa con regla, siempre disponible |

### Generación y visualización

| Tecnología | Para qué |
|---|---|
| **Geometría propia** | Construye la pieza 3D en el móvil, gratis y sin internet |
| **power3d** | Visor 3D con rotación, zoom y bloqueo |
| **share_plus** | Comparte el archivo por cualquier app |

### Opcional (IA en la nube)

| Tecnología | Para qué |
|---|---|
| **Meshy AI (API REST)** | Genera el modelo con IA, solo si el usuario pone su clave |
| **http** | Conexión con el servicio |
| **flutter_dotenv** | Lee la clave sin escribirla en el código |

> **Importante para no equivocarte al presentar:** Meshy **no tiene modo de
> prueba gratuito**. Responde error 401 con cualquier clave que no sea de una
> cuenta real. Por eso Lumina funciona sola: la generación en el dispositivo es
> la vía por defecto, y Meshy es un extra opcional.

---

## 6. Preguntas que te van a hacer

**¿Por qué Provider y no Riverpod?**
Provider es el que usa el material didáctico de Flutter, no necesita generación
de código y basta para tres fuentes de estado. Riverpod sería más potencia de la
que el proyecto necesita.

**¿Funciona en iPhone?**
La app sí. La detección de manos no: MediaPipe solo tiene implementación para
Android. En iPhone la pantalla lo explica y ofrece la medida a mano. Es una
decisión consciente, no un olvido.

**¿Y si el usuario no tiene cámara?**
La app se instala igual. La cámara está declarada como característica opcional
en el manifiesto, así que aparece también en tablets y dispositivos sin cámara.

**¿Cuánto cuesta?**
Nada. La generación es local. Solo gastaría créditos si el usuario decide usar
Meshy con su propia cuenta.

**¿Es accesible de verdad o solo tiene un botón de "modo accesible"?**
Cinco modos independientes, tres perfiles de un solo toque y persistencia. Todos
los controles llevan etiquetas `Semantics` y orden de foco lógico. Además, el
panel del paquete de accesibilidad se sustituyó por uno propio en español
porque el original venía con los textos en inglés.

**¿Qué falta?**
Verificación en iPhone real, y la medición de objetos por realidad aumentada,
que se retiró porque no funcionaba de forma fiable.

---

## 7. Qué decir con honestidad

Presentar esto te hace más creíble, no menos:

- **La medición por realidad aumentada se retiró.** Estaba planeada con el
  paquete `neom_ar`, pero no funcionaba bien en dispositivos reales y su
  dependencia nativa rompía la compilación. Se dejaron dos vías que sí
  funcionan.
- **La detección de manos es solo Android.** Limitación del motor MediaPipe.
- **iOS no está probado.** Requiere un Mac. El código es el mismo y la
  configuración está escrita, pero no se ha podido compilar.
- **La cámara y el visor necesitan un móvil real.** Las pruebas automáticas
  cubren la lógica, no el hardware.

---

## 8. Números para citar

| Dato | Valor |
|---|---|
| Pruebas automáticas | 35, todas pasando |
| Análisis estático | Sin ningún aviso |
| Perfiles de necesidad | 3 (motriz, visual, cognitiva) |
| Modos de accesibilidad | 5, más 3 perfiles rápidos |
| Herramientas cubiertas | 7 (martillo, destornillador, sierra, cuchillo, tijeras, pincel, rastrillo) |
| Puntos de la mano detectados | 21 |
| Formatos de salida | STL (para imprimir) y GLB (para ver) |

---

## 9. Antes de presentar: comprobación en 5 minutos

- [ ] Abre la app en el móvil que vas a usar y recórrela entera una vez.
- [ ] Comprueba que la cámara funciona en ese móvil concreto.
- [ ] Deja la pantalla de inicio preparada antes de empezar.
- [ ] Ten las medidas a mano: si la cámara falla en directo, usa "Medida a
      mano" sin disculparte y sigue.
- [ ] Cierra las demás apps para que el visor 3D tenga memoria libre.
- [ ] Si presentas en un proyector, sube el brillo: el alto contraste se ve
      mejor que el modo normal.
