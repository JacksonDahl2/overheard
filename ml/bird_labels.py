"""Build the species catalog: a stable ID and display name for every BirdNET label.

Usage (from ml/):
    .venv/bin/python -I bird_labels.py

The app stores species by **code**, never by BirdNET output index (indices change if the
model is upgraded). Codes are eBird species codes (e.g. "norcar") matched by scientific
or common name against the eBird/Clements taxonomy. Birds BirdNET names differently from
current eBird (taxonomy updates since v2.4) fall back to "birdnet:<scientific name>".
Non-bird labels (sounds, frogs, insects, mammals) are marked so they're never reported.
Species eBird has since lumped share one code, so the app counts them as one bird.

Writes models/coreml/species.json:
    {"species": [{"code", "common", "scientific", "bird"}, ...]}   # index = BirdNET output index
"""

import csv
import io
import json
import os
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
LABELS = os.path.join(HERE, "models/coreml/labels.txt")
OUT = os.path.join(HERE, "models/coreml/species.json")
TAXONOMY_URL = "https://api.ebird.org/v2/ref/taxonomy/ebird?fmt=csv"
TAXONOMY_CACHE = os.path.join(HERE, "models/ebird-taxonomy.csv")

# Birds whose genus has since been renamed, so neither name nor genus matches.
RENAMED_BIRDS = {"Bubulcus ibis", "Dryotriorchis spectabilis", "Tumbezia salvini"}


def taxonomy():
    if not os.path.exists(TAXONOMY_CACHE):
        with urllib.request.urlopen(TAXONOMY_URL, timeout=60) as r:
            open(TAXONOMY_CACHE, "wb").write(r.read())
    rows = csv.DictReader(io.StringIO(open(TAXONOMY_CACHE, encoding="utf-8").read()))
    return [r for r in rows if r["CATEGORY"] == "species"]


def main():
    rows = taxonomy()
    by_scientific = {r["SCIENTIFIC_NAME"]: r for r in rows}
    by_common = {r["COMMON_NAME"]: r for r in rows}
    genera = {r["SCIENTIFIC_NAME"].split()[0] for r in rows}

    species, seen, lumped = [], set(), 0
    counts = {"ebird": 0, "fallback": 0, "non-bird": 0}
    for line in open(LABELS, encoding="utf-8").read().splitlines():
        sci, _, com = line.partition("_")
        match = by_scientific.get(sci) or by_common.get(com)
        if match:
            code, common = match["SPECIES_CODE"], match["COMMON_NAME"]
            entry = {"code": code, "common": common, "scientific": sci, "bird": True}
            counts["ebird"] += 1
        else:
            bird = sci.split()[0] in genera or sci in RENAMED_BIRDS
            entry = {"code": f"birdnet:{sci}", "common": com, "scientific": sci, "bird": bird}
            counts["fallback" if bird else "non-bird"] += 1
        lumped += entry["code"] in seen
        seen.add(entry["code"])
        species.append(entry)

    with open(OUT, "w") as f:
        json.dump({"species": species}, f, indent=1, ensure_ascii=False)
    print(
        f"wrote {OUT}: {len(species)} labels · {counts['ebird']} eBird codes · "
        f"{counts['fallback']} birds with fallback codes · {counts['non-bird']} non-birds · "
        f"{lumped} labels sharing a code (lumped species)"
    )


if __name__ == "__main__":
    main()
