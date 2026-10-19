# kaikki etymology-template fixtures

Two whole, byte-identical records from kaikki.org's **Old Turkic** extract
(`kaikki.org-dictionary-OldTurkic.jsonl`, wiktextract's English Wiktionary
extraction — CC-BY-SA + GFDL, the license of every kaikki fixture here),
re-cut 2026-10-19 from the box's `canonical/wiktionary-recon/old-turkic/`
copy of
https://kaikki.org/dictionary/Old%20Turkic/kaikki.org-dictionary-OldTurkic.jsonl.

Kept: 𐱅𐰭𐰼𐰃 (noun) and 𐰆𐰍𐰞𐰣 (noun) — the two shortest records whose
`inh` etymology template carries Wiktionary's INLINE MODIFIERS in the
etymon argument (`*teŋri<alt:*täŋri>`, `*oglan<t:children>`): the word is
the text before the first `<`. Both name Proto-Turkic (`trk-pro`), a
language with no held shelf — the dangling-edge pin. Used by
`test/adapters/wiktionary_jsonl_parser_test.rb` only.
