# Quickstart — zero to first search

Prefer the smallest possible start? A single source works too:

```
bin/nabu sync sblgnt
```

This fetches the upstream snapshot into `canonical/sblgnt/` (~11 MB on
disk) and loads it into the catalog. On the reference box the entire first
run — fetch, parse, load — took **about 3 seconds** and ended with 27
books / 7,939 verses loaded, plus a `discovery:` accounting line (selected
· skipped-by-rule · quarantined · unrecognized) so nothing is silently
dropped.

Check the shelf:

```
$ bin/nabu status
…
vulgate             m           ?REPROBE     73/36K  08-14 08:12 +73
eng-web             m           ?REPROBE     84/38K  08-14 08:12 +84
sblgnt              m                       27/7.9K  08-14 08:12 +27
…
```
## 4. Read a passage

Every hit is a URN; `show` renders a passage, a whole document, or a
citation range:

```
$ bin/nabu show urn:nabu:sblgnt:john:1.1-1.3
urn:nabu:sblgnt:john — ΚΑΤΑ ΙΩΑΝΝΗΝ [grc]
  source: sblgnt   license: attribution   revision: 1
  range: urn:nabu:sblgnt:john:1.1 … urn:nabu:sblgnt:john:1.3  [3 of 878 passages]
    :1.1  Ἐν ἀρχῇ ἦν ὁ λόγος, καὶ ὁ λόγος ἦν πρὸς τὸν θεόν, καὶ θεὸς ἦν ὁ λόγος.
    :1.2  οὗτος ἦν ἐν ἀρχῇ πρὸς τὸν θεόν.
    :1.3  πάντα διʼ αὐτοῦ ἐγένετο, καὶ χωρὶς αὐτοῦ ἐγένετο οὐδὲ ἕν. ὃ γέγονεν
```

Every query command documents itself with worked examples: `bin/nabu help
search`, `help show`, `help align`, `help export`.
