"""Download the eval set: labeled bird recordings + no-bird noise clips.

Usage (from the repo root):
    ml/.venv/bin/python -I ml/eval/fetch.py            # download whatever manifest.json lists
    ml/.venv/bin/python -I ml/eval/fetch.py --rebuild  # re-query sources and rewrite manifest.json

- Birds: xeno-canto API v3, needs XENO_CANTO_API_KEY (in .env or the environment;
  free key at https://xeno-canto.org/account). Northeast US recordings, best quality first.
- Noise: ESC-50 (CC BY-NC 3.0) clips of city / people / weather sounds, no key needed.

manifest.json is committed so everyone evaluates on the same files; audio/ is gitignored.
"""

import csv
import io
import json
import os
import sys
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "../.."))
MANIFEST = os.path.join(HERE, "manifest.json")
AUDIO = os.path.join(HERE, "audio")

# Common Central Park birds, plus a few migrants we care about.
SPECIES = [
    "Cardinalis cardinalis",  # Northern Cardinal
    "Cyanocitta cristata",  # Blue Jay
    "Turdus migratorius",  # American Robin
    "Zonotrichia albicollis",  # White-throated Sparrow
    "Melospiza melodia",  # Song Sparrow
    "Baeolophus bicolor",  # Tufted Titmouse
    "Thryothorus ludovicianus",  # Carolina Wren
    "Mimus polyglottos",  # Northern Mockingbird
    "Dumetella carolinensis",  # Gray Catbird
    "Passer domesticus",  # House Sparrow
    "Sturnus vulgaris",  # European Starling
    "Zenaida macroura",  # Mourning Dove
    "Dryobates pubescens",  # Downy Woodpecker
    "Melanerpes carolinus",  # Red-bellied Woodpecker
    "Spinus tristis",  # American Goldfinch
    "Quiscalus quiscula",  # Common Grackle
    "Agelaius phoeniceus",  # Red-winged Blackbird
    "Junco hyemalis",  # Dark-eyed Junco
    "Setophaga caerulescens",  # Black-throated Blue Warbler
    "Setophaga coronata",  # Yellow-rumped Warbler
    "Buteo jamaicensis",  # Red-tailed Hawk
    "Poecile atricapillus",  # Black-capped Chickadee
]
PER_SPECIES = 5
NORTHEAST_BOX = "39.5,-76.5,42.5,-72.0"  # lat_min,lon_min,lat_max,lon_max

ESC50_META = "https://raw.githubusercontent.com/karolpiczak/ESC-50/master/meta/esc50.csv"
ESC50_AUDIO = "https://github.com/karolpiczak/ESC-50/raw/master/audio/"
NOISE_CATEGORIES = [
    "car_horn",
    "siren",
    "engine",
    "train",
    "airplane",
    "dog",
    "footsteps",
    "laughing",
    "coughing",
    "crying_baby",
    "church_bells",
    "rain",
    "wind",
]
PER_NOISE = 2


def env_key():
    if os.environ.get("XENO_CANTO_API_KEY"):
        return os.environ["XENO_CANTO_API_KEY"]
    path = os.path.join(ROOT, ".env")
    if os.path.exists(path):
        for line in open(path):
            name, _, value = line.strip().partition("=")
            if name == "XENO_CANTO_API_KEY":
                return value.strip().strip('"')
    return None


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "overheard-eval/0.1"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def xeno_canto(genus, epithet, key, box):
    query = f"gen:{genus} sp:{epithet} q:A len:10-90"
    if box:
        query += f" box:{box}"
    params = urllib.parse.urlencode({"query": query, "key": key, "per_page": 50})
    data = json.loads(get(f"https://xeno-canto.org/api/3/recordings?{params}"))
    return data.get("recordings", [])


def build_birds(key):
    recordings = []
    for name in SPECIES:
        genus, epithet = name.split(" ", 1)
        found = xeno_canto(genus, epithet, key, NORTHEAST_BOX)
        if len(found) < PER_SPECIES:  # widen to anywhere if the Northeast is thin
            found += [r for r in xeno_canto(genus, epithet, key, None) if r not in found]
        picked = found[:PER_SPECIES]
        print(f"  {name}: {len(picked)} recording(s)")
        for r in picked:
            recordings.append(
                {
                    "file": f"audio/xc{r['id']}.mp3",
                    "kind": "bird",
                    "species": name,
                    "also": [a for a in r.get("also", []) if a],
                    "date": r.get("date") or None,
                    "lat": float(r["lat"]) if r.get("lat") else None,
                    "lon": float(r["lon"]) if r.get("lon") else None,
                    "url": r["file"],
                    "source": f"https://xeno-canto.org/{r['id']}",
                    "license": r.get("lic", ""),
                }
            )
    return recordings


def build_noise():
    rows = list(csv.DictReader(io.StringIO(get(ESC50_META).decode())))
    recordings = []
    for category in NOISE_CATEGORIES:
        for row in [r for r in rows if r["category"] == category][:PER_NOISE]:
            recordings.append(
                {
                    "file": f"audio/esc50-{row['filename']}",
                    "kind": "noise",
                    "category": category,
                    "url": ESC50_AUDIO + row["filename"],
                    "source": "https://github.com/karolpiczak/ESC-50",
                    "license": "CC BY-NC 3.0",
                }
            )
    print(f"  noise: {len(recordings)} clips across {len(NOISE_CATEGORIES)} categories")
    return recordings


def main():
    rebuild = "--rebuild" in sys.argv or not os.path.exists(MANIFEST)
    if rebuild:
        print("Querying sources ...")
        key = env_key()
        birds = []
        if key:
            birds = build_birds(key)
        else:
            print("  XENO_CANTO_API_KEY not set: skipping bird recordings (noise only)")
        manifest = {"recordings": birds + build_noise()}
        with open(MANIFEST, "w") as f:
            json.dump(manifest, f, indent=2)
            f.write("\n")
    else:
        manifest = json.load(open(MANIFEST))

    os.makedirs(AUDIO, exist_ok=True)
    fetched = 0
    for r in manifest["recordings"]:
        path = os.path.join(HERE, r["file"])
        if not os.path.exists(path):
            try:
                data = get(r["url"])
            except Exception as e:  # keep going; the eval reports missing files
                print(f"  failed {r['file']}: {e}")
                continue
            with open(path, "wb") as f:
                f.write(data)
            fetched += 1
        # xeno-canto serves some WAVs; name files by their content, since
        # Apple's decoder trusts the extension.
        with open(path, "rb") as f:
            is_wav = f.read(4) == b"RIFF"
        if is_wav and not path.endswith(".wav"):
            fixed = os.path.splitext(r["file"])[0] + ".wav"
            os.replace(path, os.path.join(HERE, fixed))
            r["file"] = fixed

    with open(MANIFEST, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    total = len(manifest["recordings"])
    print(f"{total} recordings in manifest · downloaded {fetched} new · audio in {AUDIO}")


if __name__ == "__main__":
    main()
