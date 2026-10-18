"""Convert BirdNET v2.4 SavedModels to Core ML packages for the iOS app.

Usage (from ml/):
    .venv/bin/python -I convert.py

Reads  models/birdnet-v2.4/protobuf/{audio-model,meta-model}
Writes models/coreml/BirdNETAudio.mlpackage, BirdNETMeta.mlpackage and labels.txt

Both models stay at FP32: FP16 (even with the spectrogram kept at FP32) shifted audio
confidences by up to ±0.17 and changed the top species on 4 of 40 test clips, for only
~35 MB saved. Speed and battery don't need it (inference is ~21 ms per 3 s clip).
"""

import os
import shutil
import sys

import numpy as np

# Must be set before TensorFlow is imported.
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")

# isort: split
import coremltools as ct
import tensorflow as tf
from coremltools.converters.mil import Builder as mb
from coremltools.converters.mil.frontend.tensorflow import ops as tf_ops
from coremltools.converters.mil.frontend.tensorflow.tf_op_registry import register_tf_op
from coremltools.converters.mil.mil import types


# BirdNET's mel-spectrogram layer does tf.cast(stft(x), tf.float32), which keeps
# the real part of the complex STFT. coremltools' Cast doesn't accept complex
# input, so map that case to complex_real and defer everything else.
@register_tf_op(tf_alias=["Cast"], override=True)
def Cast(context, node):
    x = context[node.inputs[0]]
    if types.is_complex(x.dtype):
        context.add(node.name, mb.complex_real(data=x, name=node.name))
        return
    tf_ops.Cast(context, node)


HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "models/birdnet-v2.4/protobuf")
OUT = os.path.join(HERE, "models/coreml")

SAMPLE_RATE = 48_000
CLIP_SAMPLES = 3 * SAMPLE_RATE  # 144,000
LICENSE = "CC BY-NC-SA 4.0 (BirdNET, K. Lisa Yang Center for Conservation Bioacoustics)"


def save(fn, inputs, out_name, description, precision):
    mlmodel = ct.convert(
        [fn],
        source="tensorflow",
        inputs=inputs,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=precision,
    )
    mlmodel.short_description = description
    mlmodel.license = LICENSE
    path = os.path.join(OUT, f"{out_name}.mlpackage")
    shutil.rmtree(path, ignore_errors=True)
    mlmodel.save(path)
    print(f"  wrote {path}")


def meta_function():
    """BirdNET's location model, rebuilt with explicit shapes so coremltools can convert it.

    The original MNET_CONVERT layer slices each input column down to a scalar per row and
    re-expands it, which coremltools mis-infers. This computes the same sinusoidal encoding
    (48 features each for latitude, longitude, and week; week is zeroed outside 1-48, which
    BirdNET uses for "all year") and runs the original dense weights.
    """
    model = tf.saved_model.load(os.path.join(SRC, "meta-model"))
    w = {v.name.split(":")[0]: tf.constant(v.numpy()) for v in model.variables}
    phase = tf.constant(np.arange(48, dtype=np.float32) * np.float32(np.pi) / np.float32(48))
    two_pi = tf.constant(np.float32(2 * np.pi))
    sqrt2 = tf.constant(np.float32(np.sqrt(2)))

    def encode(x):  # (1, 1) -> (1, 48)
        return sqrt2 * tf.sin(two_pi * x + phase)

    @tf.function(input_signature=[tf.TensorSpec((1, 3), tf.float32, name="location")])
    def fn(location):
        lat = (location[:, 0:1] + 90.0) / 180.0
        lon = (location[:, 1:2] + 180.0) / 360.0
        week = location[:, 2:3]
        in_range = tf.cast(week > 0.0, tf.float32) * tf.cast(week < 49.0, tf.float32)
        h = tf.concat([encode(lat), encode(lon), encode((week - 1.0) / 48.0) * in_range], axis=1)
        for block in ["MNET_BLOCK_1_DENSE_1", "MNET_BLOCK_2_DENSE_1", "MNET_BLOCK_3_DENSE_1"]:
            h = tf.nn.relu(tf.matmul(h, w[f"{block}/kernel"]) + w[f"{block}/bias"])
        logits = tf.matmul(h, w["MNET_CLASS_ACTIVATIONS/kernel"]) + w["MNET_CLASS_ACTIVATIONS/bias"]
        return {"occurrence": tf.sigmoid(logits)}

    # Prove the rebuild matches the original before converting it.
    original = model.signatures["serving_default"]
    rng = np.random.default_rng(0)
    samples = np.stack(
        [rng.uniform(-90, 90, 500), rng.uniform(-180, 180, 500), rng.integers(-1, 49, 500)], axis=1
    ).astype(np.float32)
    worst = 0.0
    for row in samples:
        x = tf.constant(row[None, :])
        ref = original(MNET_INPUT=x)["MNET_CLASS_ACTIVATION"].numpy()
        got = fn(x)["occurrence"].numpy()
        worst = max(worst, float(np.max(np.abs(ref - got))))
    print(f"  rebuilt location model matches original: max |diff| {worst:.2e} over {len(samples)} inputs")
    assert worst < 1e-4, "rebuilt location model differs from the original"
    return fn.get_concrete_function()


def main():
    os.makedirs(OUT, exist_ok=True)
    print("Converting audio model ...", flush=True)
    audio_model = tf.saved_model.load(os.path.join(SRC, "audio-model"))  # keep alive: owns the variables
    save(
        audio_model.signatures["basic"],
        [ct.TensorType(name="inputs", shape=(1, CLIP_SAMPLES))],
        "BirdNETAudio",
        "BirdNET v2.4 audio classifier: 3 s of 48 kHz mono audio -> 6522 species logits",
        ct.precision.FLOAT32,
    )

    print("Converting location model ...", flush=True)
    save(
        meta_function(),
        [ct.TensorType(name="location", shape=(1, 3))],
        "BirdNETMeta",
        "BirdNET v2.4 location model: [latitude, longitude, week 1-48 or -1 for all year] -> "
        "per-species occurrence 0-1",
        ct.precision.FLOAT32,
    )

    shutil.copy(os.path.join(SRC, "labels/en_us.txt"), os.path.join(OUT, "labels.txt"))
    print("Done.")


if __name__ == "__main__":
    sys.exit(main())
