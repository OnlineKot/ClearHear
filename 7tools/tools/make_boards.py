#!/usr/bin/env python3
# Buduje katalog soundboardow (boards.json) z Openverse: prawdziwe nagrania na wolnych licencjach.
# Openverse bez klucza daje 20 zapytan na minute i 200 na dobe, wiec skrypt zwalnia i zapamietuje wyniki w cache.
#
#   python3 tools/make_boards.py <plik_wyjsciowy.json>
import json, sys, time, threading, urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

LICENSES = "cc0,by,by-sa,pdm"
CACHE = Path(__file__).resolve().parent / ".boards_cache.json"
cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}

# (id, tytul, emoji, [(etykieta po polsku, zapytanie, wymagane slowa w tytule/tagach (jedno z), max sekund)])
BOARDS = [
 ("perkusja", "Perkusja", "🥁", [("Stopa", "kick drum", ["kick", "bass drum"], 3), ("Werbel", "snare drum", ["snare"], 3),
   ("Hi-hat", "hi hat", ["hat", "hihat"], 3), ("Klaps", "hand clap", ["clap"], 3), ("Tom", "tom drum", ["tom"], 4),
   ("Talerz", "cymbal crash", ["cymbal", "crash"], 6), ("Cowbell", "cowbell", ["cowbell"], 4), ("Rimshot", "rimshot", ["rimshot", "rim shot", "ba dum"], 5)]),
 ("reakcje", "Reakcje", "😂", [("Śmiech", "laugh", ["laugh"], 6), ("Brawa", "applause", ["applause", "clap"], 7), ("Buczenie", "crowd boo", ["boo"], 6),
   ("Wiwaty", "crowd cheer", ["cheer"], 7), ("Westchnienie", "gasp", ["gasp"], 4), ("Smutna trąbka", "sad trombone", ["trombone", "fail"], 6),
   ("Werbel rolka", "drum roll", ["roll"], 7), ("Gwizd", "whistle", ["whistle"], 5)]),
 ("zwierzeta", "Zwierzęta", "🐶", [("Pies", "dog bark", ["dog", "bark"], 5), ("Kot", "cat meow", ["cat", "meow"], 5), ("Krowa", "cow moo", ["cow", "moo"], 6),
   ("Kogut", "rooster crow", ["rooster", "cock"], 6), ("Koń", "horse neigh", ["horse", "neigh"], 6), ("Świnia", "pig oink", ["pig", "oink"], 6),
   ("Owca", "sheep bleat", ["sheep", "bleat"], 6), ("Kaczka", "duck quack", ["duck", "quack"], 5)]),
 ("pojazdy", "Pojazdy", "🚗", [("Klakson", "car horn", ["horn"], 5), ("Policja", "police siren", ["police", "siren"], 8), ("Karetka", "ambulance siren", ["ambulance", "siren"], 8),
   ("Pociąg", "train horn", ["train"], 8), ("Samolot", "airplane flyby", ["plane", "jet", "airplane"], 8), ("Helikopter", "helicopter", ["helicopter"], 8),
   ("Motor", "motorcycle engine", ["motorcycle", "motorbike", "bike"], 8), ("Pisk opon", "tire screech", ["tire", "tyre", "screech", "skid"], 6)]),
 ("filmowe", "Efekty filmowe", "🎬", [("Wybuch", "explosion", ["explosion", "explode"], 7), ("Whoosh", "whoosh", ["whoosh", "swoosh"], 4), ("Cios", "punch hit", ["punch", "hit"], 3),
   ("Miecz", "sword", ["sword"], 5), ("Grzmot", "thunder", ["thunder"], 8), ("Szkło", "glass break", ["glass"], 5), ("Krzyk", "scream", ["scream"], 6),
   ("Uderzenie", "cinematic impact", ["impact", "boom"], 6)]),
 ("dom", "Dom", "🏠", [("Dzwonek", "doorbell", ["doorbell", "door bell"], 6), ("Pukanie", "knock on door", ["knock"], 5), ("Telefon", "telephone ring", ["phone", "ring"], 7),
   ("Budzik", "alarm clock", ["alarm"], 7), ("Mikrofalówka", "microwave beep", ["microwave"], 6), ("Kapanie", "water drip", ["drip"], 7),
   ("Klawiatura", "keyboard typing", ["typing", "keyboard"], 8), ("Aparat", "camera shutter", ["camera", "shutter"], 3)]),
 ("natura", "Natura", "🌲", [("Deszcz", "rain", ["rain"], 8), ("Wiatr", "wind", ["wind"], 8), ("Fale", "ocean waves", ["wave", "ocean", "sea"], 8),
   ("Ognisko", "fire crackle", ["fire", "crackl"], 8), ("Ptaki", "birds singing", ["bird"], 8), ("Świerszcze", "crickets", ["cricket"], 8),
   ("Wodospad", "waterfall", ["waterfall"], 8), ("Rzeka", "river stream", ["river", "stream"], 8)]),
 ("scifi", "Sci-Fi", "🛸", [("Laser", "laser", ["laser"], 4), ("Robot", "robot", ["robot"], 5), ("Obcy", "alien", ["alien"], 6), ("Teleport", "teleport", ["teleport"], 5),
   ("Statek", "spaceship", ["space", "ship"], 8), ("Power-up", "power up", ["power up", "powerup", "charge"], 5), ("Power-down", "power down", ["power down", "powerdown", "shutdown"], 5),
   ("Komputer", "computer beep", ["computer", "beep"], 5)]),
 ("retro", "Retro gry", "🕹️", [("Moneta", "8bit coin", ["coin"], 3), ("Skok", "8bit jump", ["jump"], 3), ("Game over", "game over", ["game over", "gameover", "lose"], 6),
   ("Level up", "level up", ["level"], 5), ("Wybuch 8-bit", "8bit explosion", ["explosion", "explode"], 4), ("Blip", "blip", ["blip", "beep"], 3),
   ("Laser 8-bit", "8bit laser", ["laser", "shoot"], 4), ("Bonus", "8bit power up", ["power", "bonus"], 4)]),
 ("straszne", "Straszne", "👻", [("Śmiech zła", "evil laugh", ["evil", "laugh"], 8), ("Duch", "ghost", ["ghost"], 8), ("Szept", "creepy whisper", ["whisper"], 8),
   ("Serce", "heartbeat", ["heart"], 8), ("Skrzyp drzwi", "door creak", ["creak"], 6), ("Łańcuchy", "chains", ["chain"], 6),
   ("Horror", "horror sting", ["horror", "sting"], 6), ("Wycie", "wolf howl", ["wolf", "howl"], 8)]),
 ("impreza", "Impreza", "🎉", [("Róg", "air horn", ["air horn", "airhorn"], 6), ("Scratch", "record scratch", ["scratch"], 4), ("Trąbka imprezowa", "party horn", ["party", "horn", "blower"], 5),
   ("Balon", "balloon pop", ["balloon"], 3), ("Szampan", "champagne pop", ["champagne", "cork", "pop"], 4), ("Tłum", "crowd cheering", ["crowd", "cheer"], 8),
   ("Bass drop", "bass drop", ["drop", "bass"], 8), ("Rewers", "reverse cymbal", ["reverse", "riser"], 7)]),
 ("instrumenty", "Instrumenty", "🎹", [("Pianino", "piano note", ["piano"], 6), ("Gitara", "guitar chord", ["guitar"], 6), ("Skrzypce", "violin", ["violin"], 7),
   ("Trąbka", "trumpet", ["trumpet"], 6), ("Flet", "flute", ["flute"], 7), ("Dzwon", "church bell", ["bell"], 8), ("Gong", "gong", ["gong"], 8), ("Ksylofon", "xylophone", ["xylophone"], 6)]),
 ("ludzie", "Ludzie", "🗣️", [("Pstryk", "finger snap", ["snap"], 3), ("Kaszel", "cough", ["cough"], 4), ("Kichnięcie", "sneeze", ["sneeze"], 4),
   ("Całus", "kiss", ["kiss"], 3), ("Beknięcie", "burp", ["burp"], 4), ("Ziewanie", "yawn", ["yawn"], 5), ("Dziecko", "baby laugh", ["baby"], 6),
   ("Szmer tłumu", "crowd murmur", ["crowd", "murmur"], 8)]),
]
NUMBERS = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]

