"""Download annotated soundscapes for the call-count and timing eval (prototype).

Usage (from the repo root):
    ml/.venv/bin/python -I ml/eval/soundscapes.py            # download what soundscapes-manifest.json lists
    ml/.venv/bin/python -I ml/eval/soundscapes.py --rebuild  # re-pick recordings, rewrite the manifest
    ml/.venv/bin/python -I ml/eval/soundscapes.py --summary  # ground-truth calls per window, no download

Datasets (both CC BY 4.0, see docs/research/soundscape-eval.md):
- ssw: Kahl, Charif & Klinck 2022, Sapsucker Woods, Ithaca NY. 285 one-hour FLACs, eBird codes.
  https://doi.org/10.5281/zenodo.7079380
- nepark: Panwar et al. 2025, Acadia / Hubbard Brook / Katahdin / Marsh-Billings parks.
  1,302 ten-minute FLACs, 4-letter AOU codes. https://doi.org/10.5281/zenodo.20038954

The audio sits in multi-GB zips. Zenodo serves HTTP ranges, so this reads each zip's
central directory and pulls out only the members the manifest names (the zip CRC
verifies each one). soundscapes-manifest.json is committed; soundscapes/ is gitignored.

Labels are mapped to our species by scientific name (species.json), because both
datasets use pre-2025 names, as BirdNET does. Codes that don't name a species
("????", unknown mammal) keep code null.
"""

import collections
import csv
import io
import json
import os
import sys
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "../.."))
MANIFEST = os.path.join(HERE, "soundscapes-manifest.json")
AUDIO = os.path.join(HERE, "soundscapes")
SPECIES_JSON = os.path.join(ROOT, "ml/models/coreml/species.json")

ZENODO = "https://zenodo.org/api/records/{record}/files/{name}/content"
SSW_RECORD = "7079380"
SSW_LOCATION = (42.4768, -76.4527)  # recording_location.txt
NEPARK_RECORD = "20038954"
NEPARK_SETS = ["DatasetACAD", "DatasetMABI", "DatasetSIMR"]

WINDOW = 600  # seconds evaluated per soundscape entry
SSW_MONTHS = ["201704", "201705", "201706", "201707"]
SSW_FILES_PER_MONTH = 2
SSW_WINDOWS_PER_FILE = 2
NEPARK_FILES_PER_SET = 3
CALL_GAP = 2.5  # same-species annotations closer than this are one call (the app's merge rule)

# Newer names in the datasets → the name BirdNET (and so species.json) uses.
ALIASES = {"Astur cooperii": "Accipiter cooperii", "Larus smithsonianus": "Larus argentatus"}

DATASETS = {
    "ssw": {
        "title": "A collection of fully-annotated soundscape recordings from the Northeastern United States",
        "authors": "Stefan Kahl, Russell Charif, Holger Klinck",
        "year": 2022,
        "doi": "https://doi.org/10.5281/zenodo.7079380",
        "license": "CC BY 4.0",
    },
    "nepark": {
        "title": (
            "Large-scale, Stratified, Fully Annotated Acoustic Forest Soundscape Dataset "
            "of Avian Vocalizations from Eastern North America"
        ),
        "authors": "Pooja Panwar, Wyatt J. Cummings, Sharon Martinson, David A. Lutz, "
        "Hannah ter Hofstede, Aaron Weed, Matthew P. Ayres, Laurel B. Symes",
        "year": 2025,
        "doi": "https://doi.org/10.5281/zenodo.20038954",
        "license": "CC BY 4.0",
    },
}


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "overheard-eval/0.1"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


class RemoteFile(io.RawIOBase):
    """A seekable read-only view of a URL, one HTTP range request per read."""

    def __init__(self, url):
        self.url, self.pos = url, 0
        req = urllib.request.Request(url, headers={"Range": "bytes=0-0", "User-Agent": "overheard-eval/0.1"})
        with urllib.request.urlopen(req, timeout=60) as r:
            self.size = int(r.headers["Content-Range"].rsplit("/", 1)[1])

    def readable(self):
        return True

    def seekable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, offset, whence=0):
        self.pos = [offset, self.pos + offset, self.size + offset][whence]
        return self.pos

    def readinto(self, buffer):
        n = min(len(buffer), self.size - self.pos)
        if n <= 0:
            return 0
        headers = {"Range": f"bytes={self.pos}-{self.pos + n - 1}", "User-Agent": "overheard-eval/0.1"}
        with urllib.request.urlopen(urllib.request.Request(self.url, headers=headers), timeout=120) as r:
            data = r.read()
        buffer[: len(data)] = data
        self.pos += len(data)
        return len(data)


def remote_zip(url):
    return zipfile.ZipFile(io.BufferedReader(RemoteFile(url), 1 << 22))


