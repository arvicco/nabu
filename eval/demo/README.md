# Demo eval pack

`pack.yml` is a deterministic tool-use eval over the **frozen demo slice**
baked into the public image `ghcr.io/arvicco/nabu-demo` (see the
`Dockerfile` `demo` target and `Nabu::DemoBuild`): the SBL Greek New
Testament, the Clementine Vulgate, the World English Bible, the Open
Scriptures Hebrew Bible and the LSJ + Lewis & Short lexica — 223 documents,
104,585 passages, 168,142 dictionary entries.

Each of the 36 tasks pairs a natural-language question with:

- `answer` — the reference answer in words, for grading an agent;
- `steps` — the reference MCP tool calls (`tool` + `args`);
- `expect` — machine checks on each tool reply: expected URNs, substrings,
  counts and structured fields. No task is scored by model judgment.

All 14 MCP tools are covered; search, show, parallels and define carry the
most weight. Difficulty is `lookup`, `chain` (a later call consumes an
earlier answer through a `${N.path}` argument, e.g. search → show,
clarify → parallels, concord → define) or `negative` (the honest answer is
"nothing here": an absent word, a missing verse, a layer or module the
slice does not carry). The check grammar is documented in
`lib/nabu/ops/demo_eval.rb`.

## Running it

The runner, `script/demo-eval`, needs only a stdlib Ruby (no bundle). It
replays every task against a server and prints PASS / FAIL / ERROR per
task plus a summary; the exit status is 0 only when every task passes.

Against the published image over stdio (the default target):

```
docker pull ghcr.io/arvicco/nabu-demo:latest
ruby script/demo-eval --image ghcr.io/arvicco/nabu-demo:latest
```

Against the image in HTTP mode:

```
docker run --rm -p 8080:8080 ghcr.io/arvicco/nabu-demo:latest bin/nabu mcp --http
ruby script/demo-eval --url http://localhost:8080/mcp
```

Against a local server pointed at a demo slice built by `rake demo:build`:

```
ruby script/demo-eval --command "env NABU_ROOT=tmp/demo NABU_CONFIG=tmp/demo/config/nabu.yml bin/nabu mcp"
```

Other options:

- `--only id1,id2` runs a subset;
- `-- ARGS` passes extra `docker run` flags (e.g. `-- --memory=512m`);
- `--questions` prints only the ids and questions as JSON (no server),
  the input for evaluating an agent end to end — grade its answers against
  `answer` and the checks.

`bundle exec rake demo:eval` forwards to the same runner (`IMAGE`,
`MCP_URL` or `MCP_COMMAND` picks the target; `ONLY` narrows).

## Scope

Ground truth comes from the slice, not the full library. The expected
answers are pinned to that corpus snapshot; a rebuilt slice with changed
upstream text can move a count or a ranking, and the pack moves with it.
The suite (`test/ops/demo_eval_pack_test.rb`) keeps the pack well-formed,
requires every tool to be covered, and refuses any URN outside the slice's
sources.
