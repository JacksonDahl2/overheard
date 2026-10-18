"""Check the converted Core ML audio model against the original TensorFlow model.

Usage (from ml/):
    .venv/bin/python -I verify.py [path/to/48kHz-mono.wav]

Splits the recording into 3 s clips, runs both models, and prints the largest
logit difference plus the top detections from each.
"""

import os
import sys
import wave

# Must be set before TensorFlow is imported.
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")

# isort: split
import coremltools as ct
import numpy as np
import tensorflow as tf

HERE = os.path.dirname(os.path.abspath(__file__))
SAMPLE_RATE = 48_000
CLIP = 3 * SAMPLE_RATE
MIN_CONFIDENCE = 0.25


def load_wav(path):
    with wave.open(path) as w:
        assert w.getframerate() == SAMPLE_RATE, "expected 48 kHz"
        assert w.getnchannels() == 1, "expected mono"
        assert w.getsampwidth() == 2, "expected 16-bit PCM"
        pcm = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
    return pcm.astype(np.float32) / 32768.0


def sigmoid(logits):
    # BirdNET's default (sensitivity 1.0), with the same clipping it uses.
    return 1.0 / (1.0 + np.exp(-np.clip(logits, -15, 15)))


def main():
    wav = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "models/samples/soundscape.wav")
    audio = load_wav(wav)
    clips = [audio[i : i + CLIP] for i in range(0, len(audio) - CLIP + 1, CLIP)]
    labels = open(os.path.join(HERE, "models/coreml/labels.txt")).read().splitlines()

    tf_fn = tf.saved_model.load(os.path.join(HERE, "models/birdnet-v2.4/protobuf/audio-model")).signatures[
        "basic"
    ]
    ml = ct.models.MLModel(os.path.join(HERE, "models/coreml/BirdNETAudio.mlpackage"))
    ml_out = ml.get_spec().description.output[0].name

    worst = 0.0
    mismatched_top1 = 0
    for i, clip in enumerate(clips):
        x = clip[None, :]
        ref = tf_fn(inputs=tf.constant(x))["scores"].numpy()[0]
        got = np.asarray(ml.predict({"inputs": x})[ml_out]).reshape(-1)
        worst = max(worst, float(np.max(np.abs(ref - got))))
        if int(np.argmax(ref)) != int(np.argmax(got)):
            mismatched_top1 += 1

        ref_c, got_c = sigmoid(ref), sigmoid(got)
        hits = [j for j in np.argsort(-ref_c)[:3] if ref_c[j] >= MIN_CONFIDENCE]
        if hits:
            t = i * 3
            row = ", ".join(f"{labels[j].split('_')[1]} {ref_c[j]:.2f}/{got_c[j]:.2f}" for j in hits)
            print(f"{t:4d}-{t + 3:<4d}s  {row}")

    print(f"\n{len(clips)} clips · max |logit diff| {worst:.4f} · top-1 mismatches {mismatched_top1}")
    print("(confidences shown as TensorFlow/Core ML)")


if __name__ == "__main__":
    main()
