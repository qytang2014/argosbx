# Container host-firewall prompt (private module, container script only).
# The container cannot change the host firewall, and it cannot see
# whether the host has ufw or firewalld active, so this only PRINTS
# a prompt to the container log (docker logs). It never calls ufw or
# firewall-cmd itself. The prompt is unconditional in wording ("if
# your host has ufw/firewalld active") because the container has no
# way to know the host state; users without either can ignore it.
# The listed ports are the container
# ports, with the same transport mapping as modules/ufw.sh (hy2/tuic
# udp only, ss/socks tcp+udp, xhttp-tls-UDP udp only, everything else
# tcp only). If the host uses -p bridge mapping with different host
# ports, the host ports from `docker port` win over this list; the
# prompt says so, and the host helper (ufw-host.sh apply --container)
# reads the published ports directly, so it does not have this gap.
# A note on Docker bypass: with default Docker settings, published
# ports may still be reachable even without ufw rules, because Docker
# inserts its own iptables rules ahead of ufw. The prompt therefore
# does not claim "no rules = no connection"; it says to add the rules
# so the nodes stay reachable if that bypass is ever disabled.
container_ufw_prompt(){
  local out="" out_fw="" p
  _cufw_add(){
    local v="$1" protos="$2" pr
    case "$v" in ''|*[!0-9]*) return;; esac
    if [ "$v" -lt 1 ] 2>/dev/null || [ "$v" -gt 65535 ] 2>/dev/null; then return; fi
    for pr in $protos; do out="$out
  ufw allow $v/$pr"; done
    for pr in $protos; do out_fw="$out_fw
  firewall-cmd --permanent --add-port=$v/$pr"; done
  }
  _cufw_add "$vlpt" "tcp"
  _cufw_add "$xhpt" "tcp"
  _cufw_add "$vxpt" "tcp"
  _cufw_add "$vwpt" "tcp"
  _cufw_add "$xupt" "udp"
  _cufw_add "$xcpt" "tcp"
  _cufw_add "$nvpt" "tcp"
  _cufw_add "$tupt" "udp"
  _cufw_add "$anpt" "tcp"
  _cufw_add "$arpt" "tcp"
  _cufw_add "$sspt" "tcp udp"
  _cufw_add "$hypt" "udp"
  _cufw_add "$vmpt" "tcp"
  _cufw_add "$vmtls" "tcp"
  _cufw_add "$sopt" "tcp udp"
  if [ -z "$out" ]; then return 0; fi
  echo "========================================================="
  echo "宿主防火墙提示：容器内无法修改宿主防火墙，请在宿主上执行（不是在容器里）"
  echo "如果宿主开启了 ufw，请在宿主上执行一次：$out"
  echo "如果宿主用的是 firewalld，请在宿主上执行一次：$out_fw"
  echo "  然后执行一次：firewall-cmd --reload"
  echo "删容器时，请在宿主上把上面每条 allow 换成 delete allow（firewalld 换成 --remove-port）执行一次，"
  echo "或者直接在宿主运行仓库里的 helper：bash ufw-host.sh apply --container <容器名>（删时用 delete，helper 会自动按 ufw/firewalld 处理）"
  echo "注意：桥接 -p 映射的宿主端口和容器内端口不一致时，以 docker port 看到的宿主端口为准；"
  echo "即使现在能连上也建议补齐，避免以后关掉 Docker 的 ufw 绕过后连不上。"
  echo "========================================================="
}
