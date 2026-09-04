---
title: Languages
permalink: /languages/
description: >-
  The languages of the Nabu library: the code system, the lect layer
  (historical stages via the nabu-lects registry), and the holdings —
  corpus languages, reference-shelf dictionaries, the gold-lemma index.
---

{% assign census = site.data.census -%}
As of **{{ census.as_of }}** — a live inventory: **{{ census.language_codes }}
language codes** across {{ census.documents_display }} documents and
{{ census.passages_display }} passages, every code appearing in the catalog,
the lemma index, or the reference shelf. The maintained original of this page
is
[docs/languages.md](https://github.com/arvicco/nabu/blob/main/docs/languages.md)
in the repository; this page states the system and the headline holdings.

The library carries this reference as a command: `nabu language CODE`
explains any code the tools surface — the corpus languages below and the
803 Wiktionary etymology codes that appear in `etym` cognate lists — on
one card: name, family, curated historical context, live holdings, the
[research desks]({{ '/axis/' | relative_url }}) that hold the code, and
(where the code is a registered anchor) the historical **stage ladder**
described below. The curated layer behind these cards is file-backed: one
plain Markdown dossier per language code, editable in any editor and
re-derived into the catalog on sync.

## The code system

1. **Codes are BCP-47-shaped**: a primary ISO 639 subtag (`grc`, `lat`,
   `chu`…), optionally followed by a script subtag (`san-Latn` is Sanskrit
   in Latin transliteration) or another qualifier.
2. **The code names the language of the passage text as stored** — not the
   manuscript's script, not the modern nation's. GRETIL stores IAST
   romanization, so its Sanskrit is `san-Latn`; the CCMH codices store a
   7-bit transliteration, but the language is still `chu`.
3. **Historical stages ride the nearest standard code, documented**: Old
   East Slavic, Middle Russian, and Ruthenian all live under `orv`
   (following Universal Dependencies); Early Modern Slovenian and the
   Freising Manuscripts under `sl`. Stored codes never change — but the
   stage itself is now recorded and queryable through the lect layer below.
4. **Reconstruction shelves use Wiktionary's etymology codes verbatim**
   (`sla-pro`, `ine-pro`, `gem-pro`) — non-ISO, kept because they join
   directly against the upstream descendants data. Whether something *is*
   a reconstruction is a registry fact in the lect layer, not a guess from
   the code's spelling.
5. **Search folding is per-language**: the code selects the rule — Greek
   final sigma and diacritics, Latin u/v and i/j, Old English æ/þ/ð,
   Slovene long s, cuneiform determinative stripping, and generic diacritic
   folding elsewhere.

## The lect layer

A standard code often tells less than the truth: `lat` covers Cicero and
twelfth-century charters alike, and one Wiktionary code (`la-vul`) names
both an attested register and a comparative-method reconstruction. Since
August 2026 the library resolves its codes through
**[nabu-lects](https://arvicco.github.io/nabu-lects)** — a sister project
([repository](https://github.com/arvicco/nabu-lects), CC BY 4.0, pre-1.0):
a small curated registry of *lects*, language varieties identified as

```
anchor [ ":" stage ] [ "/" variety ] [ "~" script ] [ "@" ortho ]
```

— `lat:med` is Medieval Latin, `grc:koi` Koine Greek, `zho/lit` Literary
Chinese as the written register it is, `roa:pro` Proto-Romance with
`mode: reconstructed` as a data field, `san~latn` Sanskrit held as a
romanized edition (the `~` axis, August 2026, claims the script of the
text *as held* — never the artifact's original writing system, which
stays a separate catalog fact). The registry's case for existing,
with a review of every prior system, is its own
[prior-art page](https://arvicco.github.io/nabu-lects/prior-art.html);
this page is about what the library does with it.

**Nothing about storage changes.** Stored codes stay exactly as documented
above; the registry is an optional module (`nabu sync nabu-lects`), and
every surface below reads as before when it is absent. Resolution layers
Nabu's own knowledge over the registry's universal defaults, at three
grains: a **per-source override** records that one collection's use of a
code means something specific (the medieval charter corpus resolves its
`lat` to `lat:med`, the DÉRom dictionary's `la-vul` to the reconstructed
`roa:pro`); **ratified rules** stage whole document groups by what the
catalog already knows (a CDLI period label, an AES corpus slice, a DCS
Vedic school tag names the stage of every document carrying it — and a
document whose date interval falls inside exactly one stage's band is
staged by date, containment, never overlap); and **per-document rulings**
refine single texts. Every assignment lives in a journal that survives
rebuilds, states its evidence, and is audited against the documents' own
dates (`nabu lect check-dates`). The journal holds hundreds of thousands
of assignments — most from the period/corpus rules, the rest from date ×
stage-band inference — and an unmapped code still resolves to itself,
honest coarseness.

What it buys, on three surfaces:

**The stage ladder.** `nabu language lat` now ends with live holdings per
historical stage (a representative run — the command prints today's counts):

```
  stages:
    arch  Old Latin (700–75 BCE) — 3023 documents
    cla  Classical Latin (75 BCE – 200 CE) — 88342 documents
    late  Late Latin (200–600 CE) — 22798 documents
    med  Medieval Latin (600–1350 CE) — 377 documents
    ren  Renaissance Latin (1350–1550 CE) — 111 documents
    new  New Latin (≥ 1550 CE) — 0 documents
    unstaged  — 81890 documents
```

Most of the staged Latin is epigraphy dated per inscription: an EDR or
EDH stone whose dating interval sits inside exactly one stage's band
carries that stage; one dated across a boundary stays honestly in
`unstaged`, which is what most of that line is (band-spanning or undated
inscriptions, never a guess). The same machinery gives Sumerian a
five-stage ladder topped by Neo-Sumerian (Ur III) at 111,871 documents,
and Akkadian the field's own six-way Assyrian/Babylonian grid
(`nabu language sux`, `nabu language akk`).

**Stage-aware search.** `nabu search "rex" --lect lat:med` keeps only hits
whose collection resolves to Medieval Latin (prefix semantics: `--lect lat`
matches every Latin stage). The MCP `nabu_search` tool carries the same
`lect` parameter.

**Reconstruction honesty.** The display asterisk and the etymological
machinery now ask the registry, not the code's spelling. DÉRom's
Proto-Romance etymons — filed upstream under `la-vul` — display as what
they are: `etym cheval` walks to `*kaˈβall-u [roa:pro · Proto-Romance]`.
And in the other direction, runic inscriptions filed under the
proto-looking `gmq-pro` tag are *attested* epigraphy and carry no
asterisk. Cognate lists prefer the resolved reading throughout —
`[grc:byz · Byzantine Greek]` where the raw code says `gkm`.

## Corpus languages — the headline view

The {{ census.top_languages.size }} largest passage languages, live (as of
{{ census.as_of }}) — passage counts read from the census SSOT, descriptions
from the hand-curated `site/_data/language_notes.yml`; the full per-code
inventory is maintained in
[docs/languages.md](https://github.com/arvicco/nabu/blob/main/docs/languages.md).

| Code | Language | Passages |
|---|---|---|
{% for l in census.top_languages -%}
| `{{ l.code }}` | {{ site.data.language_notes[l.code] | default: l.code }} | {{ l.millions }}M |
{% endfor %}

Beyond these: the epigraphic mass (Latin and Greek inscriptions, the
Sabellic and Alpine corpora, pre-Greek Sicily), the cuneiform state
languages (Hittite, Elamite, Old Persian, Urartian, Hurrian, Eblaite),
the Semitic shelves (Biblical Hebrew, Aramaic and Targumic, Classical
Syriac, Ugaritic, Geʿez), Coptic and Egyptian across their whole span,
Old Church Slavonic and Old East Slavic, the Celtic and Germanic
medieval corpora (with the German print era whole since the Deutsches
Textarchiv landed), Old Galician-Portuguese lyric, the Southeast
Asian family (Old Khmer, Old Mon, Old Malay, Old Javanese, Pyu, Old
Burmese — most in their only machine-readable form), Classical Newar,
and the honest `und` rows where an upstream record could not
determine a language.

## Reference-shelf languages (dictionaries)

**{{ census.dictionary_entries_display }} dictionary entries** live (as of
{{ census.as_of }}). The classical
reference shelf: Liddell-Scott-Jones (Greek, 116,497 entries), Lewis &amp;
Short (Latin, 51,636), Monier-Williams (Sanskrit, 193,890),
Bosworth-Toller (Old English, 62,815) — citations resolving into the
corpora. Seven reconstruction shelves (Proto-Indo-European through
Proto-Slavic, Proto-Germanic, Proto-Italic and their intermediates) carry
multi-hop etymological chains with per-edge loan flags, joined by
independent witnesses: IE-CoR's expert-curated cognate sets, LIV-LOD,
de Vaan's *Etymological Dictionary of Latin*, the five StarLing bases
(under a written grant), and — since August 2026 — DÉRom's Proto-Romance
etymons, displaying under their honest `roa:pro` lect. The Slovenian
historical shelf (139,405 entries), the Celtic Wiktionary extracts, and
the Tibetan lexica round out the reference floor.

## Gold-lemma languages

{{ census.gold_languages }} languages are searchable by dictionary form
(`search --lemma`) — **{{ census.gold_lemmas_display }} gold rows** (as of
{{ census.as_of }}; Sanskrit and Sumerian lead), fed by the treebanks,
ORACC, the DCS, the Hebrew and Egyptian shelves, and the Germanic reference
corpora. A further {{ census.silver_lemmas_m }} million machine-suggested
rows in {{ census.silver_languages }} languages ride an honestly labelled
silver tier. Everything else is full-text-searchable but not yet
lemma-searchable.

The same languages, grouped by the scholar who reads them rather than by
code, are the {{ census.desks }} [research desks]({{ '/axis/' | relative_url }}).
