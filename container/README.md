# Private container image

Upstream has no Dockerfile; `ygkkk/argosbx` was built outside the repo.
This private image is built from `container/nodejs/` (index.js +
package.json + the COMMITTED generated start.sh).

## Build + push (run on a machine with Docker, after `docker login`)

SAP Cloud Foundry is x86_64, so amd64 alone is enough for SAP. For
general Docker use, build multi-arch as well.

```bash
cd container/nodejs
# SAP only (amd64):
docker build -t qytang2014/argosbx:latest .
docker push qytang2014/argosbx:latest
# General use (amd64 + arm64):
docker buildx build --platform linux/amd64,linux/arm64 \
  -t qytang2014/argosbx:latest --push .
```

The image MUST be public: `sapsbx.sh` runs `cf push --docker-image`
without Docker credentials, so a private image cannot be pulled by SAP.

## After every container change

The image is a snapshot at build time: a container does NOT pull the
latest start.sh from GitHub on start (it only downloads kernels). So
after any change to `modules/container-*.sh` or `modules/egress.sh`:

1. Run `python3 build/build.py` (regenerates `container/nodejs/start.sh`).
2. Rebuild + push the image (above).
3. SAP: re-run `sapsbx.sh` (it does `cf restage` on existing apps, which
   picks up the new image) or `cf push` again.

## SAP pass-through

`sapsbx.sh` sets per-account container env vars via `cf set-env`:
`ym`, `egress_nodes`, `egress_bind`, `egress_rules` (in addition to the
existing `uuid`, `vmpt`, `argo`, `agn`, `agk`, `DOMAIN`).

Caveats, all in `sapsbx.sh` comments and `SAP.md`:

- `ym` in SAP is domain-address only (Reality / non-TLS links). The SAP
  container does NOT issue domain certificates (no host cert to mount),
  so it always falls back to self-signed for TLS links.
- Egress values are space-separated per account, so a single account's
  `egress_nodes` / `egress_rules` must not contain spaces (';' inside
  is fine); use `no` for an account that does not use that variable.
- Geo rules in SAP re-download the geo databases on every container
  start (ephemeral filesystem), ~15-25 MB per start.
