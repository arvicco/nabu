# CBETA fixtures (P33-2)

Real files from github.com/cbeta-org/xml-p5, retrieved **2026-07-20** at
master commit **2b8ab8d5e4fe957a9b94f2cde01cb0d2e2dcd2b9** ("CBETA
2026.R1", 2026-05-10) via
`https://raw.githubusercontent.com/cbeta-org/xml-p5/master/<path>`.
Layout mirrors upstream: `<canon>/<canon><vol>/<stem>.xml`.

| file | upstream path | trim | why this file |
|---|---|---|---|
| `T/T85/T85n2884.xml` | `T/T85/T85n2884.xml` | none (whole, 4.2 KB) | complete short Taishō text: gaiji `<g ref="#CB00762">` with charDecl, witness list 【CB】【大】, back-matter taisho-notes, blank layout lines |
| `T/T01/T01n0001-xu.xml` | `T/T01/T01n0001.xml` | teiHeader + body through the first `<lg>` (`lgT01p0001c0301`, lb 0001a01–0001c12) + back trimmed to 6 `<app>` + 1 `<cb:tt>`; 2.9 MB → 42 KB (Nokogiri subtree removal, whitespace-only gaps remain where siblings were dropped) | the Dīrghāgama 序: stand-off apparatus (`<app from=… wit="#wit.orig">`), anchors in the byline, verse `<lg>/<l>` with `<caesura/>`, `<cb:tt>` foot glosses, juan milestone |
| `X/X01/X01n0001.xml` | `X/X01/X01n0001.xml` | none (whole, 5.8 KB) | complete short Xuzangjing text: interleaved witness lb stream `ed="R150"`, inline notes (`<note place="inline">一行</note>`), verse lg |
| `X/X55/X55n0899.xml` | `X/X55/X55n0899.xml` | none (whole, 4.8 KB) | attribute order `<lb ed=… n=…/>` (the other files order n first — both real), `cb:mulu` TOC entry duplicating `<head>`, `ed="R098"` witness stream |
| `canons.json` | `canons.json` | none (whole, 6 KB) | upstream's own canon registry: 29 canons declared (26 ship as dirs; Q/R/Z are apparatus-only witnesses) |

The trimmed stem `T01n0001-xu` keeps fixture urns disjoint from the real
corpus urns minted at the owner-fired first sync (the SARIT rule); whole
files keep their real stems (byte-identical to upstream, so identical
urns carry identical content).

## License (the canon-level gate, quoted verbatim)

cbeta.org/copyright (版權宣告, read 2026-07-20), Category A — which names
《大正新脩大藏經》（大藏出版株式會社 ©）第一冊至第八十五冊 and
《卍新纂續藏經》（株式會社國書刊行會 ©）第一冊至第九十冊:

> 除下方「二、底本來源與授權分類」中特別註明不適用之文獻外，本資料庫未特別
> 說明處皆採用「Creative Commons 姓名標示-非商業性-相同方式分享 4.0 國際
> 授權條款」釋出。

(CC BY-NC-SA 4.0 → license_class `nc`.) Every fixture header carries the
in-file grant, byte-verbatim:

> Available for non-commercial use when distributed with this header intact.

Category B (類別 B：不屬於創用 CC 條款授權之文獻) — never ingested, no
fixture will ever exist for these: 《印順法師佛學著作集》（印順文教基金會 ©）,
《呂澂佛學著作集》（呂應中等 ©）, 《太虛大師全書》（印順文教基金會 ©）,
《演培法師全集》（演培法師全集出版委員會 ©）.
