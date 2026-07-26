# ORACC P46-3 extension fixtures — ecut (Urartian) + aemw/amarna

Real trimmed slices for two of the 64 PROJECTS rows added by packet P46-3
(the CC0 extension pack; the oracc_p14_9/oracc_p31_0 own-tree precedent, so
the discover-walked `test/fixtures/oracc/` corpus stays byte-stable). All
content is real upstream ORACC JSON — never hand-written.

Retrieved **2026-07-26** from the per-project open-data zips. THE HOST FACT
OF THIS PACKET: `oracc.museum.upenn.edu` was **down for days** (connection
timeouts on every request — the same outage the P46 scout hit), so every
zip was fetched from the official LMU build mirror

- `http://oracc.ub.uni-muenchen.de/json/ecut.zip` (6,600,041 B,
  Last-Modified Mon, 20 Mar 2023 08:15:51 GMT,
  sha256 `1e5a8425732b74070bcc199f8fd27eff3af6d6284c609213507bc3fe371019fc`)
- `http://oracc.ub.uni-muenchen.de/json/aemw-amarna.zip` (8,080,058 B,
  Last-Modified Fri, 05 Jul 2024 11:22:10 GMT,
  sha256 `aaccf5e85cf3454218bdca5787b9f1d4d213d211bcd3227e626d60809644f25d`)

(the mirror serves plain HTTP only — no TLS on that host — and answers a
missing project zip with HTTP 500, not 404). This outage is why the same
packet gives `Nabu::ZipFetch` its fallback-host capability: the sync's
identity/pins stay on the primary `oracc.museum.upenn.edu` URLs, the
mirror is the documented stand-in.

## License (recorded verbatim, machine-read from each zip's metadata.json)

Both projects' `metadata.json` carry the identical machine-readable
statement the adapter's per-project gate reads:

> This data is released under the CC0 license

→ `license_class: open`. (The standalone HTTP `metadata.json` endpoints
still serve empty bodies — on the mirror too; the zip member is the
readable copy, as at P31-0.)

## Layout (mirrors the real unpacked workdir — the load-bearing fact)

- `ecut.zip` → root `ecut/` → `<workdir>/ecut/…` (top-level shape)
- `aemw-amarna.zip` → root `aemw/` → `<workdir>/aemw-amarna/amarna/…`
  (the P11-7 saao-saa01 nested shape — one segment under the slug dir)

## Files and extract procedure

corpusjson members and metadata.json are byte-verbatim **whole** (a cdl
tree is atomic; metadata carries the license + config the adapter reads).
catalogue.json is **trimmed** by the house recipe: envelope keys verbatim,
`members`/`summaries` reduced to the fixtured ids, re-serialized
well-formed (`json.dump(..., ensure_ascii=False, indent=1)`).

### ecut/ (Urartian `xur`, Q-numbers; 806 non-empty + 10 empty upstream)

The corpus that brings **Urartian into the library**. Whole-project lang
census at fixture time (raw `"lang"` values across every non-empty
corpusjson): `xur` 22,760 · `xur-946` 3,994 · `akk` 1,684 · `xur-944` 202
· `qur` 40 · `hlu` 11. The `xur-946`/`xur-944` script variants fold to the
base subtag `xur` under the parser's standing primary-language rule — the
language is data, not config, exactly as peo/elx entered at P31-0.
ecut ships `gloss-xur.json` (plus gloss-akk/hlu/qur): Urartian is
**gold-lemmatized** and enters the lemma index for free.

| File | Whole? | Why this one |
|---|---|---|
| `metadata.json` | whole | license (CC0) + project name/config (53,903 B) |
| `catalogue.json` | trimmed | members reduced to the 2 fixtured Q-numbers (1.69 MB → ~4 KB) |
| `corpusjson/Q006944.json` | whole | eCUT A 05-046 (Minua gate inscription): the rich exemplar — 3 passages, pure Urartian, lemmatized (Haldi, Minua, šidišt-…), both `xur` and `xur-946` on its tokens |
| `corpusjson/Q007897.json` | whole | eCUT B 18-02: the smallest lemmatized pure-xur text found (3,906 B, single line) — the minimal-document case |

### aemw-amarna/ (the Amarna letters, peripheral Akkadian, P-numbers; 305 non-empty upstream)

Whole-project lang census: `akk-x-mbperi` 34,323 · `qca` 203 · `egy-020`
16 · `xhu` 10 · `xhu-946` 3 · `uga` 1 — the letters ride the standing
base-subtag fold (`akk`), traces of Hurrian/Egyptian/Ugaritic stay honest
per-token tags.

| File | Whole? | Why this one |
|---|---|---|
| `amarna/metadata.json` | whole | license (CC0) + config (22,385 B); nested path is the real zip layout |
| `amarna/catalogue.json` | trimmed | members reduced to the fixtured P-number (708 KB → ~2 KB) |
| `amarna/corpusjson/P271176.json` | whole | EA 172: 5 lines over a broken obverse (primed labels `o.001'`), lemmatized (ša, ribbatu) — a typical damaged-letter exemplar |

## Honest findings recorded here

- **atae, tcma, cmawro parents are proxy portals** (`type:corpus` with a
  `proxies` map, the riao shape): their texts live in per-site/per-volume
  subprojects, so P46-3 registers those (22 atae + 27 tcma + 4 cmawro)
  and NOT the parents. atae's proxies also point at 5,233 already-held
  saao texts — those stay saao's.
- **tcma/bderi is a broken upstream build** (HTTP 500 on the mirror, the
  ctij shape) — its 1 proxy text is unfetchable; excluded, documented in
  `Oracc::PROJECTS`.
- **cams/gkab overlap check (the P46-3 ruling)**: 585 local corpusjson
  texts; text-ID overlap vs the held library = 13 (4 vs the named
  blms+dcclt: 3 dcclt, 1 blms — 0.7%, ruled immaterial, include). Its
  other 162 upstream proxies (144 dcclt, 16 blms, 2 ccpo) are pointers,
  never local files, so they cannot double-ingest by construction.
