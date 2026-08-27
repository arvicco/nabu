# Achemenet Babylonian — acquisition

The Helsinki "Linguistically Annotated Achemenet Babylonian Texts"
(Alstola, Sahala, Valk & Ong): 2,830 Achaemenid-period texts in
lemmatized Oracc ATF, one Zenodo deposit.

**Normally no human steps are needed**: `bin/nabu sync achemenet`
fetches `Achemenet.zip` from the stable Zenodo file URL unattended.
The first acquisition (2026-08-17) was performed by hand during the
adapter build; this document keeps that route replayable in case the
automated fetch breaks or you want the files directly.

## Manual route

1. Open <https://zenodo.org/records/19067652> (concept DOI
   10.5281/zenodo.19067652 — always resolves to the latest version).
2. **License capture:** the deposit page's license field is the
   grant's authority — CC BY 4.0 as of v1.1.1 (read 2026-08-17,
   re-verified 2026-08-27). The in-zip Readme carries no license line,
   so record the deposit page's license name and the version you are
   downloading.
3. Download `Achemenet.zip` (~2.0 MB; the sibling `Scripts.zip` is the
   conversion tooling, not corpus data — not needed).

Route re-verified 2026-08-27: record live at v1.1.1, `Achemenet.zip`
2.0 MB, license CC BY 4.0.

## Where it goes

There is no ManualDrop contract for this source — the adapter fetches
into `canonical/achemenet/` itself. A hand-downloaded zip goes to the
repo's gitignored intake folder (`.docs/inbox/` on the owner's box)
as evidence/backup; the sanctioned ingest is still `bin/nabu sync
achemenet`, which downloads the same artifact and stamps
`.zip-fetch.json` provenance.

## Refresh

A new deposit version mints a new artifact URL (Zenodo versioning);
the adapter pins `ARTIFACT_URL`, so a version bump is a small code
change plus a re-sync. Check the concept DOI for new versions.
