# TLS chain fixtures

Real certificate chains as served by misconfigured upstreams, captured for
the vendored-intermediate regression tests in `test/zip_fetch_test.rb`
(`ZipFetchExtraCertsTest`). No network in tests — verification runs against
these PEMs with the store's verification time pinned inside the leaf's
validity window, so an expired leaf never rots the suite.

| Files | Captured | How |
|---|---|---|
| `trismegistos-leaf.pem`, `trismegistos-intermediate-yr2.pem` | 2026-08-21 | `openssl s_client -connect www.trismegistos.org:443 -servername www.trismegistos.org -showcerts` — the full chain the server sent (leaf `CN=trismegistos.org` ← `C=US, O=Let's Encrypt, CN=YR2`, nothing more). The link to a trusted root (`ISRG Root YR ← ISRG Root X1` cross-sign) is missing from the served chain — that omission is the defect the vendored `config/certs/isrg-root-yr-by-x1.pem` closes. |
