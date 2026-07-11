# IMP fixtures — digital library and corpus of historical Slovene (silver)

Real slices of the IMP 1.1 annotated-corpus TEI P5 distribution (CLARIN.SI,
Jožef Stefan Institute; Erjavec). Extracted **2026-07-11** from the single
zip the deposit serves (no raw per-file URLs exist):

    https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1031/IMP-corpus-tei.zip
    (handle: http://hdl.handle.net/11356/1031 — auth-free DSpace bitstream, 150.31 MB)

## License chain (verified 2026-07-11)

- Deposit page verbatim: "Creative Commons - Attribution-ShareAlike 4.0
  International (CC BY-SA 4.0)".
- Every corpus file's own teiHeader `<availability>` verbatim: "This work
  is licensed under the Creative Commons Attribution-ShareAlike 4.0
  International License."

→ CC BY-SA 4.0 → `license_class: attribution` (ShareAlike noted in the
manifest license string). Attribution: IMP digital library and corpus of
historical Slovene, Jožef Stefan Institute / CLARIN.SI.

## Annotation honesty (upstream verbatim)

The deposit page: "Note that the annotations are automatic, so they
contain a fair amount of errors." IMP is the SILVER sibling of goo300k
(whose 294k-word sample is manually validated); per the owner decision
2026-07-11 the imp adapter ingests TEXT ONLY — reg/lemma/msd are not
carried into passage annotations and imp feeds no lemma-index rows.

## Files

| fixture | trimmed to | exercises |
|---|---|---|
| `ZRC_00001-1584-ana.xml` | header + front + `pb.001` + `div.1` with `<head>` + first two `<p>` (+ re-added close tags) | the Early Modern slice: the SAME Dalmatin 1584 *Biblia* goo300k samples, here full-text and auto-annotated — the alt-edition pair, never dedupe (conventions §3); self-contained `-ana` layout (no xi:include); `<div type="part" xml:id="div.1">`; un-id'd `<head>`/`<p>` blocks; `<pb>` milestones; un-prefixed `ana` MSDs; `<fw type="catch">` page furniture (no `<s>` — yields no passage) |
| `WIKI00290-1855-ana.xml` | WHOLE file (33 KB — the corpus's smallest) | plain `xml:lang="sl"` document (post-Bohorič); body of one `<p>` with 10 `<s>`; `<w type="unknown">` tokens; front matter carrying no tokens |

## Format notes (upstream reality, do not "fix")

- TEI P5, same IMP schema family as goo300k, but self-contained one-file
  documents named `<SIGIL>-<year>-ana.xml`: teiHeader + facsimile +
  `<front>` (titlePage, divGen placeholders) + `<body>` with the tokens
  inline. Document identity = `<SIGIL>-<year>`.
- Same `<choice><orig>/<reg>`, bare `<w lemma ana>`, `<c>`, `<pc>` token
  layer as goo300k, EXCEPT `ana` has no `#` prefix (full MSDs, e.g.
  `Pi-fsn`) and annotation is automatic.
- Blocks carrying `<s>` sentences: `<head>` and `<p>` (un-id'd; divs have
  `xml:id="div.N"`). `<fw>` catchwords are untokenized page furniture.
- Corpus: 658 texts / 17,723,566 tokens / >45,000 pages, 1584–1919.
