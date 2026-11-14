# 007Tools (7Tools)

Apka na iPhone'a z narzędziami dźwiękowymi, w Liquid Glass (iOS 26). Da się ją dodać do LiveContainera, SideStore'a i AltStore'a. Strona instalacji: `/7tools/install`.

## Co jest w środku

| Zakładka | Co robi |
| --- | --- |
| **Pady** | Soundboard 4x4, dwa banki. Każdy pad ma tryb: jednorazowy, pętla (dotknij, żeby włączyć i wyłączyć) albo dopóki trzymasz. Głośność i wysokość dźwięku osobno dla każdego pada. 16 dźwięków wbudowanych (generowane z kodu). |
| **Soundboardy** (Biblioteka → Internet) | Kolekcje po 16 prawdziwych nagrań z numerowanymi padami: perkusja, reakcje, zwierzęta, pojazdy, efekty filmowe, dom, natura, sci-fi, retro, straszne, impreza, instrumenty i ludzie. Dotykasz numer, a dźwięk pobiera się i gra. Całość da się pobrać naraz albo wrzucić jako bank na pady. Katalog (`boards.json`) jest w apce i na stronie, więc kolekcje można dokładać bez nowej wersji apki. Generuje go `tools/make_boards.py` z Openverse (CC0, CC BY, CC BY-SA, domena publiczna). |
| **Biblioteka** (z Pad) | Szukanie dźwięków w internecie (Openverse, wolne licencje CC, bez klucza), odsłuch, zapis, wstawianie od razu do pada. Autor i licencja zostają przy dźwięku. Do tego nagrywanie własnych i import plików. Każdy dźwięk da się wysłać (AirDrop) jako WAV. |
| **Pętla** | Looper: pierwsza warstwa ustala długość, kolejne dogrywasz na wierzch (do 8), cofanie, wyciszanie i głośność warstw. Nagrywa z mikrofonu albo z padów i klawiszy, więc można zapętlać soundboard. Metronom, zaokrąglanie do uderzeń, korekta opóźnienia. Zgranie do WAV i wysłanie AirDropem albo zapis do biblioteki. |
| **Sampler** | Dowolny dźwięk jako instrument: klawiatura na dwie oktawy, przycinanie, nuta bazowa, narastanie i wybrzmiewanie, pętla przy trzymaniu, odwracanie. Tryb "Pocięte": 16 równych kawałków na padach (chopy). |
| **Głos** | Mikrofon z efektami na żywo w słuchawkach: Agent 007, Robot, Pisklak, Demon, Echo, Hala, Telefon. Tylko ze słuchawkami, żeby nie piszczało. |
| **Narzędzia** | Stroik (YIN), generator tonów (sinus, prostokąt, piła, trójkąt, szum, przemiatanie), miernik dźwięku z wykresem, Morse (dźwięk, błysk ekranu i latarka). |

AirDrop: apka udostępnia pliki zwykłym arkuszem udostępniania, odbiorcę wybierasz sam. Masowego wysyłania do obcych nie ma, iOS na to nie pozwala, a poza tym to by było nękanie.

## Jak to jest zrobione

Cały dźwięk gra przez jeden mikser (`SevenTools/Core/Mixer.swift`): głosy z padów i klawiszy, looper, metronom i generator. Wszystkie te klocki są w czystym Swifcie bez AVFoundation, więc `tools/core_check.swift` odpala je na Macu i na Linuksie, bez telefonu:

```
swiftc -O -parse-as-library SevenTools/Core/*.swift tools/core_check.swift -o corecheck
./corecheck
```

Sprawdza dźwięki wbudowane, WAV, resampling, granie, wysokość dźwięku, pętle bez trzasków, limiter, looper (też z opóźnieniem mikrofonu i kwantyzacją), nagrywanie, stroik i Morse'a. Ten sam sprawdzian leci w CI przed budowaniem.

Warstwa Apple (`Audio/AudioHub.swift`) składa z tego `AVAudioEngine`: `AVAudioSourceNode` gra mikser, a `AVAudioSinkNode` oddaje do niego mikrofon. Mikrofon jest włączany dopiero, gdy jakaś funkcja go potrzebuje (looper z mikrofonu, nagrywanie, stroik, miernik, efekty głosu), i wyłączany, gdy przestaje.

## Czego nie ma i dlaczego

- **Spamu AirDropem** (niechciane pliki do obcych w pobliżu). To nękanie, a API Apple i tak wymaga wyboru odbiorcy przez użytkownika.
- **Dźwięków z chronionych serwisów** (np. wielkich zbiorów memów). Biblioteka to Openverse, czyli dźwięki, które wolno używać. CC BY wymaga podania autora, jeśli coś z tego publikujesz.
- **Rozszerzeń, widżetów i Live Activity.** W LiveContainerze one nie działają, więc apka ich nie ma.

## LiveContainer

Apka nie ma rozszerzeń ani zadań w tle systemu. Tło dźwięku (`UIBackgroundModes: audio`) i zgoda na mikrofon zależą w LiveContainerze od ustawień samego LiveContainera. Apka wykrywa go i w ustawieniach podpowiada, gdzie szukać.

## Budowanie

Potrzebny jest Xcode 26 i XcodeGen:

```
brew install xcodegen
cd 7tools
xcodegen generate
open SevenTools.xcodeproj
```

Ikonę generuje `python3 tools/make_icon.py`. W CI buduje ją workflow `7Tools IPA` i wystawia jako artefakt `SevenTools-ipa`.
