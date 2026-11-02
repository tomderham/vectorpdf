<!-- keywords: Agent, IA, inteligência artificial, mecanismo, no dispositivo, modelo online, chave de API, AI, engine, on-device, Private Cloud Compute, online model, API key, OpenAI, Gemini, OpenRouter -->
<!-- source: dbbd02de21b5 -->

# Escolher como o Agent responde

A busca pelos trechos relevantes sempre acontece no seu Mac. Você pode escolher o que redige a resposta em VectorPDF > Settings > AI Synthesis Engine. Este ajuste requer o macOS 27.

| Mecanismo | Como funciona | O que sai do seu Mac |
| --- | --- | --- |
| On-Device | Apple Intelligence no seu Mac | Nada |
| Private Cloud Compute | Servidores da Apple, para respostas mais longas e detalhadas | Sua pergunta e os trechos usados, que vão para o Private Cloud Compute da Apple |
| Online Model (your API key) | Um serviço que você escolhe, cobrado na sua conta nesse serviço | Sua pergunta, os trechos (ou o texto inteiro de um documento curto) e a conversa anterior |

No macOS 26, o Agent responde no dispositivo.

O Private Cloud Compute aparece somente nas cópias do VectorPDF assinadas para esse recurso. A versão que você baixa do GitHub responde no dispositivo.

## Usar um modelo online

1. Em Settings, defina AI Synthesis Engine como Online Model.
2. Escolha um serviço: OpenAI, Google Gemini ou OpenRouter.
3. Digite sua chave de API. Há um link para obter uma em cada serviço. A chave é armazenada no seu chaveiro de início de sessão.
4. Escolha um modelo.

Se o serviço não puder responder, o VectorPDF responde no dispositivo.

> **Aviso:** A política de privacidade e os termos do serviço se aplicam ao que você envia. Nas chaves gratuitas do Gemini, o Google pode usar o que você envia para melhorar seus produtos, e pessoas podem revisar esse conteúdo, portanto não envie documentos confidenciais. Consulte [Privacidade](privacy.md).
