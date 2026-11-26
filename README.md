# Snapmaker U1: dodatkowe języki ekranu

*English version below.*

> **Nieoficjalny projekt. Używasz na własne ryzyko; zmiany w systemie drukarki mogą wpłynąć na gwarancję.**
> Projekt nie jest związany z firmą Snapmaker.

Polski i czeski na ekranie Snapmaker U1, wgrywane przez SSH do nakładki systemu. Program ekranu i firmware zostają bez zmian. Sprawdzone z firmware 2.1.2.159.

## Jak zainstalować
Najprościej: pobierz [`docs/index.html`](docs/index.html), otwórz w przeglądarce i idź krok po kroku (włączenie Root Access, adres IP, skrypt).

Wersja „dwuklik” w [`launchery/`](launchery/): `U1-wgraj-polski`, `U1-wgraj-czeski`, `U1-powrot-do-oryginalu` (`.command` na Macu, `.bat` w Windows). Mac sprawdzony; **Windows nietestowany na prawdziwym Windows**. Przeczytaj `launchery/CZYTAJ-TO.txt`.

Powrót do oryginału usuwa dodane języki i żółty pasek, czyści całą nakładkę (także inne dodatki) i restartuje drukarkę. Przeznaczone dla oryginalnego firmware Snapmakera.

Nie uruchamiaj niczego w trakcie wydruku. Aktualizacja firmware może usunąć dodany język.

## Zawartość
| Folder | Co to jest |
|---|---|
| `docs/` | strona z instrukcją i generatorem skryptu (PL i EN) |
| `launchery/` | pliki dla Maca i Windowsa |
| `tlumaczenia/` | polski i czeski (czeski nie był sprawdzony przez osobę mówiącą po czesku) |
| `instalator/` | skrypt wykonywany na drukarce i jego generator |
| `przyklady/` | zrzuty z emulatora |

## Inne języki
Alfabet łaciński (poza rumuńskimi Ț ț), cyrylica, grecki i wietnamski wystarczy wgrać jako „Własny język” (dwa pliki). O innych alfabetach jest krótka ciekawostka na stronie; nie są częścią instalatora.

## Licencja
Tłumaczenia i skrypty: MIT. Oryginalne napisy, zrzuty ekranu, firmware i nazwa Snapmaker należą do Snapmakera. Na żądanie uprawnionego podmiotu usunę lub zmienię, co trzeba.

---

# Snapmaker U1: extra screen languages

> **Unofficial project. Use at your own risk; changing the printer system may affect your warranty.** Not affiliated with Snapmaker.

Polish and Czech for the Snapmaker U1 touchscreen, installed over SSH into the system overlay. The screen program and firmware are not modified. Tested with firmware 2.1.2.159.

Download [`docs/index-en.html`](docs/index-en.html), open it in a browser and follow the steps. Double-click files are in [`launchery/`](launchery/): `U1-install-polish`, `U1-install-czech`, `U1-return-to-original` (`.command` for Mac, `.bat` for Windows; the Windows ones have **not** been tested on a real Windows). Return to original removes added languages and the yellow bar, clears the whole overlay (including other add-ons) and restarts the printer. Latin (except Romanian Ț ț), Cyrillic, Greek and Vietnamese languages work with stock fonts; other alphabets are only mentioned on the page as a side note.

License: MIT for translations and scripts. Snapmaker's original strings, screenshots, firmware and name belong to Snapmaker.
