<!-- keywords: Zeitstempel, Zeitstempelserver, beglaubigen, Felder sperren, digitale Signatur, digitale Signaturen, signieren, mit Zertifikat signieren, Zertifikat, Schlüsselbund, signiert, Unterzeichner, beglaubigt, Beglaubigung, gültig, ungültig, prüfen, Vertrauen, Identität, Zeitstempel, manipuliert, geändert, digital signature, digital signatures, sign, signing, sign with certificate, p12, pfx, keychain, signed, signer, certificate, certified, certification, valid, invalid, verify, validate, trust, identity, timestamp, PKCS, CAdES, PAdES, tampered, changed -->
<!-- source: 5ae9b04ec005 -->

# Digitale Signaturen erstellen und prüfen

Eine digitale Signatur zeigt, wer ein Dokument signiert hat und dass es sich seitdem nicht geändert hat. Du kannst [ein PDF signieren](#sign), mit einem eigenen Zertifikat. Wenn du ein signiertes PDF öffnest, prüft VectorPDF seine Signaturen und zeigt in einer Leiste über der Seite, was es gefunden hat:

- **Die Signatur ist gültig:** Das Dokument ist seit dem Signieren unverändert, und das Zertifikat des Unterzeichners wurde von einer Stelle ausgestellt, der dein Mac vertraut.
- **Die Identität des Unterzeichners ist auf diesem Mac nicht bestätigt:** Das Dokument ist unverändert, aber nichts bürgt dafür, wer es signiert hat. Siehe [Warum die Identität eines Unterzeichners nicht bestätigt sein kann](#signer-identity).
- **Ungültig:** Das Dokument wurde nach dem Signieren geändert, oder die Signatur passt nicht zu ihm.

Klicke auf **Signature Details**, um jede Signatur im Tab „Document“ der Seitenleiste zu sehen. Um die Leiste auszublenden, klicke auf ihre Schließen-Taste.

> **Hinweis:** Ein [Stempel](stamps.md) ist ein Bild einer Unterschrift, keine digitale Signatur.

## Mit einem Zertifikat signieren {#sign}

Zum Signieren brauchst du ein Zertifikat zum Signieren mit seinem privaten Schlüssel. Deine Organisation oder eine Zertifizierungsstelle kann dir eines geben, meist als .p12- oder .pfx-Datei mit einem Passwort. Zertifikate in deinem Schlüsselbund kannst du direkt verwenden.

1. Wähle Edit > Sign with Certificate und ziehe dann auf der Seite einen Rahmen an der Stelle auf, an der die Signatur stehen soll, oder klicke für einen in der üblichen Größe. Drücke Esc, um abzubrechen. Wenn das Dokument ein leeres Signaturfeld hat, kannst du stattdessen auf das Feld klicken und Sign with Certificate wählen.
2. Wähle dein Zertifikat. Eine Vorschau zeigt, wie die Signatur aussehen wird. Um eine Datei zu verwenden, klicke auf **Choose Certificate File** und gib dann ihr Passwort ein. Die Datei wird nur für diese Signatur gelesen und nicht zu deinem Schlüsselbund hinzugefügt.
3. Wenn du möchtest, gib einen Grund ein (etwa „Ich genehmige dieses Dokument“) und den Ort, an dem du signierst. Wenn du einen [Stempel](stamps.md) erstellt hast, kannst du deine handschriftliche Unterschrift im Feld zeigen. Andernfalls wird dein Name angezeigt.
4. Wenn du möchtest, wähle unter „After Signing“:
   - **Certify**, wenn noch niemand das Dokument signiert hat: Lege fest, welche Änderungen es von nun an gültig lassen: Formulare ausfüllen, signieren und Anmerkungen; Formulare ausfüllen und signieren; oder keine. Ein beglaubigtes Dokument wird jedem, der es prüft, als beglaubigt angezeigt, und spätere Änderungen, die es nicht erlaubt, machen deine Signatur ungültig.
   - **Lock form fields**, bei einem Formular: Alle seine Felder oder die, die du auswählst, werden schreibgeschützt, sodass sie die Werte behalten, die du signiert hast.
5. Klicke auf **Sign**.

Beim Signieren wird das Dokument gesichert. Hat es ungesicherte Änderungen, fragt VectorPDF daher zuerst, ob sie gesichert werden sollen. Sie werden Teil dessen, was du signierst. macOS fragt eventuell, ob VectorPDF den Schlüssel deines Zertifikats verwenden darf.

Sofern du sie nicht sperrst oder das Dokument für weniger beglaubigst, lässt die Signatur die anderen Formularfelder des Dokuments, wie sie sind, sodass andere sie weiterhin ausfüllen, ebenfalls signieren oder Anmerkungen hinzufügen können, ohne deine Signatur ungültig zu machen. Jede spätere Signatur wird auf dieselbe Weise nach den früheren angefügt.

Die Signatur ist eine PKCS-#7-Signatur mit SHA-256 und enthält dein Zertifikat und die der Stellen, die es ausgestellt haben. Sie hält die Uhrzeit auf deinem Mac fest.

Damit ein Zeitstempelserver bestätigt, wann du signiert hast, schalte **Add a timestamp** ein und gib seine Adresse an (deine Organisation betreibt vielleicht einen; kostenlose gibt es etwa von DigiCert, `http://timestamp.digicert.com`). Mit einem Zeitstempel kann deine Signatur so geprüft werden, wie sie beim Signieren war, auch nachdem dein Zertifikat abgelaufen ist. Der Server erhält nur einen Fingerabdruck der Signatur, nichts vom Dokument. Ist er nicht erreichbar, wird nichts signiert und das Dokument bleibt, wie es war.

## Was VectorPDF prüft

Für jede Signatur zeigt die Liste im Tab „Document“:

- Ob die Teile der Datei, die sie signiert hat, genau so sind, wie sie signiert wurden.
- Ob die Datei nach dem Signieren erneut gesichert wurde und ob diese Änderungen solche sind, die die Signatur erlaubt. Formularfelder ausfüllen, Signaturen hinzufügen und Anmerkungen hinzufügen oder ändern sind meist erlaubt. Eine beglaubigende Signatur kann weniger Änderungen erlauben. Wurden nach dem Signieren Anmerkungen hinzugefügt, sagt die Liste das: Eine Anmerkung kann verdecken, was signiert wurde.
- Wer sie signiert hat, mit dem Namen in seinem Zertifikat, und wer das Zertifikat ausgestellt hat. Der Name, den die Signatursoftware in das Dokument geschrieben hat, wird ebenfalls angezeigt, wenn er abweicht.
- Wann sie signiert wurde. Für eine Zeit von einer Zeitstempelstelle wird gebürgt, wenn der Zeitstempel zu dieser Signatur gehört und seiner Stelle auf deinem Mac vertraut wird; andernfalls sagt die Liste, warum er nicht zählt. Für eine Zeit vom eigenen Computer des Unterzeichners wird nicht gebürgt.
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
