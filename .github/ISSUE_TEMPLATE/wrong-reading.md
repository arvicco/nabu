---
name: Wrong reading
about: Report a passage where what nabu shows differs from the source — the philologist's defect report.
title: "Wrong reading: "
labels: wrong-reading
---

<!--
Two kinds of divergence arrive here, and they are triaged differently:
a parse defect (nabu misreads a correct upstream file) is a bug and gets
fixed with a regression fixture; an upstream defect (the source file
itself differs from the print edition) is recorded honestly — canonical
means canonical, nabu never silently "corrects" upstream text; such
corrections belong to the enrichment layer. Both reports are welcome.
-->

## URN

The passage or document URN, as `nabu show` accepts it (e.g.
`urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1`).

## What nabu shows

Paste the relevant `nabu show <urn>` output verbatim.

```
(output)
```

## What the source shows

The reading as the upstream file or the print edition actually has it,
quoted exactly — with a link to the upstream file (line number if
possible) or a bibliographic reference to the printed page.

> (source reading)

## Edition context

Which edition or witness is this (editor, year, siglum if relevant)? If
you can tell, does the divergence originate upstream (source file differs
from the print edition) or in nabu's parse (source file is correct, nabu's
text is not)?
