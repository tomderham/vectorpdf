<!-- keywords: digital signature, digital signatures, sign, signing, sign with certificate, p12, pfx, keychain, signed, signer, certificate, certified, certification, valid, invalid, verify, validate, trust, identity, timestamp, PKCS, CAdES, PAdES, tampered, changed -->

# Sign and check digital signatures

A digital signature shows who signed a document and that it hasn't changed since. You can [sign a PDF](#sign) with a certificate of your own. When you open a signed PDF, VectorPDF checks its signatures and shows what it found in a bar above the page:

- **The signature is valid:** the document is unchanged since it was signed, and the signer's certificate was issued by an authority your Mac trusts.
- **The signer's identity isn't verified on this Mac:** the document is unchanged, but nothing vouches for who signed it. See [Why a signer's identity may not be verified](#signer-identity).
- **Invalid:** the document was changed after it was signed, or the signature doesn't match it.

Click **Signature Details** to see each signature in the Document tab of the sidebar. To hide the bar, click its close button.

> **Note:** A [stamp](stamps.md) is a picture of a signature, not a digital signature.

## Sign with a certificate {#sign}

To sign, you need a certificate for signing with its private key. Your organization or a certificate authority can give you one, usually as a .p12 or .pfx file with a password. Certificates in your keychain can be used directly.

1. Choose Edit > Sign with Certificate, then drag out a box on the page where the signature should go, or click for one of the usual size. Press Esc to stop. If the document has an empty signature field, you can click the field instead and choose Sign with Certificate.
2. Choose your certificate. A preview shows how the signature will look. To use a file, click **Choose Certificate File**, then type its password. The file is read for this signature only and isn't added to your keychain.
3. If you like, type a reason (such as "I approve this document") and where you're signing. If you've made a [stamp](stamps.md), you can show your handwritten signature in the field. Otherwise your name is shown.
4. If you like, choose under After Signing:
   - **Certify**, if no one has signed the document yet: say which changes keep it valid from now on: form filling, signing and comments; form filling and signing; or none. A certified document shows as certified to everyone who checks it, and later changes it doesn't allow make your signature invalid.
   - **Lock form fields**, for a form: all its fields, or those you choose, become read-only, so they keep the values you signed.
5. Click **Sign**.

Signing saves the document, so if it has unsaved changes, VectorPDF asks to save them first. They become part of what you sign. macOS may ask you to allow VectorPDF to use your certificate's key.

Unless you lock them or certify the document for less, the signature leaves the document's other form fields as they were, so others can still fill them in, sign too, or add comments without making your signature invalid. Each later signature is added after the earlier ones in the same way.

The signature is a PKCS #7 signature with SHA-256, carrying your certificate and those of the authorities that issued it. It records the time on your Mac. It doesn't have a timestamp from a timestamp authority yet.

## What VectorPDF checks

For each signature, the list in the Document tab shows:

- Whether the parts of the file it signed are exactly as they were signed.
- Whether the file was saved again after signing, and whether those changes are ones the signature allows. Filling in form fields, adding signatures and adding or changing comments are usually allowed. A certifying signature can allow fewer changes. If comments were added after signing, the list says so: a comment can cover what was signed.
- Who signed it, by the name in their certificate, and who issued the certificate. The name the signing software wrote into the document is shown too when it's different.
- When it was signed. A time from a timestamp authority is vouched for. A time from the signer's own computer isn't.
- The reason and location the signer gave, if any.

Click a signature to go to it on the page. To see its certificates, click **Show Certificate**, or right-click it and choose Show Certificate.

VectorPDF checks the file as it was last saved, so unsaved changes aren't included. It checks again each time you save.

## Why a signer's identity may not be verified {#signer-identity}

Anyone can make a certificate with any name in it. A signature only proves who signed if the certificate was issued by an authority that checked their identity, and your Mac trusts that authority. VectorPDF uses the certificates your Mac trusts, in Keychain Access.

Many signed PDFs use certificates from authorities that Adobe Acrobat trusts but macOS doesn't, so VectorPDF reports their signers as not verified. The document can still be unchanged since it was signed. To trust an authority, add its certificate to Keychain Access and set it to Always Trust, but only if you're sure it's the real one.

VectorPDF doesn't go online to check whether a certificate was revoked. That way no one is told that you opened the document.

## Save a signed document

When you save a signed document, VectorPDF adds your changes after the signed part of the file and leaves that part as it was, so the signatures stay valid where the changes are allowed. Removing content with [redaction](redact.md) rewrites the whole file, so the document's signatures become invalid.

## Kinds of signature checked

VectorPDF checks the usual PDF signatures: PKCS #7 and CAdES (PAdES) signatures. It doesn't check document timestamps or older X.509 RSA signatures yet. They're listed as **Not checked**.
