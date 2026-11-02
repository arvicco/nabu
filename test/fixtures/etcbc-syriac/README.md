# etcbc-syriac fixture — the ETCBC Syriac Corpus (Text-Fabric tf/0.92)

Gap-anchored trimmed slices of the pinned `tf/0.92` Text-Fabric dataset of
[github.com/ETCBC/syriac](https://github.com/ETCBC/syriac) (ETCBC + the
CACCHT project; Zenodo 10.5281/zenodo.23525343, v0.92, 2026-10-21).

- **Retrieved:** 2026-11-02, from commit
  `0b6ded2b369c7d81589a98c92325290e24b20af6` (master = tag `v0.92`), via raw
  GETs of `https://raw.githubusercontent.com/ETCBC/syriac/master/tf/0.92/<name>.tf`.
- **Layout:** mirrors the sparse workdir the adapter fetches (`tf/0.92/*.tf`);
  README.md and LICENSE (also in the cone) are quoted below, not checked in.
- **Trim recipe:** headers byte-verbatim; data lines byte-verbatim for every
  node whose slots lie inside the kept slot ranges below, written
  gap-anchored; empty values drop. The Deuteronomy book node keeps its
  `oslots` line CLIPPED to chapter 14 — the one non-verbatim edit. `otype.tf`
  and `otext.tf` ride WHOLE — the census of record. All 35 feature files are
  included (every one is read).

## Upstream delivery grains

Upstream serves only Text-Fabric, in every released version side by side
(`tf/0.1` … `tf/0.92`); the adapter pins `tf/0.92`, the older version
directories are outside the sparse cone. Node types: word (slot), verse,
chapter, book. The adapter takes **book** as the document and **verse** as
the passage; nothing is rejected inside the pinned version.

## Upstream census (at the pin, from otype.tf — checked in WHOLE)

407,319 words / 31 books / 807 chapters / 18,132 verses. Full-data parse
(2026-11-02): 31 documents / 18,132 passages / 407,319 tokens, every
(chapter, verse) unique per book, zero non-NFC word forms. The 31 book
nodes reconcile with the README's text list: 18 Peshitta books, the
EpBar and OrMan A/B pairs, and nine further texts (PsH, PsS, ApBar, ApDn,
PsE, PsM, BLC, Eprx, ESNJ). Nine verse nodes are discontiguous (README:
"a single verse node consisting of both parts, with a gap in between" —
Deut 14:16–17, Josh 21:34, Sir 5:6, 9:9, 27:14, 28:24–25, 33:20). Feature
headers carry no license line; the grant is the README's.

## License (verbatim, retrieved 2026-11-02)

README: "This work is licensed under a Attribution-NonCommercial 4.0
International (CC BY-NC 4.0)"; LICENSE: the CC BY-NC 4.0 legal code. The
Zenodo record's license field reads `cc-by-4.0`; it conflicts with the
repository and is not followed (the ETCBC directorate, by email 2026-10-15:
all ETCBC data is CC BY-NC) → source class `nc`.

## The slices (4,107 words / 186 verses)

| book | node | kept | verses | why |
|---|---|---|---|---|
| Deuteronomy | 407324 | chapter 14 (slots 114170–114709), clipped | 29 | the interleaved discontiguous 14:16–17 |
| Jonah | 407334 | whole (1,132 words) | 48 | a Peshitta book shared with `peshitta` (same text) |
| OrManA | 407340 | whole (430 words) | 16 | the A version; superscription as verse 0 |
| OrManB | 407341 | whole (485 words) | 16 | the B version — a different text |
| PsE | 407349 | whole (1,520 words) | 77 | a non-biblical text (the Apocalypse of Pseudo-Ezra) |
