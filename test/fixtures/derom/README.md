# DÉRom fixtures (P56-4)

Real files from the **Ortolang workspace `derom`** — *Dictionnaire
Étymologique Roman (DÉRom)*, ATILF (CNRS/Université de Lorraine) &
Universität des Saarlandes, dir. Éva Buchi & Wolfgang Schweickard.
Retrieved **2026-08-02** via the Ortolang diffusion content API
(`https://repository.ortolang.fr/api/content/derom/latest/...`), workspace
snapshot **4** (market tag v1, publication date 2025-07-24; the market page
is https://www.ortolang.fr/market/corpora/derom).

## License (the P56-4 license gate)

`ortolang-item-license.json` is the verbatim license/status/title extract of
the workspace's market item metadata
(`https://repository.ortolang.fr/api/search/items/derom?type=corpora`,
retrieved 2026-08-02): **CC BY-NC-SA 4.0** ("Licence Creative Commons
Attribution - Pas d'Utilisation Commerciale - Partage dans les Mêmes
Conditions 4.0 International", status "Free for non commercial use") →
Nabu `license_class: nc` (ingestible, MCP-surface-excluded). The workspace
ships no LICENSE file at its root; this item metadata IS the formal grant.

## Article XMLs (whole files, untrimmed — they are small)

Kept in their upstream collection directories (names verbatim — the fetch
lands the same layout):

- `1 Fichiers XML articles DERom 1/'lakt-e.xml` — the flagship pan-Romance
  article */ˈlakt-e/ "lait": 3 subdivs (gender split), 24 cognat signifiants
  over 21 idiomes (incl. the two-variant romanch. lat/latg and the joint
  `gal./port.` idiome), Commentaire, Notes, Bibliographie, Signatures.
- `1 Fichiers XML articles DERom 1/ka'Ball-u.xml` — */kaˈβall-u/ "cheval":
  the β (betacism) headword pin; 21 signifiants, 18 idiomes,
  transcription_phonetique elements.
- `5 Fichiers XML articles de renvoi a Mertens 2021/ara't-ur-a.xml` — a
  renvoi stub: Lemme (gloss present) + `<Lien>` to the Mertens 2021 PDF,
  no Materiaux/cognats.
- `6 Fichiers XML articles potiches en attente/'al-a.xml` — a potiche
  placeholder: bare Signifiant/catgramm + `<NonRedige/>` (no Lemme, no
  gloss) — the shape the parser SKIPS.

Upstream URLs are the content API base + the collection dir + filename,
e.g.
`https://repository.ortolang.fr/api/content/derom/latest/1%20Fichiers%20XML%20articles%20DERom%201/%27lakt-e.xml`.

## fetch/ — listing + defense fixtures (trimmed real bytes)

- `listing-1.html` … `listing-6.html`: the five OPEN collection index pages
  (Apache-style HTML the content API serves), each trimmed to the header,
  parent row and 1–2 real `.xml` rows (listing-1 keeps the two article
  fixtures; byte-verbatim rows otherwise). Collections 4 ("futur DERom 4")
  and 7 ("Articles en anglais") are AUTH-GATED upstream (HTTP 303 to
  auth.ortolang.fr) and deliberately absent.
- `auth-gate.html`: the first 2,500 bytes of the real Keycloak login page a
  gated collection 303s to — the reshaped/gated-listing defense fixture
  (no "Index of", no `.xml` hrefs).

## Open-content census (2026-08-02, request budget 21/25)

Collection 1: 110 xml · 2: 40 · 3: 38 · 5 (renvoi): 45 · 6 (potiche): 280
→ 513 open XMLs; expected first sync ≈ 233 entries (188 full + 45 renvoi;
280 potiches skipped as `<NonRedige/>`). Next upstream refresh announced
for September 2026 (É. Buchi, correspondence 2026-07-29, №45-3).