def species_index():
    """scientific name → (code, bird) from species.json."""
    return {s["scientific"]: (s["code"], s["bird"]) for s in json.load(open(SPECIES_JSON))["species"]}


def normalize(label, scientific, index):
    scientific = ALIASES.get(scientific, scientific) if scientific and scientific != "NA" else None
    code, bird = index.get(scientific, (None, None)) if scientific else (None, None)
    return {"label": label, "scientific": scientific, "code": code, "bird": bird}


def calls(annotations, gap=CALL_GAP):
    """Ground-truth calls per code: same-species boxes whose gap is under `gap` s merge."""
    spans = collections.defaultdict(list)
    for a in annotations:
        if a["code"] and a["bird"]:
            spans[a["code"]].append((a["start"], a["end"]))
    out = {}
    for code, iv in spans.items():
        iv.sort()
        merged = []
        for s, e in iv:
            if merged and s - merged[-1][1] < gap:
                merged[-1][1] = max(merged[-1][1], e)
            else:
                merged.append([s, e])
        out[code] = {"calls": len(merged), "first": round(merged[0][0], 2)}
    return out


def in_window(rows, start, end):
    return [a for a in rows if a["end"] > start and a["start"] < end]


def build_ssw(index):
    names = {r["Species eBird Code"]: r["Scientific Name"] for r in csv.DictReader(io.StringIO(
        get(ZENODO.format(record=SSW_RECORD, name="species.csv")).decode()))}  # fmt: skip
    rows = csv.DictReader(io.StringIO(get(ZENODO.format(record=SSW_RECORD, name="annotations.csv")).decode()))
    by_file = collections.defaultdict(list)
    for r in rows:
        a = normalize(r["Species eBird Code"], names.get(r["Species eBird Code"]), index)
        a["start"], a["end"] = float(r["Start Time (s)"]), float(r["End Time (s)"])
        by_file[r["Filename"]].append(a)

    archive = ZENODO.format(record=SSW_RECORD, name="soundscape_data.zip")
    sizes = {i.filename: i.file_size for i in remote_zip(archive).infolist()}
    entries = []
    for month in SSW_MONTHS:
        files = sorted(
            (f for f in by_file if f.split("_")[2].startswith(month)), key=lambda f: -len(by_file[f])
        )
        for name in files[:SSW_FILES_PER_MONTH]:
            # The densest non-overlapping windows by number of species.
            starts = range(0, 3600, WINDOW)
            scored = sorted(starts, key=lambda s: -len(calls(in_window(by_file[name], s, s + WINDOW))))
            for start in sorted(scored[:SSW_WINDOWS_PER_FILE]):
                _, _, day, clock = name.removesuffix(".flac").split("_")
                entries.append(
                    {
                        "file": f"soundscapes/ssw/{name}",
                        "kind": "soundscape",
                        "dataset": "ssw",
                        "window": [start, start + WINDOW],
                        "date": f"{day[:4]}-{day[4:6]}-{day[6:]}",
                        "time_utc": f"{clock[:2]}:{clock[2:4]}:{clock[4:6]}",
                        "lat": SSW_LOCATION[0],
                        "lon": SSW_LOCATION[1],
                        "archive": archive,
                        "member": name,
                        "bytes": sizes[name],
                        "annotations": in_window(by_file[name], start, start + WINDOW),
                    }
                )
    return entries


def build_nepark(index):
    def table(name):
        text = get(ZENODO.format(record=NEPARK_RECORD, name=name)).decode("utf-8", errors="replace")
        return list(csv.DictReader(io.StringIO(text)))

    names = {r["AOU_Code"]: r["Scientific_Name"] for r in table("species_metadata.csv")}
    sites = {r["SiteID"]: (float(r["Latitude"]), float(r["Longitude"])) for r in table("site_metadata.csv")}
    entries = []
    for dataset in NEPARK_SETS:
        ann_zip = zipfile.ZipFile(
            io.BytesIO(get(ZENODO.format(record=NEPARK_RECORD, name=f"{dataset}_Annotations.zip")))
        )
        archive = ZENODO.format(record=NEPARK_RECORD, name=f"{dataset}_Recordings.zip")
        members = {os.path.basename(i.filename): i for i in remote_zip(archive).infolist() if not i.is_dir()}
        per_file = {}
        for info in ann_zip.infolist():
            if info.is_dir() or not info.filename.endswith(".txt"):
                continue
            text = ann_zip.read(info).decode("utf-8", errors="replace")
            anns = []
            for r in csv.DictReader(io.StringIO(text), delimiter="\t"):
                a = normalize(r["Species"].strip(), names.get(r["Species"].strip()), index)
                a["start"], a["end"] = float(r["Begin Time (s)"]), float(r["End Time (s)"])
                anns.append(a)
            # DatasetSIMR names them "<recording>.Table.1.selections.txt", the others "<recording>.txt".
            stem = os.path.basename(info.filename).removesuffix(".txt").removesuffix(".Table.1.selections")
            per_file[stem + ".flac"] = anns
        ranked = sorted((f for f in per_file if f in members), key=lambda f: (-len(calls(per_file[f])), f))
        picked = {}  # the richest recording at each of the richest sites
        for name in ranked:
            picked.setdefault(name.removesuffix(".flac").split(".")[-1].split("_")[0], name)
        for name in list(picked.values())[:NEPARK_FILES_PER_SET]:
            site, day, clock = name.removesuffix(".flac").split(".")[-1].split("_")
            lat, lon = sites.get(site, (None, None))
            entries.append(
                {
                    "file": f"soundscapes/nepark/{name}",
                    "kind": "soundscape",
                    "dataset": "nepark",
                    "window": [0, WINDOW],
                    "date": f"{day[:4]}-{day[4:6]}-{day[6:]}",
                    "time_local": f"{clock[:2]}:{clock[2:4]}",  # assumed local; the dataset doesn't say
                    "site": site,
                    "lat": lat,
                    "lon": lon,
                    "archive": archive,
                    "member": members[name].filename,
                    "bytes": members[name].file_size,
                    "annotations": sorted(per_file[name], key=lambda a: a["start"]),
                }
            )
    return entries


