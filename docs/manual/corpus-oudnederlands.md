# Corpus Oudnederlands — acquisition

The Corpus Oudnederlands (INT/IvdNT) — all surviving Old-Dutch (`odt`)
word material 475–1200, v1.0 — is distributed behind the taalmaterialen
registration wall (a one-time personal license acceptance). Account-gated
downloads fail Nabu's automation bar, so this is a human acquisition by
design (the Manual Adapter pattern, ruling Dp-a). The adapter
(`Nabu::Adapters::CorpusOudnederlands`) prints this same instruction card
until the archive is dropped.

## License — the strictest reading

INT tags the corpus **"Niet-commercieel (non-commercial)"**, and the
download checkbox carries **no explicit redistribution grant**. The owner's
standing rule then applies: with no such grant, the strictest reading —
`research_private`, **local research ingest only, never served to third
parties, never redistributed**. Because this repository is public, **no
corpus bytes ever enter git**: the adapter's test fixtures live under the
gitignored `local/fixtures/corpus-oudnederlands/`, and the suite skips its
data-bearing cases when they are absent.

## Steps

1. Register once at https://taalmaterialen.ivdnt.org/registreren/ and log in
   (a personal identity act — never an automated agent).
2. Open the Corpus Oudnederlands download page and CAPTURE THE LICENSE TEXT
   verbatim (screenshot/copy) at the checkbox BEFORE agreeing. The terms are
   only shown at this moment, and the library records the accepted grant per
   passage.
3. Download the corpus archive.
4. Save it as corpus-oudnederlands.zip and drop it as listed below.

Get it from:
<https://taalmaterialen.ivdnt.org/download/corpus-oudnederlands-download/>

Then place the download here:

- `incoming/corpus-oudnederlands/corpus-oudnederlands.zip` — the Corpus
  Oudnederlands TEI archive (research_private — never redistributed).

Re-run `nabu sync corpus-oudnederlands` once the file is in place. The
adapter validates it (a TEI member is present), attics any prior holding,
moves the archive into `canonical/corpus-oudnederlands/` and stamps
`.manual-fetch.json` provenance. The ZIP itself is the canonical asset —
`discover`/`parse` read its members in-process, so nothing is unpacked and
`nabu rebuild` stays a pure function of `canonical/`.

## Refresh

INT deposits are versioned (Corpus Oudnederlands is hdl 10032/tm-a3-f3,
v1.0). Re-acquire on a new version; re-acceptance of the terms may be
required per version.
