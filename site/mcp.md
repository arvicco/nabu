---
title: MCP — ask your model
permalink: /mcp/
description: >-
  Run the Nabu demo MCP server in one command or one click — Docker,
  Claude Code, VS Code, Cursor, Docker's MCP Toolkit, or a hosted
  deploy — over a baked open slice of the library.
---

{% assign mcp = site.data.mcp %}
Nabu's MCP server is read-only: a model can search, read, align, and look
things up in the library, quote what it finds, and cite it, but nothing it
does can change the collection. This page runs the **demo**, a public image
(release **{{ mcp.version }}**) with an open slice of the library baked in.
Worked research examples and wiring the server to your own full library are
on the Tools page:
[**Ask your model**]({{ '/tools/#ask-your-model' | relative_url }}).

## The tools

The server answers `tools/list` with these {{ mcp.tool_count }} tools, every
one read-only and every payload stamped with the license class of the text
it carries. Each tool's full input schema and usage notes come back from
`tools/list` itself.

| Tool | What it does |
|---|---|
{% for tool in site.data.mcp.tools %}| `{{ tool.name }}` | {{ tool.title }} |
{% endfor %}

### A sample call

One `tools/call` against the demo image (the protocol is JSON-RPC 2.0,
one object per line on stdin and stdout). The request:

```json
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"nabu_show","arguments":{"urn":"urn:nabu:sblgnt:john:1.1"}}}
```

The reply's `content[0].text` is a JSON document. Unwrapped, it reads
as follows (the `provenance` load record is trimmed here):

```json
{
  "type": "passage",
  "urn": "urn:nabu:sblgnt:john:1.1",
  "language": "grc",
  "license_class": "attribution",
  "source": "sblgnt",
  "document_urn": "urn:nabu:sblgnt:john",
  "document_title": "ΚΑΤΑ ΙΩΑΝΝΗΝ",
  "text": "Ἐν ἀρχῇ ἦν ὁ λόγος, καὶ ὁ λόγος ἦν πρὸς τὸν θεόν, καὶ θεὸς ἦν ὁ λόγος.",
  "sequence": 0,
  "revision": 1,
  "withdrawn": false,
  "provenance": [ … ]
}
```

## Run the demo

The public image `{{ mcp.image }}` serves the Greek New Testament, Hebrew
Bible, Latin Vulgate, World English Bible, LSJ and Lewis & Short through
the read-only MCP server. There is nothing to clone and no sync to run.
Every source in the image and its license are listed in
[the license table below](#what-the-demo-carries). The full library is a
local build ([Quickstart]({{ '/quickstart/' | relative_url }})).

**Docker (stdio):**

```
docker run -i --rm {{ mcp.image }}
```

**Claude Code:**

```
claude mcp add nabu -- docker run -i --rm {{ mcp.image }}
```

**Any MCP client** that reads the standard `mcpServers` configuration
(Claude Desktop's `claude_desktop_config.json`, Cursor's `mcp.json`, and
others):

```json
{{ mcp.client_config }}
```

**Check that it answers:** pipe the protocol handshake into the image. The
second line of output is the `tools/list` reply, naming all
{{ mcp.tool_count }} tools:

```
{{ mcp.verify_command }}
```

**Editors, one click** (both need Docker installed locally):

- [Install in VS Code]({{ mcp.vscode_install_url }})
  (or through the [vscode.dev redirect]({{ mcp.vscode_redirect_url }}))
- [Add to Cursor]({{ mcp.cursor_install_url }})
  (or through the [cursor.com redirect]({{ mcp.cursor_redirect_url }}))

**Docker Desktop's MCP Toolkit**: a one-entry custom catalog
([docker-mcp-catalog.yaml]({{ '/docker-mcp-catalog.yaml' | relative_url }})):

```
docker mcp catalog import https://arvicco.github.io/nabu/docker-mcp-catalog.yaml
# current Toolkit CLIs, which replaced `import`:
docker mcp catalog create nabu --from-legacy-catalog https://arvicco.github.io/nabu/docker-mcp-catalog.yaml
```

**Over HTTP** (streamable HTTP; `PORT` sets the port, default 8080):

```
docker run --rm -p 8080:8080 {{ mcp.image }} bin/nabu mcp --http
# endpoint: POST http://localhost:8080/mcp
```

### Hosted, one click

Both buttons deploy the same prebuilt image, release {{ mcp.version }}, as
an HTTP endpoint at `https://<your-service>/mcp`, on your own account: the
deployer's plan pays, and a free instance is enough, since the demo
answers comfortably within 512 MB.

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/arvicco/nabu)
[![Deploy to Koyeb](https://www.koyeb.com/static/images/deploy/button.svg)]({{ mcp.koyeb_deploy_url }})

- [Deploy to Render](https://render.com/deploy?repo=https://github.com/arvicco/nabu).
  Render reads the repository's `render.yaml`, a Blueprint that names the
  prebuilt image by its release tag, then pulls that image and starts it
  in HTTP mode. It does not compile anything from the repository, and
  auto-deploys are off, so a deployed instance changes only when you
  redeploy it. **Render's free instances sleep after fifteen minutes
  without traffic, and the first request after that waits about a minute
  while the instance wakes.**
- [Deploy to Koyeb]({{ mcp.koyeb_deploy_url }}).
  Koyeb pulls the same tagged image directly. **Its free instance scales
  to zero after an hour without traffic, so the first request after a
  quiet spell pays a cold start of a few seconds.**

**Access control over HTTP.** Local stdio is the default: the client
starts the container itself and talks to it over a pipe, so nothing
listens on the network. HTTP mode is different. The server has no
authentication and no TLS of its own, and inside the image it binds every
interface, so anyone who can reach `/mcp` can call every tool. The tools
are read-only and the demo data is openly licensed, but a hosted endpoint
you don't mean to be public needs its own access control in front of it
(a reverse proxy that authenticates, a private network, or your platform's
access rules), with TLS terminated there. Browser requests from origins
other than loopback are refused unless listed in
`NABU_MCP_ALLOWED_ORIGINS`.

## What the demo carries

The demo is built only from sources whose license class is `open` or
`attribution`, and the build refuses anything else. The demo set is the
texts and dictionaries in the image; the instruments are the registries
and gazetteers the tools read. The image's `/demo/demo-census.json` lists the
same sources with their document and passage counts.

| Source | Role | Class | License |
|---|---|---|---|
{% for src in mcp.demo_sources %}| [{{ src.name }}]({{ src.upstream_url }}) (`{{ src.slug }}`) | {% if src.role == "demo" %}demo set{% else %}instrument{% endif %} | {{ src.license_class }} | {{ src.license }} |
{% endfor %}