lock = threading.Lock()

def search(q, page=1):
    key = f"{q}|{page}"
    if key in cache: return cache[key]
    p = {"q": q, "page_size": 20, "page": page, "license": LICENSES}
    url = "https://api.openverse.org/v1/audio/?" + urllib.parse.urlencode(p)
    for attempt in range(4):
        try:
            time.sleep(3.4)
            req = urllib.request.Request(url, headers={"User-Agent": "7Tools-catalog-builder"})
            data = json.load(urllib.request.urlopen(req, timeout=60))
            with lock:
                cache[key] = data.get("results", [])
                CACHE.write_text(json.dumps(cache))
            return cache[key]
        except Exception as e:
            print("  blad", q, e, file=sys.stderr)
            time.sleep(8)
    return []

RANK = {"cc0": 0, "pdm": 0, "by": 1, "by-sa": 2}

def usable(r, words, max_s, used):
    if r["id"] in used: return False
    d = (r.get("duration") or 0) / 1000
    if d < 0.15 or d > max_s: return False
    if (r.get("filesize") or 0) > 900_000: return False
    if not r["url"].endswith((".mp3", ".wav", ".m4a", ".ogg")): return False
    hay = (r.get("title", "") + " " + " ".join(t.get("name", "") for t in (r.get("tags") or []))).lower()
    return any(w in hay for w in words)

