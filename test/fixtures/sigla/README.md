# sigla fixtures

From SigLA — The Signs of Linear A: a paleographical database (Ester
Salgarella & Simon Castellan, https://sigla.phis.me), retrieved
2026-10-22. Site footer, verbatim: "Dataset and drawings are available
under the CC BY-NC-SA 4.0 license." — small samples ride public, the
damos/proiel nc precedent.

## Upstream's delivery grains (probed 2026-10-22)

- **`database.js`** (https://sigla.phis.me/database.js — 2,516,528
  bytes, Last-Modified Fri, 26 Jun 2026 06:18:15 GMT, sha256
  `cc624f14…8f1b9d`): THE artifact. Two JS variables, `signs` (the sign
  list: 376 signs) and `data` (802 inscriptions), each an OCaml Marshal
  payload written as `'"\\DDD\\DDD…"'` (every byte a decimal escape).
  The adapter takes `data`'s inscriptions as documents; the `signs`
  list is a reference table, not ingested (every attestation carries
  its own copy of the sign record).
- **The rendered pages** (`document/<id>/index.html`, `browse.html`,
  the sign and sequence pages): HTML views of the same database —
  rejected, never fetched. Specimen pinned below; the adapter counts
  it skipped-by-rule.
- **The drawings** (tablet images, per-sign crops): images, not text —
  not fetched.
- No JSON/SQL export is served (`database.json`, `data.json`,
  `db.json`, `signs.json` → 404) and no public source repository exists.

## Files

- `database.js` — `signs` BYTE-VERBATIM (the whole 77 KB line, untrimmed;
  the ocaml-marshal family's real-payload test re-encodes it
  byte-identical). `data` TRIMMED to seven inscriptions — ARKH 1a,
  HT 10a, HT 22, HT 79+83, HT 99a, KH 56, PH Wc 37a — re-encoded
  through `OcamlMarshalParser.encode`, the writer proven byte-faithful
  to extern.c on both full upstream payloads (decode → encode
  reproduces the 15,405- and 487,889-byte originals exactly). The
  trimmed Map is rebuilt as a balanced tree over the kept keys in
  OCaml string order; every document value is upstream's own,
  sharing included.
- `document/ARKH 1a/index.html` — `GET
  https://sigla.phis.me/document/ARKH%201a/index.html`, whole: the
  rejected page grain's specimen (and the reference the adapter's
  rendering is checked against: "ta pi AB16 ki a ra a su mi *118 AB24
  a pa [?] mi ki sa ne").

## Re-cut

```ruby
# full = a fresh GET of https://sigla.phis.me/database.js
P = Nabu::Adapters::OcamlMarshalParser
ids = ["ARKH 1a", "HT 10a", "HT 22", "HT 79+83", "HT 99a", "PH Wc 37a", "KH 56"]
text = File.binread(full)
vars = text.scan(/^var (\w+) = '"(.*)"';$/).to_h do |name, body|
  [name, body.scan(/\\\\(\d{3})/).map { _1[0].to_i }.pack("C*")]
end
entries = P.map_entries(P.decode(vars["data"])[0]).select { |k, _| ids.include?(k) }.sort_by { |k, _| k.b }
tree = lambda do |list|
  next [0, 0] if list.empty?
  mid = list.size / 2
  (l, hl), (r, hr) = tree.(list[0...mid]), tree.(list[(mid + 1)..])
  h = [hl, hr].max + 1
  [P::Block.new(0, [l, list[mid][0], list[mid][1], r, h]), h]
end
data = P.encode(P::Block.new(0, [tree.(entries).first]))
escaped = data.bytes.map { format("\\\\%03d", _1) }.join
signs_line = text.lines.find { _1.start_with?("var signs = ") }
File.binwrite("database.js", "/* Signs */\n#{signs_line}/* Data */\nvar data = '\"#{escaped}\"';\n")
```
