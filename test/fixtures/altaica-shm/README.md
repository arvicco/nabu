# altaica-shm fixtures

Retrieved 2026-09-28 from altaica.ru/SECRET/SH-24UP.pdf — Street's
Text of the Secret History of the Mongols, Version 24 (10 Oct 2013),
"Copyright John C. Street 1985-2013". USE GRANTED by the Monumenta
Altaica maintainer by email, 2026-09-27 ("Yes, you can use it… the
late prof. Street… always wanted free propagation of his works").
Fixture = pages 1+3+4 of the real PDF via mutool merge (60 numbered
lines).

Shape (text layer): front matter documents Street's OWN ASCII
substitutions for searchability (6 = ŋ, @ / + / ^ / " for special
letters — served verbatim, the table recorded in source metadata);
then one line per Street line number (4 digits, 1010–9492), section
markers "(§N)" inline, footnote pointers sometimes GLUED to the line
number (e.g. "10951" = line 1095, fn 1); a trailing apparatus section
("114. C Y435 …") is excluded from passages, censused.

The Kozin transcription page (e_oldmng.php) is a JS shell as of
2026-09-28 — recorded residue, not fetched.

`SH-24UP.textlayer.txt` — the RECORDED mutool extraction of the
fixture PDF (`mutool draw -F txt -o -`, mutool 1.26, 2026-09-28),
checked in so the suite never depends on mutool being installed
(the local-library law). The guarded live test pins agreement; if
mutool output drifts across versions, re-cut this file with the
command above and eyeball the diff.
