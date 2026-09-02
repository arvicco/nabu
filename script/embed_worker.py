# P93-4: the semantic-vector worker (№R-36) — a thin line-oriented JSONL
# server over sentence-transformers (intfloat/multilingual-e5-base, the
# P79-5 trial model), MPS/CPU. Vectors ship INT8-quantized (the trial's
# 6 GB tier): embeddings are unit-normalized, so round(v*127) preserves
# cosine ranking, and int8 is what sqlite-vec's distance functions scan
# natively (float16 is not — verified against the sqlite-vec API,
# 2026-09-02). Nabu's Ruby runner (Nabu::Embed, via
# Nabu::Shell.duplex) keeps ONE worker alive per campaign (model load
# costs minutes) and feeds it text batches; the worker answers base64
# int8 vectors and keeps NO state — delta selection, sha bookkeeping
# and store writes are the Ruby side's job. The E5 "passage: " input
# prefix is applied HERE, so the Ruby side shas the bare text.
#
# Runs inside the owner-bootstrapped venv (docs/manual/embed-venv.md);
# never invoked by the test suite (tests speak the same protocol to a
# fake worker).
#
# Protocol (one JSON object per line, stdin -> stdout):
#   ready:    {"ready": true, "worker": "e5", "version": "<st version>",
#              "model": "multilingual-e5-base", "dim": 768, "encoding": "i8"}
#   request:  {"id": 1, "texts": ["...", ...]}
#   response: {"id": 1, "vectors": ["<base64 of dim int8>", ...]}
#   error:    {"id": 1, "error": "..."}   (the runner aborts the campaign)
# EOF on stdin ends the worker cleanly.

import argparse
import base64
import json
import sys

MODEL_ID = "intfloat/multilingual-e5-base"
MODEL_NAME = "multilingual-e5-base"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", required=True, help="sentence-transformers cache dir")
    parser.add_argument("--batch-size", type=int, default=128)
    args = parser.parse_args()

    import numpy  # deferred: argparse errors must not require the model stack
    import sentence_transformers

    model = sentence_transformers.SentenceTransformer(
        MODEL_ID,
        cache_folder=args.model_dir,
        local_files_only=True,  # never the network: the model is pre-fetched
    )
    dim = model.get_sentence_embedding_dimension()

    emit({"ready": True, "worker": "e5", "version": sentence_transformers.__version__,
          "model": MODEL_NAME, "dim": dim, "encoding": "i8"})

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        request = json.loads(line)
        try:
            texts = ["passage: " + t for t in request["texts"]]
            vecs = model.encode(texts, batch_size=args.batch_size,
                                normalize_embeddings=True, show_progress_bar=False)
            out = [base64.b64encode(numpy.clip(numpy.round(v * 127), -127, 127)
                                    .astype(numpy.int8).tobytes()).decode("ascii")
                   for v in vecs]
            emit({"id": request["id"], "vectors": out})
        except Exception as e:  # surface, don't die: the runner decides
            emit({"id": request.get("id"), "error": f"{type(e).__name__}: {e}"})
    return 0


def emit(obj) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    sys.exit(main())
