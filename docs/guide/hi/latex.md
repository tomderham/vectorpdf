<!-- keywords: LaTeX, TeX, SyncTeX, फ़ॉरवर्ड सर्च, इनवर्स सर्च, सोर्स, सोर्स कोड, एडिटर, सोर्स पर जाएँ, LaTeX, TeX, SyncTeX, synctex, forward search, inverse search, backward search, source, editor, Visual Studio Code, VS Code, LaTeX Workshop, latexmk, pdflatex, displayline, Skim, jump to source, show in editor -->
<!-- source: a865c846e0d7 -->

# LaTeX सोर्स और PDF के बीच आना-जाना

अगर आप LaTeX में लिखते हैं, तो VectorPDF आपको PDF की किसी जगह से उस सोर्स लाइन पर ले जा सकता है जिसने उसे बनाया, और किसी सोर्स लाइन से PDF में उस जगह पर जो उसने बनाई। इसके लिए SyncTeX का इस्तेमाल होता है, जिसे TeX `-synctex=1` के साथ बिल्ड करने पर चालू करता है। ज़्यादातर LaTeX एडिटर इसी तरह बिल्ड करते हैं।

SyncTeX उस PDF के साथ काम करता है जिसके बगल में PDF के नाम वाली उसकी SyncTeX फ़ाइल हो: `paper.pdf` और `paper.synctex.gz`। फ़ोल्डर के दूसरे PDF पर इसका कोई असर नहीं होता।

## अपना एडिटर चुनें

1. VectorPDF > Settings चुनें, फिर LaTeX (SyncTeX) के बगल में Set Up… पर क्लिक करें।
2. Source Editor में से अपना एडिटर चुनें: Visual Studio Code, VSCodium, Cursor, Zed, Sublime Text, BBEdit, TextMate, MacVim, Emacs या TeXstudio।
3. अगर आपका एडिटर सूची में नहीं है, तो Other चुनें और वह कमांड डालें जो किसी फ़ाइल को किसी लाइन पर खोलता है। फ़ाइल के लिए `%file` और लाइन के लिए `%line` लिखें, जैसे `myeditor +%line %file`।

एडिटर के नीचे, Settings वह प्रोग्राम दिखाता है जो उसे मिला। अगर लिखा हो कि प्रोग्राम नहीं मिला, तो अपने एडिटर का कमांड-लाइन टूल इंस्टॉल करें, या Other चुनकर प्रोग्राम का पूरा पाथ दें।

## PDF से सोर्स पर जाएँ

PDF में किसी जगह पर ⇧⌘ दबाकर क्लिक करें। आपका एडिटर सोर्स फ़ाइल को उस लाइन पर खोलता है जिसने उसे बनाया।

आप राइट-क्लिक करके **Show in Editor** भी चुन सकते हैं। SyncTeX फ़ाइल वाले PDF के मेनू में यह सबसे ऊपर होता है।

## सोर्स से PDF पर जाएँ

आपका एडिटर VectorPDF के साथ आने वाला `displayline` चलाकर VectorPDF से कोई लाइन दिखाने को कहता है:

```
/Applications/VectorPDF.app/Contents/Helpers/displayline LINE PDFFILE TEXFILE
```

VectorPDF उस PDF को सामने लाता है, अगर वह खुला न हो तो उसे खोलता है, और लाइन को कुछ पल के लिए लाल रंग में हाइलाइट करता है। वह तभी स्क्रॉल करता है जब लाइन पहले से स्क्रीन पर न हो। VectorPDF को अपने एडिटर के पीछे रहने देने के लिए LINE से पहले `-g` जोड़ें।

`displayline` वही आर्ग्युमेंट लेता है जो Skim का लेता है। अगर आपके एडिटर में Skim के लिए कोई सेटिंग है, तो उसकी जगह VectorPDF का `displayline` इस्तेमाल करें।

### Visual Studio Code

LaTeX Workshop एक्सटेंशन के साथ, अपनी सेटिंग्स में ये लाइनें जोड़ें। उन्हें खोलने के लिए Command Palette में Preferences: Open User Settings (JSON) चुनें।

```
"latex-workshop.view.pdf.viewer": "external",
"latex-workshop.view.pdf.external.viewer.command": "open",
"latex-workshop.view.pdf.external.viewer.args": ["-a", "VectorPDF", "%PDF%"],
"latex-workshop.view.pdf.external.synctex.command": "/Applications/VectorPDF.app/Contents/Helpers/displayline",
"latex-workshop.synctex.afterBuild.enabled": true
```

फिर Visual Studio Code में, बिल्ड करने के लिए ⌥⌘B, VectorPDF में PDF खोलने के लिए ⌥⌘V, और जिस लाइन पर आप हैं उसे दिखाने के लिए ⌥⌘J दबाएँ। आख़िरी सेटिंग के साथ, VectorPDF हर बिल्ड के बाद भी वह लाइन दिखाता है।

## लिखते समय

जब आपका एडिटर PDF को फिर से बिल्ड करता है, तो VectorPDF उसे रीलोड करता है और आपकी जगह, ज़ूम, रोटेशन और पेज लेआउट बनाए रखता है। अगर फ़ाइल अभी लिखी जा रही हो, तो VectorPDF उसके पूरा होने तक इंतज़ार करता है।

## अगर यह काम न करे

- **मेनू में Show in Editor नहीं है:** PDF के साथ कोई SyncTeX फ़ाइल नहीं है। SyncTeX चालू करके बिल्ड करें, और SyncTeX फ़ाइल को PDF के बगल में रखें, या उसके बगल में build या out नाम के फ़ोल्डर में।
- **No Source Here:** उस जगह, जैसे मार्जिन या तस्वीर, के लिए कोई सोर्स लाइन नहीं है। टेक्स्ट पर क्लिक करें।
- **VectorPDF में कुछ नहीं होता:** जाँचें कि आपका एडिटर VectorPDF का `displayline` चलाता है, और सोर्स में आपके पिछले बदलाव के बाद से PDF SyncTeX चालू करके बिल्ड हुआ है।
- **इंस्टॉल करने के बाद भी आपके एडिटर को TeX नहीं मिलता:** एडिटर से बाहर निकलें और उसे फिर से खोलें।
