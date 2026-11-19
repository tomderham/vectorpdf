<!-- keywords: signature manuscrite, signature, signer, tampon, tampons, initiales, stamp, stamps, signatures, sign, signing, initials, PDF, handwritten signature, digital signature, sign with certificate, certificate, p12, pfx, keychain, timestamp, certify, lock fields, which signature -->
<!-- source: b94ff6b8a43e -->

# Signer un document

Il y a deux façons de signer, et elles ne font pas la même chose. Toutes deux se trouvent sous le bouton Sign, la signature dans la barre d’outils Markup (⇧⌘A).

| | Signature manuscrite | Signature numérique |
| --- | --- | --- |
| Ce que c’est | Une image de votre signature ou de vos initiales sur la page | Une signature faite avec votre certificat et conservée dans le fichier |
| Montre qui a signé | Non : n’importe qui peut coller une image | Oui, si le certificat provient d’une autorité à laquelle le lecteur fait confiance |
| Montre que le document n’a pas changé depuis | Non | Oui |
| Ce qu’il vous faut | Rien : dessinez, tapez ou choisissez une image | Un certificat de signature, fourni par votre organisation ou une autorité de certification |
| Peut être retirée ensuite | Oui, comme un commentaire | Seulement en revenant à une copie enregistrée avant la signature |

Une signature manuscrite suffit là où une image fait l’affaire, comme pour un formulaire informel. Utilisez une signature numérique pour les contrats, les approbations et tout ce que quelqu’un pourrait devoir vérifier plus tard. Une signature numérique peut aussi afficher votre signature manuscrite dans son cadre.

## Ajouter votre signature manuscrite {#add-your-handwritten-signature}

1. Affichez la barre d’outils Markup (⇧⌘A), cliquez sur le bouton Sign, puis choisissez Add Handwritten Signature. La première fois, VectorPDF vous demande de créer votre signature :
   - **Draw :** signez avec votre trackpad ou votre souris.
   - **Type :** saisissez votre nom ou vos initiales et choisissez une police.
   - **Image :** choisissez un fichier PNG ou JPEG. Si vous choisissez **Transparent background**, la page apparaît à travers l’arrière-plan de l’image.
2. Cliquez là où vous la voulez.

Faites-la ensuite glisser pour la déplacer, ou faites glisser un angle pour la redimensionner. Pour la retirer, sélectionnez-la et appuyez sur Delete, ou cliquez dessus avec le bouton droit et choisissez Delete Signature.

VectorPDF conserve votre signature sur ce Mac pour la prochaine fois. Pour la modifier ou la supprimer, choisissez VectorPDF > Settings, cliquez sur General, puis utilisez les boutons à côté de Handwritten Signature.

## Signer avec un certificat {#sign}

Pour signer, il vous faut un certificat de signature avec sa clé privée. Votre organisation ou une autorité de certification peut vous en fournir un, généralement sous forme de fichier .p12 ou .pfx protégé par un mot de passe. Les certificats de votre trousseau peuvent être utilisés directement.

1. Cliquez sur le bouton Sign de la barre d’outils Markup et choisissez Sign with Certificate, ou choisissez Edit > Sign with Certificate. Faites ensuite glisser un cadre sur la page à l’endroit de la signature, ou cliquez pour en placer un de taille habituelle. Appuyez sur Échap pour arrêter. Si le document a un champ de signature vide, vous pouvez plutôt cliquer sur ce champ et choisir Sign with Certificate.
2. Choisissez votre certificat. Un aperçu montre à quoi ressemblera la signature. Pour utiliser un fichier, cliquez sur **Choose Certificate File**, puis saisissez son mot de passe. Le fichier n’est lu que pour cette signature et n’est pas ajouté à votre trousseau.
3. Si vous le souhaitez, saisissez un motif (par exemple « J’approuve ce document ») et le lieu où vous signez. Si vous avez créé une [signature manuscrite](#add-your-handwritten-signature), vous pouvez l’afficher dans le champ. Sinon, votre nom est affiché.
4. Si vous le souhaitez, choisissez sous After Signing :
   - **Certify**, si personne n’a encore signé le document : indiquez quelles modifications le laissent valide désormais : remplir des formulaires, signer et ajouter des annotations ; remplir des formulaires et signer ; ou aucune. Un document certifié apparaît comme tel à quiconque le vérifie, et les modifications ultérieures qu’il n’autorise pas rendent votre signature non valide.
   - **Lock form fields**, pour un formulaire : tous ses champs, ou ceux que vous choisissez, passent en lecture seule et gardent les valeurs que vous avez signées.
5. Cliquez sur **Sign**.

La signature enregistre le document : s’il contient des modifications non enregistrées, VectorPDF vous propose d’abord de les enregistrer. Elles font alors partie de ce que vous signez. macOS peut vous demander d’autoriser VectorPDF à utiliser la clé de votre certificat.

Sauf si vous les verrouillez ou certifiez le document pour moins, la signature laisse les autres champs de formulaire du document tels quels, afin que d’autres personnes puissent encore les remplir, signer à leur tour ou ajouter des annotations sans rendre votre signature non valide. Chaque signature ultérieure est ajoutée après les précédentes de la même façon.

Il s’agit d’une signature PKCS #7 avec SHA-256, qui contient votre certificat et ceux des autorités qui l’ont émis. Elle enregistre l’heure de votre Mac.

Pour qu’un serveur d’horodatage garantisse le moment de votre signature, activez **Add a timestamp** et indiquez son adresse (votre organisation en a peut-être un ; il en existe de gratuits, comme celui de DigiCert, `http://timestamp.digicert.com`). Grâce à l’horodatage, votre signature peut être vérifiée telle qu’elle était au moment de la signature, même après l’expiration de votre certificat. Le serveur ne reçoit qu’une empreinte de la signature, rien du document. S’il est injoignable, rien n’est signé et le document reste tel qu’il était.

Pour vérifier les signatures d’un document, consultez [Vérifier des signatures numériques](digital-signatures.md).

## Signer un formulaire

Si un formulaire a un champ de signature, cliquez sur **Sign** dans le champ, puis choisissez Add Handwritten Signature ou Sign with Certificate. Consultez [Remplir des formulaires](forms.md).
