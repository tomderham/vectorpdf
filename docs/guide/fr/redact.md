<!-- keywords: caviarder, caviardage, caviardages, supprimer, masquer, noircir, sensible, numéro de sécurité sociale, carte bancaire, e-mail, téléphone, rechercher et caviarder, métadonnées, signets, pièces jointes, redact, redaction, redactions, remove, black out, sensitive, SSN, credit card, email, phone, date, find and redact, metadata, bookmarks, attachments, PDF -->
<!-- source: d8be777cd6d7 -->

# Caviarder des informations sensibles

Le caviardage supprime définitivement du contenu d’un PDF. VectorPDF efface du fichier le texte, les pixels d’image et les tracés situés sous la zone caviardée, ainsi que les annotations et les champs de formulaire qui la touchent. Il ne se contente pas de les recouvrir d’un cadre, et les révisions antérieures ne sont pas conservées lorsque vous enregistrez.

La première fois que vous caviardez dans un document, une alerte explique ce qui change également :

- **Supprimé de tout le document :** les métadonnées comme le titre et l’auteur, les pièces jointes, les vignettes de page, le texte de remplacement pour l’accessibilité et les données de formulaire XFA. Pour les conserver, caviardez une copie.
- **Les signets sont conservés,** et chaque mot caviardé dans leurs titres est remplacé par [Redacted]. Le texte des images et des numérisations ne peut pas être comparé : vérifiez donc vous-même les signets après avoir caviardé ces éléments.
- **Non supprimé :** les destinations nommées, les étiquettes de page, les noms de calques et le code JavaScript. Ils pourraient encore contenir le texte.

> **Attention :** Le caviardage prend effet dès que vous l’appliquez, et il n’y a pas de commande Undo. Votre fichier d’origine ne change pas tant que vous n’enregistrez pas : pour recommencer, fermez le document sans l’enregistrer. Conservez une copie de l’original et utilisez Save As pour enregistrer la version caviardée sous un nouveau nom.

Appuyez sur ⌥⌘R, ou choisissez View > Show Redact Toolbar.

## Caviarder une zone

1. Choisissez **Redact Region**.
2. Choisissez Black ou White comme couleur de caviardage.
3. Faites glisser le pointeur sur la zone à caviarder.

## Rechercher et caviarder

1. Choisissez **Find & Redact**.
2. Choisissez ce qu’il faut rechercher :
   - **Text / Phrase**, avec les options Match Case et Whole Word.
   - **Custom Regular Expression**, par exemple `[A-Z]{3}-\d{5}`.
   - **Social Security Number (SSN)**, **Credit Card Number**, **Email Address**, **Phone Number** ou **Date**. Ces options trouvent automatiquement les formats courants.
3. Cliquez sur Find.
4. Vérifiez les occurrences. Cliquez sur l’une d’elles pour la voir sur sa page, et désélectionnez celles que vous voulez conserver.
5. Choisissez une action :
   - **Redact** supprime le contenu et laisse un cadre noir ou blanc.
   - **Remove** supprime le contenu sans laisser de cadre.
6. Cliquez sur **Redact Selected** ou **Remove Selected**.

> **Attention :** La détection automatique peut laisser passer des éléments, en particulier les formats inhabituels ou le texte dans les images. Vérifiez le document avant de le partager. Le texte des pages numérisées doit être caviardé avec Redact Region.

## Enregistrer le résultat

Appuyez sur ⇧⌘S pour enregistrer le document caviardé sous un nouveau nom. L’enregistrement supprime aussi l’index de recherche de l’[Agent](agent.md) pour ce document, car il pourrait contenir le texte retiré.
