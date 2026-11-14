#!/usr/bin/env python3
# Plik dla systemu aktualizacji w apce (updateapi/7tools.json).
# Apka pobiera go zwyklym GET-em i porownuje "build" ze swoim numerem.
#
#   make_update.py <adres_strony> <wersja> <build> <rozmiar_bajtow> <data RRRR-MM-DD>
#
import json
import sys

site, version, build, size, date = sys.argv[1:6]
site = site.rstrip("/")

update = {
    "app": "7tools",
    "name": "007Tools",
    "version": version,
    "build": int(build),
    "date": date,
    "size": int(size),
    "minOS": "26.0",
    "ipa": f"{site}/7tools/install/SevenTools.ipa",
    "page": f"{site}/7tools/install/",
}

print(json.dumps(update, ensure_ascii=False, indent=2))
