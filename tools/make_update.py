#!/usr/bin/env python3
# Plik dla systemu aktualizacji w apce (updateapi/hearnow.json).
# Apka pobiera go zwyklym GET-em i porownuje "build" ze swoim numerem.
#
#   make_update.py <adres_strony> <wersja> <build> <rozmiar_bajtow> <data RRRR-MM-DD>
#
import json
import sys

site, version, build, size, date = sys.argv[1:6]
site = site.rstrip("/")

update = {
    "app": "hearnow",
    "name": "HearNow",
    "version": version,
    "build": int(build),
    "date": date,
    "size": int(size),
    "minOS": "26.0",
    "ipa": f"{site}/hearnow/install/HearNow.ipa",
    "page": f"{site}/hearnow/install/",
}

print(json.dumps(update, ensure_ascii=False, indent=2))
