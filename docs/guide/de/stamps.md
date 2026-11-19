<!-- keywords: handschriftliche Unterschrift, Unterschrift, unterschreiben, Stempel, Unterschriften, signieren, Initialen, stamp, stamps, signature, signatures, sign, signing, initials, PDF, handwritten signature, digital signature, sign with certificate, certificate, p12, pfx, keychain, timestamp, certify, lock fields, which signature -->
<!-- source: b94ff6b8a43e -->

# Ein Dokument unterschreiben

Es gibt zwei Arten zu unterschreiben, und sie bewirken Unterschiedliches. Beide findest du unter der Taste „Sign“, der Unterschrift in der Symbolleiste „Markup“ (⇧⌘A).

| | Handschriftliche Unterschrift | Digitale Signatur |
| --- | --- | --- |
| Was es ist | Ein Bild deiner Unterschrift oder Initialen auf der Seite | Eine mit deinem Zertifikat erstellte Signatur, die in der Datei gespeichert ist |
| Zeigt, wer unterschrieben hat | Nein: Jeder kann ein Bild einfügen | Ja, wenn das Zertifikat von einer Stelle stammt, der der Leser vertraut |
| Zeigt, dass sich das Dokument seitdem nicht geändert hat | Nein | Ja |
| Was du brauchst | Nichts: zeichnen, tippen oder ein Bild wählen | Ein Zertifikat zum Signieren, von deiner Organisation oder einer Zertifizierungsstelle |
| Lässt sich später entfernen | Ja, wie eine Anmerkung | Nur durch Zurückgehen zu einer vor dem Signieren gesicherten Kopie |

Eine handschriftliche Unterschrift genügt, wo ein Bild reicht, etwa bei einem formlosen Formular. Verwende eine digitale Signatur für Verträge, Genehmigungen und alles, was jemand später prüfen muss. Eine digitale Signatur kann in ihrem Feld auch deine handschriftliche Unterschrift zeigen.

## Deine handschriftliche Unterschrift hinzufügen {#add-your-handwritten-signature}

1. Blende die Symbolleiste „Markup“ ein (⇧⌘A), klicke auf die Taste „Sign“ und wähle dann „Add Handwritten Signature“. Beim ersten Mal fordert VectorPDF dich auf, deine Unterschrift zu erstellen:
   - **Draw:** Unterschreibe mit dem Trackpad oder der Maus.
   - **Type:** Gib deinen Namen oder deine Initialen ein und wähle eine Schrift aus.
   - **Image:** Wähle eine PNG- oder JPEG-Datei aus. Wenn du **Transparent background** wählst, scheint die Seite durch den Hintergrund des Bilds hindurch.
2. Klicke an die Stelle, an der sie stehen soll.

Ziehe sie anschließend, um sie zu bewegen, oder ziehe an einer Ecke, um ihre Größe zu ändern. Um sie zu entfernen, wähle sie aus und drücke die Delete-Taste, oder klicke mit der rechten Maustaste darauf und wähle „Delete Signature“.

VectorPDF bewahrt deine Unterschrift für das nächste Mal auf diesem Mac auf. Um sie zu ändern oder zu löschen, wähle VectorPDF > Settings, klicke auf „General“ und verwende dann die Tasten neben „Handwritten Signature“.

## Mit einem Zertifikat signieren {#sign}

Zum Signieren brauchst du ein Zertifikat zum Signieren mit seinem privaten Schlüssel. Deine Organisation oder eine Zertifizierungsstelle kann dir eines geben, meist als .p12- oder .pfx-Datei mit einem Passwort. Zertifikate in deinem Schlüsselbund kannst du direkt verwenden.

1. Klicke in der Symbolleiste „Markup“ auf die Taste „Sign“ und wähle „Sign with Certificate“, oder wähle Edit > Sign with Certificate. Ziehe dann auf der Seite einen Rahmen auf, wo die Signatur hin soll, oder klicke für einen in der üblichen Größe. Drücke Esc, um abzubrechen. Hat das Dokument ein leeres Signaturfeld, kannst du stattdessen auf das Feld klicken und „Sign with Certificate“ wählen.
2. Wähle dein Zertifikat. Eine Vorschau zeigt, wie die Signatur aussehen wird. Um eine Datei zu verwenden, klicke auf **Choose Certificate File** und gib dann ihr Passwort ein. Die Datei wird nur für diese Signatur gelesen und nicht zu deinem Schlüsselbund hinzugefügt.
3. Wenn du möchtest, gib einen Grund ein (etwa „Ich genehmige dieses Dokument“) und den Ort, an dem du signierst. Wenn du eine [handschriftliche Unterschrift](#add-your-handwritten-signature) erstellt hast, kannst du sie im Feld zeigen. Andernfalls wird dein Name angezeigt.
4. Wenn du möchtest, wähle unter „After Signing“:
   - **Certify**, wenn noch niemand das Dokument signiert hat: Lege fest, welche Änderungen es von nun an gültig lassen: Formulare ausfüllen, signieren und Anmerkungen; Formulare ausfüllen und signieren; oder keine. Ein beglaubigtes Dokument wird jedem, der es prüft, als beglaubigt angezeigt, und spätere Änderungen, die es nicht erlaubt, machen deine Signatur ungültig.
   - **Lock form fields**, bei einem Formular: Alle seine Felder oder die, die du auswählst, werden schreibgeschützt, sodass sie die Werte behalten, die du signiert hast.
5. Klicke auf **Sign**.

Beim Signieren wird das Dokument gesichert. Hat es ungesicherte Änderungen, fragt VectorPDF daher zuerst, ob sie gesichert werden sollen. Sie werden Teil dessen, was du signierst. macOS fragt eventuell, ob VectorPDF den Schlüssel deines Zertifikats verwenden darf.

Sofern du sie nicht sperrst oder das Dokument für weniger beglaubigst, lässt die Signatur die anderen Formularfelder des Dokuments, wie sie sind, sodass andere sie weiterhin ausfüllen, ebenfalls signieren oder Anmerkungen hinzufügen können, ohne deine Signatur ungültig zu machen. Jede spätere Signatur wird auf dieselbe Weise nach den früheren angefügt.

Die Signatur ist eine PKCS-#7-Signatur mit SHA-256 und enthält dein Zertifikat und die der Stellen, die es ausgestellt haben. Sie hält die Uhrzeit auf deinem Mac fest.

Damit ein Zeitstempelserver bestätigt, wann du signiert hast, schalte **Add a timestamp** ein und gib seine Adresse an (deine Organisation betreibt vielleicht einen; kostenlose gibt es etwa von DigiCert, `http://timestamp.digicert.com`). Mit einem Zeitstempel kann deine Signatur so geprüft werden, wie sie beim Signieren war, auch nachdem dein Zertifikat abgelaufen ist. Der Server erhält nur einen Fingerabdruck der Signatur, nichts vom Dokument. Ist er nicht erreichbar, wird nichts signiert und das Dokument bleibt, wie es war.

Wie du die Signaturen eines Dokuments prüfst, erfährst du unter [Digitale Signaturen prüfen](digital-signatures.md).

## Ein Formular unterschreiben

Hat ein Formular ein Signaturfeld, klicke im Feld auf **Sign** und wähle dann „Add Handwritten Signature“ oder „Sign with Certificate“. Siehe [Formulare ausfüllen](forms.md).
