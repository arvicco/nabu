# The MCP server — talking to the corpus

`bin/nabu mcp` runs a **Model Context Protocol** server: a read-only,
conversational surface over your local nabu corpus, spoken to by an AI client
(Claude Code, Claude Desktop) over stdio. It exposes twelve tools — search,
read by urn, concordance, cross-source alignment, dictionary lookup, the
reconstruction walk, intertext (quotation/echo finding), cognates-in-parallel,
the mined links graph, the place desk, the cuneiform sign desk, and coverage —
so a model can look things up in your texts, quote them, and cite them,
without any ability to change the collection.

This is also a **rehearsal for `nabu.ac`** (concept §"eventual read-only query
endpoint" / architecture §9): the same tool contract that will one day sit
behind a public read-only endpoint runs here first, locally, against the real
corpus. What you register today is what that surface promises.

---

## 1. What it is (and is not)

- **Read-only, positively.** The catalog and index are opened
  `SQLITE_OPEN_READONLY` — the SQLite engine itself refuses writes, not merely
  our code declining to. There are no write tools. A conversation cannot sync,
  rebuild, withdraw, or edit anything.
- **stdio, JSON-RPC 2.0**, MCP spec revision **2025-11-25** (newline-delimited
  JSON, one object per line — see architecture §9 for the protocol details).
- **STDOUT is the protocol channel.** The command prints *nothing* else to
  stdout. Diagnostics go to stderr, or to a file with `--log FILE`. This is why
  you never run `nabu mcp` to read output yourself — a client drives it.
- **Lazy and resilient.** The openers are resolved per tool call, so a corpus
  that is absent at launch and appears later, or is rebuilt mid-session
  (`nabu rebuild` deletes and recreates the catalog), is picked up without
  restarting the server. Missing/rebuilding/busy corpus states come back as
  ordinary, informative tool responses, never crashes.

---

## 2. The twelve tools

Every passage in every response carries **urn**, **language**, and
**license_class** (search, concord, align, and parallels rows also carry the
**source** slug). Preserve those fields when you quote — see §6.

### `nabu_search`

Full-text or exact-lemma search over the whole corpus. Give **exactly one** of:

- `query` — FTS5 full text. Words are AND by default; `"quoted phrase"` for
  adjacency; `prefix*`. Diacritics optional: `μηνιν` finds `μῆνιν`.
- `lemma` — exact dictionary form over the gold treebanks. `λέγω` finds every
  inflection (`εἶπας`, `εἰπεῖν`, …), including suppletive stems no text query
  reaches. With `lemma`, an optional `morph` — comma-joined `key=value` facets
  in Universal Dependencies vocabulary (`case=dat,number=pl`; keys case, number,
  gender, person, tense, mood, voice, degree; values `dat`, `pl`/`sg`, `masc`,
  `aor`, `opt`, `sub`…) — keeps only attestations with that morphology, each hit
  returning the decoded `morph` evidence. UD treebanks match on their `feats`;
  PROIEL/TOROT are decoded from their positional tag into the same names; ORACC
  has no inflectional morphology, so those facets never match it (honest
  absence). `morph` requires `lemma` (bare morphology search is out of scope).

An optional `near` turns either mode into **proximity search**: keep only hits
where `near`'s term occurs within `window` words (default 10, `0` = adjacent) of
the `query`/`lemma` in the **same passage**. It is FTS5 NEAR over the folded
search forms — order-independent (`A … B` and `B … A` both count), the window
counting folded tokens (so a cuneiform sign-joined word, folded to several
tokens, reads tighter). With a `lemma` anchor the lemma first expands to its
attested surface forms, so `lemma: "λέγω", near: "κύριος"` finds `τάδε λέγει
κύριος`. Both matched terms are bracketed in the returned snippet.
Cross-passage adjacency is out (the passage is the unit); `near` does not
compose with `morph`.

Optional `lang` (ISO-639-3), `license` (exact class), `limit` (default 10, max
50). Optional `meter` / `meter_pattern` (P45-5, text search only — refused
with `lemma`/`near`): restrict hits to metrically **scanned** passages — the
pedecerto (Latin) / hypotactic (Greek) meter enrichment layer — matching the
meter code/name (`H`, `P`, `dactylic hexameter`) and/or the exact foot
pattern (`DSDS`), case-insensitively. The response note names the source
layer when the facet is active, and an empty layer or unknown code explains
itself (known meters listed) rather than returning a silent zero.

Optional `words` (P54-4, text search only — refused with `lemma`/`near`): the
Tibetan word-grain filter. Tibetan is indexed at **syllable** grain (tsheg-
delimited), so a multi-syllable query also lands on an accidental syllable run
crossing a word boundary; `words: true` keeps only hits whose matched span
aligns with word boundaries per the nabu-data `xct/segmentation` dataset (any
aligned occurrence in the passage counts; filtered-out hits are simply
absent). When the filter ran, the response carries a present-only
`word_grain: true`; a non-Tibetan query or an unsynced nabu-data module
degrades to plain search with a present-only `word_grain_note` mirroring the
CLI note — never an error.

Hits are
relevance-ranked and bounded, with an honest "showing k of N"
note; a no-match response carries a one-line coverage hint so an empty result
is interpretable. Each hit returns urn, language, license_class, source, the
document title, and a bounded text/snippet (lemma hits also return the matched
surface forms, and a morph-filtered hit its decoded `morph` evidence).

### `nabu_show`

Read the corpus by urn — the pristine edition text behind a search hit:

- a single **passage** urn → the text plus its full provenance trail;
- a whole **document** urn → the header and its passages in citation order,
  bounded by `max_passages` (default 50, cap 200) with a truncation note;
- an inclusive **range** (`<document-urn>:1.1-1.10`) → a sequence-ordered slice;
- a shortened **citation prefix** between document and passage grain
  (`…:avest020:Y.19.1` over passages `Y.19.1.a/b`, P44) → everything below it,
  boundary-exact (`Y.19.1` never swallows `Y.19.10`), served through the range
  shape — term-less browsing without a search hit first;
- `parallel: true` (with `parallel_lang`, default `eng`) → the same work's
  translation, aligned line by line / block by block (CTS editions and, since
  P13-4, ORACC tablets ↔ their `-en` sibling documents; since P48-r2 also
  cross-source over a `kind=translation` link edge, paired at Degé
  folio/page grain — the Kangyur↔84000 crosswalk).

Withdrawn and retired-upstream items appear, flagged. The owner's notes on the
urn ride in `notes` by default (P24-1). Two additive keys appear only when the
fact exists (P44-3): `meter` — a scanned passage's metrical code, foot pattern,
and producer (the Pedecerto/Hypotactic enrichments, P44-6/7) — and `findspot` —
an epigraphic document's parse-captured Pleiades id resolved through the local
gazetteer dump (id, title, place types; absent dump, absent id, or unknown id
all leave the payload unchanged, exactly the CLI's degradation).

`segmented: true` (P54-2) adds the Tibetan word-segmentation lane — the
consumed-back nabu-data `xct/segmentation` dataset read through
`Nabu::TibetanWords`. On a Tibetan-language row (xct/bod/otb) every passage
record gains a present-only `segmented` key: the passage text with a space
inserted at each word boundary, tokens verbatim (trailing tsheg kept) — the
exact rendering `nabu show --segmented` prints, one serializer
(`Query::Show#segmented_text`). When the flag is not applicable — an
off-language row, or a box that has not run `nabu sync nabu-data` — a
present-only top-level `segmentation_note` says why, mirroring the CLI's one
honest note line. Flag off: byte-identical payloads.

### `nabu_concord`

KWIC concordance over the same search machinery (P8-3): one row per hit as
left context / matched keyword / right context, located in the pristine
edition text, in corpus order. Give exactly one of `query`/`lemma`; optional
`lang`, `license`, `limit` (default 10, max 50), `width` (context characters
per side, default 40, max 120).

### `nabu_align`

Cross-source alignment (P11-3, architecture §10): one citation of a registered
work rendered across every witness `config/alignments.yml` names — the
flagship is the five-way New Testament (grc/lat/got/xcl/chu, all PROIEL-family
treebanks). `ref` is a citation in the work's scheme (`"MARK 2.3"`;
case/spacing/`chapter:verse` colons normalize) or a passage urn to pivot from
a search/show hit; `work` picks the registry work when several exist.
Witnesses come in registry order, each with status `ok` (sentences follow,
each listing every ref it covers — sentence≠verse), `no_match` (synced, verse
not attested), `not_synced` (registered, no data yet), or `withheld`
(license-excluded). Every sentence row carries urn, language, license_class,
and source — the five NT witnesses are all `nc`, so the labels matter when
quoting.

`ref` also accepts a whole **chapter** (`"JON 1"`) or an inclusive same-book
**verse range** (`"JON 1.1-1.16"`) — the range separator is the last hyphen,
its tail a bare end suffix against the start's book (the `nabu show` range
grammar, in citation space). The reply is then a `refs` array (`type:
"alignment_range"`), one entry per ref in document order, each carrying the
same witness columns; a witness that attests some refs but not others is
honest per ref. A witness absent from **every** rendered ref is summarized once
in a range-level `absent_witnesses` array (each `{label, reason}`, reason
`not_attested` for a synced witness whose verses are all absent or
`not_synced` for a registered-but-unsynced one) and **dropped** from the
per-ref `witnesses` arrays — so a chapter with a not-yet-synced witness stays
readable instead of repeating the same dash on every ref (P11-9). It is capped
at 200 rendered refs (`total_refs`/`shown_refs`/`truncated`, with a note —
narrow the range), mirroring `nabu_define`'s body cap. The CLI `nabu align
"JON 1"` renders the same, compactly (the witness titles/licenses shown once as
a legend, the all-absent witnesses summarized once, then one line per present
witness per ref).

`collate: true` (P15-4, design §2) returns a witness **diff** instead of a
listing (`type: "collation"`). Witnesses are grouped into `cells` by
`(language, script)` — the collatable unit, because language alone lumps the
Cyrillic Marianus with the Helsinki-ASCII CCMH codices (same `chu`, two
transcription systems the conventions-§9 fold cannot bridge) while script alone
lumps Latin, Gothic and English. A cell of ≥2 witnesses diffs RAW tokens
(punctuation-only tokens dropped, every diacritic marker kept — folding would
destroy the very distinctions a critic wants) against a base (the first witness
in registry order, or `base: "LABEL"`), emitting per witness only its `edits`
(`op` ∈ `sub`/`del`/`ins`, with the `base` and `witness` token runs;
agreements elided, `agrees: true` when identical) plus its full `tokens`. A
witness alone in its cell becomes an `aside`, rendered undiffed with a `reason`:
`cross_script` (a same-language witness exists in another script — the honest
"not collated" case) or `sole` (the only witness of its language here). The
license gate applies as everywhere: an excluded witness is `withheld` from the
diff bodily (listed in `missing`, never leaking through an `edits` line) unless
`include_restricted`. Ranges collate per ref (`refs` array, same 200-ref cap).

### `nabu_define`

The dictionary shelf (P11-4, architecture §11): look a lemma up in the
classical lexica the corpus holds — LSJ for Greek, Lewis & Short for Latin
(CC BY-SA, Perseus). Diacritics optional (μηνις finds μῆνις); `lang`
(grc|lat) picks a shelf. Each entry carries headword, dictionary, license
fields, a short gloss, the entry body as structured plain text (bounded at
6 000 chars with an honest note — the CLI `nabu define` prints entries
whole), and the entry's citations with `resolved_urn` set where the cited
work is in-catalog (`Il. 1.1` → the actual Iliad line, one `nabu_show`
away); unresolved citations keep their display text and a null urn. Lemma
hits from `nabu_search` carry these glosses too. A leading asterisk
(`*bogъ`; quote it in a shell — zsh globs a bare `*`) scopes to the
reconstruction shelves (P14-1), whose entries also carry their descendant
`reflexes` (bounded, attested-first, honest totals — this conversational
surface stays capped by design; the CLI `nabu define --long` is the
unbounded, grouped-by-language expansion, P14-11); proto headwords fold
to ASCII (§9: ʰ→h, ʷ→w), so `*gwhew-` reaches `*gʷʰew-`.

### `nabu_etym`

The reconstruction walk (P14-1, architecture §12): give an attested lemma
(богъ, guþ) and get every reconstruction whose Wiktionary descendants name
it — Proto-Slavic / PIE / Proto-Germanic (kaikki.org extracts, CC-BY-SA +
GFDL) — each with the reflex that matched (`matched_via`), its cognates
across languages with **corpus attestation counts** (`attested_count` =
gold-lemma passages in this catalog; null is an honest absence, not a
zero), and one hop of proto-to-proto ancestors with *their* cognates
(богъ → \*bogъ → \*bʰeh₂g- → ἔφᾰγον in one call). Romanization bridges
scripts: guþ reaches \*gudą through Gothic 𐌲𐌿𐌸. `lang` scopes the attested
match. An unstarred lemma that names no descendant **falls back** to a
reconstruction-headword lookup, so the proto form itself resolves —
superscripted (`bʰewgʰ`) or pure ASCII (`bhewgh`, the §9 fold ʰ→h/ʷ→w),
root hyphen optional; a leading asterisk (quote it in a shell — zsh globs a
bare `*`) forces the direct lookup. A lemma with **no crosswalk path at
all** falls back once more (P24-2) — to the same lookup `nabu_define` runs:
a prose etymological article (Vasmer's Russian dictionary carries no reflex
edges) still answers, returned as `dictionary_entries` (the `nabu_define`
payload shape) plus an explanatory note; a genuine total miss enumerates
the crosswalk's live shelves, derived from the catalog, never a hardcoded
roll call. Cognate lists are bounded (attested
first, 20 shown) with honest totals — this conversational surface stays
capped by design; the CLI `nabu etym --long` (P14-11) prints everything,
grouped by language.

### `nabu_parallels`

Passage-anchored intertext (P15-1, architecture §13): give one passage `urn`
and get the passages that **quote or echo** it — reception discovery, the
inverse of `nabu_align` (which renders one verse across its registered
translation witnesses; this one *discovers* quotation across the whole corpus
from surface text alone). Query-time over the same FTS index as `nabu_search`,
no precomputation: the anchor is folded, cut into overlapping 4-word grams,
each probed as an exact phrase; passages sharing grams are ranked by
shared-gram count **weighted by rarity** (a rare shared phrase — a real
quotation — outweighs a pile of common function-word grams). The elision
apostrophe is folded across editions (SBLGNT `ἐπʼ` ≡ Swete `ἐπ’`), which is what
lets Matthew 4:4 find LXX Deuteronomy 8:3. Each `hits` entry is **one document**
(duplicate witnesses and multi-edition works otherwise flood the ranks; `loci`
counts how many of its passages matched) with its best passage urn, `score`,
`shared_grams`, and the shared **phrase** spans (the grams merged back to
contiguous text; diacritic-folded — *what* matched, `nabu_show` gives pristine
text). Only the anchor's own document is excluded — translations self-exclude
(no shared folded tokens). When the anchor carries gold treebank lemmas,
`lemma_echoes` adds passages sharing ≥2 of its **rare** lemmas
(re-inflected/reordered allusion verbatim grams miss). Bounded (default 10, max
50) with an honest note; every hit carries urn, language, license_class, and
source. `lang`/`license` scope the candidates; the default restricted-exclusion
stance applies (§below).

### `nabu_cognates`

Cognates in parallel (P15-3, design §6): verses of a registered alignment work
where witnesses in **two or more languages** use reflexes of the **same
reconstruction root** — the alignment hub crossed with the Wiktionary
reconstruction crosswalk, a join no other tool holds both halves of. Gothic
*salt* ~ OCS *соль* meet at PIE `*sḗh₂l` in the salt saying (Luke 14:34);
*hlaifs* ~ *хлѣбъ* at `*hlaibaz` in "he who eats my bread". `target` is a work
id (`nt` — batches the whole work; the Gothic × OCS NT runs in under a second)
or a citation/chapter/book ref; `langs` restricts to ≥2 named languages
(`["got","chu"]`). Each group carries the verse ref, the **root** (headword,
**shelf**, gloss, license), and per-language witness words (lemma, attested
surface forms, attesting documents with licenses). **Read the shelf**: a meet
at `gem-pro` involving a Slavic witness is very possibly a **borrowing**
(Wiktionary descendant trees include loans), not common descent — `ine-pro`
meets are the inheritance signal. Corpus-common words (df ≥ max(50, 10% of the
language's gold passages)) are suppressed with an honest count; `all: true`
lifts. Recall is bounded by Wiktionary descendants coverage and by gold
lemmatization (~10% of the corpus): **no hit is absence of evidence**. Bounded
(default 10 groups, max 50); the restricted-exclusion stance applies to
witness documents (a private witness's words never join).

### `nabu_links`

The links journal reader (P16-1/P16-2, design §7, architecture §15):
batch-mined cross-reference edges touching a urn, grouped by kind
(`parallel`, `formula`, `cognate`, and `reuse` — the KITAB import's
upstream-computed pairwise Arabic text-reuse alignments, whose `detail`
carries the milestone/offset spans verbatim; the kind vocabulary is open,
so any future producer's kind flows through unchanged), **both directions**
(`out` = this urn's
batch anchor discovered the counterpart, `in` = the reverse), each
counterpart resolved to document title/language/license against the current
catalog (`null` when a rebuild dropped it — edges are urn-keyed and outlive
rebuilds). Each edge carries a `detail` field with its kind's evidence
(`null` for parallels; the folded gram for a formula edge — the counterpart
of an `in` edge is the refrain's hub locus; `ref · root [shelf]` for a
cognate edge, the shelf being the borrowing signal). `runs` carries the
provenance of every edge: producer, scope, params, code_version, date. This
tool **reads only what a batch run already persisted** — an empty result
means no batch has covered the urn, *not* that no parallel exists
(`nabu_parallels` discovers on the fly); it never mines (batch runs are
owner-fired: `nabu parallels|formulas --batch SCOPE`, `nabu cognates --batch
WORK`). Bounded per kind (default 20, max 100); the restricted-exclusion
stance applies to counterparts.

### `nabu_place`

The place desk (P44-2's `nabu place`, exposed P44-3; **v2 P66-2**): one
ancient place — resolved through the **local** Pleiades gazetteer dump or
the derived multi-gazetteer place index — plus the library's holdings at
that place, per source. `query` is a Pleiades numeric id, a
`pleiades.stoa.org/places` URL, a **namespaced ref** (`tm:2788` ·
`cigs:GIR` · `pleiades:462281` — the tm/cigs gazetteers resolve through
their own derived index slices), or an **exact** case-insensitive place
title ("Segesta" works, "Seges" does not — no fuzzy matching anywhere in
the pipeline, by design; homonym titles return one card per bearer). Each
card carries the gazetteer facts (title, place types, attested time-period
vocabulary, representative point — display only, no maps, no coordinate
math), a `ref` (the namespaced identity), `holdings`: per-source counts of
live documents whose parsers captured that upstream-asserted id from their
headers (isicily, edh, iip, itant) — and `axis_holdings` (P66-2): the
SEPARATE `place_ref` lane — adapter-asserted refs plus the nabu-places
registry's applied decisions, both spellings read through the one
PlaceRefs reader, one count per document, labeled apart because the
provenance differs. Counts are **aggregate only** — reading the texts is
`nabu_search`/`nabu_show`'s job. An honest labelled `unlinked` tail counts
id-less documents whose captured findspot **text** mentions the name
(exact substring), never merged into the id-matched holdings. Degradation is the CLI's exactly: with the dump absent on
this box, a numeric id still counts holdings (fact-less card, honest note),
and a name lookup returns a graceful state note with the sync hint — never an
error. Since P45-6 lookups read the derived catalog place index (instant;
derived at every pleiades sync/rebuild); the in-memory dump load (~3 s /
~3.9 GB peak on the real 42k-place dump, paid per call and released — the
P44-2 v1 cost) survives only as the fallback while the index is not yet
derived.

### `nabu_char`

The sign/character desk card (P65's `nabu char`, exposed P68-3): ONE glyph
or sign identity in, the full held identity out — the payloads ARE the
frozen `nabu char --json` contracts (one serializer each,
`Query::SignCard.json_payload` / `Query::HieroCard.json_payload`). Dispatch
by input, the CLI's lanes verbatim: a **cuneiform** glyph (𒊬, compound
renderings included) or sign name / spelled value / list number (SAR ·
szesz · idx — a trailing x reads as ₓ · MZL535 · bare 852 matched across
every held list) serves the Oracc Sign List card — name, @aka, print-list
concordances grouped by list, values by %lang with deprecation, CDLI
meaning glosses, Wiktionary senses (the wiktionary-sux shelf, P68),
variant forms, form-of parent, fulltext corpus counts; an ambiguous value
lists **all** candidate signs (each naming the matching list token via the
present-only `via` key), never one silently. An **Egyptian hieroglyph**
(𓅃) or Gardiner-style code (G5, N35) serves the Unikemet card — catalog
code, description, function, phonetic value, JSesh/Hieroglyphica/IFAO
concordances, aes `hiero_inventar` attestation. A Han character answers a
state note (no machine contract yet — `nabu_define` serves Han dictionary
entries meanwhile); a missing module answers the sync-hint note (the
lane-off rule). Absent data is null/[], never a placeholder.

### `nabu_signs`

The cuneiform sign desk (P53-2's `nabu signs`, exposed the same phase): ATF
transliteration resolved token by token through the **local** Oracc Sign List
(the osl feature module, `nabu sync osl`) into sign identities — value → sign
name → Unicode codepoint(s). Give exactly one of `urn` (a passage or document
urn out of the ATF corpora — cdli/oracc/ebl/etcsl — language read from the
row, the catalog opened read-only) or `text` (raw ATF; `lang` optional). The
C-ATF ASCII folds apply (sz→š, s,→ṣ, t,→ṭ, '→ʾ, u2→u₂); `dialect: "etcsl"`
adds the ETCSL romanization (c→š, j→ŋ), auto-selected for etcsl urns. Every
token carries one honest status — `deterministic` · `qualified` (a
valueₓ(SIGN) form, the explicit sign resolved) · `ambiguous` (**all**
candidate signs listed, never one silently) · `no-codepoint` (sign resolved,
honestly unencoded upstream) · `broken` (x, [...]) · `unknown` (not in the
OSL, said plainly) — and determinatives are unbraced and flagged. The payload
IS the frozen `nabu signs --json` contract (one serializer, `Query::Signs`):
per-token records `input_value` / `status` / `sign_name` / `codepoints[]` /
`candidates[]` / `language_qualifier`, plus present-only `determinative` and
`form_of` (a value resolving through another sign's variant form names its
parent — a sign and its same-named form never render as indistinguishable
twins), script-consumed downstream (the Edubba
reading panels — the boundary holds: **the sign list adds identity, not
curriculum**). Bounded (default 40 lines, max 200, honest truncation note);
with the sign list not on this box the tool answers a graceful state note
with the sync hint (every other tool byte-identical — the lane-off rule);
urn mode passes the restricted-exclusion gate.

### `nabu_status`

Coverage of the corpus, and the tool to call to interpret an empty search
*before* concluding a text is unattested: per-source document/passage counts and
last-sync recency, passage counts by language and by license class, index
state, and what is excluded by default. Each source also carries its
`description` when the owner's local-source dossier has one (P24-0,
architecture §16) — a 1–3 sentence account of what the shelf holds, served
by default because the library's own metadata is useful context for
deciding where to search. Takes no arguments.

The `sources` array defaults to this box's **enabled set** — the sources
active in `config/profile.yml` (the local enablement config, P44-r3b) — plus
the owner's own shelves, matching what `nabu list` / `nabu status` show on the
CLI. Grant-gated private-research sources (`availability: blocked`) that were
never enabled do not appear. This is a visibility default, not a data gate:
`nabu_search` / `nabu_show` stay library-wide.

### The restricted-exclusion stance

License classes `research_private` and `restricted` are **excluded by default**
from every tool — they never appear in search results, `nabu_show` withholds
them, and `nabu_status` counts them only under `excluded_by_default`. The
Freising Manuscripts shelf carries `research_private` today (BY-ND posture),
and the coming local-library shelf will default to it — so the exclusion is
live, not theoretical: a conversational surface never leaks restricted
material casually. A caller who understands and will honor the restriction can opt in
per call with `include_restricted: true`.

---

## 3. Registration — Claude Code

### Project scope (this repo — nothing to do)

This repo ships **`.mcp.json`** in its root:

```json
{
  "mcpServers": {
    "nabu": {
      "command": "bundle",
      "args": ["exec", "bin/nabu", "mcp"]
    }
  }
}
```

Open Claude Code with this repo as the working directory and the `nabu` server
is offered automatically (Claude Code asks once whether to trust project-scoped
servers). The command is run from the repo root, so `bundle` finds the Gemfile
and `bin/nabu` resolves. Nothing else is required.

### User scope (nabu tools in every project)

To have the tools everywhere — not just when your cwd is this repo — add a
user-scoped server. The catch: `bundle` needs *this repo's* Gemfile, but a
user-scoped server is spawned without the repo as its working directory. Pin the
Gemfile with an **absolute** `BUNDLE_GEMFILE` and give `bin/nabu` an absolute
path so neither depends on cwd:

```bash
claude mcp add --scope user nabu \
  --env BUNDLE_GEMFILE=/Users/vb/Dev/nabu/Gemfile \
  -- bundle exec /Users/vb/Dev/nabu/bin/nabu mcp
