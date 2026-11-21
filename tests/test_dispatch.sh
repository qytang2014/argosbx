#!/bin/bash
# Test: private subcommands dispatch via `run_hook dispatch` (step 3).
# The 7 chained build.py dispatch anchors became one hook call before
# the upstream `del` block; handlers live in their modules and exit on
# match (restore returns and sets _agsbx_restore_done instead).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }
BUILT="$ROOT/argosbx.sh"

# 1. structural: exactly one dispatch hook call, before the del block
n=$(grep -c 'run_hook dispatch "\$@"' "$BUILT" || true)
[ "$n" = "1" ] || fail "run_hook dispatch call count $n (expected 1)"
hook_line=$(grep -n 'run_hook dispatch "\$@"' "$BUILT" | cut -d: -f1)
del_line=$(grep -n 'if \[ "\$1" = "del" \]; then' "$BUILT" | head -1 | cut -d: -f1)
[ "$hook_line" -lt "$del_line" ] || fail "dispatch hook ($hook_line) not before del block ($del_line)"
grep -q 'if \[ "\$_agsbx_restore_done" = "1" \]; then set --; fi' "$BUILT" \
  || fail "restore fall-through (set --) missing after dispatch hook"
# old inline dispatch blocks are gone: each $1 check appears exactly
# once, inside its handler (one-line form)
for c in 'certwatch' 'certrestart' 'ufwsync' 'fwsync' 'fwstatus' 'subhttpsync' 'check' 'audit' 'backup' 'restore'; do
  n=$(grep -c "if \[ \"\$1\" = \"$c\" \]; then" "$BUILT" || true)
  [ "$n" = "1" ] || fail "dispatch check for $c appears $n times (expected 1, in handler)"
done
# help handler checks three names in one if (single line in handler)
n=$(grep -cF 'if [ "$1" = "--help" ] || [ "$1" = "-h" ] || [ "$1" = "help" ]; then agsbx_help; exit; fi' "$BUILT" || true)
[ "$n" = "1" ] || fail "dispatch help line appears $n times (expected 1, in handler)"
# update handler checks two names in one if (single line in handler)
n=$(grep -cF 'if [ "$1" = "up" ] || [ "$1" = "update" ]; then agsbx_update; exit; fi' "$BUILT" || true)
[ "$n" = "1" ] || fail "dispatch update line appears $n times (expected 1, in handler)"
# every handler registered, and the del block still runs on_uninstall
for h in dispatch_cert dispatch_fw dispatch_subhttpsync dispatch_check dispatch_help dispatch_audit dispatch_update dispatch_backup dispatch_restore; do
  grep -q "register_hook dispatch $h" "$BUILT" || fail "handler $h not registered in built script"
done
grep -q 'run_hook on_uninstall' "$BUILT" || fail "on_uninstall hook missing from del block"
python3 - "$BUILT" << 'PY' || fail "del block must call on_uninstall then cleandel"
import sys
t = open(sys.argv[1]).read()
assert 'run_hook on_uninstall\ncleandel\n' in t, "del hook sequence wrong"
PY
echo "ok: dispatch structure (1 hook call, 9 handlers registered, old blocks gone)"

# 2. functional: source the real handler modules, stub the leaf
# functions, fire each subcommand through run_hook dispatch
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/run_dispatch.sh" << 'RUN'
#!/bin/bash
# $1 = hook.sh, $2 = modules dir, $3 = trace file, $4.. = dispatch args
. "$1"
for m in cert-watch ufw sub-https check help audit update backup; do
  . "$2/$m.sh"
