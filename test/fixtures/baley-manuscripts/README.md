# baley-manuscripts fixture

Retrieved 2026-11-02 from two of Julien Baley's nine Zenodo deposits,
by HTTP Range reads of the deposit zips (the image crops never
transferred):

| subdir | record | file |
|---|---|---|
| `jinteng/` | https://zenodo.org/records/23870159 (v1.0.0, 2026-11-01) | jinteng-alignment-dataset-1.0.0.zip (54,693,674 bytes, md5 df97d4c4…) |
| `aisong/` | https://zenodo.org/records/22983015 (v1.0.0, 2026-09-26) | aisong-alignment-dataset-1.0.0.zip (38,751,270 bytes, md5 f2691b41…) |

Each subdir is a subset of what `Nabu::ZipRangeFetch` lands (the zip's
top directory stripped): `dataset/manifest.json`, `dataset/alignment.json`,
each witness's `transcription.json` and (manuscript witnesses)
`source_mapping.json`, all WHOLE and byte-identical; plus LICENSE.md,
README.md, CITATION.cff, docs/data-dictionary.md and
witness-images/RIGHTS.md. The fetch also keeps CHANGELOG.md,
CONTRIBUTORS.md, VERSION and the other docs/ files, not copied here.

`fetch/jinteng-subset.zip` is eleven real Jinteng members repacked with
zip(1) (the container is test scaffolding, the member bytes upstream's),
served by a Range-honouring stub in `test/zip_range_fetch_test.rb`. No
manuscript image is checked in: the crops are distributed "under specific
publication permission" (witness-images/RIGHTS.md), not under CC BY.

## Delivery grains (every grain a deposit serves; census of all nine)

| grain | taken? |
|---|---|
| manuscript witness transcription (`dataset/<w>/transcription.json`) | TAKEN — one document; passage = line |
| edition witness (a scholar's reading: Chen Qi, Qiū Ruìfēng) | TAKEN — one document |
| received-text witness (Shangshu, Yizhoushu, Wang Bi, Analects, Mao Shi, Liji …) | rejected, skipped by rule — held via kanripo (`jinteng/dataset/shangshu/` is the pinned specimen) |
| alignment groups (`alignment.json`) | mined into line annotations (`aligned`) |
| graph → slip mapping (`source_mapping.json`) | mined into line annotations (`strips`) |
| image geometry (strip/character mappings, expected_media.json) | never fetched |
| image crops (`witness-images/<w>/…`), fonts, viewer, tools, schemas | never fetched |
| superseded transcription (Fuyang `transcription_previous.json`) | never fetched |

## Census (2026-11-02, all nine deposits by Range)

40,031 zip members, 39,764 images; ~20 MB of kept text of ~2 GB.
Taken: 19 witnesses / 4,626 lines — aisong 2 (34 + 34), caomozhizhen 2
(376 + 399), jigong 1 (38), jinteng 1 (30), laozi 4 (1,099 + 221 + 97 +
67), lunyu 3 (41 + 78 + 465), shaner 2 (131 + 131), shentudi 2 (106 +
106), shijing 2 (788 + 385). Rejected by rule: 13 received-text
witnesses. Graph counts follow the deposits' validator and match each
data dictionary except Shangbo (1,794 counted by upstream's own
tokenizer vs the dictionary's 1,795).
