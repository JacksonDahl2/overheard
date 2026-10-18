"""Convert BirdNET v2.4 SavedModels to Core ML packages for the iOS app.

Usage (from ml/):
    .venv/bin/python -I convert.py

Reads  models/birdnet-v2.4/protobuf/audio-model
Writes models/coreml/BirdNETAudio.mlpackage and labels.txt
"""

import os
import shutil
import sys

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


def convert(name, signature, inputs, out_name, description):
    print(f"Converting {name} ({signature}) ...", flush=True)
    model = tf.saved_model.load(os.path.join(SRC, name))
    fn = model.signatures[signature]
    mlmodel = ct.convert(
        [fn],
        source="tensorflow",
        inputs=inputs,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT32,
    )
    mlmodel.short_description = description
    mlmodel.license = "CC BY-NC-SA 4.0 (BirdNET, K. Lisa Yang Center for Conservation Bioacoustics)"
    path = os.path.join(OUT, f"{out_name}.mlpackage")
    shutil.rmtree(path, ignore_errors=True)
    mlmodel.save(path)
    print(f"  wrote {path}")
    return mlmodel


def main():
    os.makedirs(OUT, exist_ok=True)

    convert(
        "audio-model",
        "basic",
        [ct.TensorType(name="inputs", shape=(1, CLIP_SAMPLES))],
        "BirdNETAudio",
        "BirdNET v2.4 audio classifier: 3 s of 48 kHz mono audio -> 6522 species logits",
    )
    # The location (meta) model doesn't convert yet: its MNET_CONVERT input
    # encoding trips coremltools' ExpandDims on a scalar. species_list.py
    # precomputes its output for the places we need instead.

    shutil.copy(os.path.join(SRC, "labels/en_us.txt"), os.path.join(OUT, "labels.txt"))
    print("Done.")


if __name__ == "__main__":
    sys.exit(main())