done
TRACE="$3"; shift 3
cert_watch(){ echo "cert_watch" >> "$TRACE"; }
cert_restart(){ echo "cert_restart" >> "$TRACE"; }
fw_apply_saved(){ echo "fw_apply_saved" >> "$TRACE"; }
fw_status(){ echo "fw_status" >> "$TRACE"; }
sub_https_sync(){ echo "sub_https_sync" >> "$TRACE"; }
agsbx_check(){ echo "agsbx_check" >> "$TRACE"; }
agsbx_help(){ echo "agsbx_help" >> "$TRACE"; }
agsbx_audit(){ echo "agsbx_audit" >> "$TRACE"; }
agsbx_update(){ echo "agsbx_update" >> "$TRACE"; }
agsbx_backup(){ echo "agsbx_backup:$*" >> "$TRACE"; }
agsbx_restore(){ echo "agsbx_restore:$*" >> "$TRACE"; AGSBX_RESTORE_READY=1; }
run_hook dispatch "$@"
echo "RETURNED" >> "$TRACE"
echo "_restore_done=${_agsbx_restore_done:-0}" >> "$TRACE"
RUN
chmod +x "$TMP/run_dispatch.sh"

# each exit-handler: leaf fires exactly once, runner exits 0 (bare
# `exit` = leaf status), RETURNED never reached
check_exit_handler() {
  local sub="$1" leaf="$2"; shift 2
  local trace="$TMP/trace-$leaf"
  rm -f "$trace"
  bash "$TMP/run_dispatch.sh" "$ROOT/modules/hook.sh" "$ROOT/modules" "$trace" "$sub" "$@" || fail "dispatch $sub exited non-zero"
  [ "$(grep -c "^$leaf" "$trace" || true)" = "1" ] || fail "dispatch $sub: leaf $leaf trace wrong: $(cat "$trace" 2>/dev/null)"
  if grep -q "^RETURNED$" "$trace"; then fail "dispatch $sub: handler should exit, not return"; fi
}
check_exit_handler certwatch cert_watch
check_exit_handler certrestart cert_restart
check_exit_handler ufwsync fw_apply_saved
check_exit_handler fwsync fw_apply_saved
check_exit_handler fwstatus fw_status
check_exit_handler subhttpsync sub_https_sync
check_exit_handler check agsbx_check
check_exit_handler --help agsbx_help
check_exit_handler -h agsbx_help
check_exit_handler help agsbx_help
check_exit_handler audit agsbx_audit
check_exit_handler up agsbx_update
check_exit_handler update agsbx_update

# backup passes extra args through (shift in handler, then "$@")
trace="$TMP/trace-backup-args"; rm -f "$trace"
bash "$TMP/run_dispatch.sh" "$ROOT/modules/hook.sh" "$ROOT/modules" "$trace" backup /tmp/x.tar.gz || fail "dispatch backup exited non-zero"
grep -q '^agsbx_backup:/tmp/x.tar.gz$' "$trace" || fail "dispatch backup args wrong: $(cat "$trace")"

# restore: leaf fires, handler RETURNS (no exit), flag set for the
# dispatch call site to `set --` on
trace="$TMP/trace-restore"; rm -f "$trace"
bash "$TMP/run_dispatch.sh" "$ROOT/modules/hook.sh" "$ROOT/modules" "$trace" restore /tmp/r.tar.gz || fail "dispatch restore exited non-zero"
grep -q '^agsbx_restore:/tmp/r.tar.gz$' "$trace" || fail "dispatch restore leaf wrong: $(cat "$trace")"
grep -q '^RETURNED$' "$trace" || fail "dispatch restore: handler should return, not exit"
grep -q '^_restore_done=1$' "$trace" || fail "dispatch restore: _agsbx_restore_done not set: $(cat "$trace")"

# non-matching arg: nothing fires, hook returns, flag unset
trace="$TMP/trace-nomatch"; rm -f "$trace"
bash "$TMP/run_dispatch.sh" "$ROOT/modules/hook.sh" "$ROOT/modules" "$trace" del || fail "dispatch del exited non-zero"
grep -q '^RETURNED$' "$trace" || fail "dispatch del should return"
grep -q '^_restore_done=0$' "$trace" || fail "dispatch del: flag wrong: $(cat "$trace")"
[ ! -s "$trace" ] || [ "$(grep -vc '^RETURNED$\|^_restore_done=' "$trace")" = "0" ] || fail "dispatch del fired a handler: $(cat "$trace")"

echo "ok: each dispatch handler fires exactly once (restore returns with flag)"
echo "PASS: dispatch hook"