```

(The `--` separates Claude's own flags from the command it runs. `--env` is
repeatable. Replace `/Users/vb/Dev/nabu` with your checkout path.) This is the
honest, cwd-independent form: `bundler/setup` and `bundle exec` both read
`BUNDLE_GEMFILE`, so the corpus resolves from any directory.

Manage what you have added with `claude mcp list` / `claude mcp remove nabu`.

---

## 4. Registration — Claude Desktop

Claude Desktop reads `~/Library/Application Support/Claude/claude_desktop_config.json`
(macOS). It is spawned with no useful cwd, so use absolute paths, exactly as for
user scope:

```json
{
  "mcpServers": {
    "nabu": {
      "command": "bundle",
      "args": ["exec", "/Users/vb/Dev/nabu/bin/nabu", "mcp"],
      "env": {
        "BUNDLE_GEMFILE": "/Users/vb/Dev/nabu/Gemfile"
      }
    }
  }
}
```

Restart Claude Desktop after editing. The `nabu` tools then appear in the
tools menu of any conversation.

---

## 5. Example conversation

A realistic search → show → quote-with-citation flow (paraphrased):

> **You:** Where does Homer open the Iliad with "wrath"? Quote the first line.
>
> *(model calls `nabu_search` with `query: "μηνιν"`, `lang: "grc"`)*
> → one hit: `urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1`, language `grc`,
>   license_class `attribution`, source `perseus`, snippet
>   `[μηνιν] αειδε θεα…`
>
> *(model calls `nabu_show` with that urn)*
> → passage: `μῆνιν ἄειδε θεὰ Πηληϊάδεω Ἀχιλῆος`, document *Iliad*, license_class
>   `attribution`, revision 1.
>
> **Claude:** The Iliad opens on exactly that word — *mēnin*, "wrath":
>
> > μῆνιν ἄειδε θεὰ Πηληϊάδεω Ἀχιλῆος
> >
> > — *Iliad* 1.1
> > (`urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1`, Perseus,
> > license: attribution)

If the search had returned nothing, the coverage hint (and a `nabu_status` call)
would say whether Greek, Perseus, or the epic is even in this corpus — so "no
match" never gets mistaken for "unattested."

---

## 6. License and attribution

Outputs carry `license_class` on every passage precisely so attribution is never
guesswork. The corpus mixes classes (`open`, `attribution`, `nc`, and — behind
the `include_restricted` gate — `research_private`/`restricted`). When you
**quote a passage publicly**, honor its class: `attribution` and the Creative
Commons classes require crediting the source edition per their terms (the
`source` slug and the passage urn identify it; `nabu_status` and
`docs/02-sources.md` name each source's upstream and license). The read-only
surface hands you the fields; using them correctly downstream is the caller's
responsibility. A source carrying an owner-recorded **credit line**
(`sources.credit` — a grant's "clearly indicated wherever displayed" duty)
serves it as an additive `credit` key on every text-serving `nabu_show` /
`nabu_search` payload; preserve it with the license fields.

---

## 7. Parity with the CLI (the P44-3 audit)

The standing table: every CLI capability a conversational user would reach
for, the MCP tool that answers it, and the honest status. Statuses: **parity**
(same capability, pinned by a test on the MCP surface), **added P44-3** (gap
found by this audit, fixed additively — no frozen payload key changed),
**documented gap** (deliberately not exposed, with the reason). Frozen-contract
rule: existing payload keys/shapes never change or disappear; additions are
new, present-only keys.

| Capability | CLI surface | MCP tool | Status |
| --- | --- | --- | --- |
| Term-less browse: whole document by urn | `nabu show <document-urn>` | `nabu_show` (document shape, bounded) | parity (pinned P8-1) |
| Term-less browse: range slice | `nabu show <doc>:1.1-1.10` | `nabu_show` (range shape) | parity (pinned P8-1) |
| Term-less browse: citation-prefix listing | `nabu show <doc>:Y.19.1` (shortened urn, P44) | `nabu_show` — the same `Query::Show` prefix walk, range shape, boundary-exact | parity (pinned P44-3) |
| Term-less browse: enumerate a source's documents/entries | `nabu list SOURCE --documents/--entries` | — | documented gap: an unbounded per-source roll (sources run to 10⁵ documents) does not fit the bounded conversational surface; discovery flows through `nabu_search` → `nabu_show`, coverage through `nabu_status` |
| Random sampling | `nabu show --random [--source] [--lang]` | — | documented gap: the sampler is the owner's sync-time eyeball ritual, not a citation-anchored lookup; exposing it would also mean relaxing `nabu_show`'s frozen required-`urn` input contract |
| Owner notes on a urn / dictionary entry | `nabu note --list`, `show`/`define` note lines | `nabu_show` / `nabu_define` — `notes` lane served by default, withheld with a withheld target | parity (pinned P24-1) |
| Guarded (research_private) library pages | CLI shows everything (owner surface) | default-excluded everywhere, per-call `include_restricted` opt-in; open-override pages served | parity-by-design (pinned P13-11/P41) — the never-leak stance is the surface's contract, not a missing feature |
| Links kinds parallel/formula/cognate | `nabu links <urn>` | `nabu_links` | parity (pinned P16-1/2) |
| Links kind `reuse` (KITAB) with offset detail | `nabu links <urn>` | `nabu_links` — the kind vocabulary is open; reuse edges flow through with verbatim detail | parity (pinned P44-3) |
| Credit lines (`sources.credit`, migration 020) | `show`/`search` credit line | `nabu_show` / `nabu_search` — additive `credit` key, only when the source carries one | parity (verified; pinned P43-2) |
| The place desk | `nabu place NAME\|ID` (P44-2) | `nabu_place` | **added P44-3** — new tool, read-only, `Query::Place` unchanged; dump-absent degradation mirrors the CLI (id counts holdings, name lookup notes the sync hint) |
| Findspot line | `nabu show` findspot (P44-2) | `nabu_show` — additive `findspot` key when the captured id resolves through the dump | **added P44-3** (pinned, incl. the dump-absent byte-identical case) |
| Meter line | `nabu show` meter (P44-6/7 enrichments) | `nabu_show` — additive `meter` key on scanned passages | **added P44-3** (pinned) |
| Meter search facet | `search --meter CODE [--meter-pattern PATTERN]` (P45-5) | `nabu_search` `meter`/`meter_pattern` — text mode only, refusal parity with lemma/near; the honesty note (source layer named, empty layer explained) rides the free-text `note` | **added P45-5** (pinned; no frozen payload key changed) |
| Tibetan word-grain search | `search --words` (P54-4) | `nabu_search` `words` — text mode only, refusal parity with lemma/near; present-only `word_grain` key when the filter ran, present-only `word_grain_note` when it degraded (non-Tibetan query / nabu-data not synced) | **added P54-4** (pinned; additive keys only, flag-off byte-identical) |
| `--lang` on search/concordance | `search`/`concord` `--lang` | `nabu_search` / `nabu_concord` `lang` | parity (pinned P8) |
| `--lang`/`langs` on intertext/cognates | `parallels --lang`, `cognates --langs` | `nabu_parallels` `lang`, `nabu_cognates` `langs` | parity (pinned P15) |
| Shelf-language scoping | `define --lang`, `etym --lang` | `nabu_define` / `nabu_etym` `lang` (define's enum live-derived) | parity (pinned P35-6) |
| `list SOURCE --lang` implying the mode (P44-r1) | `nabu list` | — | documented gap (subsumed by the list gap above; the filters themselves exist on every MCP tool that lists passages) |
| Refusal parity | date/place × lemma/near refused; near × morph refused; morph without lemma refused | same refusals, as `isError` the model can self-correct | parity (pinned P13-6/P14-8/P15-2) |
| Availability semantics after the `wired:` rename (P44-r4) | registry `wired:` drives `list`/`status` visibility | `nabu_status` — sources default to the enabled set; the frozen payload key stays **`enabled`**, mirroring `wired`; no payload byte changed | parity (pinned P44-3: `enabled` key asserted, `"wired"` asserted absent) |
| The sign desk | `nabu signs URN\|TEXT [--lang] [--dialect etcsl] [--json]` (P53-2) | `nabu_signs` — the same `Query::Signs`, the payload IS the CLI's frozen `--json` contract (one serializer); bounded lines with an honest note; lane-off (no canonical/osl) answers the sync-hint note like the CLI's refusal | **added P53-2** — new tool, read-only; urn mode passes the restricted-exclusion gate |
| Tibetan word-segmented rendering | `nabu show <urn> --segmented` (P54-2) | `nabu_show` `segmented: true` — present-only `segmented` key per passage record (`Query::Show#segmented_text`, one serializer); not-applicable calls carry `segmentation_note` | **added P54-2** (pinned, incl. the flag-off byte-identical case) |
| Lect (nabu-lects) search filter | `search --lect LECT-ID` (P57-4) | `nabu_search` `lect` — text mode only, refusal parity with lemma/near; resolution-level filter (Nabu::Lects, prefix semantics), errors naming the module when nabu-lects is not synced | **added P57-4** (pinned; no frozen payload key changed) |

