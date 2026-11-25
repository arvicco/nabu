# PCMEP — acquisition

The Parsed Corpus of Middle English Poetry (Richard Zimmermann,
pcmep.net) — 57 Middle English poems, c. 1150–1420, 235,439 words,
parsed in the annotation scheme of the Penn-Parsed Corpus of Middle
English (PPCME2) — is distributed as one release zip behind a
password-gated download page: the maintainer issues the username and
password on request. A password-gated download fails Nabu's automation
bar, so this is a human acquisition by design (the Manual Adapter
pattern, ruling Dp-a). The adapter (`Nabu::Adapters::Pcmep`) prints this
same instruction card until the archive is dropped.

The release held today, `PCMEP_Nov2025.zip` (1.3 MB), was delivered by
the maintainer by email on 2026-11-23.

## License — research_private

The pcmep.net Download page states the terms the user agrees to by
downloading (verbatim, as displayed 2026-11-25):

> (1) The copy-right of the text editions used as the basis for the
> electronic text files must not be violated.
> (2) The copy-right of the annotations remains with the creators of the
> Parsed Corpus of Middle English Poetry.
> (3) The PCMEP will not be used direclty or indirectly for any
> commercial purposes.
> (4) The corpus must not be re-distributed without the consent of the
> creators of the Parsed Corpus of Middle English Poetry.
> (5) There is no guarantee that the annotations are correct. The
> creators of the Parsed Corpus of Middle English Poetry are not
> responsible for inaccurate statements that result from using the
> corpus.
> (6) All research publications that use the Parsed Corpus of Middle
> English Poetry must cite the corpus appropriately.

No redistribution → `research_private`: local research ingest only,
never served to third parties, never redistributed. Because this
repository is public, **no corpus bytes ever enter git**: the adapter's
test samples live under the gitignored `local/fixtures/pcmep/`, and the
suite skips its data-bearing cases when they are absent. At each new
acquisition, capture the Download page's terms again verbatim — the
wording above is what the library records.

## Steps

1. Take the release archive the maintainer delivered by email on
   2026-11-23 (PCMEP_Nov2025.zip, 1.3 MB) — for a later release,
   download it from the pcmep.net Download page with the username and
   password the maintainer issues on request (a personal identity act —
   never an automated agent).
2. Do not unpack it — the zip itself is the canonical asset.
3. Save it as pcmep.zip and drop it as listed below.

Get it from: <https://pcmep.net/download.php>

Then place the download here:

- `incoming/pcmep/pcmep.zip` — the PCMEP release zip of
  `<band>.<text>.psd` files (research_private — never redistributed).

Re-run `nabu sync pcmep` once the file is in place. The adapter
validates it (at least one period-band `.psd` member such as
`M1a.TheGrave.psd`), attics any prior holding, moves the archive into
`canonical/pcmep/` and stamps `.manual-fetch.json` provenance. The ZIP
itself is the canonical asset — `discover`/`parse` read its members
in-process, so nothing is unpacked and `nabu rebuild` stays a pure
function of `canonical/`.

## What to expect

One document per poem (`urn:nabu:pcmep:<text code>`, e.g.
`urn:nabu:pcmep:TheGrave`) — 57 documents, the 57 rows of
<https://pcmep.net/texts.php>; one passage per parse tree (each poem's
per-text page on pcmep.net gives its "Token count" = trees). Members
that are not `<band>.<text>.psd` files are counted in the sync's
discovery accounting (macOS archiver litter by rule, anything else as
unrecognized), never silently dropped.

## Refresh

The maintainer publishes new releases occasionally (check pcmep.net
every other year); drop the new zip under the same name — the held one
is atticked.

## Citation

The terms require citing the corpus "appropriately"; the site publishes
no citation form. Credit as: Richard Zimmermann, *The Parsed Corpus of
Middle English Poetry (PCMEP)*, pcmep.net, release Nov 2025.
