# P84-1: the silver-lemma enricher's model worker — a thin line-oriented
# JSONL server over Stanza (tokenize,pos,lemma), CPU. Nabu's Ruby runner
# (Nabu::LemmaEnrich, via Nabu::Shell.duplex) keeps ONE worker alive per
# campaign (model load costs ~10s) and feeds it passage batches; the
# worker answers raw [surface, lemma, upos] triples and keeps NO state —
# resumability, shelf writes and provenance are the Ruby side's job.
#
# Runs inside the owner-bootstrapped venv (docs/manual/silver-lemma-venv.md);
# never invoked by the test suite (tests speak the same protocol to a fake
# worker).
#
# Protocol (one JSON object per line, stdin -> stdout):
#   ready:    {"ready": true, "worker": "stanza", "version": "1.14.0",
#              "lang": "la", "lemma_model": "<model file stem>"}
#   request:  {"id": 1, "texts": ["...", ...]}
#   response: {"id": 1, "results": [[["form", "lemma", "upos"], ...], ...]}
#   error:    {"id": 1, "error": "..."}   (the runner aborts the campaign)
# EOF on stdin ends the worker cleanly.

import argparse
import json
import os
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lang", required=True, help="stanza language code (e.g. la)")
    parser.add_argument("--model-dir", required=True, help="stanza resources dir")
    parser.add_argument("--package", default="default", help="stanza package")
    args = parser.parse_args()

    import stanza  # deferred: argparse errors must not require the model stack

    nlp = stanza.Pipeline(
        args.lang,
        dir=args.model_dir,
        package=args.package,
        processors="tokenize,pos,lemma",
        use_gpu=False,
        verbose=False,
        download_method=None,  # never the network: models are pre-fetched
    )
    lemma_model = ""
    try:
        path = nlp.processors["lemma"].config.get("model_path", "")
        lemma_model = os.path.splitext(os.path.basename(path))[0]
    except (KeyError, AttributeError):
        pass

    emit({"ready": True, "worker": "stanza", "version": stanza.__version__,
          "lang": args.lang, "lemma_model": lemma_model})

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        request = json.loads(line)
        try:
            docs = nlp.bulk_process(request["texts"])
            results = [
                [[w.text or "", w.lemma or "", w.upos or ""]
                 for s in d.sentences for w in s.words]
                for d in docs
            ]
            emit({"id": request["id"], "results": results})
        except Exception as e:  # surface, don't die: the runner decides
            emit({"id": request.get("id"), "error": f"{type(e).__name__}: {e}"})
    return 0


def emit(obj) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    sys.exit(main())