def pick(results, words, max_s, used, n):
    ok = [r for r in results if usable(r, words, max_s, used)]
    ok.sort(key=lambda r: RANK.get(r["license"], 3))
    return ok[:n]

def entry(label, r, n, suffix=""):
    return {"n": n, "title": label + suffix, "original": (r.get("title") or "")[:60], "url": r["url"],
            "creator": r.get("creator") or "", "license": r["license"], "page": r.get("foreign_landing_url") or "",
            "seconds": round((r.get("duration") or 0) / 1000, 2)}

# opoznienie odpowiedzi API bywa duze, wiec zapytania lecą rownolegle (8 naraz miesci sie w limicie 20/min)
queries = [q for _, _, _, slots in BOARDS for (_, q, _, _) in slots]
with ThreadPoolExecutor(max_workers=8) as ex:
    list(ex.map(search, queries))
print("zapytania gotowe:", len(cache), file=sys.stderr)

used = set()
boards = []
for bid, title, emoji, slots in BOARDS:
    print("==", title)
    sounds = []
    for label, q, words, max_s in slots:
        res = search(q)
        chosen = pick(res, words, max_s, used, 2)
        if len(chosen) < 2:   # druga strona wynikow, jesli za malo
            res2 = search(q, 2)
            chosen = pick(res + res2, words, max_s, used, 2)
        for i, r in enumerate(chosen):
            used.add(r["id"])
            sounds.append(entry(label, r, len(sounds) + 1, "" if i == 0 else " 2"))
        print("  ", label, len(chosen))
    boards.append({"id": bid, "title": title, "emoji": emoji, "sounds": sounds})

# paczka startowa: 16 dzwiekow na pady banku A
def find(bid, label):
    for b in boards:
        if b["id"] == bid:
            for s in b["sounds"]:
                if s["title"] == label: return {"board": bid, "n": s["n"]}
    return None

STARTER = [("perkusja", "Stopa"), ("perkusja", "Werbel"), ("perkusja", "Hi-hat"), ("perkusja", "Klaps"),
           ("impreza", "Róg"), ("impreza", "Scratch"), ("reakcje", "Śmiech"), ("reakcje", "Brawa"),
           ("filmowe", "Wybuch"), ("filmowe", "Whoosh"), ("scifi", "Laser"), ("retro", "Moneta"),
           ("pojazdy", "Policja"), ("zwierzeta", "Pies"), ("impreza", "Bass drop"), ("filmowe", "Cios")]
starter = [x for x in (find(b, l) for b, l in STARTER) if x]

out = {"version": 1, "updated": time.strftime("%Y-%m-%d"), "source": "Openverse (Freesound i inne), licencje CC0 / CC BY / CC BY-SA / domena publiczna",
       "boards": boards, "starter": starter}
Path(sys.argv[1]).write_text(json.dumps(out, ensure_ascii=False, indent=1))
print("zapisano", sys.argv[1], sum(len(b["sounds"]) for b in boards), "dzwiekow,", len(starter), "w paczce startowej")
