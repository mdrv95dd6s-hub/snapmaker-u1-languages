#!/bin/bash
# Snapmaker U1: screen language: Polski (double-click file for macOS).
# Requirements: macOS with Terminal and the built-in ssh command. Printer: Root Access enabled, firmware 2.1.2.159.
# It asks for the printer IP address, connects with ssh as root and runs the script at the end of this file (after the __U1_PAYLOAD__ line).
# First run: right-click the file, Open. If it does not start: chmod +x in Terminal.
SSH="${U1_SSH:-ssh}"; PORT="${U1_PORT:-22}"
echo "=== Snapmaker U1: Polski ==="
echo "The printer must have Root Access enabled and must not be printing."
echo
echo "Where to find the IP address: on the printer screen tap the cube icon (Settings), then open Wi-Fi."
echo "Under the name of the connected network (green mark) there is the IP, e.g. 192.168.0.100. The computer must be on the same network."
echo
read -r -p "Printer IP address (on the printer: Settings, Wi-Fi): " IP
IP="${IP//[[:space:]]/}"
if ! [[ "$IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || "$IP" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,60}$ ]]; then echo "That does not look like an IP address."; read -r -p "Press Enter to close."; exit 1; fi
T="$(mktemp -t u1jezyk)"; trap 'rm -f "$T"' EXIT
sed -n '/^__U1_PAYLOAD__$/,$p' "$0" | tail -n +2 > "$T"
echo
echo "ssh will now ask for the root password (the one from the instructions on the page, under Root Access)."
echo "Characters are not shown while you type the password. That is normal."
echo
$SSH -p "$PORT" -o StrictHostKeyChecking=accept-new root@"$IP" sh -s < "$T"; RC=$?
echo
if [ $RC -ne 0 ]; then
  echo "Something went wrong (code $RC)."
  echo "If you see REMOTE HOST IDENTIFICATION HAS CHANGED, type: ssh-keygen -R $IP  and run this file again."
fi
read -r -p "Press Enter to close."
exit $RC
__U1_PAYLOAD__
cat > /tmp/u1lang.sh <<'U1_EOF'
#!/bin/sh
# Snapmaker U1: additional screen languages. This script runs ON THE PRINTER (over SSH).
# It adds language files to the overlay, sets the language and the persistence flag.
set -eu
MODE="install"        # install | remove
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
cat > "$T/pl-PL.json.b64" <<'B64'
H4sIAAAAAAAC/9V9244cR3bgu74izacZoLc8osbAQg/mSiRnLFMiuSQFjjlcJKIyo6ujKjOjJi9M
ZRoG1sQQ8wF+ovUTC+jBwEBPI/aP7JfsucUtK6ubGvtlDXjUrIzriRPnfk788yd38lr36s7n2T9/
cueNbjtjG/jH3U9/dfHJHdPlxdD1tjazLuHXS1V1+pN/gS+VanaD2um8UbWGL3ee2qo7mDvwqVBN
oSv87YtmqIY9/WabS9PW3LAfjW7L6z/jB3vA3548wr9NfmjsiP9+ZuehNrrmrvWx0j3Nf+eVOtjr
PxazbSx+64ai0F2HX54PB/gTf7xUhmZ/bPTRjracdWM0fihtQ0v9re3tSL9UqtctLeqnH67/DM1o
sfaoG1pVP/70QzvTIirbaV5AfWiM21NvmoF+fgR/T83Am93ZvNWdrd7Qp8fq2Koxg4nUzGve1qbH
Ly+n6+8rHqvVtTKNaXYModl2vbp+S3vsba9oP8/UzBDpKrtTtMLnvMJ6ygp7/X02dkfVGOiod3ZD
LXvV9twQ/4BfDpU5HnWb67a1rUApG0qcLOvMh/fZ0A7FFRz4hz9lj7itolWYYw6IcMyPrWl63ld2
1GNjs1n17TzVCnqU7XCwI6xB38NOAH6YCkDXIUB62+ocxqGtz3DSBg+G+gyvmwfwH9UeVCZ7V9k4
Xb/98A7PGmayZTGrLkygNtn9ecpGGucjZgbQRnOr0Sg3twy3IYDR7vLalozAD/yoGf02LNq4If3i
9zBZtkP8ggW+nGhvezieF3BO++wIeD92sGzq/Dcrg33KeLGFU82OlTmsTXhXEO7S7IZWFXuVHWxl
259+GFcafybX6WiL+cP7ItkzI54/0Ae0WAA1gFRuDHy1bZ8rQ6i/AyQBLDu2dlvpOpthG41h2MJd
zb74KhrQQeYpjRbNCth2/eO013Ah9lkHxGOf4bijKabMwI87S7/Cfy5NBX80/UAnc1nZMS9UVRk3
9CNVmS0D4NjO+nj9dhqHTB+6vh3mvQnAYIJUMQWJjlQBecI/ZasdkBzAEg+Pm/BEDT1e8sqqMnfr
JIoHv9eqn4oZ9nyUvQMylzJl2BOPU1zp4kC4aW11pVXJtAwpRjlTDwFOPC/Oin3OTnzDhEe4g/o7
gFApxOZl1394f4Qr5gCXbHFobp2stXOYT/pudZmXQLOL3s0yHdqJVwS38fqt3796Y/op73V9zFW5
B14jHQC/y6nYIwSp18HWtp3iW4qLamwOGAGIISgBxKy08wjXgcC/pBnMBMZ4T8K7tnAzaR66dFlp
mSzJfAgwRXvxXfBKAS8aZVPUTVoD9aQmX6qZZrTbPQAiB+4oN6I213/McMpDPxGVTr5E7JL65Nwf
G7yAy2KRIhd7kzFRuv4Rjq6wl82Hdx/+tMlwCPrz3hK6V2Z3xWPUOEIPpEOAykRr3k49kNzOHoBy
fQPjwg0l2n5Aws7IUep2kwmrA4iekl0gOnDqOM233cBbQcaR/EzLg5ng6jYMOHPPNdTfIb1hhIEp
8R88z3pzOP4OhgbgumMB0gknOVM7PMUB5jNI9+gkThsndLayBXPapwr43/sPf8Ifh25LC3/+JWOC
W+BDXh5zfOqZn3wEEnmkoQoTWi1gtGgDpwMntiuAfvt1ftmqA60SSHz2W/yELRvASiJoqmKxRXbH
t5vFGgcOISIf3vvbEwi+iGyN7SPeHnCrFd7xLj5t5W7FgOJi7mgzkuOe5cc7DyaQDA1QCECzNUId
qJl+o6sg+RjAyZhQZDvoMhYzcAQ+9lrnlTqyNPYC/sX/cKPp70yf0KpnTJ6IsfGlxra1OrIIFFEO
3iosuIl5T/YKBFE4JiBNiiQWdZGp7QR3Z/UaEAUIxwcEFGXaJprGzzJl/XTk84xvVcpv6Bg0i2ZE
aFBsuv4e5qyGLSxqPoCAiwJQrUCwaD68Z7koXh1dlw6OGOkXLY14zEE52so0jxeyObOBGxbvCD6R
mRma5KNqqcOXsNQfQYSb+D4yCFXWexIEm5JTBjT5VfaX/3N/CQne/ixi/wQbdaAIsn0txHp950RL
U/6VCE/+qFcae5HsxdCrPUqk3wP4+wr3T1TTNYQVlvhjWSmRFDdnhrv7UcNdqgOxV4N7d+x1Ir4E
ZDCITOdm+SyRSlXg14hc9qi6Ya/dmv2kpY0mSySwRC6Dgx8yCye231bm+kdAu5ol0FkL5+hm6HD9
I3ZA7NQVYRkoCUfT4XWh1sna8T468Vxoll/WydyFlaXzTdzLlujI40GRpOHApYHOouhd/3ury8YU
KisnlMQJwjsFwhYj1hxd9NpkXWUKQNVNxiLZ9Z8vMsBCOgQZgHvV2AHo2gXIsEdLCh+MPO9s2Vi8
rTctK+8MaLjmcvrr1xdkXZDvLnWrG9SFkaC6f+51IH5RG6/A3EKtXzdZ9pf/APEiG1kpg/kHGvEU
wbBtlnU8DuIZiBmgUXcwJGwgEtXxz5IGgTu8kSleATsriNVbWMr1jyVgO4B3IcySRjBUFeqkLZoh
SsAs0Ery3nMEUtaBLKJmC8ezBwrI+BJzNN8c6DyIjaDZS1sNB9kdQanaRioRy8XlG9QnytwekdcR
mJ8cC7pPCi5O51UKJ24gd7yRK+PN82A3CyYpo1RadX0uFgw3QkHXsEbDBVyDEkSrc4PSSPaSeWN+
adutKUW6xwF/4y4bQKOjc2TUs9sOqPMOTzE6Y7yJsdivVsQPFiZy3ZR5pEmsbB9vbzpawqmX289X
x7oNECerReNNayu2jQDPIm6DHx7beWax6wFcQGrb+J9K91Oirv1WNhJ/iH7nMYY6P/ettmwpejYU
VzSG5496IbGTeqFVnzt+u2i2EXZ6rt3dpQawKmPxyXVHzRrzU2DT5YHIWDiW0TQnH0dAoKlSeCNJ
3AWNo2dxutOH7OuHD2jwoTWXhi/CE6Cl3QxKWjGzUGaaHAdenxsOFARgQr5opqy4AlCSIECzqq4z
gCnnhyltCUqNHW8Zhw/90/issk/Dh7vJh7vhw2fJh8/Ch18nH34dPtABhRMkuk9ooA6Rdjq7nxJS
8go4LNDDfSrhP3v44tkX918QTuGfj+7/4xf4+8PfvXj27YOHpKE8eg5/v+Lf4xEfOk2PNRbl7ATX
/7rQ8Vt9rFSxWA5Q69osVoPWRB4DNOJkCP6SfzclH7Pf/ZN8r9V3HoMdp/pGHboNiZAxsmPLCJpr
jT1cYc7VtqY5aUpmX88jbY+m3+wIHBiRJ2EqM9qFSQdnKnDMC7jVBJTfgpJJJkwygbDqNuZJEzKP
gLoNbAYpF3aA/3IPBmIDqnza51svB3AHvZcOsBighSh3gRzW4B1vLetTQudYe2tQ9EhGlA3yhpAJ
7eXCRF2Xi3uXbJeUwGD6QxNMJC6cLJNYfT0Jf4VBPb8Cqh2kBgNkZ6eu/+ggjWZnVHn2KqZKGzG9
Oz1UBxsh3A9vfr9UzTpdWFAvOyB8PqY1yPGF+fBuRySF/BhN87FdW11M7WGoHIuuyG7tuzpQviLO
1pG2AycjYxUmGYtVpaPd2bYjTWkBn3X1yAlOYb/u+Fq0rzsTPMj4fYvMNjOzpeXC3HBm7/t2xjON
rFHSZ1psFanYbsjm0Iuh5RYQoHbLAiJCnY728YsYl4tguC8O7j8H/e4AEAVhiY8AxK6eBLHUgHYv
vT4ACxBMGhR4ZO6UeATniLtYtgHl5IsbrsVFuITZnu4ty7IifR9ibbtmNWVoWy0+hFSLxwMId8N9
f4IwjU5iCncgbTKmTWAnTbmdwjwaRIGpYYDFbClHUUZYyGNFsgpbSRyZjr434Tt++YfVnjS7eiM6
AiilTBkiC4GTh0VU7IYacXT5BbRRFr2mIzes2Kf2iP7AIRGLdoPhDX7VIGs9oGYVCbuJ/SFItt5u
5fgwLzb8Zi8vTWFUla+te8osfN2rqtGf87i3NIfzmoor9O2UQwG/gKT1uRDUWjUD9HNrgGupBZ8a
Fbsa4GKQQ+DvmSEnnYL04Jol3owcfbZMKc85MpzxC5GZXZX3eGNAQu2uQQd1YgFJtJrIhgJMpNKg
I7AxgfVrvlTB/jdtMgD/CET9+ke0ghPzWHIfVPINLgY4Gd60TaStiHjBp7k0bNysmKQjRGC8eRgG
6i624KyNFyB+02gLVW85pAez9w7hSH4n07rnadELDqsx3RW7oEAN6A/B2ZU4lTQ6Ukmq9BYh3q3o
42TxPfVTeYurc1MjvWvJWnt2pff8eDHclyO+ioyRcF8K3UXgD5C6l2yaRvKU4AySv27+8h/Zy24Y
1T6xygEFV/vGHFDWBIw8sO56QFMTx1LMSNg9PoLa3ik2jW6y5wBaXdPu0Reik4HHCdAdmQhJZfNE
/OncDfRGWLZEHa23pLwvxBg0bF43r5tnco8W0KXdrRCorIPVt6GPTs1JsGc/xiqdgl3UaqeQuYVz
GI8osIqUgLbC4orWdm5z//d//xvBaFd9eFe+btboaDbyyfznDiQee43oeuTmSYhIGbaYxl6Jl/81
a1mQasbQHDCGMP2ZW8q4wEmE1Oxn5okLoBIHvL2EKoAUW+NMloA3b9Fa2agjCE9w7+DvccWG3dY5
HCSoZ7FO+S0R3D2NdZGhkOWXQTbzsDXr5gVp8dZZk9u5M29SRXbDjttOt4sPqR14DrELoARcobHb
r46sJFe6v8JoGx7Bj9xqEKXcr46u/KPGcKCwOwK8jHqBAu1PPwCYdzaIcHD6UezEKKT8qR17jAry
Hn10Cj3BvYwDOh3ItLgJApbQb+//T77kl62tg10APmckLF0Bssj6xRBXmOvv0dfa20h24/NkbfBk
VScE0pkazocv+OYpgXac5JmIICtUCyMCOooR4yCq9ZEkdGxlnFP5IxklEmX8am4jpGeXlMpFP08q
woHuV1q5YLL7bGJzMXCX1dBdOW8r25mHg3EOV9Umbh+S0bYYARTkUuzkQjlSRuoDR6jHitTou61w
S+nrZQOBRBTLl0SpBfmAdSter0RUaW8d5tiW9YCYqG3g7GJN6+bjUCHpQgcOnljWTsA90U+R+gXK
eP7N/+e8O4JIHC5HUQrJzDAw6r9kQqUgiGSXJCUHEWk8PYSNi3rJo8OSuJjxpjNj3eJElXFLBfli
GZrEAj07pWDXMvpUh+GHzRkFKRr1JUkYjUddHM374VCVBimhGm6bA3QpXXLo58Ny6mOrFGGhU4Rf
gJqdpSK33IukxYnqkIjjz1Ih16tbqwTXa2dslU4jKCj8JLk2V4uot1deQbBMY0CGRpMOSxO96V28
DUFRCRQVyD8AgBG9k2q1n5gRCZ4ArXAbjdekib8DT6HorQvATrbRUlAMSo6N4tNAbqkrQNCeSSZZ
7JpIqbjIduUU4pyyLcgMs5HIi8JewhY364u8y6s8GREXRlaRd307+2i0Jc1MxkwVxmdxZF10CbyP
jgRdAqpDzH0EU7OJpDtRA89qfV6GLhIx+kT107r0sTqlWiGpTP09B1vS/oVqecIASPuKmel53Uvd
FvKYamCl7oWZPEd+uANp6u2Urh13B9JaY/PRthSY7uhaBH1CpRmjrOXScYBPfB+8Od9ojpUJHOIp
Wd0isAJ910wMmIpkNcak4/BDbFFwpiZ3cqgWJGsv9RtQnHN2f5HI0CH3ADQcWmAxwbFVd7ucosz8
3T7YekDajfoH8jDSxq3bZCxgb/wALnz891+iLaj8X+6DC/35/RO4SLMGcR226L+a5tLS16/gj7bG
IAP/zQUmPbIlUUR92efdHwYQSXJ0CRx0T87W35P8jK7Fta9+tBDZj2EntibHTRzkj42iKP1g73Hh
zZ42c5xYtLxsC3t+X7J7ejhSiLTg53Pk7+pAMgTrPtLgf3SghtTqoNtNYdnO6ro2SJS/izQAtwIK
lhbiB7St+xlj+5itOJOi06DauQ2/sluQHpAc4b5nbxYtVIPhAf7C6e4AFGQPSFJm//OZsHfqi3fQ
E2KWyWioSZz4vAsJS+90j4bYLvVcuRldQBpbNhvdu/v33Gi2BY/m0uRHwG74QkTlH1SH0uBL899+
Q56TsbUYvB21wPyPSK66og4Xp1Edon6S1d3Jm0+t91utCdlnRqFFAsFVOzEt881j4dpo5BAhSjan
1ksr1eACZHuMjcPd34vXd2XKUjfxChENeOhsQKrDU7j2QA2CqQ8N3dnz51894B7sBSzaieJYiMIs
+QNSGSAHl5HfEO3mZR4dERnQUTbyg9LGMG1H9Uas5i9lsYClHXCaCp19ITqKVoKKMgxL0pH7m+Py
KXHkUhXw3ymPEQnv9gjnAOAKUVHZpdq2kzcxF4UdfNQf66YVoHgiSX39xeMQn7vEvqyyB1iwWkRO
nY2uEkKMwQy96L4wM2rfSuQc9ip3Rat1QwFLdhC2sVMdYwsJNIMLeKUIpXwl9jjEL6VNlzHGSTPg
0DyfJ8Ja3DE9sA5TSL5QD1xgAj0F0zX6KOzXZX4Rwfrwfp4OHLPS1gSTZ3o3AFsyDe9UozNNYrQA
ubo0CNwbfimum8NJMQvELfdeiLmmuB+OxQ7bBwkrCczOlXF5BxKF7G9JuacwcBB08JZoMWFxzspK
5yB9kng1ZqVRu8ZyiMIQEbczaTBh0fo7gE3DgeVh5ZXdmdPlk9hTrLZFVVLixBPPa9Qb2p12jFDS
peo9VvOolmKBQ1uX+vQN/nGmUcfhwEMNcjIg9rRvxJzW1iNy5JBGeOcl/ElBtvyJEY3RoVBHVRiW
Q57ava7FVRqHw5MMU7udPQCBvEFpjH8GGZol3CJXZdlKIuAX+Ff2zRf3ffKgwXi9vNBtD4Sp8BHq
9+GH6RLlnilJxWn0CDQn3kScj4MMWFVmJl+uGDyqVqtyWun4jaIQjD2wiA71/BGh4SxHAqzhuGsV
E6MVYDFNitp8EeZXMWnixAFp6FMHHpMNkaXRiBmi3k5B3/Fu4uyYXBIxJfYoCENuAvnuVhPrsgRI
R0Zz1ZQ5mTtj6ylztrUQS88/TJeDRh4pj8jo2eJLKhQ7vzXr1XBvqJMwBxADmD6htL3H+SgVhDgE
UEMvMzhGQJM1MTvgiULwwea0OdCKrgjpGUFgUKSg9sTBdL3JomQKB262W9mmMo1kDOAW/Pg3bYOi
eSZmtnL+Ok6xjXElpNrGB432H5fywvSOGPoSd9OYpBhzgaGWcctXQN30DP+wcTOHKZ6Qsv4bY5zc
4zjHYUZ+ryTth2Hn8kDVHvSmDnQeAPHfLJEVFJ+DIGyLsCVslAAXBeQDN+jWjOdHN5ZuCMzEy1aS
uHlLpxxoP9y1k7t4tD2w+Myi28Fmf5cBCxxA4fvWU1Dtc2udEU7M+Im7C3qcODzctrV4PELwB8Yt
p0iVbtzsAkkgFztsSeOF3FrK91ndiaM/ieDL8ee4H9pDxBl0Gh+9Pq0nd6Z5A9/Lv2ru1PlCOSW+
/cIXNG2iYzy/liClRgt6LJH72o/+uomPcREYjYmshEDGtxfPGtnhxTsyT07SRaGoxbzF5EskDJUS
P25Qauyd1PNY7Sl/2HuCjropW/NGowyxCWKAmGce+vQ5jrfMnrYWeNB7AJ0+uEQJERyiNHqfueZ9
FFPio5AeTk9yzd1p/fQDQD+c1kr4PImmssZv0Vx+w/LOyf5eknQEbuaADNYGCi2Ks5B7pw9MxdW9
MCr5ts7qFKpQZwcRrj+HWHzMImz1DqgEJxFdmUaRhAF/uJA7DdpA1QhP34EE7jfhdb/iqsCQTSIO
44StKETsdYNpF/JvFD5xZWKehOaWsu8nuvyYFgOLJV0EuNBzZxfInrQFcJ/GwI8K7w1JL4ykQ4cm
r1Q0FJEfjUJhwbxZ+NvFJNEuHCa89AtcU5hfN571H2PVOiiv59ItyCDxB7a/oBxomjOmCb8xGMxv
nO0VzFmUg+hGlh8NpWhbQnKxSxQ/OJccpeDTBFzey4d3m1jXdvq8QyOy83mg1JSPgRYcDwFnxiF5
xIev8miJiu9FK0BCF1D176NRoiD/YUDWHXXEcL2SU/siscTHbSft/QGudzrjYdzpPt9iiD1hzzkv
3VGYMfYnGxMKnkvkOhZ8rDjA1x6FZor/xTjDpJE7MCnNscRwUI3IyNHrhrCiFN8BDQG9YyPe068e
MzgugSBc5byAJyWl5LHZMpslggpAxZkeVF/keIVpKKtr7oG4XQoV8NLcz5Esk03+DMFyDcM5wtsP
fTk0Xi3+KIESzxh7K2IOfAFvO2kA+uCh7uwqOJCD/seNAGdDJrZIWZCBWC6OjjLK3Xddl7UVYotO
pMnRjqUtCHnmcsLGrOKKNkbqIYolkR4sPXx5gxzu5CEODpHR0QvTutZy2bA5xZRwLuK/xnSQ2sOx
yvA+EhgEltDlWVB97Gkn5kFoQjhwVMa3cNcwHgcV6hJEJm6ATjPCQrtDwIkc+dR6QzDlFgdyTm0R
0SozgrgzVQfgRzIW7pQiiRVMlYDJ8Ugv8f2hdWe2EKYEX4DGjtnWBRvXfoIE0cdppxsixA5XgPID
FrvVrsx75Hv6XzopYBk79x3MVBLF5GQDz/R42Bg+5xmeXLv6ptvCggmK+0BW/EXzevZT2yTlYBov
q/gyHCwjjJxQDiLEkLb2jCyql0JxsicKC/q7qf4P52yStQFjCrpj9eFdn4Y4E2JRTQkKy3Px29G0
nW4605s3Yhe6Pw9UdIZKQMja1fraK7ZIPDYd85Val2aoo5xazp6TMhgvqdIFwXtU/RUqRj7LL4IS
TLBP18pOdK1vqPsyzMNRX79tTOp414sIZc4dLKeAfsF1TIfcia/z4kyiLdkwRU6RtHj0qafJj2jE
rzF9Gv7XuxYpjIViCnV9ppyBS/HSGM3EWaNm16A07sPcX+kZuHCFsyZbprjG2o1/y0AJJG7dP1sK
zkLBlwcgOExxDrkrNlTDOAZtzJhJPsZLnfUZUGDKBoZfjlzPKTFXUOK3MFw6Zszs9hBK0MIlqZ+6
zJN+HiAS/XOyWcyiR73TJeBj/A8m9KcYxEWzWH+JfMru3AeWEMocFeJ+aBu0tklRMhY6v374IC2Z
YUAIwMjQHCPugR9NLDCB1uoCyKD5gFkuyIuBKQoJWtrkv/HmcrGVN9aWlZZGy2pBR7W7QrZ/0jCu
vfVXEqho6IjuuIGjBLtCyBDa3j0Zkr2xj2PrwiAD6dgWGNzLdX4EFL7tyh5W7rdbONo1CtRM9uIg
FlsaIgPbrBrn2djzxDJt8DYp72p8gVaqqGBJ9o2pLWY5ODsb3qI6PqN7YRjK6Y0GS87yRLTNHDIR
00WE4qtjtw3g7US5hQeMhGiWJH51VfcEDSkLNmCLq0uGITpApMcpU5Vq69PGUQgI8tM5mC1VA1Cv
DKrEkc0UZsdcquXAsFNRnbmUH/mNFJVQ5OQYLOrHTpsAxgHhYzILwgipw75QETuSMGSOwo1HSnnw
J0yJppLHRVmZtv7ph0JKTJgbAMiLfIr/6vnj5xxHCOBUEnPPkhzK3RTKjEA6UBQhQYfE6nqS4PlE
bePo6KIYMFYGryTRulEBifk8vVbcCJPt0SWomFk+SRF0OEahaE/9Gn2WMH+PjVTUCNugBFZjFUVh
tNLUe/Gjwc4osnKE0eAgGawNrS4p5w2Nuuz8FRdno0U0f2x2JUkI5PZAF2aQ8YEV+VJkYiJSDRbP
5Kwc76L+GoTxreJ6F46Hx0nzeTL2faYBCqEZMumVF4tYvBl2O1L3eUbMQ3Sp41RoA+kGTqeiZYVG
LyeufkTpiyctQrgA5eeg4X7ipoDqswumBdkWWPiedNmDAmHZhkivM8PRgiRnMk7RUpFdMqERlKl8
LxbBMTJFVVW0l8RYyJsGDs6T3HvdRNCUiT07GaeZbT8T7YuJ8xbpV2XYRGpL3CYs6dYSbUw53Cp5
/wtfjVubhK8hZFqNaoErYHpmqddvo5Vuot7nsIY7n8USdx6n04WKcSVawc2F5HKzULSXuES/CYwX
DTslnGqMlHBFk1f6SUrgJStZy6HkGdyaXjefbjJnFnKZ8/7bXZ9EFiHp6+YzdJ9EaOp+//WGSt1M
UndGYkxI4SNlF4PIqMyNGE9MyNo5VIarBABvLkAXyV5HG35954K6MSkX9w+wIcAiFDaLJaAZWbw2
6CTDly4VGu1JAzkijNgWGWc5oSo4iSQSxplxnAksNo8Fg0NiZ1jaIpZGiPR7ErlKPrtuTjxFM8IH
DVM1yN5scoI9AMdxNnC/bMfv/ebTWQgOjwjWXNbUd1RIEdbmpHpJfsozY3PWN2u+NtHX19xvU3b9
oyrR2Egz+ECiYdtSoEGzy62pfFCkr23UgRYSAq7xeqiSQPvcf4izREJsqgu8TWNSo9hVZ850Mixw
7ZGyyJDVw8qzAxAZyWQABmcxq1sXV2gFavQeqJOrcmEOTNfEHkoyhd3aQ7aDv+ZSLUP+vfcFqSsK
LdZlJWSNRq2g4vGTEkpJFFZUPmlyZZjz1lquVciomtG/4485/iWlXaM2tB4Kvg3CazKg13PKxcjC
k28oGuaT11VbUnWnKJlmArTuy40zNax8HqduczJCZH2gskOZ+yrBGklFKD/wSS+q32lOe7yx1VDr
PMpXj2qcCCu6sj3qg1ykbMGRDqFgHmYIn+nqiuV5bSYU8FvoNSimovEKdXAa7cS3axsqLafiqV1N
tKQeGtsfP7xHksIiByFQvUj1O10qhe0vgOMEMn82rlZbFN5Lq6FcBwF3gPVFFNhtoyOczkxDB3nz
FNEg5+bhVZDkCXRG5Og4/FpMg6jku/yTl8TRklKzUg8hLc/uUh8/zW+/FiEX8dO4692f1fVu3PWz
n9X1s7jrr39W11+HCKoQRJmUX8W6EuokkjKqxnxDll5EnpOCQk+Ddkv1cc4lNLhUlFAQXVOhSVuS
pE/SSJpNK3F6oKlI3eDuJA0Av+U3FOOi7wXArlVcSKd2leB1x75OH5UVNefAOuaC9FN7aVhm+M1X
D5i6JpPG8WmxDpP4b+IOsYsl7uAqQztFyScocH7CyeC+YaT5RRBYS37gQrkIhjwRhxg0sVigoqZL
4UlaLxpLyHTUjuPdnPdPhABqhgRjpSmVRE1aHy2D4DlsZDuxsG2FU27bia8LVUZvHI8F4gPbnqQm
cO7Cw+J4MODZA2gacsjYChcUt4wPlVsPrvnCxrePS+bBpmwLV0n1WmqBh3hikvc7TOB4i8S+JJNE
pCBz+5+Z5SQjm5ORN9GQYVEft5pptW9UQ2w6qL3nb5z+z5rCTz+MUqASJ2HzM56oFW/0yGoEqfgy
mcspvX6rDyJu2UYswa4ImLeIX3/f2vIweAHOUwzWdfABgYbiS5Ikus3Z/dzl7FBQ6aHnQX3OSalu
GLHVo/zPpr60VNP1n1uKFcJlYSQD/HVmJjTmeL3CaVnzSd27oE+hBMZVw+yBYAGbAAXD5wEeXSa6
QwBEjOVpgvSNFBg38rczVrWLvIuna8TYee0rTt8wLJoc0VEK1wPEazniRCj39Sb2a/J59sBimVLN
JiJ8SGIHmNxRLWTGGM5Nms5twL8nEG2E6/g5jeEk+nA8Lc+C1kNYGz3+4UQuD3gF+3SgX1wmV1Eh
MECn5RADxKEAoQcMAmtHquLQkLXlQHXshlEdBm/Hg/822R6Qiy0xQKUtGtri6cjEtMywEWNRNt9A
AG6D3r2Y5jADSSZbmJr26DnQ9143L+N5dFzzNbgvMDNGUmq8ukQTYVhl81FZsR/eSRCT3EbyWq/R
CPi/T/F/ZiEKgH+BKmQsjK1gu+x4UReRn9XxZZK41HODqVdjuu1EVHHDI7NfMvjoFNDwdnoO7kEI
FF5jTi45STYqMrkoTx89HrKVwpPCtSuTS5db0Cc6PT/EveUYlA4b2badd2its38TI3RPCMujqDoi
ERAq58EsXwrG/AxKskiPc5dBC01ZISl+oezGZwqUHGaPXjSLHq5K3gg6ki2MCsBiaRbJtXDtPDJX
A6YQ/AJLczkFEUi92v8yK0faGRmONfKwYTtdkNOiIEaO5b/HrNIjCJAu+LrEOOxtC7x24+rr5t2o
8DGjhItwYQUsOuBZq9sPJ/LzrPuM7u/1j4VLG4rmKaZDpSWisDj4nT+wuAMi765YC26E15/RnaDB
kdhIIVEhlUt8Zdwhr91hBWld3nQHmokSAew5iLBsrkYL3PJgQjrG2vGEBUcBKntNNUQyF4Z4Kp15
xF2R5tbWf1Z8ii+BH8s5dKIB1uLD0QBkO7wVKcE5F2ojatJ50rDQmXxBQpfHHDLoMpsIgJS97Czu
4TiO7mWvcDKnHiXaunv1bLGgyP3hmzrgPLoJOOGFFfS6pBuOk+qjCqz3Qjo/vdFRxWRsNFR1xL/W
EYOHMnfQX3EesK6kCV0RuBjVEEvzNw0UypKI4GlWqqf7oT92UC7ac+ZlqfWFpq4ojNXlqHw4XMzd
ffrwK3zaxY5AhjCXm2ptA3mTUtsT52m/8StYwspXv1VS/fZs81shAsL1wPQtGsqXB19MfPsTLOmD
LWw8jVBBnRv91nWuzoaDHFt9pgToSZfoASrolbxBFUsWvN4hfYyKEo/y7kq1RyllvFi5vKM2uYDb
w8khgcT2Su0B2OiEWKQCScwATYLrq9FOvwafEEMS1D/FiDUhXsFyXzdnicrn2ae/4hnjCV05Jjm7
j9nda2GU6ZMQ0UGTN2tebjedncMvsEBG12tdoa7R6xAgH8jNO5bvkKyEG8Q2HVJPbu1+XLmBaRww
dUYK2PVJMMwYB+3oouFAnwTeDEi/AjJ5uPrsYhhhZYl6Kbr9qd8a8497IBSvTneZmZO6NcswtIgs
b3wgEb+A5jwAUaEvsalvQtPwLIMLoHdpR9iUqn460xHqkzAOLAj+KtuhMKSTGAztArKF3BVN9Hhz
CEykUdAIh0hHJqxbyDH5m5jQBHRbyMMn5CoSCVZHisj1adHwmzqH8Kudjyul8MCRgibxNhlWdhtk
85V4UhcI9VegUkCiBBuTbN3QZ525nHKUZb2jEzPOyrR3f/a8tyNrLBdEFeGWjMaJERFuJ0JWEVWx
w/KCEuXvvU+hIYiJrtqdrw2+1hBurLR75TVLncht4fUSxANp6/XOM21xYws8jNtJuKQ8KSmRgPRG
7Mrvp28qrGn6znyI93Kp9Hv53ZtmghwER2gkr4JME3vSDb2JceMptltGoY/uvMSQnurktgz/ivcM
lyXON/kWk6c43Nrr1qdDJ4r4gmGdiCZRGekegxJ1kzdDpK5H5r4bLSVx7MY4kRYMTYsZFjxRHAmQ
bXIEsMRA9sSVaKbFGu5yYOLyvDDBwBcS9NOKMnvrpGjrJY9PO6Mer+KWM1t6ooqrfyww4IEUTrGR
YCkEzFdRnXYF91SL1BylWiknqDmStLNS4p520JlQACIWqGwTebjEkNMMC7O9LFJfv423M/FTN6GT
Z0wCjPNQyPBFMc5LHckzBwSp0mnBtuAasyLCj1jADS3dtuNCbVz5kPX5dEQ2lKOPhpJR98nrQqTG
g748NOWEftjG1EIQ0dYdaG2Mv0ns4goSn60Iqsoy37VaDuyxEnKM4SNZZXrxLIdWAf1PWyKgPkML
Lb51kB0GrEHpHthKPOUkL+BDBomcwMVg6Oek0YlAERrijM54HDR8NA9T6ZNgdAk6VSKGkNUFqOR8
4KJGbI9zNgFXYCcKQqQOhP2u3o657VUMpIcHF7aCwTJWwmUFUmiaAFjpA+LOmlHXPVxES0m09lD0
Z6m217a3bV7qxppOr2t7gMZVY1wIfdzBPZB7k9ATeieqTTLvirJ700CL+gaf/nfRauI3ulYrA8nH
8+nSlEIKOp1eeFDEHJJ+Dhm7VNnTl0ILFJb9PrUEfGG8pjogryEz1qm0QlXBXyoymia1jjAUHG7O
dEAjgAujLgyrNYZXxFQeo1HqEFFcqJMU5WXZNMqVEUef2yfnfUmkgo8CGRZl67jqZPzMjo+2IZOw
lwCZXAbhit+BkESQavmSBQ97WjvfcdELZBNIN4eFVntxUloWK+KX+LbYuTcuuJJptJDocYikIQar
JA0f4pPQypVbXSTRxDFlUVDYSWhZlKAQpUcsI9J8eFi/FpqWThbqxD4/aqlpP6CQ1bAWc7RY9WQi
eiSvHL6M8iJ6ChmmO6f2OrtvKOiAXOeYf+rexOP3f/lxxRAUhbWX0N8mmgvpl8XkwGnLlpBzYms9
Jh5g954C+l1tA59WIiWdUfkCVjYylpoMBDlMC+A1LucnSuHmXnVOSiF+Tlbg7k3ietj5UpO4z8jk
epE1x01miyuMsZWV+7froCNcq0ht/N0/vbpIzBNi3OGOwUIEJGFRhPQolUwjPHWvUZ5iD8wwqgoG
H+2WxbuSun/40wUW78M/eEb0kYQjxEtPNc6So9PybC9IEoVlVuVezxx61w0j1girkLZJvggQjYus
3phm83kG0IV/cj9OUaNIAliaLamSBfZ0TwWH93LxyC78eURNgSNiU6SetlVzNGU2c/utno8G+DIg
T9ePlEwYk0i0G7gXFxDXOe6x4WAaRRloLQoLZD3w2cNwoAL0kNRPAYTK5R6zRNoJF6arBafGS5pH
ztZ2R4/wQ67lL55kysZvdO7shju/dAWG0J+EtQOw7QUFZuxB7sTbgLENBshUzYsAHBKmAh8F9N2s
K/SSu4KaKImgdNhOwAkt4QMJJoeRKwYaUtU64waYxW6Ptw5A6ERYuBqVPCKbvQwFFCcMdzy0KJtz
d/fw/VQ7J9WWs5OFEzBRYaqAIyPWoKOWe2McMwqfePITVQqRZY8TxvjyEBzL4V2AHnkox4EBExrQ
qxaHfqDB2BbmF4QJT8QtHEWgIJBS1I9TbyUSI0x8VBi/EtXe84twCVz42IPF9GIKrJEkqpir+2Vd
sJGHu9NNyhRmMLmiVAPdIOapvCgQYzAVBjkdxjP3k6PJmzWivoJtIouOeB+4ACLcCeel/fCOlyKF
hQA2O1gOcBkgEx/eIW3lRC+m0aDN/MiRslGhEpzToVKgWGJ3DgHTgV09icCOHiwJhaYpbC+7+hYT
PNny4uo6UIA1VxDgVBcsEOZDjwlxlFyt56qO3wxeDiKOKjiSvV57RVgALaDYG6YidIIX9NArqGv+
4jHyCgF1/mvHjij6n082CgNjcTFakeADh9UEIkzrwLxqtxBUB5xdwWIWCNwAelHFvZM8CNiGxY6j
PLoMm+DGxwlFV7flSHJwdQ418QfHeji1yb194CpUYd+VB2UuJEeZg0DiMG4HDX+J4K5YrJbjJsU9
4h1Au4ObB64NHhAwstAtElS09F5/qCeyiAPicm8RMmL67bzsURWfZUzCmhwRpAidShF0r7WTY4Tn
RfwwhkSUkHnC5hxKJ+yJafgJtS5Q8Uipqp8YbWGGyOIBkyZKOItfsMWZ6RC9Q9TOUtEe7bpHQC/V
yhn3x80vE/x2qEY1hmJc82EaXj5AIz0mRaAk4dQK0oAAaZ8xwQ+ASYQxwew0x0IQcpAccBLx+Dt6
9qoBpOyRw6kAs7z06sCNVUgSESlIQXDP26GTEtM9QMPxQCGS7bQzDQra+DQ8D+funiuiTdJWdIEw
IRe0pEjUJI7Mi1Qncm2USjVL+pZOEc5exGlGjnDg4muqbukw6SJDu7Mmm+EWY8mpDKCi3DJeBCf4
3obTDn+xCaxsaypnqVhe5Fie0zGmL44ag8hTJFe3EzCuGaOdXO5mF+SOEqYIfsgaLCbU4qtMTMZQ
Pnp/wNyO1i9jTa5U7kQfkxt+Iv7nlZUurs18gUYfDOoUP6DLzkIeJQsLZPciJHbC/1d6pyo2lys4
J7xRauVgfZ4QGm4RDHzSFHq4VWgU0vweTI9oQpKcEHKvu8gAF/y0LmetyXMwRE1JgW/RXMY3Hym+
6E5uAMYO0GRMCVJWRRTWibqB9zSq7EHlhN1ImB9TT4nDldkpszw+LieKUaQMCPAVRyfjMES7lc80
LK5q0r+EXmJzfKiiVkImkJNER4kCP6qhhiJfjQuZMV5QJgoRg7xe4GksUceFTN+RByIUoKg/gv1G
iYF8hBRC6s9ZxC8mZk42IzjEdUufvPjiQurC7aUyNJk9nTBKAi8hJHZ1CrTADRWj7Bs6kh5AgpIT
iBZH44jbGt2g4P7RkeV4LRdEtIDY9YJmUooy5WXaV1tH9SxClQV7X2XbJirg5shcKaWxAvNsxFXq
gIb+lJine1VNcP4MpycvG0lZPekJ4lYX5ByJ+gw3rzcRsdCiLFgZEvrTbEWpQosQY2xSbP7thy4E
Ue7cCrqjagujRKyWEDKsKdmaKAGCDt/RbJ2d3DaCVCi/tTpU5Bb+mOFAgEB1x7KW5+tb8fPAg9sX
KVdrj0nQB8JJUbviOoqEA/gcYRMX/U6W8Ivub5tfIo0i0sE1UQVJzObOJ//yyf8D49vvU2uUAAA=
B64
cat > "$T/exception_pl-PL.json.b64" <<'B64'
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
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
