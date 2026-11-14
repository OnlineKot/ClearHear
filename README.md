# HearNow

Apka na iPhone'a, która bierze dźwięk z mikrofonu telefonu i na żywo gra go w słuchawkach, ale głos jest głośniejszy i wyraźniejszy, a szum cichszy. Coś jak Live Listen, tylko z własnym odszumianiem. Działa w tle (po zablokowaniu ekranu) i da się ją dodać do LiveContainera. Strona instalacji: `/hearnow/install`.

## Jak to działa

Mikrofon idzie przez `AVAudioSinkNode` do własnego procesora (`HearNow/Voice.swift`), potem przez bufor kołowy (`Ring.swift`) do `AVAudioSourceNode` i do słuchawek. Procesor liczy w ramkach po 1024 próbki co 256:

1. FFT.
2. Śledzenie szumu osobno w każdym paśmie (szybko w dół, wolno w górę) i odjęcie go filtrem Wienera z "decision directed", żeby nie było "brzęczenia" po odszumieniu.
3. Krzywa pod głos: odcięcie poniżej 70 Hz, lekkie odmulenie 250 Hz, podbicie około 2,8 kHz (tam siedzą spółgłoski) i ucięcie syku powyżej 6 kHz.
4. Bramka między zdaniami: gdy w paśmie 300 do 3400 Hz nie ma nic wyraźnie ponad tłem, przycina jeszcze do 8 dB.
5. FFT w drugą stronę, wyrównywanie głośności (cichy głos jest podciągany, głośny przycinany, suwak ustawia docelowy poziom), limiter i miękki sufit 0,6, a po starcie głośność narasta przez pół sekundy. Okrzyk nie bije po uszach, a szept nie ginie.

Suwaki: **Głośność** (docelowy poziom, 0 do +24 dB), **Odszumianie** (siła i głębokość), **Wyrazistość głosu** (siła podbicia). Cztery gotowe ustawienia: Rozmowa, Tłum, Z daleka, Cisza.

W ustawieniach wybierasz mikrofon (dolny, przedni, tylny) i czy ma być kierunkowy. Kieruje się go na rozmówcę.

## Sprawdzian bez telefonu

`HearNow/Voice.swift` i `Ring.swift` nie używają niczego z Apple poza Foundation, więc `tools/dsp_check.swift` odpala je na Macu i na Linuksie:

```
swiftc -O -parse-as-library HearNow/Voice.swift HearNow/Ring.swift tools/dsp_check.swift -o dspcheck
./dspcheck
```

Sprawdza FFT, bufor, przejście tonu bez zmiany poziomu, sztuczną mowę z różowym szumem, limiter, ciszę i obciążenie procesora. Na sztucznej mowie szum między słowami spada o ok. 25 dB (przy pełnym odszumianiu o 35 dB), a głos zmienia się o mniej niż 3 dB. Ten sam sprawdzian leci w CI przed budowaniem apki. To sztuczny sygnał, na prawdziwej mowie i prawdziwym hałasie warto posłuchać samemu.

## Czego trzeba i co z tym bywa

- **Słuchawki są wymagane.** Bez nich mikrofon grałby w głośnik i piszczał, więc apka się nie włączy. Odłączenie słuchawek w trakcie wyłącza słuchanie.
- **Bluetooth ma opóźnienie.** Dźwięk z mikrofonu telefonu idzie do słuchawek przez A2DP (dobra jakość, bez przełączania na rozmowny profil HFP), ale to dokłada ok. 0,1 do 0,3 s. Przewodowe mają najmniej.
- **Tło.** `UIBackgroundModes: audio` plus sesja `playAndRecord`. Apka podpina się też pod ekran blokady i przycisk w słuchawkach (play/pauza).
- **Przerwania.** Rozmowa albo Siri zatrzymują słuchanie, a po ich końcu apka wraca sama.
- **LiveContainer.** Apka nie ma żadnych rozszerzeń ani zadań w tle systemu, więc ma wszystko, czego LiveContainer potrzebuje. Jedyna niewiadoma to tło i mikrofon: zależą od tego, co ma włączone sam LiveContainer (zgoda na mikrofon i praca w tle). Nie sprawdzałem tego na prawdziwym telefonie. Apka wykrywa LiveContainera (`Runtime.swift`) i w ustawieniach podpowiada, gdzie szukać.
- **Izolacji głosu Apple** (tryb mikrofonu z Centrum sterowania) apka nie używa, bo wymaga trybu rozmowy, który psuje jakość Bluetooth i zmienia dźwięk. Zamiast tego ma własny procesor.

## Aktualizacje

Tak samo jak w Liquid Glass: apka przy starcie pobiera `https://fastlink.teodorteo.com/updateapi/hearnow.json` i porównuje `build` ze swoim numerem. Numer to numer przebiegu workflow `HearNow IPA`, a wersja (`1.0`) jest w `project.yml`. Po scaleniu do domyślnej gałęzi workflow jednym commitem wrzuca:

| Plik | Po co |
| --- | --- |
| `hearnow/install/HearNow.ipa` | plik do instalacji |
| `hearnow/install/source.json` | źródło dla AltStore |
| `hearnow/install/index.html` | strona instalacji (LiveContainer, SideStore, IPA) |
| `updateapi/hearnow.json` | numer najnowszego buildu dla apki |

## Budowanie

Potrzebny jest Xcode 26 (szkło to API z iOS 26) i XcodeGen:

```
brew install xcodegen
cd ClearHear
xcodegen generate
open HearNow.xcodeproj
```

Potem iPhone z iOS 26 i Run. W symulatorze nie ma sensu, bo nie ma prawdziwego mikrofonu ani słuchawek. Ikonę (i ikony na stronę) generuje `python3 tools/make_icon.py`.
