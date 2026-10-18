"""Precompute BirdNET's location filter for one place, for all 48 weeks.

The meta (location) model doesn't convert to Core ML yet, so the app ships this
table instead. BirdNET weeks are 1-48: four per month.

Usage (from ml/):
    .venv/bin/python -I species_list.py [lat lon name]

Defaults to Central Park. Writes models/coreml/species-<name>.json:
    {"name", "lat", "lon", "threshold", "weeks": {"1": [label indices], ...}}
"""

import json
import os
import sys

# Must be set before TensorFlow is imported.
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")

# isort: split
import numpy as np
import tensorflow as tf

HERE = os.path.dirname(os.path.abspath(__file__))
THRESHOLD = 0.03  # BirdNET-Analyzer's default location-filter threshold


def main():
    if len(sys.argv) == 4:
        lat, lon, name = float(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
    else:
        lat, lon, name = 40.7812, -73.9665, "central-park"

    fn = tf.saved_model.load(os.path.join(HERE, "models/birdnet-v2.4/protobuf/meta-model")).signatures[
        "serving_default"
    ]
    labels = open(os.path.join(HERE, "models/coreml/labels.txt")).read().splitlines()

    weeks = {}
    for week in range(1, 49):
        x = tf.constant([[lat, lon, float(week)]], dtype=tf.float32)
        occ = fn(MNET_INPUT=x)["MNET_CLASS_ACTIVATION"].numpy()[0]
        weeks[str(week)] = [int(i) for i in np.flatnonzero(occ >= THRESHOLD)]

    out = {"name": name, "lat": lat, "lon": lon, "threshold": THRESHOLD, "weeks": weeks}
    path = os.path.join(HERE, f"models/coreml/species-{name}.json")
    with open(path, "w") as f:
        json.dump(out, f, separators=(",", ":"))

    counts = [len(v) for v in weeks.values()]
    print(f"wrote {path}: {min(counts)}-{max(counts)} species per week")
    oct_week = 39  # mid-October
    print(
        f"week {oct_week} sample:",
        ", ".join(labels[i].split("_")[1] for i in weeks[str(oct_week)][:12]),
        "...",
    )


if __name__ == "__main__":
    main()
