# Vendored CA intermediates

PEMs here are loaded (alongside the system default roots) into the cert
store used by `Nabu::ZipFetch.default_http` for real HTTP fetches. They are
**public intermediate certificates** vendored to close incomplete TLS chains
served by misconfigured upstreams — every one must still chain to a root the
default store already trusts, so nothing gains trust it didn't have. Never
put a self-signed or private CA here.

| File | Subject | Issuer (trusted root) | SHA-256 fingerprint | Why | Added |
|---|---|---|---|---|---|
| `incommon-rsa-server-ca-2.pem` | C=US, O=Internet2, CN=InCommon RSA Server CA 2 (expires 2032-11-15) | USERTrust RSA Certification Authority | `87:E0:1C:C4:DD:0C:9D:92:A3:DB:D4:90:92:FF:13:F9:CD:38:74:45:CD:C5:7E:5B:98:4E:1B:77:21:B5:B0:29` | oracc.museum.upenn.edu serves leaf-only chain; Ruby OpenSSL does no AIA chasing | 2026-07-09, fetched from the leaf's AIA URL `http://crt.sectigo.com/InCommonRSAServerCA2.crt` |
| `isrg-root-yr-by-x1.pem` | C=US, O=ISRG, CN=Root YR (cross-sign, expires 2032-09-02) | ISRG Root X1 (Internet Security Research Group) | `07:26:39:D0:B1:40:D5:BF:FA:E1:6A:D9:C3:F6:CC:60:86:04:06:21:F5:1E:E6:1A:6D:46:A8:91:5C:07:CF:76` | www.trismegistos.org serves leaf + Let's Encrypt YR2 only; YR2's issuer ISRG Root YR is not yet in the major trust stores, and upstream omits this cross-sign (the chain Let's Encrypt marks Default) | 2026-08-21, fetched from `https://letsencrypt.org/certs/gen-y/root-yr-by-x1.pem` (byte-identical to YR2's AIA URL `http://yr.i.lencr.org/`) |

To verify a vendored PEM:
`openssl x509 -in <file> -noout -subject -issuer -dates -fingerprint -sha256`
