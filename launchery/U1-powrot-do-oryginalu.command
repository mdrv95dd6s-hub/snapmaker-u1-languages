#!/bin/bash
# Snapmaker U1: powrót do oryginału (macOS).
# Wymagania: macOS z Terminalem i wbudowanym poleceniem ssh. Drukarka: Root Access włączony, firmware 2.1.2.159.
# Pyta o adres IP drukarki, łączy się przez ssh jako root i uruchamia skrypt z końca tego pliku (po linii __U1_PAYLOAD__).
# Pierwsze uruchomienie: kliknij plik prawym przyciskiem, Otwórz. Jeśli się nie uruchamia: chmod +x w Terminalu.
SSH="${U1_SSH:-ssh}"; PORT="${U1_PORT:-22}"
echo "=== Snapmaker U1: powrót do oryginału ==="
echo "Drukarka musi mieć włączony Root Access i nie może drukować."
echo
echo "Gdzie znaleźć adres IP: na ekranie drukarki dotknij ikony sześcianu (Ustawienia), potem wejdź w Wi-Fi."
echo "Pod nazwą połączonej sieci (zielony znacznik) jest napis IP, np. 192.168.0.100. Komputer musi być w tej samej sieci."
echo
read -r -p "Adres IP drukarki (na drukarce: Ustawienia, Wi-Fi): " IP
IP="${IP//[[:space:]]/}"
if ! [[ "$IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || "$IP" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,60}$ ]]; then echo "To nie wygląda na adres IP."; read -r -p "Naciśnij Enter, aby zamknąć."; exit 1; fi
T="$(mktemp -t u1jezyk)"; trap 'rm -f "$T"' EXIT
sed -n '/^__U1_PAYLOAD__$/,$p' "$0" | tail -n +2 > "$T"
echo
echo "Zaraz ssh zapyta o hasło konta root (takie jak w instrukcji na stronie, przy Root Access)."
echo "Podczas wpisywania hasła znaki nie są widoczne. To normalne."
echo
$SSH -p "$PORT" -o StrictHostKeyChecking=accept-new root@"$IP" sh -s < "$T"; RC=$?
echo
if [ $RC -ne 0 ]; then
  echo "Coś poszło nie tak (kod $RC)."
  echo "Jeśli widzisz napis REMOTE HOST IDENTIFICATION HAS CHANGED, wpisz: ssh-keygen -R $IP  i uruchom ten plik jeszcze raz."
fi
read -r -p "Naciśnij Enter, aby zamknąć."
exit $RC
__U1_PAYLOAD__
cat > /tmp/u1lang.sh <<'U1_EOF'
#!/bin/sh
# Snapmaker U1: dodatkowe języki ekranu. Skrypt wykonuje się NA DRUKARCE (przez SSH).
# Dodaje pliki języka w nakładce, zapisuje ustawienie języka i flagę trwałości.
set -eu
MODE="remove"        # install | remove
LANGS="pl-PL"      # np. "pl-PL cs-CZ"
ACTIVE="pl-PL"    # język do włączenia po instalacji (puste = nie zmieniaj)
HIDE="yes"        # yes = ukryj pasek debug na dole ekranu (zalecane), no = zostaw
R=/home/lava/resource
T=/tmp/u1lang
say() { echo ">> $*"; }
die() { echo "BŁĄD: $*"; exit 1; }

[ "$(id -u)" = 0 ] || die "to nie jest konto root"
[ -f "$R/locales/en-GB.json" ] || die "to nie wygląda na Snapmaker U1"
command -v python3 >/dev/null 2>&1 || die "brak python3 na drukarce"
say "Firmware: $(cat /etc/FULLVERSION 2>/dev/null)"

python3 - <<'PY' || exit 1
import json, sys, urllib.request
try:
    s = json.load(urllib.request.urlopen("http://127.0.0.1:7125/printer/objects/query?print_stats", timeout=5))["result"]["status"]["print_stats"]["state"]
except Exception as exc:
    print("BŁĄD: nie udało się sprawdzić stanu drukarki. Nie wprowadzono zmian.", file=sys.stderr)
    sys.exit(2)
print(">> Stan drukarki:", s)
if s not in ("standby", "complete", "cancelled"):
    print("BŁĄD: drukarka nie jest gotowa do zmiany języka. Sprawdź jej stan i spróbuj ponownie.", file=sys.stderr)
    sys.exit(2)
PY

# Sprawdza, czy wcześniej wgrano języki tą metodą (lub podmieniono slot turecki) i wypisuje stan.
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
        changed.append(c + " (zawiera \"" + str(n) + "\")")
try:
    active = json.load(open("/home/lava/printer_data/config/gui_config.json", encoding="utf-8"))["system"]["language"]
except Exception:
    active = "?"
print(">> Aktywny język ekranu:", active)
if extra:
    print(">> Wcześniej wgrane języki dodatkowe:", ", ".join(extra))
if changed:
    print(">> Podmieniony język wbudowany (starsza instalacja):", ", ".join(changed))
if not extra and not changed:
    print(">> Wcześniej nie wgrywano tu żadnych języków.")
PYDET
}

# Pasek debug na dole ekranu pokazuje gui, gdy przy jego starcie istnieje /oem/.debug.
# Plik jest potrzebny, by nakładka przetrwała restart, więc chowam go tylko na czas startu gui:
# kopia S90lmd w nakładce (tworzona z oryginału z /overlay) chowa plik i oddaje go po starcie ekranu.
hide_patch() {   # $1 = on | off
  python3 - "$1" <<'PYHIDE'
import os, sys
mode = sys.argv[1]
lower, p = "/overlay/etc/init.d/S90lmd", "/etc/init.d/S90lmd"
OLD = '        start-stop-daemon -S -b -x "$PROG" -- -c "$APPS_CGROUP"\n'
NEW = OLD.replace("        start", """        # u1-lang: ukryj /oem/.debug na czas startu ekranu (inaczej gui pokazuje pasek debug na dole);
        # plik wraca zaraz po starcie gui, bo bez niego nakładka jest kasowana przy następnym rozruchu
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
    print(">> Pasek debug: pomijam (brak oryginału S90lmd)"); sys.exit(0)
if mode == "on":
    if base.count(OLD) != 1:
        print(">> Pasek debug: pomijam (S90lmd w tym firmware wygląda inaczej)"); sys.exit(0)
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
print(">> Pasek debug na ekranie:", "ukrywany przy starcie" if mode == "on" else "bez zmian (oryginalny S90lmd)")
PYHIDE
  if [ -f /oem/.debug.u1hold ] && [ ! -f /oem/.debug ]; then mv -f /oem/.debug.u1hold /oem/.debug; fi
}

lang_name() {   # $1 = kod języka; wypisuje jego nazwę z pliku (albo sam kod)
  python3 - "$R" "$1" <<'PYNAME' 2>/dev/null || echo "$1"
import json, sys
print(json.load(open(sys.argv[1] + "/locales/" + sys.argv[2] + ".json", encoding="utf-8")).get("language_name", sys.argv[2]))
PYNAME
}

set_language() {
  say "Zatrzymuję ekran (chwilę będzie czarny)..."
  say "NIE WYŁĄCZAJ drukarki ani zasilania, dopóki w tym oknie nie pojawi się napis „Gotowe.” (około minuty)."
  # Przy błędzie lub przerwaniu spróbuj przywrócić działanie ekranu.
  trap '/etc/init.d/S90lmd start >/dev/null 2>&1 || true' EXIT
  trap 'exit 1' HUP INT TERM
  /etc/init.d/S90lmd stop >/dev/null 2>&1 </dev/null || true
  # stop działa asynchronicznie: poczekaj, aż ekran i jego nadzorca naprawdę się zamkną
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
print(">> Język w konfiguracji:", sys.argv[1])
PYCONFIG
  sync
  # start bywa zgłaszany kodem błędu mimo powodzenia (lub gdy poprzedni lmd jeszcze się zamykał),
  # więc o sukcesie decyduje obecność procesu gui, a start ponawiam
  n=0
  while [ -z "$(pidof gui || true)" ] && [ "$n" -lt 4 ]; do
    /etc/init.d/S90lmd start >/dev/null 2>&1 </dev/null || true
    i=0; while [ -z "$(pidof gui || true)" ] && [ "$i" -lt 25 ]; do sleep 2; i=$((i+1)); done
    n=$((n+1))
  done
  [ -n "$(pidof gui || true)" ] || die "ekran nie wystartował; sprawdź drukarkę (wyłącz i włącz zasilanie, jeśli ekran jest czarny)"
  sleep 5
  trap - EXIT HUP INT TERM
  say "Ekran działa."
}

if [ "$MODE" = remove ]; then
  # Powrót do oryginału. /overlay to fabryczny system tylko do odczytu; bez niego niczego nie ruszamy.
  [ -f "/overlay$R/locales/en-GB.json" ] || die "brak oryginalnego systemu w /overlay; niczego nie zmieniłem"
  say "Wracam do oryginału: usuwam dodane języki i ukrywanie paska, a potem czyszczę nakładkę."
  say "Uwaga: czyszczenie usuwa też inne zmiany zapisane w nakładce (np. inne dodatki)."
  CUR=$(python3 -c "import json;print(json.load(open('/home/lava/printer_data/config/gui_config.json'))['system']['language'])")
  for F in "$R"/locales/*.json; do
    L=$(basename "$F" .json)
    [ -e "/overlay$R/locales/$L.json" ] && continue
    rm -f "$R/locales/$L.json" "$R/text/exception_$L.json"; say "Usunięto dodany język $L"
  done
  hide_patch off
  if [ ! -e "/overlay$R/locales/$CUR.json" ]; then set_language en-GB; fi
  # bez /oem/.debug drukarka przy starcie sama czyści nakładkę (S01aoverlayfs), czyli tak jak fabrycznie
  rm -f /oem/.debug /oem/.debug.u1hold; sync
  say "Usunięto /oem/.debug: po restarcie nie będzie żółtego paska, a nakładka wróci do stanu fabrycznego."
  say "Gotowe. Za kilka sekund drukarka uruchomi się ponownie. Nie wyłączaj zasilania; poczekaj, aż pojawi się ekran."
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
            data = raw   # plik własny (bez gzip)
        open(f"{T}/{name}", "wb").write(data)
        pl = json.loads(data); e = json.load(open(f"{R}/{sub}/{en}", encoding="utf-8"))
        if not isinstance(pl, dict) or not isinstance(e, dict):
            raise ValueError(f"{name}: oczekiwano obiektu JSON")
        miss = [k for k in e if k not in pl]
        bad = [k for k in e if k in pl and (type(e[k]) is not type(pl[k]) or (isinstance(e[k], str) and tok(e[k]) != tok(pl[k])))]
        if miss or bad:
            good = False; print(f">> POMIJAM {L}: {name} nie pasuje do tego firmware (brak kluczy: {len(miss)}, złe znaczniki: {len(bad)})")
    if good: ok.append(L)
open(f"{T}/ok", "w").write(" ".join(ok))
PY

OK=$(cat "$T/ok")
[ -n "$OK" ] || die "żaden język nie pasuje do tego firmware, niczego nie zmieniłem"
for L in $OK; do
  cp "$T/$L.json" "$R/locales/$L.json"; cp "$T/exception_$L.json" "$R/text/exception_$L.json"
  chmod 644 "$R/locales/$L.json" "$R/text/exception_$L.json"; say "Wgrano język $L"
done
touch /oem/.debug; sync
if [ "$HIDE" = yes ]; then hide_patch on; else hide_patch off; fi
say "Pliki zapisane w nakładce. Flaga /oem/.debug utrzymuje je po restarcie."
if [ -n "$ACTIVE" ]; then
  case " $OK " in *" $ACTIVE "*)
      N=$(lang_name "$ACTIVE")
      say "Język $N ($ACTIVE) ustawi się automatycznie."
      say "Uwaga: po wybraniu innego języka w menu drukarki nie będzie powrotu do: $N. Żeby do niego wrócić, uruchom ten skrypt ponownie."
      set_language "$ACTIVE" ;; *) echo "UWAGA: język $ACTIVE nie został wgrany, nie zmieniam ustawienia." ;; esac
fi
rm -rf "$T"
say "Gotowe."

U1_EOF
sh /tmp/u1lang.sh </dev/null; rc=$?; rm -f /tmp/u1lang.sh; exit $rc
