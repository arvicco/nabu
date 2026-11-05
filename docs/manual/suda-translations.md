# Suda On Line — acquiring the entry export (manual drop)

Where from: supplied by the Suda On Line's maintainer by email (no bulk download exists; the site is https://www.cs.uky.edu/~raphael/sol/sol-html/).

The site serves entries only through its search form, one at a time.

The SOL's translations, notes and bibliography are published under
**CC BY-NC-SA 1.0** ("All our entries, including translations and
annotations, are covered by a Creative Commons
'Attribution-NonCommercial-ShareAlike License'" — the home and rights
pages). The library's copy is the export the SOL's maintainer made from
the live database (`solEntries.zip`, entries saved 2025-07-24) and
supplied for this use by email, 2026-11-02. Every ingested passage
names its translator and carries its vetting history, which is the
credit the license asks for.

## The drop, step by step

1. Obtain the SOL entry export (solEntries.zip) from the SOL's maintainers
   (the 2025 export: 91,070,805 bytes, sha256
   `dbd63ed79f751f80651d32893146fe9ac739c97977e55795b9dac1cbfd2f24aa`;
   the 2026 refresh, crawled 25–28 Oct 2026 and supplied by the
   readsuda.org maintainer by email 2026-11-04: 89,137,980 bytes, sha256
   `261890d0af49df3c6f7541037103abf35486b3d6483174c66367f8c88f5fa97d`,
   151 entries changed since the 2025 export per its own change list).
2. Save it as received — no re-zipping (no unzipping either); the sha
   pin records the bytes as supplied.
3. Place it at `incoming/suda-translations/solEntries.zip` in the
   library root.
4. Run `bin/nabu sync suda-translations`. The drop is validated (zip
   magic bytes and at least one `sol-entries/<letter>/<n>` entry page),
   moved into `canonical/suda-translations/`, and sha-stamped in
   `.manual-fetch.json`. The parse reads the zip in place: 27 letter
   documents / 31,341 entry passages; the 27 index pages, two
   "no matches" pages and one mis-keyed query page skip by rule.

## Refresh

A fresher export (the SOL is still edited) drops the same way; an
identical re-drop is a sha-verified no-op, and the replaced zip moves to
the attic.