---

## 8. The user perspective — one desk at a time (P44-4)

The tools above are the plumbing. What a person actually does with them is
ask their model desk-shaped questions — and the answer is almost always a
short COMPOSITION of tools, not one call. This section documents that
perspective; the per-desk examples live in ONE curated home,
`site/axis/_mcp.yml`, projected onto every [axis page](
https://arvicco.github.io/nabu/axis/) as its "Ask your model" block and
summarized on the site's [MCP page](https://arvicco.github.io/nabu/mcp/).
Every example there was run LIVE against this library before it was
written down (the no-fiction guard): the asks are real, the calls are the
ones that answered, and the result summaries describe actual payloads.

Three walkthroughs showing the shape of the composition:

**Reception.** "Who quotes the opening of the Iliad?" →
`nabu_parallels urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1` returns
the documents sharing its rare phrases — Galen, Aristotle's Ars Rhetorica,
Sextus Empiricus (seven loci) — each with the folded phrase that matched
and a best-passage urn; `nabu_show` on that urn reads the pristine
context. Two calls, a reception史 sketch.

**Comparative philology.** "Show me MARK 2.3 everywhere" →
`nabu_align "MARK 2.3"` returns fourteen witness columns (Greek, Latin,
Gothic, Armenian, four OCS codices, Old English, Coptic, English …);
`nabu_cognates "LUKE 14.34" (langs: [got, chu])` then finds the verses
where Gothic and OCS use reflexes of the SAME root — salt ~ соль under
*sḗh₂l — and `nabu_etym` walks any single word's chain up the proto
shelves with corpus-attested cognate counts.

**A desk's own conventions.** Empty results usually mean a convention,
not an absence — and `nabu_status` is the tool to check before concluding
anything. Hittite is stored syllabified (`ne-pi-ša-aš`, not `nepišaš`);
Old Japanese is romanized (`yama`, not 山 or 夜麻); Akkadian kingship
hides behind the logogram LUGAL until you search `lemma: šarru`. The
axis-page examples encode one such lesson per desk where it exists.

Server note: a long-running MCP server serves the code it started with —
after updating nabu, restart the server (re-open the client session) to
pick up new tools and folds.
