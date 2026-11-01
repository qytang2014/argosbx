#!/bin/bash
# 构建 argosbx 用的预编译 Caddy（含 Coraza WAF + Cloudflare DNS 插件），输出 linux amd64 + arm64。
# 用法：bash build/caddy-build.sh [输出目录]（默认 ./dist）
# 产物：caddy-linux-amd64、caddy-linux-arm64、SHA256SUMS。
# 发布流程：把 3 个文件传到 qytang2014/software 的 GitHub Release（tag 形如 caddy-v2.11.7），然后把
# modules/cert.sh 里 ensure_caddy_download 的 CADDY_VER 默认值改成新 tag，重建、测试、推送。
set -e
CADDY_VER="v2.11.7"            # 上游 Caddy 版本
CLOUDFLARE_VER="v0.2.4"        # github.com/caddy-dns/cloudflare
CORAZA_VER="v2.6.2"            # github.com/corazawaf/coraza-caddy/v2
OUT="${1:-./dist}"
mkdir -p "$OUT"
command -v xcaddy >/dev/null 2>&1 || { echo "需要先安装 xcaddy：go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest"; exit 1; }
for arch in amd64 arm64; do
  echo "building caddy-linux-$arch ..."
  GOOS=linux GOARCH=$arch xcaddy build "v$CADDY_VER" \
    --with "github.com/caddy-dns/cloudflare@$CLOUDFLARE_VER" \
    --with "github.com/corazawaf/coraza-caddy/v2@$CORAZA_VER" \
    --output "$OUT/caddy-linux-$arch"
done
echo "verifying ..."
"$OUT/caddy-linux-amd64" version
# 注意：coraza-caddy v2 注册的模块名为 http.handlers.waf（模块 ID 里不带 coraza 字样）
"$OUT/caddy-linux-amd64" list-modules 2>/dev/null | grep -q "dns.providers.cloudflare" || { echo "Cloudflare 插件校验失败"; exit 1; }
"$OUT/caddy-linux-amd64" list-modules 2>/dev/null | grep -q "http.handlers.waf" || { echo "Coraza WAF 插件校验失败"; exit 1; }
file "$OUT/caddy-linux-arm64" | grep -q "aarch64" || { echo "arm64 架构校验失败"; exit 1; }
(cd "$OUT" && sha256sum caddy-linux-amd64 caddy-linux-arm64 > SHA256SUMS)
echo "done: $OUT/caddy-linux-amd64, caddy-linux-arm64, SHA256SUMS"
echo "release tag 建议：caddy-v$CADDY_VER"
