# docs/history — the early record, retired

Two large files from Nabu's first two months — the flat packet backlog
(frozen 2026-07-23, after P43) and the completion worklog (frozen
2026-08-02, at the P55 gate) — lived here verbatim until 2026-11-03.
They were working records, not documentation: per-packet state, design
notes, and process narration from the era before the coordination moved
to per-phase boards kept outside the public tree, with the **phase-gate
pull request** as the public record of each phase.

On 2026-11-03 both files were retired from the public tree (they are
preserved privately): internal working records belong off the public
surface, whatever their age.

What remains true for readers of the code:

- Packet ids (`P12-3`, `P42-6`, …) cited in code comments as design
  provenance refer to entries in that retired backlog — they date and
  name the design decision, and the adapter or test beside the comment
  carries the decision's substance.
- The current process is [`dev-loop.md`](../dev-loop.md); the living
  documentation index is [`README.md`](../README.md).