def write_manifest(manifest):
    # One annotation per line keeps the file diffable without being enormous.
    with open(MANIFEST, "w") as f:
        f.write("{\n")
        f.write(f'  "kind": "soundscape",\n  "call_gap": {CALL_GAP},\n')
        f.write(
            f'  "datasets": {json.dumps(manifest["datasets"], indent=2).replace(chr(10), chr(10) + "  ")},\n'
        )
        f.write('  "recordings": [\n')
        for i, r in enumerate(manifest["recordings"]):
            head = {k: v for k, v in r.items() if k != "annotations"}
            f.write("    {\n")
            for k, v in head.items():
                f.write(f"      {json.dumps(k)}: {json.dumps(v)},\n")
            f.write('      "annotations": [\n')
            rows = r["annotations"]
            for j, a in enumerate(rows):
                a = {"start": round(a["start"], 3), "end": round(a["end"], 3), **{
                    k: a[k] for k in ("label", "scientific", "code", "bird")}}  # fmt: skip
                f.write(f"        {json.dumps(a)}{',' if j < len(rows) - 1 else ''}\n")
            f.write(f"      ]\n    }}{',' if i < len(manifest['recordings']) - 1 else ''}\n")
        f.write("  ]\n}\n")


def summary(manifest):
    for r in manifest["recordings"]:
        truth = calls(in_window(r["annotations"], *r["window"]))
        top = sorted(truth.items(), key=lambda kv: -kv[1]["calls"])[:5]
        listed = ", ".join(f"{c} {v['calls']}" for c, v in top)
        n = sum(v["calls"] for v in truth.values())
        print(f"  {os.path.basename(r['file'])} {r['window']}: {len(truth)} species, {n} calls · {listed}")


def download(manifest):
    os.makedirs(AUDIO, exist_ok=True)
    zips = {}
    fetched = 0
    for r in manifest["recordings"]:
        path = os.path.join(HERE, r["file"])
        if os.path.exists(path) and os.path.getsize(path) == r["bytes"]:
            continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        print(f"  {r['member']} ({r['bytes'] / 1e6:.0f} MB)")
        z = zips.setdefault(r["archive"], remote_zip(r["archive"]))
        try:
            with z.open(r["member"]) as src, open(path + ".part", "wb") as dst:
                while chunk := src.read(1 << 20):  # zipfile checks the CRC at the end
                    dst.write(chunk)
        except Exception as e:  # keep going; the eval reports missing files
            print(f"  failed {r['file']}: {e}")
            continue
        os.replace(path + ".part", path)
        fetched += 1
    return fetched


def main():
    rebuild = "--rebuild" in sys.argv or not os.path.exists(MANIFEST)
    if rebuild:
        print("Reading annotations ...")
        index = species_index()
        manifest = {"datasets": DATASETS, "recordings": build_ssw(index) + build_nepark(index)}
        write_manifest(manifest)
    else:
        manifest = json.load(open(MANIFEST))
    summary(manifest)
    if "--summary" in sys.argv:
        return
    total = sum(r["bytes"] for r in {r["file"]: r for r in manifest["recordings"]}.values())
    print(f"Downloading up to {total / 1e9:.1f} GB ...")
    fetched = download(manifest)
    print(f"{len(manifest['recordings'])} windows in manifest · downloaded {fetched} new · audio in {AUDIO}")


if __name__ == "__main__":
    main()
