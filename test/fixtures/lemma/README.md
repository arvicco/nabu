# lemma fixtures (P84-1 — the silver-lemma enricher)

- `fake_worker.rb` — the suite's protocol-identical stand-in for
  `script/stanza_lemma_worker.py`: deterministic toy lemmatizer, no
  Python/venv/model (the enricher-tests-stub-model-calls rule at
  subprocess grain). Lives here rather than `test/support/` because
  support files are auto-required and this one RUNS a protocol loop.
- `worker_ready.jsonl` / `worker_response.jsonl` — the recorded-shape
  fixtures (one per protocol message kind): REAL output of the real
  worker (stanza 1.14.0, la:ittb_nocharlm, CPU) recorded 2026-08-27
  during the P84-1 smoke run, texts "In fronte pedes VI in agro pedes X"
  and "Dis Manibus sacrum". Response parsing is tested against these
  exact bytes so the Ruby side can never drift from what Stanza actually
  emits.
