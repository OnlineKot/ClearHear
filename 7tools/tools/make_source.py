#!/usr/bin/env python3
# Generuje source.json dla AltStore / SideStore.
#
#   make_source.py <adres_strony> <wersja> <build> <rozmiar_bajtow> <data RRRR-MM-DD>
#
import json
import sys

site, version, build, size, date = sys.argv[1:6]
site = site.rstrip("/")
icon = f"{site}/7tools/icons/icon-512.png"
ipa = f"{site}/7tools/install/SevenTools.ipa"

app = {
    "name": "007Tools",
    "bundleIdentifier": "pl.fastlink.seventools",
    "developerName": "FastLink",
    "subtitle": "Dźwięk, narzędzia i psikusy",
    "localizedDescription": "Looper, soundboard z biblioteką dźwięków z internetu, sampler, słuchanie z odszumianiem (dawne HearNow), efekty głosu, lokalizacja, tryb obrotowy, gesty, narzędzia i psikusy.",
    "iconURL": icon,
    "tintColor": "E0B84D",
    "screenshotURLs": [],
    # nowy format (AltStore 2, SideStore)
    "versions": [{
        "version": version,
        "buildVersion": str(build),
        "date": date,
        "downloadURL": ipa,
        "size": int(size),
        "minOSVersion": "26.0",
    }],
    # stary format, dla starszych klientow
    "version": version,
    "versionDate": date,
    "downloadURL": ipa,
    "size": int(size),
    "appPermissions": {"entitlements": [], "privacy": {}},
}

source = {
    "name": "FastLink 007Tools",
    "identifier": "pl.fastlink.seventools.source",
    "sourceURL": f"{site}/7tools/install/source.json",
    "subtitle": "007Tools",
    "description": "Źródło z aplikacją 007Tools.",
    "iconURL": icon,
    "website": f"{site}/7tools/install/",
    "tintColor": "E0B84D",
    "apps": [app],
    "news": [],
}

print(json.dumps(source, ensure_ascii=False, indent=2))
