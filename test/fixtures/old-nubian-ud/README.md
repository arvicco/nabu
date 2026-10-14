# old-nubian-ud fixtures

`OldNubian.conllu` — ten real sentence blocks of the Old Nubian UD
treebank (Innokentii Smirnov), byte-verbatim (every comment and token
line intact; blocks separated by one blank line as upstream), selected
from the repository's single treebank file:

https://raw.githubusercontent.com/Innokentii-Smirnov/OldNubianUDTreebank/64a7b043b42dc0c776c320407de7856b44db4445/OldNubian.conllu

Retrieved 2026-10-14 (upstream HEAD 64a7b043, "Add a license",
2026-10-13; the full file is 124 sentences, 187,611 bytes).

License — the repository's LICENSE.txt, verbatim: "The treebank is
licensed under the Attribution-NonCommercial-ShareAlike 4.0
International." (CC BY-NC-SA 4.0; https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode).
These blocks are redistributed under it. Credit: Innokentii Smirnov,
Old Nubian UD Treebank.

Selected sent_ids (file order) and what each documents:

- `0`, `1`, `2` — the opening of the Miracle of Saint Menas (sentence 0
  is its incipit): multiword-token ranges (`3-6`), the MISC morpheme
  layer (Gloss / MGloss / MSeg), Russian translations.
- `6` — upstream is not NFC here: `ǧ` written as g + U+030C in the text
  comment and in the token lines.
- `75` — the homily (English translation lane): a lacuna `[*****]` in
  the text and in a token form.
- `100`, `106` — `CorrectForm=` MISC fields (the annotator's emendation).
- `118` — restoration brackets (`[p]`, `[kon]`) and an EMPTY
  `# translation =`.
- `121` — the Emmanuel verse ("And they called him Emmanuel.").
- `124` — the file's last sentence, empty translation.

Re-cut: fetch the URL above and keep the blocks whose `# sent_id` is in
the list, verbatim and in file order.
