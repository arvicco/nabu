# nabu-places fixtures

TRIMMED REAL copy of the sibling registry (~/Dev/nabu-places, the P63-6
seed wave), pinned 2026-08-08 for the read-seam tests and the drift guard
(the nabu-lects fixture pattern).

- `names.yml`: cdli 5 rows (exact matches, the `?`-suffix alias
  "Girsu (mod. Tello) ?", the low-certainty direct match
  "Nereb (mod. Neirab) ?") + oracc 4 rows — real decision rows verbatim.
- `namespaces.yml`: the whole real file (4 namespaces + id shapes).

Re-trim from the sibling repo when its schema moves; the drift-guard test
validates these rows under the same rules as the upstream bin/validate.
