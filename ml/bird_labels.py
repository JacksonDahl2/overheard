"""Find BirdNET's non-bird labels (sounds, frogs, insects, mammals) so the app never reports them.

Usage (from ml/):
    .venv/bin/python -I bird_labels.py

Matches every label against the eBird/Clements taxonomy: by scientific or common name,
then by genus, since BirdNET v2.4 predates some taxonomy updates.
Writes models/coreml/non-birds.json: {"indices": [...], "names": [...]}
"""

import csv
import io
import json
import os
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
LABELS = os.path.join(HERE, "models/coreml/labels.txt")
OUT = os.path.join(HERE, "models/coreml/non-birds.json")
TAXONOMY_URL = "https://api.ebird.org/v2/ref/taxonomy/ebird?fmt=csv"
TAXONOMY_CACHE = os.path.join(HERE, "models/ebird-taxonomy.csv")

# Birds whose genus has since been renamed, so neither name nor genus matches.
RENAMED_BIRDS = {"Bubulcus ibis", "Dryotriorchis spectabilis", "Tumbezia salvini"}


def taxonomy():
    if not os.path.exists(TAXONOMY_CACHE):
        with urllib.request.urlopen(TAXONOMY_URL, timeout=60) as r:
            open(TAXONOMY_CACHE, "wb").write(r.read())
    return list(csv.DictReader(io.StringIO(open(TAXONOMY_CACHE, encoding="utf-8").read())))


def main():
    rows = taxonomy()
    scientific = {r["SCIENTIFIC_NAME"] for r in rows}
    common = {r["COMMON_NAME"] for r in rows}
    genera = {r["SCIENTIFIC_NAME"].split()[0] for r in rows}

    indices, names = [], []
    for i, line in enumerate(open(LABELS, encoding="utf-8").read().splitlines()):
        sci, _, com = line.partition("_")
        is_bird = sci in scientific or com in common or sci.split()[0] in genera or sci in RENAMED_BIRDS
        if not is_bird:
            indices.append(i)
            names.append(com)

    with open(OUT, "w") as f:
        json.dump({"indices": indices, "names": names}, f, indent=1)
    print(f"wrote {OUT}: {len(indices)} non-bird labels")


if __name__ == "__main__":
    main()
