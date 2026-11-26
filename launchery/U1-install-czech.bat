@echo off
rem Snapmaker U1: screen language: ?e?tina (double-click file for Windows).
rem Requirements: Windows 10 version 1809 or newer, or Windows 11, OpenSSH Client (ssh), PowerShell 5.1. NOT tested on a real Windows.
rem Printer: Root Access enabled, firmware 2.1.2.159. The script is at the end of the file, after the line with PAYLOAD.
chcp 65001 >nul
powershell -NoProfile -Command "$f=[IO.File]::ReadAllText('%~f0',[Text.Encoding]::UTF8); $a=$f.LastIndexOf('#'+'PS1#'); $b=$f.LastIndexOf('#'+'PAYLOAD#'); Invoke-Expression $f.Substring($a,$b-$a)"
pause
exit /b
#PS1#
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Write-Host '=== Snapmaker U1: Čeština ==='
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
MODE="install"        # install | remove
LANGS="cs-CZ"      # np. "pl-PL cs-CZ"
ACTIVE="cs-CZ"    # language to activate after install (empty = leave unchanged)
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
cat > "$T/cs-CZ.json.b64" <<'B64'
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
AAA=
B64
cat > "$T/exception_cs-CZ.json.b64" <<'B64'
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
wUcBAA==
B64


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
