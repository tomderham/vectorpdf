<!-- keywords: digitale Signaturen prüfen, Zeitstempel, Zeitstempelserver, beglaubigen, Felder sperren, digitale Signatur, digitale Signaturen, signieren, mit Zertifikat signieren, Zertifikat, Schlüsselbund, signiert, Unterzeichner, beglaubigt, Beglaubigung, gültig, ungültig, prüfen, Vertrauen, Identität, manipuliert, geändert, digital signature, digital signatures, sign, signing, sign with certificate, p12, pfx, keychain, signed, signer, certificate, certified, certification, valid, invalid, verify, validate, trust, identity, timestamp, PKCS, CAdES, PAdES, tampered, changed, check signature -->
<!-- source: b817ac7da979 -->

# Digitale Signaturen prüfen

Eine digitale Signatur zeigt, wer ein Dokument signiert hat und dass es sich seitdem nicht geändert hat. Wie du ein PDF mit einem eigenen Zertifikat signierst, erfährst du unter [Mit einem Zertifikat signieren](stamps.md#sign). Wenn du ein signiertes PDF öffnest, prüft VectorPDF seine Signaturen und zeigt in einer Leiste über der Seite, was es gefunden hat:

- **Die Signatur ist gültig:** Das Dokument ist seit dem Signieren unverändert, und das Zertifikat des Unterzeichners wurde von einer Stelle ausgestellt, der dein Mac vertraut.
- **Die Identität des Unterzeichners ist auf diesem Mac nicht bestätigt:** Das Dokument ist unverändert, aber nichts bürgt dafür, wer es signiert hat. Siehe [Warum die Identität eines Unterzeichners nicht bestätigt sein kann](#signer-identity).
- **Ungültig:** Das Dokument wurde nach dem Signieren geändert, oder die Signatur passt nicht zu ihm.

Klicke auf **Signature Details**, um jede Signatur im Tab „Document“ der Seitenleiste zu sehen. Um die Leiste auszublenden, klicke auf ihre Schließen-Taste.

> **Hinweis:** Eine [handschriftliche Unterschrift](stamps.md) ist ein Bild einer Unterschrift, keine digitale Signatur.

## Was VectorPDF prüft

Für jede Signatur zeigt die Liste im Tab „Document“:

- Ob die Teile der Datei, die sie signiert hat, genau so sind, wie sie signiert wurden.
- Ob die Datei nach dem Signieren erneut gesichert wurde und ob diese Änderungen solche sind, die die Signatur erlaubt. Formularfelder ausfüllen, Signaturen hinzufügen und Anmerkungen hinzufügen oder ändern sind meist erlaubt. Eine beglaubigende Signatur kann weniger Änderungen erlauben. Wurden nach dem Signieren Anmerkungen hinzugefügt, sagt die Liste das: Eine Anmerkung kann verdecken, was signiert wurde.
- Wer sie signiert hat, mit dem Namen in seinem Zertifikat, und wer das Zertifikat ausgestellt hat. Der Name, den die Signatursoftware in das Dokument geschrieben hat, wird ebenfalls angezeigt, wenn er abweicht.
- Wann sie signiert wurde. Für eine Zeit von einer Zeitstempelstelle wird gebürgt, wenn der Zeitstempel zu dieser Signatur gehört und seiner Stelle auf deinem Mac vertraut wird; andernfalls sagt die Liste, warum er nicht zählt. Für eine Zeit vom eigenen Computer des Unterzeichners wird nicht gebürgt. Das Zertifikat des Unterzeichners wird so geprüft, wie es zum Zeitpunkt des Zeitstempels war, oder ohne Zeitstempel so, wie es jetzt ist. Eine Signatur ohne Zeitstempel gilt daher nicht mehr als verifiziert, sobald ihr Zertifikat abläuft.
- Den Grund und den Ort, die der Unterzeichner angegeben hat, falls vorhanden.

Klicke auf eine Signatur, um auf der Seite zu ihr zu gehen. Um ihre Zertifikate zu sehen, klicke auf **Show Certificate**, oder klicke mit der rechten Maustaste darauf und wähle Show Certificate.

VectorPDF prüft die Datei, wie sie zuletzt gesichert wurde, ungesicherte Änderungen sind also nicht enthalten. Bei jedem Sichern prüft es erneut.

## Warum die Identität eines Unterzeichners nicht bestätigt sein kann {#signer-identity}

Jeder kann ein Zertifikat mit einem beliebigen Namen darin erstellen. Eine Signatur beweist nur dann, wer signiert hat, wenn das Zertifikat von einer Stelle ausgestellt wurde, die dessen Identität geprüft hat, und dein Mac dieser Stelle vertraut. VectorPDF verwendet die Zertifikate, denen dein Mac vertraut, in der Schlüsselbundverwaltung.

Viele signierte PDFs verwenden Zertifikate von Stellen, denen Adobe Acrobat vertraut, macOS aber nicht, daher meldet VectorPDF ihre Unterzeichner als nicht bestätigt. Das Dokument kann trotzdem seit dem Signieren unverändert sein. Um einer Stelle zu vertrauen, füge ihr Zertifikat zur Schlüsselbundverwaltung hinzu und stelle es auf „Immer vertrauen“, aber nur, wenn du sicher bist, dass es das echte ist.

VectorPDF geht nicht online, um zu prüfen, ob ein Zertifikat widerrufen wurde. So erfährt niemand, dass du das Dokument geöffnet hast.

## Ein signiertes Dokument sichern

Wenn du ein signiertes Dokument sicherst, fügt VectorPDF deine Änderungen hinter den signierten Teil der Datei an und lässt diesen Teil, wie er war, sodass die Signaturen gültig bleiben, soweit die Änderungen erlaubt sind. Das Entfernen von Inhalten durch [Schwärzung](redact.md) schreibt die ganze Datei neu, daher werden die Signaturen des Dokuments ungültig.

## Geprüfte Arten von Signaturen

VectorPDF prüft die üblichen PDF-Signaturen: PKCS-#7- und CAdES-Signaturen (PAdES). Dokumentzeitstempel und ältere X.509-RSA-Signaturen prüft es noch nicht. Sie werden als **Not checked** aufgeführt.
