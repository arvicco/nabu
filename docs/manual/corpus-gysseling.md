# Corpus Gysseling — acquisition

The Corpus Gysseling (INT/IvdNT) — the 13th-century originals that sourced
the Vroegmiddelnederlands Woordenboek: the Early Middle Dutch (`dum`)
reference corpus, ~2,228 documents, lemma + POS annotated — is distributed
behind the taalmaterialen registration wall (a one-time personal license
acceptance). Account-gated downloads fail Nabu's automation bar, so this is
a human acquisition by design (the Manual Adapter pattern, ruling Dp-a). The
adapter (`Nabu::Adapters::CorpusGysseling`) prints this same instruction
card until the archive is dropped.

## License — the strictest reading

Identical posture to Corpus Oudnederlands: INT tags it **"Niet-commercieel
(non-commercial)"** with **no explicit redistribution grant**, so the
owner's strictest reading applies — `research_private`, **local research
ingest only, never redistributed**. The repository is public, so **no corpus
bytes ever enter git**: fixtures live under the gitignored
`local/fixtures/corpus-gysseling/`, and the suite skips when they are absent.

## Steps

1. Register once at https://taalmaterialen.ivdnt.org/registreren/ and log in
   (a personal identity act — never an automated agent).
2. Open the Corpus Gysseling download page and CAPTURE THE LICENSE TEXT
   verbatim (screenshot/copy) at the checkbox BEFORE agreeing. The terms are
   only shown at this moment, and the library records the accepted grant per
   passage.
3. Download the corpus archive (the .fromdb documents plus plaats.txt/regio.txt).
4. Save it as corpus-gysseling.zip and drop it as listed below.

Get it from:
<https://taalmaterialen.ivdnt.org/download/tstc-corpus-gysseling/>

Then place the download here:

- `incoming/corpus-gysseling/corpus-gysseling.zip` — the Corpus Gysseling
  archive (research_private — never redistributed). It must carry the
  `.fromdb` documents **and** `plaats.txt` / `regio.txt`, the place/region
  code tables the adapter resolves at parse time.

Re-run `nabu sync corpus-gysseling` once the file is in place. The adapter
validates it (a `.fromdb` member is present), attics any prior holding, moves
the archive into `canonical/corpus-gysseling/` and stamps `.manual-fetch.json`
provenance. The ZIP itself is the canonical asset — `discover`/`parse` read
its members in-process, so nothing is unpacked and `nabu rebuild` stays a
pure function of `canonical/`.

## Refresh

INT deposits are versioned — re-acquire on a new version; re-acceptance of
the terms may be required per version.
