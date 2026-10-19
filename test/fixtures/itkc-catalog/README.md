# itkc-catalog fixtures

Trimmed from REAL responses of the 한국고전종합DB OpenAPI (Institute for
the Translation of Korean Classics), the keyless search endpoint
`https://db.itkc.or.kr/openapi/search`, retrieved 2026-10-19. One file per
response page, named by its `start` offset under its 서지 section, exactly
the layout `Adapters::ItkcCatalog#fetch` writes:

- `MO_SJ/0000.xml` — `?secId=MO_SJ&start=0&rows=1000` (한국문집총간 서지,
  totalCount 1259; the full page held 1,000 docs / 631,371 bytes), trimmed
  to 5 docs: ITKC_MO_0001A 계원필경집 (최치원, birth 857, death the 9999
  unknown sentinel, 간행년 1834), ITKC_MO_0003A 서하집 (임춘, birth the 0
  unknown sentinel AND death 9999, 간행년 1713), ITKC_MO_0004A
  동국이상국집 (이규보 1168–1241, 간행년 "미상"), ITKC_MO_0009A 홍애유고
  (홍간, birth 0, death 1304), ITKC_MO_0672A 괴은유고 (정구, birth 1490,
  death 9999, 간행년 "미상" — the one shape that bounds nothing above).
- `MO_SJ/1000.xml` — `?secId=MO_SJ&start=1000&rows=1000` (the full page
  held 259 docs / 161,969 bytes), trimmed to 3 docs: ITKC_MO_1247A 총쇄
  (오횡묵 1834–1906), ITKC_MO_1250A 심석재집 (송병순 1839–1912, 간행년
  1912 — matches the 원문간행년 in the held itkc 서지 sidecar
  ITKC_MO_1250A.xml), ITKC_MO_1255A 농산집 (신득구 1850–1900).
- `GO_SJ/0000.xml` — `?secId=GO_SJ&start=0&rows=1000` (고전원문 서지,
  totalCount 257, all on one page), trimmed to ITKC_GO_1432A 임하필기
  (이유원 1814–1888).
- `KP_SJ/0000.xml` — `?secId=KP_SJ&start=0&rows=1000` (한국고전총간 서지,
  totalCount 24), trimmed to ITKC_KP_C004A 국조인물고 (author "미상|",
  birth 0, death 9999, 간행년 미상 — wholly undatable).

Trim rule: the response header (secId/keyword/start/rows/totalCount) and
every kept `<doc>` block are byte-verbatim; only the other docs are
dropped, so the header's totalCount still states the upstream census.

Upstream facts the fixtures pin: `rows` is capped at 1000 by the server
(a `rows=1300` request answered `rows` 1000); 저자생년 "0" and 저자몰년
"9999" are the catalog's unknown sentinels (MO_SJ census: 8 zero births,
18 9999 deaths over 1,259 records); 간행년 is a year or the prose "미상"
(213 of 1,259 MO records).

Never hand-edit; re-trim from fresh API responses.
