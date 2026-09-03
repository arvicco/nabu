# DiCCAS fixtures (CLARIN.SI hdl 11356/2097, CC BY-NC-SA 4.0)

Retrieved 2026-09-04 from the deposit's single `DiCCAS.tei.xml`
(3.6 MB upstream). TRIMMED to the complete teiHeader (all ten msDesc
book identities) + two whole books — book 1 (the Qurʾān excerpts,
94 paragraphs with the embedded-English-gloss quirk throughout) and
book 10 (Rasāʾil al-Jāḥiẓ, the smallest) — books 2–9 removed;
everything kept is byte-verbatim upstream (91 KB).

Quirks the trim documents: the in-paragraph
`<gloss ana="translation" xml:lang="en">` English translations (never
passage text — annotation), catastrophe `<term>` tagging with
`translation` attributes, the div1(book)/div2(sura|section)/…@n
ladder, and in-file `<licence>CC BY-NC-SA</licence>` agreeing with
the deposit page.
