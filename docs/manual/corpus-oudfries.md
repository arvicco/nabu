# Corpus Oudfries — acquisition

The Corpus Oudfries (INT/IvdNT, v1.0, hdl 10032/tm-a3-f6) — 177 Old
Frisian (`ofs`) text witnesses c. 1200–1550, compiled and annotated by
Rita van de Poel — is distributed behind the taalmaterialen login (a
one-time personal license acceptance). Account-gated downloads fail
Nabu's automation bar, so this is a human acquisition by design (the
Manual Adapter pattern, ruling Dp-a). The adapter
(`Nabu::Adapters::CorpusOudfries`) prints this same instruction card
until the archive is dropped.

## License — the strictest reading

INT catalogues the corpus **"Niet-commercieel (non-commercial)"**; the
release follows the corpus owner's permission, communicated by INT by
email, 2026-10-09. The archive carries no licence member of its own
(`README.txt` describes the corpus and gives the citation string). With
no explicit redistribution grant the owner's standing rule applies — the
strictest reading, `research_private`: **local research ingest only,
never served to third parties, never redistributed** — the same posture
as Corpus Oudnederlands and Corpus Gysseling. Because this repository is
public, **no corpus bytes ever enter git**: the adapter's test fixtures
live under the gitignored `local/fixtures/corpus-oudfries/`.

Cite as: Corpus Oudfries / Old Frisian Corpus. Compiled and annotated by
Rita van de Poel. (Version 1.0) [Dataset]. Available at the Dutch
Language Institute: http://hdl.handle.net/10032/tm-a3-f6.

## Steps

1. Register once at https://taalmaterialen.ivdnt.org/registreren/ and log in
   (a personal identity act — never an automated agent).
2. Open the Corpus Oudfries download page and CAPTURE THE LICENSE TEXT
   verbatim (screenshot/copy) at the checkbox BEFORE agreeing. The terms are
   only shown at this moment, and the library records the accepted grant per
   passage.
3. Download the corpus archive (CorpusOudfries1.0.zip) and keep its name.
4. Drop it as listed below.

Get it from:
<https://taalmaterialen.ivdnt.org/download/corpus-oudfries-download/>

Then place the download here:

- `incoming/corpus-oudfries/CorpusOudfries1.0.zip` — the Corpus Oudfries
  TEI archive (research_private — never redistributed).

Re-run `nabu sync corpus-oudfries` once the file is in place. The adapter
validates it (a `Data/*.xml` witness member is present), attics any prior
holding, moves the archive into `canonical/corpus-oudfries/` and stamps
`.manual-fetch.json` provenance. The ZIP itself is the canonical asset —
`discover`/`parse` read its members in-process through `unzip`, so nothing
is unpacked and `nabu rebuild` stays a pure function of `canonical/`.

## Refresh

INT deposits are versioned (Corpus Oudfries is hdl 10032/tm-a3-f6, v1.0).
A new version ships a new archive filename: re-pin the adapter's
`ZIP_NAME`, then re-acquire; re-acceptance of the terms may be required
per version.
