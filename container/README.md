# Container image (GHCR only)

Upstream has no Dockerfile; `ygkkk/argosbx` was built outside the repo.
This image is built from `container/nodejs/` (index.js +
package.json + the COMMITTED generated start.sh) and pushed ONLY to
GHCR as `ghcr.io/qytang2014/argosbx:latest`. No Docker Hub push.

## Automatic build (preferred)

`.github/workflows/container-image.yml` builds and pushes on every push
to `main` that touches `container/**`, the container/egress/reality
modules, or `build/build.py`, plus manual `workflow_dispatch` runs.

That workflow file cannot be pushed by the GitHub App (it lacks the
Workflows permission): upload it manually once to
`.github/workflows/container-image.yml`, then it runs automatically.
No extra secrets are needed: GHCR login uses `GITHUB_TOKEN`.

The workflow first runs `python3 build/build.py` in-run, so the image
always matches the current modules even if the committed start.sh lags.
It does NOT commit anything back.

After the FIRST successful push, make the GHCR package PUBLIC, or SAP
cannot pull it: the package inherits this private repo's visibility by
default. On github.com, open the package -> Package settings -> Danger
Zone -> Change visibility to public.

## Manual build (if you ever need it)

Run on a machine with Docker, after `docker login ghcr.io`:

```bash
cd container/nodejs
# SAP only (amd64):
docker build -t ghcr.io/qytang2014/argosbx:latest .
docker push ghcr.io/qytang2014/argosbx:latest
# General use (amd64 + arm64):
docker buildx build --platform linux/amd64,linux/arm64 \
  -t ghcr.io/qytang2014/argosbx:latest --push .
```

## After every container change

The image is a snapshot at build time: a container does NOT pull the
latest start.sh from GitHub on start (it only downloads kernels). With
the workflow, a push rebuilds automatically; without it, rebuild + push
manually, then SAP: re-run `sapsbx.sh` (it does `cf restage` on existing
apps, which picks up the new image) or `cf push` again.

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
