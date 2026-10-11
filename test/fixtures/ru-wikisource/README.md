# ru-wikisource fixtures

Real api.php captures from ru.wikisource.org, retrieved 2026-10-10,
stored in the adapter's own envelope shape (`pages/<pageid>.json`:
title/pageid/ns/revid/timestamp/wikitext verbatim + the fetch's "cone"
provenance + "html", the `action=parse&oldid=<revid>` rendering, only
on pages the wikitext rules admit). Chosen for the edition filter's
real cases:

- `pages/433334.json` — Повесть временных лет (Нестор)/1997 (ДО): the
  ruled taint case (ИСТОЧНИК: Творогов's text in the 1997 Библиотека
  литературы Древней Руси; ДАТАПУБЛИКАЦИИ 1997). Wikitext TRIMMED to
  the {{Отексте}} header + the opening lines (627,072 → 4,158 bytes,
  cut at a line boundary); no rendering.
- `pages/54545.json` — Слово о погибели Русской земли/ДО: keys to
  "Библиотека литературы Древней Руси, т. 5" with no year (the
  named-series arm of the rule). Whole wikitext; no rendering.
- `pages/1101386.json` — Стихотворения (Шаховской): an az.lib.ru
  import whose header names only the website while the body opens with
  its source book's imprint (Виршевая поэзия, М., 1989) — the body-head
  arm of the rule. Wikitext TRIMMED to the header + the body head
  (56,345 → 3,158 bytes, line boundary); no rendering.
- `pages/34445.json` — Слово о полку Игореве (Жуковский): a
  translation (ПЕРЕВОДЧИК filled). Wikitext TRIMMED to the header +
  opening (44,988 → 3,964 bytes, line boundary); no rendering.
- `pages/473330.json` — Поучение Владимира Мономаха/Поучение
  детям/1893/ВТ: the modern-orthography duplicate class. Whole
  wikitext; no rendering.
- `pages/34424.json` — Слово о полку Игореве/Текст: ADMITTED, the 1800
  editio princeps. Wikitext TRIMMED to the header + opening (33,399 →
  2,704 bytes, line boundary); rendering TRIMMED at the first </p>
  under 22,000 bytes (48,976 → 18,408).
- `pages/293263.json` — Хвала о церкве (Аввакум): ADMITTED, a
  web-sourced page naming no edition ("unstated"-class statement,
  ДАТАСОЗДАНИЯ 1670). Whole.

Re-cut: fetch each title's current revision via api.php
(prop=revisions, rvslots=main) and, for admitted pages, action=parse
with oldid=<revid>; re-apply the stated trims.
