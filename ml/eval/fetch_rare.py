"""Build the rare-bird eval set: real recordings of birds that were unlikely where and when
they were recorded, according to BirdNET's location model.

Usage (from the repo root):
    ml/.venv/bin/python -I ml/eval/fetch_rare.py            # download what manifest-rare.json lists
    ml/.venv/bin/python -I ml/eval/fetch_rare.py --rebuild  # re-query xeno-canto and rewrite it

How it picks recordings:
1. Query xeno-canto broadly (eastern US, quality A or B, 10-90 s, every species).
2. Run the location model (ml/models/coreml/BirdNETMeta.mlpackage) at each recording's
   coordinates and week, and read the occurrence of the recorded species.
3. Keep recordings whose species was in the app's "unusual" tier there and then:
   1% <= occurrence < 3% (see ConfidenceBar.standard). At most 2 per species.

These measure the rare-bird side of the confidence bar: is a clearly heard but unlikely bird
reported, or wrongly hidden? Needs XENO_CANTO_API_KEY (in .env or the environment).
manifest-rare.json is committed; audio goes to ml/eval/audio/ (gitignored) with the main set.
"""

import json
import os
import sys
import time
import urllib.parse

# Shared helpers (API key, HTTP, WAV-vs-MP3 naming) live in fetch.py.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import coremltools as ct  # noqa: E402
import fetch  # noqa: E402
import numpy as np  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "../.."))
MANIFEST = os.path.join(HERE, "manifest-rare.json")
META_MODEL = os.path.join(ROOT, "ml/models/coreml/BirdNETMeta.mlpackage")
CATALOG = os.path.join(ROOT, "ml/models/coreml/species.json")

EASTERN_US = "35.0,-85.0,47.5,-66.5"  # lat_min,lon_min,lat_max,lon_max
UNUSUAL = (0.01, 0.03)  # ConfidenceBar.standard's "unusual" tier
PER_SPECIES = 2
MAX_RECORDINGS = 40
MAX_PAGES = 30


def birdnet_week(date):
    """yyyy-mm-dd → BirdNET week 1-48, or None if the date is incomplete."""
    try:
        _, month, day = (int(x) for x in date.split("-"))
    except ValueError:
        return None
    if not (1 <= month <= 12 and 1 <= day <= 31):
        return None
    return (month - 1) * 4 + min(4, (day - 1) // 7 + 1)


class Occurrence:
    """BirdNET's location model, cached per (rounded place, week)."""

    def __init__(self):
        self.model = ct.models.MLModel(META_MODEL)
        self.output = self.model.get_spec().description.output[0].name
        self.cache = {}

    def at(self, lat, lon, week):
        key = (round(lat, 1), round(lon, 1), week)
        if key not in self.cache:
            x = np.array([[lat, lon, week]], dtype=np.float32)
            self.cache[key] = np.asarray(self.model.predict({"location": x})[self.output]).reshape(-1)
        return self.cache[key]


def query(key, page):
    q = f'box:{EASTERN_US} q:">C" len:10-90'
    params = urllib.parse.urlencode({"query": q, "key": key, "per_page": 500, "page": page})
    return json.loads(fetch.get(f"https://xeno-canto.org/api/3/recordings?{params}"))


def build(key):
    species = json.load(open(CATALOG))["species"]
    index_by_scientific = {}
    for i, s in enumerate(species):
        index_by_scientific.setdefault(s["scientific"], i)
    occurrence = Occurrence()

    picked, per_species, scanned = [], {}, 0
    page, pages = 1, 1
    while page <= min(pages, MAX_PAGES) and len(picked) < MAX_RECORDINGS:
        data = query(key, page)
        pages = int(data.get("numPages", 1))
        for r in data.get("recordings", []):
            scanned += 1
            name = f"{r['gen']} {r['sp']}"
            index = index_by_scientific.get(name)
            week = birdnet_week(r.get("date") or "")
            if (
                index is None
                or not species[index]["bird"]
                or week is None
                or not r.get("lat")
                or not r.get("lon")
            ):
                continue
            occ = float(occurrence.at(float(r["lat"]), float(r["lon"]), week)[index])
            if not (UNUSUAL[0] <= occ < UNUSUAL[1]) or per_species.get(name, 0) >= PER_SPECIES:
                continue
            per_species[name] = per_species.get(name, 0) + 1
            picked.append(
                {
                    "file": f"audio/xc{r['id']}.mp3",
                    "kind": "bird",
                    "set": "rare",
                    "species": name,
                    "also": [a for a in r.get("also", []) if a],
                    "date": r["date"],
                    "lat": float(r["lat"]),
                    "lon": float(r["lon"]),
                    "occurrence": round(occ, 4),
                    "url": r["file"],
                    "source": f"https://xeno-canto.org/{r['id']}",
                    "license": r.get("lic", ""),
                }
            )
            if len(picked) >= MAX_RECORDINGS:
                break
        page += 1
        time.sleep(1)  # be polite to xeno-canto
    print(f"  scanned {scanned} recordings on {page - 1} page(s); kept {len(picked)} unusual-tier recordings")
    return picked


def main():
    if "--rebuild" in sys.argv or not os.path.exists(MANIFEST):
        key = fetch.env_key()
        if not key:
            sys.exit("XENO_CANTO_API_KEY is required (in .env or the environment)")
        print("Querying xeno-canto and scoring with the location model ...")
        manifest = {"recordings": build(key)}
    else:
        manifest = json.load(open(MANIFEST))

    fetched = fetch.download(manifest["recordings"])
    with open(MANIFEST, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    names = sorted({r["species"] for r in manifest["recordings"]})
    print(f"{len(manifest['recordings'])} rare recordings ({len(names)} species) · downloaded {fetched} new")


if __name__ == "__main__":
    main()
