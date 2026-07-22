# YCOE — GATED. Owner must fetch manually before P40-4.

**This directory intentionally holds NO fixtures and NO `manifest.yml`.** The
York-Toronto-Helsinki Parsed Corpus of Old English Prose (**YCOE**) is behind a
**click-through licence gate** at the Oxford Text Archive; it cannot be acquired
by an anonymous raw GET, so no sample could be committed under P40-g. (The file
is deliberately named `FETCH-GATE.md`, not `README.md`, so the P5-4 fixture-
sentinel — which requires every `README.md`-bearing dir to ship a manifest that
lists ≥1 real file — does not fail on an empty gated dir.)

## The gate (verified live, 2026-07-22)

- Item: **OTA handle `20.500.12024/2462`**, at
  `https://ota.bodleian.ox.ac.uk/repository/xmlui/handle/20.500.12024/2462`
  (the old global handle proxy `hdl.handle.net/20.500.12024/2462` now 500s; the
  live repo is the Bodleian DSpace/XMLUI above).
- Download bitstream: `.../bitstream/handle/20.500.12024/2462/2462.zip` — the
  14.25 MB `2462.zip`. Its link carries `isAllowed=n`.
- A direct GET of the bitstream **302-redirects to
  `/handle/20.500.12024/2462/license/agree?bitstreamId=217026`** — a licence
  agreement + a form (COUNTRY, ORGANIZATION, INTENDED_USE). Fetching it returns
  the HTML agreement page, **not** the zip. The metadata bitstream
  (`header2462.xml`) is gated the same way. **Not bypassable without agreeing.**

## License / terms (OTA "Academic Use", recorded verbatim)

The item is labelled **"Academic Use · Attribution Required · Noncommercial"**
under the *University of Oxford Text Archive User Agreement*
(`https://ota.bodleian.ox.ac.uk/repository/xmlui/page/licence-ota`). Verbatim
clauses:

> … only for the purposes of non-commercial research or teaching. To obtain
> permission prior to using part or all of the data collections for commercial
> purposes … contacting the University of Oxford Text Archive …

> To acknowledge, in any publication … the original data creators, depositors
> or copyright holders, the funders … and the University of Oxford Text Archive.

> Electronic or print copies may not be offered, whether for sale or otherwise,
> to anyone who is not an authorised user.

Copyright: "Copyright (c) 2019 University of Oxford. All rights reserved." →
license_class would be **`nc`** (Noncommercial + Attribution). Note the Academic-
Use + Noncommercial posture is more restrictive than the CC licences of the
other five Germanic-phase sources; the owner should decide whether YCOE clears
the MCP-surface / redistribution bar before P40-4 implements the adapter.

## Manual fetch steps for the owner (unblocks P40-4)

1. Go to `https://ota.bodleian.ox.ac.uk/repository/xmlui/handle/20.500.12024/2462`.
2. Click **Download** on `2462.zip` (14.25 MB) → you are sent to the licence
   agreement.
3. Read/accept the **University of Oxford Text Archive User Agreement** and fill
   the required form fields (COUNTRY, ORGANIZATION, INTENDED_USE) — this is the
   Academic-Use, Noncommercial, Attribution-Required grant.
4. Download `2462.zip`, unzip, and hand two SMALL `.psd` texts (whole) plus one
   `.pos` sibling into this dir; then add `README.md` + `manifest.yml`
   (`refetchable: false`, `provenance: manual-ota`, `reason:` = this gate) and
   re-run the fixture-manifest sentinel.

## Format note (for when the fixtures arrive)

YCOE is Penn labeled-bracketing like HeliPaD/PPCME2: parsed `.psd` files (the
same CorpusSearch annotation) with parallel `.pos` part-of-speech files. The
zip contains `psd/`, `pos/` and a `header2462.xml` catalogue. P40-3's HeliPaD
Penn parser is the natural base to reuse.

Sources:
- OTA item: https://ota.bodleian.ox.ac.uk/repository/xmlui/handle/20.500.12024/2462
- OTA user agreement: https://ota.bodleian.ox.ac.uk/repository/xmlui/page/licence-ota
