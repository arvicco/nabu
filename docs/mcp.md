# The MCP server — talking to the corpus

`bin/nabu mcp` runs a **Model Context Protocol** server: a read-only,
conversational surface over your local nabu corpus, spoken to by an AI client
(Claude Code, Claude Desktop) over stdio. It exposes eight tools — search, read
by urn, concordance, cross-source alignment, dictionary lookup, the
reconstruction walk, intertext (quotation/echo finding), and coverage — so a
model can look things up in your
texts, quote them, and cite them, without any ability to change the
collection.

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

## 2. The eight tools

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
50). Hits are relevance-ranked and bounded, with an honest "showing k of N"
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
- `parallel: true` (with `parallel_lang`, default `eng`) → the same work's
  translation, aligned line by line / block by block (CTS editions and, since
  P13-4, ORACC tablets ↔ their `-en` sibling documents).

Withdrawn and retired-upstream items appear, flagged.

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
bare `*`) forces the direct lookup. Cognate lists are bounded (attested
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

### `nabu_status`

Coverage of the corpus, and the tool to call to interpret an empty search
*before* concluding a text is unattested: per-source document/passage counts and
last-sync recency, passage counts by language and by license class, index
state, and what is excluded by default. Takes no arguments.

### The restricted-exclusion stance

License classes `research_private` and `restricted` are **excluded by default**
from every tool — they never appear in search results, `nabu_show` withholds
them, and `nabu_status` counts them only under `excluded_by_default`. Nothing
synced today carries those classes; the exclusion is forward-looking (the ad-hoc
pipeline will), so a conversational surface never leaks private material
casually. A caller who understands and will honor the restriction can opt in
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
responsibility.
