<!-- keywords: Agent, IA, inteligencia artificial, motor, en el dispositivo, modelo en línea, clave de API, AI, engine, on-device, Private Cloud Compute, online model, API key, OpenAI, Gemini, OpenRouter -->
<!-- source: dbbd02de21b5 -->

# Elegir cómo responde el Agent

La búsqueda de pasajes relevantes siempre se realiza en tu Mac. Puedes elegir qué redacta la respuesta en VectorPDF > Settings > AI Synthesis Engine. Este ajuste requiere macOS 27.

| Motor | Cómo funciona | Qué sale de tu Mac |
| --- | --- | --- |
| On-Device | Apple Intelligence en tu Mac | Nada |
| Private Cloud Compute | Los servidores de Apple, para respuestas más largas y detalladas | Tu pregunta y los pasajes utilizados, que se envían a Private Cloud Compute de Apple |
| Online Model (your API key) | Un servicio que eliges tú, facturado a tu cuenta en ese servicio | Tu pregunta, los pasajes (o todo el texto de un documento breve) y la conversación anterior |

En macOS 26, el Agent responde en el dispositivo.

Private Cloud Compute solo aparece en las copias de VectorPDF firmadas para usarlo. La versión que se descarga de GitHub responde en el dispositivo.

## Usar un modelo en línea

1. En Settings, ajusta AI Synthesis Engine en Online Model.
2. Elige un servicio: OpenAI, Google Gemini u OpenRouter.
3. Escribe tu clave de API. Hay un enlace para obtener una en cada servicio. La clave se guarda en tu llavero de inicio de sesión.
4. Elige un modelo.

Si el servicio no puede responder, VectorPDF responde en el dispositivo.

> **Advertencia:** Lo que envías está sujeto a la política de privacidad y a las condiciones del servicio. Con las claves gratuitas de Gemini, Google puede usar lo que envías para mejorar sus productos, y es posible que algunas personas lo revisen, así que no envíes documentos confidenciales. Consulta [Privacidad](privacy.md).
