---
title: "The commons wave: Wikisource, the Diet Library, and the Luwian corpus"
date: 2026-10-01 07:17:00 +0000
description: >-
  Two Wikisource cones and the National Diet Library's classical OCR
  mass open the East Asian commons lane; the Annotated Corpus of
  Luwian Texts arrives by the editor's grant as the library's 174th
  source; Early Middle Japanese becomes a real answer; and the
  fulltext index learns both restraint and bulk manners.
---

Three phases since the Central Asia wave, and most of the growth came
from the commons — the great volunteer-transcribed and
national-library collections that sit in plain sight. Plus one
corpus that could only arrive by asking.

**The Chinese cone.** Chinese Wikisource joins as a censused-works
source: the complete *Quan Tangwen* (全唐文, all 1,001 juan — the
verified delta over the held Kanripo mass, whose copy is partial),
the *Xu Zizhi Tongjian* (續資治通鑑, 221 juan), and the *Secret
History of the Mongols* in its Ming-era Chinese paraphrase (元朝秘史
— the census confirmed no Middle Mongol transcription is hosted, so
the work claims the Ming vernacular it actually is). The 全唐文 juan
pages are transclusion shells whose ~20,000 piece pages the fetch
expands offline into each envelope, so a re-parse never touches the
network. A follow-up scrub removed the magic-word junk the MediaWiki
markup leaks (`__NOEDITSECTION__` lines had become "passages") and
taught the parser that header templates stack — recovering titles
and author claims (續資治通鑑: 畢沅) across two hundred juan. The
cone stands at 71,547 passages; the texts are public domain, the
transcription layer CC BY-SA 4.0, credited to the Wikisource
contributors.

**The Japanese cone.** Japanese Wikisource arrives as an era cone:
every page reachable from the eight premodern era categories, 飛鳥
through 江戸. The *Man'yōshū* volumes get their own block grammar —
the man'yōgana 原文 is the passage text in Old Japanese, with the
kundoku reading and kana layers riding as annotations and each
poem's own 歌番号 as its citation (variant verses keep their letter
suffixes; stripping them turned out to collide identifiers, which
the census caught on the third volume). Each page's era categories
band an honest era-attribution date — never a typed year — and its
stated 底本 base edition rides verbatim, else "unstated".

Then the cone doubled. Two classes of page hold no text of their
own: ProofreadPage scan transclusions (`<pages index>`, whose text
lives page-by-page in the Page: namespace) and parameterized
dispatcher pages, where a volume renders entirely from a sibling
page's template machinery. The fetch now expands both — the scan
shells by walking their declared page ranges, the dispatchers by
asking MediaWiki itself to expand the templates server-side — and
the parser strips the rendered furniture: navigation boxes, tables
of contents, ruby readings (the base text stays), scan-page anchors.
Heading links become section annotations. The source went from 530
to 838 documents and 88,745 passages; among the recovered texts is
芭蕉俳句全集, a complete Bashō haiku collection of 2,206 verses.

**The Diet Library's classical stacks.** The National Diet Library's
次世代デジタルライブラリー serves machine-OCR full text for its
digitized classical materials, and NDL Lab confirmed the bulk route
by email (2026-09-29). The library's census found 97,731
copyright-expired items in the NDL's own open bibliographic dataset;
a resumable crawl now walks them at a deliberately gentle committed
pace, a few hundred books per phase, refusals ledgered and never
retried. The shelf stands at 7,966 books and 135,116 koma (scanned
frames) of OCR text so far, every document carrying its
machine-OCR nature label and its permalink back to the NDL viewer —
both promised in the access request. Honest footnote: the latest
stretch of the ID space crossed an ukiyo-e corner of the collection
— single-sheet Hiroshige prints of the 江戸名所 series, one koma
apiece — so the frame count grew modestly while the book count
soared. The crawl continues.

**The Luwian corpus.** The library's 174th source could not be
fetched from anywhere: the Annotated Corpus of Luwian Texts (ACLT,
luwian.web-corpora.net) — the annotated edition of the Hieroglyphic
Luwian inscriptions — arrived by the editor's personal grant (Ilya
Yakubovich, by email, 2026-09-28/29, with the corpus files prepared
by the platform's developer, Timofey Arkhangelskiy). It is held as a
personal research copy, never redistributed. 266 inscriptions, 2,682
clause units, each clause in two paired representations: a broad
transcription carrying full morphology — lemma, part of speech,
case/gender/number, English glosses — and a sign-by-sign
transliteration of the hieroglyphs. Iron Age Anatolia's monumental
language joins the Hittite desk, which now spans five corpora from
Old Hittite to the Luwian inscriptions.

**Early Middle Japanese becomes an answer.** The classical Japanese
of the Heian court — the language of the *Genji* — is now a real
language-stage claim, not a bare "Japanese": the Genji TEI corpus,
the NIJL/Kokubunken text, and the Heian-band Wikisource documents
are staged onto Early Middle Japanese, 220 documents answering for
the stage. In the same spirit of layered honesty, the SBL Greek New
Testament's own apparatus now rides its verses: per-verse variant
readings with their witness sigla (WH, Treg, NA28, RP), carried
verbatim down to the upstream's non-breaking spaces.

**The index learns manners.** Two fulltext-engine improvements, both
born of measurement. First, restraint: a re-parse that changes no
passage content — a metadata reconcile, an idempotent re-run — used
to pay a full rewrite of the source's index slice; for the largest
sources that meant hours of disk churn to re-derive nothing. The
index now proves nothing passage-visible changed and says "skipped"
in about a second. Second, bulk manners: when a big slice genuinely
must be rewritten (millions of rows), the engine now defers all
B-tree merging during the storm and consolidates afterwards in one
announced pass — SQLite's own recipe, applied with a crash-safe
restore. One honest flag remains on the board: a whitespace-class
parser bug (an ideographic space that ASCII trimming cannot see)
had quarantined 35 sutras of the Chinese Buddhist canon; the bug is
fixed and the sutras recover wholesale at the next rebuild.

**The numbers, as of this gate:** 2,314,083 documents · 107,759,513
passages · 174 live sources.
