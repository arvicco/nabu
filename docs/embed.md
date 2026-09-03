# Semantic search — what `nabu embed` does and why

*The plain-language companion to the vector lane: what it builds, what
it costs, what it can and cannot answer. Setup mechanics live in
[manual/embed-venv.md](manual/embed-venv.md); the storage contract
lives in [architecture.md](architecture.md).*

## The problem it solves

Every other search in Nabu works on **words**. Full-text search finds
the passages that contain the letters you typed; lemma search widens
that to a dictionary form's every inflection. Both fail at a question
scholars ask constantly: *"where else does the library say this?"* —
same thought, different words. A Vulgate verse quoted loosely inside a
twelfth-century sermon. The Qumran copy of a psalm whose wording drifts
from the Masoretic text. The same Homeric line across four held
editions with different orthography. No word search finds these,
because the words differ; what matches is the **meaning**.

`nabu embed` builds the index that makes meaning searchable.

## What "embedding" means, without the math

A neural language model reads each passage once and distills it into a
fixed-size numerical **fingerprint** (a "vector") — 768 numbers that
encode roughly *what the passage says*, not which letters it uses.
Fingerprints have a useful property: passages that say similar things
get fingerprints that sit close together, so "find passages like this
one" becomes a fast geometric question — *whose fingerprint is nearest?*
— that the computer answers in a fraction of a second, across millions
of passages, with no network and no per-query model run.

The model is `multilingual-e5-base`, run entirely on this machine. No
text ever leaves the box; the only network step is the one-time model
download during setup.

## What it looks like at the desk

Anchor on any embedded passage and ask for its neighbors:

```
nabu search --similar urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1
```

The answer is that passage's nearest same-language neighbors, ranked
and **banded**:

- **close** — near-identical text: another edition's copy of the same
  passage, a direct quotation, a shared formula;
- **near** — clearly related: paraphrase, allusion, the same pericope
  in a divergent witness;
- **loose** — the rest of the requested page, shown honestly as loose.

Desk examples of the kind of question this answers:

- *Cross-edition:* reading Iliad 1.1 in the Perseus edition — which
  other held editions (First1KGreek, Diorisis, GLAUx) carry this line?
  The measured design case: in trials, the top hit was the correct
  cross-edition witness 80% of the time.
- *Quotation hunting:* a Vulgate verse → its echoes inside the
  medieval Latin of Corpus Corporum and the Carolingian material, even
  where the quotation is from memory and inexact.
- *Witness comparison:* a Masoretic verse in the Leningrad Codex →
  its Dead Sea Scrolls counterpart, wording drift and all.

The same lane is available to an AI assistant over MCP (the
`similar_to` tool), so a research conversation can ask "what else in
the library resembles this passage?" mid-discussion.

## What `bin/nabu embed` actually does when it runs

1. **Census first.** It counts the scope and reports, before doing
   anything: how many passages already carry an up-to-date fingerprint
   (*fresh*), how many changed since they were fingerprinted (*stale*),
   how many were never done (*missing*) — and an honest time estimate
   for the remainder. `bin/nabu embed --status` runs *only* this step.
2. **Delta only.** It then embeds exactly the stale-or-missing
   remainder. A passage whose text has not changed is never redone —
   the fingerprint stores a checksum of the exact text it was made
   from, and matching checksum means skip.
3. **Batch by batch, committed as it goes.** Work lands in small
   batches, each saved immediately. Interrupting a run (Ctrl-C, sleep,
   crash) loses at most one batch; re-firing the command picks up
   where it left off. It is safe to run any night and stop any morning.

The consequence of the delta design: the **first** run is the priced
build — the literary core is about 4.9 million passages across 17
sources, roughly a 20-hour overnight-and-a-day run on this hardware
(`caffeinate -i bin/nabu embed` keeps the machine awake for it). Every
**later** run is seconds to minutes, catching up only what a sync
added or revised. And because fingerprints are keyed to the passage's
identity and text — never to internal database row numbers — a full
`nabu rebuild` does not invalidate a single vector.

## What is in scope, and why not everything

The embedded scope is the **literary core** — the sources flagged
`embed_index: true` in the registry: the Greek canon (Perseus,
First1KGreek, Diorisis, GLAUx), the Latin canon (Perseus, DigilibLT,
CroALa, Corpus Corporum), the biblical tradition across its languages
(Vulgate, SBLGNT, WEB, Open Scriptures Hebrew Bible, Sefaria, the
Dead Sea Scrolls), and the treebanked witnesses (PROIEL, TOROT, CCMH).

The full library is deliberately *not* embedded. Trials priced a
whole-library build and the answer was no: the epigraphic and
documentary masses (tens of millions of short, fragmentary,
formulaic passages) cost far more than they return in this lane —
word search and the desks serve them better. The scope is a registry
flag, so widening it later is one line plus a delta run, not a
rebuild.

## Honest limits

These are measured findings, not modesty:

- **Same language only.** Cross-language retrieval with this model
  class tested too weak to trust (Greek→Latin found the right passage
  first only a third of the time; Hebrew→Greek far less), so the
  search is pinned to the anchor's language and no option widens it.
  Cross-linguistic questions remain the province of lemma search,
  aligned witnesses, and the reference desks.
- **Bands, not scores.** Raw similarity numbers invite
  over-interpretation, so the desk shows *close / near / loose* and
  names the model — a hit is a machine suggestion for a scholar to
  judge, never a curated alignment (those live in the parallels desk).
- **Pointed Hebrew and Aramaic embed a marks-stripped variant.** The
  model cannot see through the vowel points (trials showed essentially
  zero signal on pointed text; stripping the points rescued it). The
  stored passage text is untouched — canonical means canonical — only
  the fingerprint input is stripped.
- **No fingerprint, honest answer.** Asking `--similar` on a passage
  outside the embedded scope, or before the store is built, gets a
  short explanation of what to run — never a silent empty result.

## Setup and commands, in order

```
bundle exec rake tools:embed        # one-time: installs everything (idempotent, re-run freely)
bin/nabu embed --status             # census + honest ETA; runs nothing
caffeinate -i bin/nabu embed        # the build (first run ~20 h; interrupt and re-fire freely)
bin/nabu search --similar <urn>     # use it
```

The store lives in `db/vectors.sqlite3` beside the catalog. It is
expensive-derived: rebuilds never drop it, and `nabu embed` alone
maintains it. Switching to a better model someday is a deliberate,
separate build — new fingerprints land beside the old, never silently
over them.
