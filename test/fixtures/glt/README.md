# glt fixtures — Greek Orthodox Liturgical Texts (glt.goarch.org)

Real upstream pages, retrieved 2026-11-04 from https://glt.goarch.org/
(the Greek Orthodox Archdiocese of America's Greek liturgical-texts site,
compiled and maintained by Fr. Leo Schefe). License: permission by email
from the site maintainer, 2026-11-02 — the texts are in the public domain
and "you are welcome to use them"; reports of errors in the texts are
invited.

The tree mirrors the canonical layout the fetch lands (`canonical/glt/`):
site-relative paths, percent-decoded.

| File | Upstream URL | Kept |
|---|---|---|
| `index.html` | https://glt.goarch.org/index.html | whole — the catalog (654 in-site texts/ links) |
| `extra.htm` | https://glt.goarch.org/extra.htm | whole — "ΑΛΛΕΣ ΑΚΟΛΟΥΘΙΕΣ", the additional services (75 texts/ links) |
| `texts/Sep/Sep05.html` | https://glt.goarch.org/texts/Sep/Sep05.html | whole — Menaion, 5 September (St Zachariah): the tag-soup markup, the model-melody mp3 links, tone rubrics, the Synaxarion |
| `texts/Euch/Baptism.html` | https://glt.goarch.org/texts/Euch/Baptism.html | trimmed — source lines 1–60 (the opening rubrics, the exorcisms, the renunciations) + 254–257 (the page close, Cloudflare script and all); the blue/green/bold inks and the inline-rubric alternates |
| `texts/Sep/14b.html` | https://glt.goarch.org/texts/Sep/14b.html | trimmed — source lines 1–130 (the Akathist of the Cross: title, rubric, kontakion, the first oikos and its chairetismoi) + a `</p>` + 1519–1529 (the closing apolytikion); the LibreOffice-export variant |
| `daily/Mon.html` | https://glt.goarch.org/daily/Mon.html | trimmed — source lines 1–24 + 337–338; REJECTED-grain specimen |
| `misc/Prosomia.html` | https://glt.goarch.org/misc/Prosomia.html | trimmed — source lines 1–90 + a `</p>` + 8375–8378; REJECTED-grain specimen |

## Delivery grains (census 2026-11-04)

The site is static HTML behind Cloudflare: no bulk archive, no sitemap
(`/sitemap.xml` 404s), no directory listings (`/texts/Sep/` 403s). The two
index pages are the catalog; text pages are leaves (they link only their
mp3 recordings, an icon and the Archdiocese). Every grain upstream serves:

- **the service page** `texts/<shelf>/<page>.html` — ACCEPTED, the
  document. 727 unique texts/ targets across both indexes = 725 `.html`
  pages (Sep 41, Oct 40, Nov 36, Dec 58, Jan 44, Feb 40, Mar 33, Apr 30,
  May 35, Jun 32, Jul 34, Aug 35 — the Menaia 458; Och 81, Tri 70, Pen 60,
  Oro 47, Euch 6, Synek 3) + 1 `.rtf` + 1 `.pdf`.
- **the catalog pages** `index.html`, `extra.htm` — fetched and kept as
  provenance; discovery skips them by rule (specimens: both, whole).
- **the weekly-compiled daily services** `daily/`, `Lite/`, `Athos/`,
  `AthosJ/` ("Καθημερινὲς ἀκολουθίες" for chanters, priests, a LITE
  version, and the monastic old/new calendar — 35 `.html` + 34 `.epub`
  links) — regenerated every week (Last-Modified 2026-11-02 on all of
  them) from the same books: derivative and volatile. Never fetched;
  skipped by rule if present (specimen `daily/Mon.html`).
- **the misc/ shelf** — the lectionary scripture books (`Evangelion.html`,
  `Apostelos.html`, `Psaltirion.html`: biblical text, a widening
  candidate), the Automela-and-Heirmoi anthology `Prosomia.html` (hymn
  incipits drawn from the books, keyed to recordings, with an English
  apparatus), and two PDFs (`Evangelion.pdf`, `Theotokarion.pdf`). Never
  fetched; skipped by rule if present (specimen `misc/Prosomia.html`).
- **non-HTML renderings** — the `.epub` twins of the daily services, the
  PDFs (above, plus `texts/Mar/Patrick Greekservice.pdf`), the
  Greek+English funeral `texts/Euch/Funeral.rtf`. Never fetched; skipped
  by rule if present under texts/.
- **recordings** `music/NNNN.mp3` (the model melodies a melody incipit
  links) — never fetched; their paths ride the passages as `recordings`.
- **external links** (the Ecumenical Patriarchate's typikon, the GOARCH
  kanonion) — not this site's texts.

Upstream's own robots.txt carries a Cloudflare-managed content-signal block
(`search=yes, ai-train=no`) and a site block disallowing `/texts/`,
`/misc/` and `/Lite/` to all agents; the crawl rests on the maintainer's
direct permission above.

## Quirks the fixtures pin

- Polytonic Greek keyed with the Greek Extended OXIA vowels (U+1F71 …
  U+1F7D) and ANO TELEIA (U+0387) — NFC folds them to the tonos vowels and
  U+00B7 (Sep05: "ἀοίδιμε" carries U+1F77).
- Red `<FONT COLOR>` rubrics that span `</p>` and `<br/>` (Baptism's
  opening rubric runs over three lines).
- Melody incipits carry an inline `<a href=../../music/NNNN.mp3>ΤΟ
  ΑΚΟΥΤΕ</a>` ("listen to it") — site chrome, dropped from the text.
- Every page ends in a Cloudflare email-protection `<script>` — stripped.
