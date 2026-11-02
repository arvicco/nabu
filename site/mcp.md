---
title: MCP — ask your model
permalink: /mcp/
description: >-
  Run the Nabu demo MCP server in one command or one click — Docker,
  Claude Code, VS Code, Cursor, Docker's MCP Toolkit, or a hosted
  deploy — over a baked open slice of the library.
---

The MCP server itself — its fourteen tools, worked examples, and how to
wire it to your own full library — is documented in the Tools page:
[**Ask your model**]({{ '/tools/#ask-your-model' | relative_url }}).
This page is the shortcut to the **demo**.

## Run the demo

The public image `ghcr.io/arvicco/nabu-demo` bakes an open demo slice of
the library — Greek New Testament, Hebrew Bible, Latin Vulgate, World
English Bible, LSJ and Lewis & Short; the sources and their per-source
licenses are listed in `/demo/demo-census.json` inside the image — behind
the read-only MCP server. No clone and no sync; the full library is a
local build ([Quickstart]({{ '/quickstart/' | relative_url }})).

**Docker (stdio):**

```
docker run -i --rm ghcr.io/arvicco/nabu-demo
```

**Claude Code:**

```
claude mcp add nabu -- docker run -i --rm ghcr.io/arvicco/nabu-demo
```

**Editors, one click** (both need Docker installed locally):

- [Install in VS Code](vscode:mcp/install?%7B%22name%22%3A%22nabu%22%2C%22command%22%3A%22docker%22%2C%22args%22%3A%5B%22run%22%2C%22-i%22%2C%22--rm%22%2C%22ghcr.io%2Farvicco%2Fnabu-demo%22%5D%7D)
  (or through the [vscode.dev redirect](https://vscode.dev/redirect/mcp/install?name=nabu&config=%7B%22command%22%3A%22docker%22%2C%22args%22%3A%5B%22run%22%2C%22-i%22%2C%22--rm%22%2C%22ghcr.io%2Farvicco%2Fnabu-demo%22%5D%7D))
- [Add to Cursor](cursor://anysphere.cursor-deeplink/mcp/install?name=nabu&config=eyJjb21tYW5kIjoiZG9ja2VyIiwiYXJncyI6WyJydW4iLCItaSIsIi0tcm0iLCJnaGNyLmlvL2FydmljY28vbmFidS1kZW1vIl19)
  (or through the [cursor.com redirect](https://cursor.com/install-mcp?name=nabu&config=eyJjb21tYW5kIjoiZG9ja2VyIiwiYXJncyI6WyJydW4iLCItaSIsIi0tcm0iLCJnaGNyLmlvL2FydmljY28vbmFidS1kZW1vIl19))

**Docker Desktop's MCP Toolkit** — a one-entry custom catalog
([docker-mcp-catalog.yaml]({{ '/docker-mcp-catalog.yaml' | relative_url }})):

```
docker mcp catalog import https://arvicco.github.io/nabu/docker-mcp-catalog.yaml
# current Toolkit CLIs, which replaced `import`:
docker mcp catalog create nabu --from-legacy-catalog https://arvicco.github.io/nabu/docker-mcp-catalog.yaml
```

**Over HTTP** (streamable HTTP; `PORT` sets the port, default 8080):

```
docker run --rm -p 8080:8080 ghcr.io/arvicco/nabu-demo bin/nabu mcp --http
# endpoint: POST http://localhost:8080/mcp
```

### Hosted, one click

Both buttons run the same prebuilt image as an HTTP endpoint at
`https://<your-service>/mcp`; nothing is built on the host. The demo
answers comfortably within a 512 MB free instance.

- [Deploy to Render](https://render.com/deploy?repo=https://github.com/arvicco/nabu)
  (reads the repo's `render.yaml`). Render's free instances sleep after
  about fifteen minutes idle, and the first request after that waits
  roughly a minute while the instance wakes.
- [Deploy to Koyeb](https://app.koyeb.com/deploy?type=docker&name=nabu-demo&image=ghcr.io/arvicco/nabu-demo:latest&instance_type=free&ports=8080;http;/&env[PORT]=8080&command=bin/nabu&args=mcp&args=--http).
  Koyeb's free instance scales to zero when idle, so the first request
  after a quiet spell pays a cold start of several seconds.

Every tool is read-only; the license class rides on every payload.
