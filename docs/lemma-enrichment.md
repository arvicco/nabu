# Lemma enrichment — what `nabu lemma-enrich` does and why

*The plain-language companion to the silver-lemma lane: what it
builds, what it costs, what it can and cannot promise. Setup mechanics
live in [manual/silver-lemma-venv.md](manual/silver-lemma-venv.md);
the sibling explainer for semantic search is [embed.md](embed.md).*

## The problem it solves

The classical languages are heavily inflected. A Latin noun wears a
dozen different endings; a verb can wear well over a hundred. *Rex*,
*regis*, *regi*, *regem*, *rege*, *reges*, *regum*, *regibus* are all
one word — "king" — but to a plain text search they are eight
different strings. Search for one and you miss the other seven.

The fix scholars have always used is the **lemma**: the dictionary
headword that stands for all of a word's forms. When every word in a
passage is tagged with its lemma, you can search by *word* instead of
by *spelling* — `nabu search --lemma rex --lang lat` finds every king
in every case and number, in one query.

The catch: someone has to do the tagging. A minority of the library
came with lemmas — the **treebanks**, corpora where scholars
hand-verified every single word (we call that coverage **gold**). The
great mass of Latin — the 85-million-word Corpus Corporum, the
Croatian and Italian neo-Latin collections, and the rest — arrived
with no lemmas at all. Lemma search simply cannot see those texts.

`nabu lemma-enrich` closes that gap with a machine.

## Gold and silver — the honesty system

A neural tagger reads each untagged passage and proposes a lemma for
every word. Machine output is good but not gold, and the library never
pretends otherwise:

- **gold** — a human verified it (the treebanks' own annotations);
- **silver** — a machine proposed it (this lane, and a few corpora
  whose upstream shipped automatic annotations).

Every count, search hit, and frequency figure that rests on silver
rows is **labeled** `[silver]` wherever it appears, silver counts are
tallied separately from gold ones, and `--gold-only` restricts any
lemma search to human-verified rows. A machine guess is never
mistakable for scholarship — but it makes eighty-five million words
searchable that were dark before.

How good is the machine? Measured, not assumed: on held-out
gold-annotated passages the Latin model scores **~99%** on text like
its training data and **75–89%** on text further from it (medieval and
neo-Latin drift from the classical training corpus). The
`--spot-check` mode re-runs that measurement any time, on your own
library, and writes nothing.

## What it looks like at the desk

Before the campaign, `search --lemma` over Latin answers only from the
treebanked slice. After it, the whole Latin shelf answers:

- *Every king in the Vulgate and the sermons that quote it:*
  `nabu search --lemma rex --lang lat` — all eight-plus surface forms,
  one query, silver hits labeled.
- *A word study across a millennium:* how does *gratia* behave in
  classical prose vs. twelfth-century theology? Lemma search plus the
  date filters turns that from weeks of collecting into a query.
- *From attestation to dictionary:* a lemma found in the wild links
  straight into the `define` desk (Lewis & Short and the other held
  dictionaries) and the `etym` desk walks it toward reconstructed
  ancestors.
- *Honest counts:* frequency views show gold and silver tallies side
  by side, never blended.

## What `bin/nabu lemma-enrich lat` actually does when it runs

1. **Census first.** It counts the language's live passages and
   reports: how many already carry lemmas of any tier (those are
   *never touched* — gold is sacred), how many the machine has already
   done, and the uncovered remainder with an honest time estimate.
   `--dry-run` runs only this step and stops.
2. **The uncovered slice only.** The model — a local, CPU-run tagger
   inside a Python sandbox on this machine; no text leaves the box —
   processes exactly the passages that have nothing. Batches stream
   through one worker process, and progress ticks as it goes.
3. **Results land on a shelf, not in the database.** Hours of compute
   are expensive to redo, so the raw model output is stored like the
   owner's own material — on a permanent shelf that database rebuilds
   never destroy. Each batch is saved as it lands and the campaign
   checkpoints continuously: interrupt it at hour three and you lose
   at most half a minute of work; re-fire the same command and it
   continues where it stopped.
4. **Nothing becomes searchable until you say so.** Projecting the
   shelf into the live search index is a deliberate, separate step —
   `--index` after a campaign, or `--index-only` any time. A rebuild
   announces that the shelf exists and names the command; it never
   projects it silently. What the machine wrote and what the library
   serves stay under explicit control.

## Honest limits

- **One language wave at a time.** The lane currently runs Latin only.
  Greek is measured and planned, but each language gets its own
  verification wave before it is wired — accuracy claims are earned
  per language, not extrapolated.
- **Cross-domain accuracy is the real number.** ~99% holds on
  classical-style text; medieval abbreviations, orthographic drift,
  and neo-Latin coinages pull the model down into the 75–89% band.
  That is still transformative for search — and it is exactly why
  silver is labeled and gold is never overwritten.
- **Provenance is pinned.** Every shelf record carries the model name
  and version that produced it. Upgrading the model is a deliberate
  act between campaigns (spot-check first), never a silent drift.
- **The model needs a one-time setup.** The tagger and its language
  model install with one idempotent command; after that, campaigns run
  fully offline.

## Setup and commands, in order

```
bundle exec rake tools:stanza[la]           # one-time: venv + tagger + Latin model
bin/nabu lemma-enrich lat --dry-run         # census + honest ETA; runs nothing
bin/nabu lemma-enrich lat --spot-check 200  # score the model against gold; writes nothing
bin/nabu lemma-enrich lat                   # the campaign (hours; interrupt and re-fire freely)
bin/nabu lemma-enrich lat --index-only      # when satisfied: project the shelf into search
bin/nabu search --lemma rex --lang lat      # use it
```

The shelf lives under `local/shelves/local-lemmas/` beside the owner's
other permanent material, written only through its sanctioned gateway.
Rebuilds never drop it; re-projection after a rebuild is one
`--index-only` away.
