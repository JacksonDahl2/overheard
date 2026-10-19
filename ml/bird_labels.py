"""Build the species catalog: a stable ID and display name for every BirdNET label.

Usage (from ml/):
    .venv/bin/python -I bird_labels.py

The app stores species by **code**, never by BirdNET output index (indices change if the
model is upgraded). Codes are eBird species codes (e.g. "norcar") matched by scientific
or common name against the eBird/Clements taxonomy. Birds BirdNET names differently from
current eBird (taxonomy updates since v2.4) fall back to "birdnet:<scientific name>".
Non-bird labels (sounds, frogs, insects, mammals) are marked so they're never reported.
Species eBird has since lumped share one code, so the app counts them as one bird.

Species eBird has since **split** keep BirdNET's broader concept, since BirdNET can't tell
the daughters apart: BirdNET's name ("Yellow Warbler"), eBird's code for the whole group
when one exists ("yelwar", Northern/Mangrove Yellow Warbler) or "birdnet:<scientific>",
and the daughter species' codes under "split" (so the app could later pick the local one).
Matching by scientific name alone would pick whichever daughter kept the name, which is
often the wrong bird (BirdNET's Yellow Warbler became the tropical Mangrove Yellow Warbler).

Writes models/coreml/species.json, one entry per BirdNET output index:
    {"code", "common", "scientific", "bird", "split"?: [daughter codes]}
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
    """All taxonomy rows (species plus slashes, spuhs, …)."""
    if not os.path.exists(TAXONOMY_CACHE):
        with urllib.request.urlopen(TAXONOMY_URL, timeout=60) as r:
            open(TAXONOMY_CACHE, "wb").write(r.read())
    return list(csv.DictReader(io.StringIO(open(TAXONOMY_CACHE, encoding="utf-8").read())))


def split_daughters(birdnet_common, species_rows):
    """Current species whose names extend BirdNET's: "Herring Gull" → American/European Herring Gull."""
    return [r for r in species_rows if r["COMMON_NAME"].endswith(" " + birdnet_common)]


def group_code(daughters, slashes):
    """eBird's code for a slash covering exactly these daughter species, if there is one."""
    names = {d["COMMON_NAME"] for d in daughters}
    for s in slashes:
        parts = s["COMMON_NAME"].split("/")
        # "Northern/Mangrove Yellow Warbler" → ["Northern Yellow Warbler", "Mangrove Yellow Warbler"]
        last = parts[-1]
        tail = last[last.index(" ") + 1 :] if " " in last else ""
        expanded = {p if " " in p and p.endswith(tail) else f"{p} {tail}".strip() for p in parts}
        if expanded == names:
            return s["SPECIES_CODE"]
    return None


def main():
    rows = taxonomy()
    species_rows = [r for r in rows if r["CATEGORY"] == "species"]
    slashes = [r for r in rows if r["CATEGORY"] == "slash"]
    by_scientific = {r["SCIENTIFIC_NAME"]: r for r in species_rows}
    by_common = {r["COMMON_NAME"]: r for r in species_rows}
    genera = {r["SCIENTIFIC_NAME"].split()[0] for r in species_rows}

    species, seen = [], set()
    counts = {"ebird": 0, "split": 0, "split-group": 0, "fallback": 0, "non-bird": 0, "lumped": 0}
    for line in open(LABELS, encoding="utf-8").read().splitlines():
        sci, _, com = line.partition("_")
        match = by_scientific.get(sci) or by_common.get(com)
        daughters = split_daughters(com, species_rows) if match and match["COMMON_NAME"] != com else []
        if match and len(daughters) >= 2 and match in daughters:
            # eBird split BirdNET's species: keep BirdNET's concept rather than one daughter.
            code = group_code(daughters, slashes)
            entry = {
                "code": code or f"birdnet:{sci}",
                "common": com,
                "scientific": sci,
                "bird": True,
                "split": sorted(d["SPECIES_CODE"] for d in daughters),
            }
            counts["split"] += 1
            counts["split-group"] += code is not None
        elif match:
            entry = {
                "code": match["SPECIES_CODE"],
                "common": match["COMMON_NAME"],
                "scientific": sci,
                "bird": True,
            }
            counts["ebird"] += 1
        else:
            bird = sci.split()[0] in genera or sci in RENAMED_BIRDS
            entry = {"code": f"birdnet:{sci}", "common": com, "scientific": sci, "bird": bird}
            counts["fallback" if bird else "non-bird"] += 1
        counts["lumped"] += entry["code"] in seen
        seen.add(entry["code"])
        species.append(entry)

    with open(OUT, "w") as f:
        json.dump({"species": species}, f, indent=1, ensure_ascii=False)
    print(
        f"wrote {OUT}: {len(species)} labels · {counts['ebird']} eBird codes · "
        f"{counts['split']} split species ({counts['split-group']} with an eBird group code) · "
        f"{counts['fallback']} birds with fallback codes · {counts['non-bird']} non-birds · "
        f"{counts['lumped']} labels sharing a code (lumped species)"
    )


if __name__ == "__main__":
    main()
