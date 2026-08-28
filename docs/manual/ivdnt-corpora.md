# IvdNT corpora (Gysseling, Oudnederlands) — acquisition

The Instituut voor de Nederlandse Taal (INT/IvdNT) distributes its
historical Dutch corpora through the taalmaterialen portal behind a
registration wall with a per-corpus license checkbox. Upstream
confirmed (correspondence, 2026-08-25) that the account is purely a
**one-time license acceptance** — after the checkbox, the download is
direct; no session is needed thereafter. Account-gated downloads fail
Nabu's automation bar, so this is a human acquisition by design.

Targets:

- **Corpus Gysseling (Data)** — all 13th-century originals that
  sourced the Vroegmiddelnederlands Woordenboek: the Early Middle
  Dutch reference corpus, lemma + POS annotated.
- **Corpus Oudnederlands** — all surviving Dutch word material
  475–1200 (v1.0 published 2026), the Old Dutch corpus.
- **CRM14** (Corpus Van Reenen–Mulder, 14th-c. charters) — not in the
  logged-out catalog; see below.
- **Corpus Oudfries** — pending its upstream owners (INT will
  report); nothing to do yet.

## Steps

1. Register at <https://taalmaterialen.ivdnt.org/registreren/>.
   Registration is an identity act — the account holder registers and
   agrees personally, never an automated agent.
2. Log in.
3. **Corpus Gysseling:** open
   <https://taalmaterialen.ivdnt.org/download/tstc-corpus-gysseling/>.
4. **Corpus Oudnederlands:** open
   <https://taalmaterialen.ivdnt.org/download/corpus-oudnederlands-download/>.
5. **License capture — the critical step:** each download page shows
   its license terms at a checkbox before the download. CAPTURE THE
   LICENSE NAME AND TEXT VERBATIM (copy the text or screenshot it)
   **before** ticking agree — the library records the accepted terms
   per passage, and the terms are only displayed at this moment. The
   catalog tags both corpora **"Niet-commercieel (non-commercial)"**
   (seen logged-out, 2026-08-27); expect the checkbox terms to be the
   authoritative, fuller text. Strictest reading applies: these
   corpora are never redistributed.
6. Download each archive. Record file names, sizes and download date
   alongside the captured terms.
7. **CRM14:** while logged in, search the catalog for "Reenen". The
   corpus is not in the logged-out catalog; if it does not appear
   logged-in either, ask via the existing INT correspondence thread
   (it was unaddressed in the 2026-08-25 reply).

Route verified 2026-08-27: the registration page and both corpus
pages are live (the portal serves logged-out product pages; the
download itself is behind the login). The exact archive names, sizes
and checkbox wording could not be verified logged-out — record them
at acquisition time.

## Where it goes

The adapters do not exist yet (work-queue Q48 — they build after the
first acquisition, in the manual-drop class): until they land, the
archives go to the repo's gitignored intake folder (`.docs/inbox/`)
untouched. Once the adapters exist, drops go to
`incoming/<slug>/` per their ManualDrop instruction cards
(expected slugs: corpus-gysseling, corpus-oudnederlands), and this
document gets updated to match — the suite pins the agreement.

## Refresh

INT corpora are versioned deposits with handles (Corpus Oudnederlands
is hdl 10032/tm-a3-f3, v1.0). Re-check the product pages for new
versions; re-acceptance of terms may be required per version.
