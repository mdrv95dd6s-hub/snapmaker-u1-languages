@echo off
rem Snapmaker U1: return to original (Windows).
rem Requirements: Windows 10 version 1809 or newer, or Windows 11, OpenSSH Client (ssh), PowerShell 5.1. NOT tested on a real Windows.
rem Printer: Root Access enabled, firmware 2.1.2.159. The script is at the end of the file, after the line with PAYLOAD.
chcp 65001 >nul
powershell -NoProfile -Command "$f=[IO.File]::ReadAllText('%~f0',[Text.Encoding]::UTF8); $a=$f.LastIndexOf('#'+'PS1#'); $b=$f.LastIndexOf('#'+'PAYLOAD#'); Invoke-Expression $f.Substring($a,$b-$a)"
pause
exit /b
#PS1#
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Write-Host '=== Snapmaker U1: return to original ==='
Write-Host 'The printer must have Root Access enabled and must not be printing.'
Write-Host ''
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
  Write-Host 'The ssh command is missing. Enable: Settings, Apps, Optional features, OpenSSH Client. Then run this file again.'
  exit 1
}
Write-Host 'Where to find the IP address: on the printer screen tap the cube icon (Settings), then open Wi-Fi.'
Write-Host 'Under the name of the connected network (green mark) there is the IP, e.g. 192.168.0.100. The computer must be on the same network.'
Write-Host ''
$ip = (Read-Host 'Printer IP address (on the printer: Settings, Wi-Fi)').Trim()
if (($ip -notmatch '^(\d{1,3}\.){3}\d{1,3}$') -and ($ip -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{0,60}$')) { Write-Host 'That does not look like an IP address.'; exit 1 }
$port = if ($env:U1_PORT) { [int]$env:U1_PORT } else { 22 }
$p = ([regex]::Split($f.Substring($b), "\r?\n", 2))[1] -replace "`r", ''
$t = Join-Path $env:TEMP 'u1-jezyk.sh'
[IO.File]::WriteAllText($t, $p, (New-Object Text.UTF8Encoding($false)))
Write-Host ''
Write-Host 'ssh will now ask for the root password (the one from the instructions on the page, under Root Access).'
Write-Host 'Characters are not shown while you type the password. That is normal.'
Write-Host ''
cmd /c "ssh -p $port -o StrictHostKeyChecking=accept-new root@$ip sh -s < `"$t`""
$rc = $LASTEXITCODE
Remove-Item $t -ErrorAction SilentlyContinue
Write-Host ''
if ($rc -ne 0) {
  Write-Host "Something went wrong (code $rc)."
  Write-Host "If you see REMOTE HOST IDENTIFICATION HAS CHANGED, type: ssh-keygen -R $ip  and run this file again."
}
#PAYLOAD#
cat > /tmp/u1lang.sh <<'U1_EOF'
#!/bin/sh
# Snapmaker U1: additional screen languages. This script runs ON THE PRINTER (over SSH).
# It adds language files to the overlay, sets the language and the persistence flag.
set -eu
MODE="remove"        # install | remove
LANGS="pl-PL"      # np. "pl-PL cs-CZ"
ACTIVE="pl-PL"    # language to activate after install (empty = leave unchanged)
HIDE="yes"        # yes = hide the debug bar at the bottom of the screen (recommended), no = leave it
R=/home/lava/resource
T=/tmp/u1lang
say() { echo ">> $*"; }
die() { echo "ERROR: $*"; exit 1; }

[ "$(id -u)" = 0 ] || die "this is not the root account"
[ -f "$R/locales/en-GB.json" ] || die "this does not look like a Snapmaker U1"
command -v python3 >/dev/null 2>&1 || die "python3 is missing on the printer"
say "Firmware: $(cat /etc/FULLVERSION 2>/dev/null)"

python3 - <<'PY' || exit 1
import json, sys, urllib.request
try:
    s = json.load(urllib.request.urlopen("http://127.0.0.1:7125/printer/objects/query?print_stats", timeout=5))["result"]["status"]["print_stats"]["state"]
except Exception as exc:
    print("ERROR: could not read the printer state. No changes were made.", file=sys.stderr)
    sys.exit(2)
print(">> Printer state:", s)
if s not in ("standby", "complete", "cancelled"):
    print("ERROR: the printer is not ready for a language change. Check its state and try again.", file=sys.stderr)
    sys.exit(2)
PY

# Checks whether languages were installed this way before (or the Turkish slot was replaced) and prints the state.
detect_previous() {
  python3 - <<'PYDET' || true
import json, os
R = "/home/lava/resource"
BUILTIN = {"de-DE": "Deutsch", "en-GB": "English", "es-ES": "Español", "fr-FR": "Français", "he-IL": "עברית", "ru-RU": "Русский", "tr-TR": "Türkçe", "zh-CN": "中文", "zh-TW": "繁體中文"}
try:
    files = sorted(f[:-5] for f in os.listdir(R + "/locales") if f.endswith(".json"))
except OSError:
    files = []
extra = [c for c in files if c not in BUILTIN]
changed = []
for c, name in BUILTIN.items():
    try:
        n = json.load(open(R + "/locales/" + c + ".json", encoding="utf-8")).get("language_name")
    except Exception:
        continue
    if n and n != name:
        changed.append(c + " (contains \"" + str(n) + "\")")
try:
    active = json.load(open("/home/lava/printer_data/config/gui_config.json", encoding="utf-8"))["system"]["language"]
except Exception:
    active = "?"
print(">> Active screen language:", active)
if extra:
    print(">> Previously installed extra languages:", ", ".join(extra))
if changed:
    print(">> Replaced built-in language (older install):", ", ".join(changed))
if not extra and not changed:
    print(">> No languages have been installed here before.")
PYDET
}

# gui shows the debug bar at the bottom of the screen when /oem/.debug exists at its start.
# The file is needed for the overlay to survive a restart, so I hide it only while gui starts:
# a copy of S90lmd in the overlay (built from the original in /overlay) hides the file and gives it back after the screen has started.
hide_patch() {   # $1 = on | off
  python3 - "$1" <<'PYHIDE'
import os, sys
mode = sys.argv[1]
lower, p = "/overlay/etc/init.d/S90lmd", "/etc/init.d/S90lmd"
OLD = '        start-stop-daemon -S -b -x "$PROG" -- -c "$APPS_CGROUP"\n'
NEW = OLD.replace("        start", """        # u1-lang: hide /oem/.debug while the screen starts (otherwise gui shows a debug bar at the bottom);
        # the file is restored right after gui starts, because without it the overlay is wiped at the next boot
        [ -f /oem/.debug ] && mv -f /oem/.debug /oem/.debug.u1hold
        start""", 1) + """        ( trap '' HUP; i=0
          while [ $i -lt 120 ]; do
              if pidof gui >/dev/null 2>&1; then sleep 20; break; fi
              sleep 1; i=$((i+1))
          done
          [ -f /oem/.debug.u1hold ] && mv -f /oem/.debug.u1hold /oem/.debug
        ) >/dev/null 2>&1 </dev/null &
"""
try:
    base = open(lower).read()
except OSError:
    print(">> Debug bar: skipping (original S90lmd not found)"); sys.exit(0)
if mode == "on":
    if base.count(OLD) != 1:
        print(">> Debug bar: skipping (S90lmd looks different in this firmware)"); sys.exit(0)
    new = base.replace(OLD, NEW, 1)
else:
    new = base
cur = open(p).read()
if cur != new:
    tmp = p + ".u1new"
    with open(tmp, "w") as f:
        f.write(new)
    os.chmod(tmp, 0o755)
    os.replace(tmp, p)
print(">> Debug bar on screen:", "hidden at startup" if mode == "on" else "unchanged (original S90lmd)")
PYHIDE
  if [ -f /oem/.debug.u1hold ] && [ ! -f /oem/.debug ]; then mv -f /oem/.debug.u1hold /oem/.debug; fi
}

lang_name() {   # $1 = language code; prints its name from the file (or the code itself)
  python3 - "$R" "$1" <<'PYNAME' 2>/dev/null || echo "$1"
import json, sys
print(json.load(open(sys.argv[1] + "/locales/" + sys.argv[2] + ".json", encoding="utf-8")).get("language_name", sys.argv[2]))
PYNAME
}

set_language() {
  say "Stopping the screen (it will be black for a moment)..."
  say "DO NOT switch off the printer or its power until the word “Done.” appears in this window (about a minute)."
  # On error or interruption, try to bring the screen back.
  trap '/etc/init.d/S90lmd start >/dev/null 2>&1 || true' EXIT
  trap 'exit 1' HUP INT TERM
  /etc/init.d/S90lmd stop >/dev/null 2>&1 </dev/null || true
  # stop is asynchronous: wait until the screen and its supervisor have really exited
  i=0; while [ -n "$(pidof lmd gui || true)" ] && [ "$i" -lt 40 ]; do sleep 1; i=$((i+1)); done
  sleep 2
  python3 - "$1" <<'PYCONFIG'
import json, os, sys, tempfile
p = "/home/lava/printer_data/config/gui_config.json"
with open(p, encoding="utf-8") as f:
    d = json.load(f)
d["system"]["language"] = sys.argv[1]
fd, tmp = tempfile.mkstemp(prefix=".gui_config.", dir=os.path.dirname(p))
try:
    st = os.stat(p)
    os.fchmod(fd, st.st_mode & 0o777)
    os.fchown(fd, st.st_uid, st.st_gid)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent="\t")
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, p)
except BaseException:
    if os.path.exists(tmp):
        os.unlink(tmp)
    raise
print(">> Language in config:", sys.argv[1])
PYCONFIG
  sync
  # start is sometimes reported with an error code despite succeeding (or while the previous lmd was still exiting),
  # so success is decided by the presence of the gui process, and I retry start
  n=0
  while [ -z "$(pidof gui || true)" ] && [ "$n" -lt 4 ]; do
    /etc/init.d/S90lmd start >/dev/null 2>&1 </dev/null || true
    i=0; while [ -z "$(pidof gui || true)" ] && [ "$i" -lt 25 ]; do sleep 2; i=$((i+1)); done
    n=$((n+1))
  done
  [ -n "$(pidof gui || true)" ] || die "the screen did not start; check the printer (power-cycle it if the screen is black)"
  sleep 5
  trap - EXIT HUP INT TERM
  say "The screen is running."
}

if [ "$MODE" = remove ]; then
  # Return to original. /overlay is the read-only factory system; without it nothing is touched.
  [ -f "/overlay$R/locales/en-GB.json" ] || die "the original system in /overlay is missing; nothing was changed"
  say "Returning to the original: removing added languages and bar hiding, then clearing the overlay."
  say "Note: clearing also removes other changes stored in the overlay (for example other add-ons)."
  CUR=$(python3 -c "import json;print(json.load(open('/home/lava/printer_data/config/gui_config.json'))['system']['language'])")
  for F in "$R"/locales/*.json; do
    L=$(basename "$F" .json)
    [ -e "/overlay$R/locales/$L.json" ] && continue
    rm -f "$R/locales/$L.json" "$R/text/exception_$L.json"; say "Removed added language $L"
  done
  hide_patch off
  if [ ! -e "/overlay$R/locales/$CUR.json" ]; then set_language en-GB; fi
  # without /oem/.debug the printer clears the overlay at boot by itself (S01aoverlayfs), as from the factory
  rm -f /oem/.debug /oem/.debug.u1hold; sync
  say "Removed /oem/.debug: after the restart there is no yellow bar and the overlay returns to factory state."
  say "Done. The printer restarts in a few seconds. Do not cut the power; wait until the screen appears."
  ( sleep 5; reboot ) >/dev/null 2>&1 </dev/null &
  exit 0
fi

detect_previous
rm -rf "$T"; mkdir -p "$T"


python3 - "$LANGS" <<'PY' || exit 1
import base64, gzip, json, os, re, sys
T = "/tmp/u1lang"; R = "/home/lava/resource"
tok = lambda s: sorted(re.findall(r"%[sd]|\{[^}]*\}", s))
ok = []
for L in sys.argv[1].split():
    good = True
    for sub, en, name in (("locales", "en-GB.json", L + ".json"), ("text", "exception_en-GB.json", "exception_" + L + ".json")):
        raw = base64.b64decode(open(f"{T}/{name}.b64").read())
        try:
            data = gzip.decompress(raw)
        except Exception:
            data = raw   # custom file (no gzip)
        open(f"{T}/{name}", "wb").write(data)
        pl = json.loads(data); e = json.load(open(f"{R}/{sub}/{en}", encoding="utf-8"))
        if not isinstance(pl, dict) or not isinstance(e, dict):
            raise ValueError(f"{name}: oczekiwano obiektu JSON")
        miss = [k for k in e if k not in pl]
        bad = [k for k in e if k in pl and (type(e[k]) is not type(pl[k]) or (isinstance(e[k], str) and tok(e[k]) != tok(pl[k])))]
        if miss or bad:
            good = False; print(f">> SKIPPING {L}: {name} does not match this firmware (missing keys: {len(miss)}, bad placeholders: {len(bad)})")
    if good: ok.append(L)
open(f"{T}/ok", "w").write(" ".join(ok))
PY

OK=$(cat "$T/ok")
[ -n "$OK" ] || die "no language matches this firmware, nothing was changed"
for L in $OK; do
  cp "$T/$L.json" "$R/locales/$L.json"; cp "$T/exception_$L.json" "$R/text/exception_$L.json"
  chmod 644 "$R/locales/$L.json" "$R/text/exception_$L.json"; say "Installed language $L"
done
touch /oem/.debug; sync
if [ "$HIDE" = yes ]; then hide_patch on; else hide_patch off; fi
say "Files saved in the overlay. The /oem/.debug flag keeps them after a restart."
if [ -n "$ACTIVE" ]; then
  case " $OK " in *" $ACTIVE "*)
      N=$(lang_name "$ACTIVE")
      say "Language $N ($ACTIVE) will be set automatically."
      say "Note: if you later choose another language in the printer menu, there will be no way back to: $N. To return to it, run this script again."
      set_language "$ACTIVE" ;; *) echo "NOTE: language $ACTIVE was not installed, leaving the setting unchanged." ;; esac
fi
rm -rf "$T"
say "Done."

U1_EOF
sh /tmp/u1lang.sh </dev/null; rc=$?; rm -f /tmp/u1lang.sh; exit $rc
