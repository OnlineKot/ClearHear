#!/usr/bin/env python3
# Generuje source.json dla AltStore / SideStore.
#
#   make_source.py <adres_strony> <wersja> <build> <rozmiar_bajtow> <data RRRR-MM-DD>
#
import json
import sys

site, version, build, size, date = sys.argv[1:6]
site = site.rstrip("/")
icon = f"{site}/hearnow/icons/icon-512.png"
ipa = f"{site}/hearnow/install/HearNow.ipa"

app = {
    "name": "HearNow",
    "bundleIdentifier": "pl.fastlink.hearnow",
    "developerName": "FastLink",
    "subtitle": "Słyszysz wyraźniej",
    "localizedDescription": "Mikrofon telefonu na żywo w słuchawkach. Odszumia i podbija głos, działa w tle.",
    "iconURL": icon,
    "tintColor": "0A84FF",
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
    "name": "FastLink HearNow",
    "identifier": "pl.fastlink.hearnow.source",
    "sourceURL": f"{site}/hearnow/install/source.json",
    "subtitle": "HearNow",
    "description": "Źródło z aplikacją HearNow.",
    "iconURL": icon,
    "website": f"{site}/hearnow/install/",
    "tintColor": "0A84FF",
    "apps": [app],
    "news": [],
}

print(json.dumps(source, ensure_ascii=False, indent=2))
