<!-- keywords: signature numérique, signatures numériques, signer, signer avec un certificat, certificat, trousseau, signé, signataire, certifié, certification, valide, non valide, vérifier, valider, confiance, identité, horodatage, falsifié, modifié, digital signature, digital signatures, sign, signing, sign with certificate, p12, pfx, keychain, signed, certificate, certified, valid, invalid, verify, validate, trust, identity, timestamp, PKCS, CAdES, PAdES, tampered, changed -->
<!-- source: 3d32c92200ad -->

# Signer et vérifier des signatures numériques

Une signature numérique montre qui a signé un document et qu’il n’a pas changé depuis. Vous pouvez [signer un PDF](#sign) avec votre propre certificat. Lorsque vous ouvrez un PDF signé, VectorPDF vérifie ses signatures et indique ce qu’il a trouvé dans une barre au-dessus de la page :

- **La signature est valide :** le document n’a pas changé depuis sa signature, et le certificat du signataire a été émis par une autorité à laquelle votre Mac fait confiance.
- **L’identité du signataire n’est pas vérifiée sur ce Mac :** le document n’a pas changé, mais rien ne garantit qui l’a signé. Consultez [Pourquoi l’identité d’un signataire peut ne pas être vérifiée](#signer-identity).
- **Non valide :** le document a été modifié après sa signature, ou la signature ne lui correspond pas.

Cliquez sur **Signature Details** pour voir chaque signature dans l’onglet Document de la barre latérale. Pour masquer la barre, cliquez sur son bouton de fermeture.

> **Remarque :** Un [tampon](stamps.md) est une image d’une signature, pas une signature numérique.

## Signer avec un certificat {#sign}

Pour signer, il vous faut un certificat de signature avec sa clé privée. Votre organisation ou une autorité de certification peut vous en fournir un, généralement sous forme de fichier .p12 ou .pfx protégé par un mot de passe. Les certificats de votre trousseau peuvent être utilisés directement.

1. Choisissez Edit > Sign with Certificate, puis cliquez sur la page à l’endroit où doit figurer la signature. Appuyez sur Esc pour arrêter. Si le document comporte un champ de signature vide, vous pouvez plutôt cliquer sur le champ et choisir Sign with Certificate.
2. Choisissez votre certificat. Pour utiliser un fichier, cliquez sur **Choose Certificate File**, puis saisissez son mot de passe. Le fichier n’est lu que pour cette signature et n’est pas ajouté à votre trousseau.
3. Si vous le souhaitez, saisissez un motif (par exemple « J’approuve ce document ») et le lieu où vous signez. Si vous avez créé un [tampon](stamps.md), vous pouvez afficher votre signature manuscrite dans le champ. Sinon, votre nom est affiché.
4. Cliquez sur **Sign**.

La signature enregistre le document : s’il contient des modifications non enregistrées, VectorPDF vous propose d’abord de les enregistrer. Elles font alors partie de ce que vous signez. macOS peut vous demander d’autoriser VectorPDF à utiliser la clé de votre certificat.

La signature laisse les autres champs de formulaire du document tels quels, afin que d’autres personnes puissent encore les remplir, signer à leur tour ou ajouter des annotations sans rendre votre signature non valide. Chaque signature ultérieure est ajoutée après les précédentes de la même façon.

Il s’agit d’une signature PKCS #7 avec SHA-256, qui contient votre certificat et ceux des autorités qui l’ont émis. Elle enregistre l’heure de votre Mac. Elle ne comporte pas encore d’horodatage d’une autorité d’horodatage.

## Ce que VectorPDF vérifie

Pour chaque signature, la liste de l’onglet Document indique :

- Si les parties du fichier qu’elle a signées sont exactement telles qu’elles ont été signées.
- Si le fichier a été enregistré de nouveau après la signature, et si ces modifications font partie de celles que la signature autorise. Remplir des champs de formulaire, ajouter des signatures et ajouter ou modifier des annotations sont généralement autorisés. Une signature de certification peut autoriser moins de modifications. Si des annotations ont été ajoutées après la signature, la liste l’indique : une annotation peut masquer ce qui a été signé.
- Qui l’a signée, selon le nom figurant dans son certificat, et qui a émis le certificat. Le nom que le logiciel de signature a écrit dans le document est aussi affiché lorsqu’il est différent.
- Quand elle a été signée. Une heure fournie par une autorité d’horodatage est garantie. Une heure provenant de l’ordinateur du signataire ne l’est pas.
- Le motif et le lieu indiqués par le signataire, le cas échéant.

Cliquez sur une signature pour y accéder sur la page. Pour voir ses certificats, cliquez sur **Show Certificate**, ou cliquez dessus avec le bouton droit et choisissez Show Certificate.

VectorPDF vérifie le fichier tel qu’il a été enregistré pour la dernière fois : les modifications non enregistrées ne sont donc pas prises en compte. Il vérifie de nouveau à chaque enregistrement.

## Pourquoi l’identité d’un signataire peut ne pas être vérifiée {#signer-identity}

N’importe qui peut créer un certificat contenant n’importe quel nom. Une signature ne prouve qui a signé que si le certificat a été émis par une autorité qui a vérifié son identité, et que votre Mac fait confiance à cette autorité. VectorPDF utilise les certificats auxquels votre Mac fait confiance, dans Trousseau d’accès.

De nombreux PDF signés utilisent des certificats d’autorités auxquelles Adobe Acrobat fait confiance, mais pas macOS : VectorPDF indique alors que leurs signataires ne sont pas vérifiés. Le document peut néanmoins n’avoir pas changé depuis sa signature. Pour faire confiance à une autorité, ajoutez son certificat à Trousseau d’accès et réglez-le sur « Toujours approuver », mais seulement si vous êtes sûr qu’il est authentique.

VectorPDF ne se connecte pas à Internet pour vérifier si un certificat a été révoqué. Ainsi, personne n’apprend que vous avez ouvert le document.

## Enregistrer un document signé

Lorsque vous enregistrez un document signé, VectorPDF ajoute vos modifications après la partie signée du fichier et laisse cette partie telle qu’elle était, afin que les signatures restent valides dans la mesure où les modifications sont autorisées. Supprimer du contenu par [caviardage](redact.md) réécrit tout le fichier : les signatures du document deviennent alors non valides.

## Types de signatures vérifiés

VectorPDF vérifie les signatures PDF habituelles : signatures PKCS #7 et CAdES (PAdES). Il ne vérifie pas encore les horodatages de document ni les anciennes signatures X.509 RSA. Elles sont indiquées comme **Not checked**.
