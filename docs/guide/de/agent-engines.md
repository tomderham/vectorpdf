<!-- keywords: Agent, KI, Engine, auf dem Gerät, Online-Modell, API-Schlüssel, Datenschutz, AI, engine, on-device, Private Cloud Compute, online model, API key, OpenAI, Gemini, OpenRouter -->
<!-- source: dbbd02de21b5 -->

# Festlegen, wie der Agent antwortet

Die Suche nach passenden Textstellen findet immer auf deinem Mac statt. Unter VectorPDF > Settings > AI Synthesis Engine kannst du festlegen, was die Antwort verfasst. Für diese Einstellung ist macOS 27 erforderlich.

| Engine | Funktionsweise | Was deinen Mac verlässt |
| --- | --- | --- |
| On-Device | Apple Intelligence auf deinem Mac | Nichts |
| Private Cloud Compute | Apple-Server, für längere und ausführlichere Antworten | Deine Frage und die verwendeten Textstellen, die an Private Cloud Compute von Apple gesendet werden |
| Online Model (dein API-Schlüssel) | Ein Dienst deiner Wahl, der über dein Konto bei diesem Dienst abgerechnet wird | Deine Frage, die Textstellen (oder der gesamte Text eines kurzen Dokuments) und der bisherige Gesprächsverlauf |

Unter macOS 26 antwortet der Agent auf dem Gerät.

Private Cloud Compute wird nur in Versionen von VectorPDF angezeigt, die dafür signiert sind. Die Version, die du von GitHub lädst, antwortet auf dem Gerät.

## Online-Modell verwenden

1. Setze in Settings die Option „AI Synthesis Engine“ auf „Online Model“.
2. Wähle einen Dienst aus: OpenAI, Google Gemini oder OpenRouter.
3. Gib deinen API-Schlüssel ein. Für jeden Dienst gibt es einen Link, über den du einen Schlüssel erhältst. Der Schlüssel wird in deinem Schlüsselbund „Anmeldung“ gespeichert.
4. Wähle ein Modell aus.

Wenn der Dienst nicht antworten kann, antwortet VectorPDF auf dem Gerät.

> **Warnung:** Für alles, was du sendest, gelten die Datenschutzrichtlinie und die Nutzungsbedingungen des Dienstes. Bei kostenlosen Gemini-Schlüsseln kann Google deine Daten zur Verbesserung seiner Produkte verwenden, und sie können von Menschen geprüft werden. Sende daher keine vertraulichen Dokumente. Weitere Informationen findest du unter [Datenschutz](privacy.md).
