# Domain address for protocols that do not use a domain certificate:
# Reality (verified by public key, not by certificate) and the non-TLS
# protocols (xhttp-enc, ws-enc, shadowsocks-2022, vmess-ws, which have
# no SNI/certificate verification at all).
# domain_addr = ym when set, otherwise the server IP. ym is read from
# $HOME/agsbx/ym first (saved at install time, so `list` later also
# uses the domain), then from the $ym variable.
# reality_addr is the same value, kept as an alias for clarity.
# TLS protocols are NOT changed here: they keep using $add/$sni, which
# only switch to ym when the domain certificate is ready.
domain_addr="$server_ip"
if [ -s "$HOME/agsbx/ym" ]; then domain_addr=$(cat "$HOME/agsbx/ym" 2>/dev/null); elif [ -n "$ym" ]; then domain_addr="$ym"; fi
reality_addr="$domain_addr"
