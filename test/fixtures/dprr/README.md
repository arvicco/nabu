# DPRR fixtures (Digital Prosopography of the Roman Republic, CC BY-NC 4.0)

Retrieved 2026-10-27 from the project's public SPARQL endpoint,
`https://romanrepublic.ac.uk/rdf/endpoint/` (Accept:
`application/sparql-results+json`), with the two SELECT queries the
adapter itself sends (`Nabu::Adapters::Dprr::PERSONS_QUERY` /
`DATES_QUERY`). The live answers held 4,876 person rows (one per
`:Person`, no duplicates) and 1,917 date assertions.

Trimmed to four persons, every binding verbatim (re-indented only):

- `Person/1` — L. Iunius Brutus (IUNI0001): praenomen + nomen +
  cognomen + filiation; birth -540 (interval S, uncertain) and violent
  death -509 (S).
- `Person/146` — `-. (Furius?) Carve(tus)` (FURI0146): the unknown
  praenomen placeholder `-.`, an uncertain parenthesised nomen and a
  partly restored cognomen; death -458 (S).
- `Person/1016` — L. Cornelius Scipio Asiaticus (CORN1016): an
  `otherNames` agnomen beside the cognomen; birth -230 (S, uncertain).
- `Person/1698` — Aemilia (AEMI1698), a Vestal: female, nomen-only
  name; birth "before -140" (interval B — not a year) and violent
  death -114 (S).

## Delivery grains

The endpoint serves the whole triple store; DPRR's entity types are
Person, PostAssertion (offices), StatusAssertion (senatorial/equestrian
status), RelationshipAssertion (kinship), DateInformation, and the
authority lists (Praenomen, Sex, Office, SecondarySource, …). The
adapter takes the Person grain (one person-index row each) and the
DateInformation grain restricted to persons (birth/death years). Posts,
statuses and relationships are not fetched — declared scope, not a
silent drop: the person index has no office or kinship lane.

Re-cut recipe: run the two adapter queries against the endpoint and
keep the bindings whose `person` is one of the four URIs above.
