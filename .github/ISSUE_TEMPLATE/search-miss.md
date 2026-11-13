---
name: Search miss
about: A text you know is in the library, but search does not surface it.
title: "Search miss: "
labels: search-miss
---

<!--
A search miss is its own defect class, distinct from a wrong reading:
the text is (or should be) in the library, but `nabu search` does not
return it. Common real causes: a normalization gap (accents, vowel
length, script variants folding differently in the query and the
index), a language lane missing rows it should have, or a source that
loaded but was never indexed. All three are machine-checkable once
reported — the exact query string is the whole report.
-->

## The query

The exact `nabu search` invocation, verbatim (flags included).

## What you expected to find

The passage or document you know (or believe) is in the library —
a URN if you have one, otherwise the text/work name and the wording
you searched for, as it appears in the edition.

## What came back

The search output (or "no results"), pasted verbatim.

## Where did you find Nabu? (optional)

One line — a listing, a mailing list, a colleague, a search engine.
It helps the project know which doors are worth keeping open.
