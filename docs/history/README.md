# docs/history — the frozen early record

Two large files from Nabu's first two months live here. Both are
**frozen**: kept verbatim, never updated, and not a description of how the
project works today.

| File | Frozen | What it is |
|---|---|---|
| [`backlog.md`](backlog.md) | 2026-07-23 | The flat packet backlog that coordinated the dev loop from Phase 0 (the scaffold, 2026-07-03) through P43 — every packet with its tier, status, dependencies, Goal and Acceptance text, plus the phase plan blocks and design notes written beside them. |
| [`worklog.md`](worklog.md) | 2026-08-02 | The completion journal: one line per finished packet or gate (date · packet · commit · notes), newest first, ending at the P55 gate and the synchronized Nabu v1.4.0 / nabu-data v1.0.0 release. |

## Why frozen

In the loop's first weeks the backlog file was the entire coordination
state: a session picked the next `ready` packet, implemented it, flipped
its status, and appended a worklog line. As phases grew to dozens of
packets with parallel agents, riders, and owner rulings, the one flat file
became the bottleneck (and passed 700 KB). The coordination moved to a
per-phase board — a plan document per phase, a work queue, and a decision
register — kept outside the public tree, with the **phase-gate pull
request** as the public record of each phase. The backlog stopped receiving
packets after P43; the worklog's last line records the P55 gate.

The files moved from `docs/` to `docs/history/` on 2026-10-11 so the
`docs/` folder lists the living documentation first. Their contents are
unchanged apart from a frozen-record banner at the top of each.

## Reading them

- Figures, paths, and statuses are as of the day each line was written;
  many have since changed (sources were added, commands renamed, numbers
  grew by an order of magnitude). Check the living docs —
  [`../README.md`](../README.md) is the index — before relying on any claim.
- Packet ids (`P12-3`, `P42-6`, …) are still cited in code comments as
  design provenance; search these files for the id to find the original
  Goal/Acceptance text.
- The current process is [`../dev-loop.md`](../dev-loop.md).
