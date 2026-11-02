<!-- keywords: Agent, IA, intelligenza artificiale, motore, sul dispositivo, modello online, chiave API, Private Cloud Compute, OpenAI, Gemini, OpenRouter, AI, engine, on-device, online model, API key -->
<!-- source: dbbd02de21b5 -->

# Scegliere come risponde l'Agent

La ricerca dei passaggi pertinenti avviene sempre sul tuo Mac. Puoi scegliere cosa scrive la risposta in VectorPDF > Settings > AI Synthesis Engine. Questa impostazione richiede macOS 27.

| Motore | Come funziona | Cosa esce dal Mac |
| --- | --- | --- |
| On-Device | Apple Intelligence sul Mac | Niente |
| Private Cloud Compute | I server di Apple, per risposte più lunghe e dettagliate | La domanda e i passaggi utilizzati, che vengono inviati a Private Cloud Compute di Apple |
| Online Model (la tua chiave API) | Un servizio a tua scelta, addebitato sul tuo account di quel servizio | La domanda, i passaggi (o l'intero testo di un documento breve) e la conversazione precedente |

Su macOS 26, l'Agent risponde sul dispositivo.

Private Cloud Compute viene visualizzato solo nelle copie di VectorPDF firmate per questo servizio. La versione scaricata da GitHub risponde sul dispositivo.

## Usare un modello online

1. In Settings, imposta AI Synthesis Engine su Online Model.
2. Scegli un servizio: OpenAI, Google Gemini oppure OpenRouter.
3. Inserisci la chiave API. Per ogni servizio è disponibile un link per ottenerne una. La chiave viene conservata nel portachiavi login.
4. Scegli un modello.

Se il servizio non è in grado di rispondere, VectorPDF risponde sul dispositivo.

> **Attenzione:** a ciò che invii si applicano l'informativa sulla privacy e i termini del servizio. Con le chiavi Gemini gratuite, Google può usare ciò che invii per migliorare i propri prodotti e il materiale può essere esaminato da persone, quindi non inviare documenti riservati. Consulta [Privacy](privacy.md).
