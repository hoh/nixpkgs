"""Targeted runtime checks for the packaged MediaPipe Python library.

These checks exist to protect the nixpkgs package from the most valuable
regressions without importing the cost and fragility of the full upstream test
suite into every build.

The business goal is packaging confidence, not full product validation:
- confirm the source-built native library can be loaded by the installed Python
  package
- confirm the public Python API surface exported by nixpkgs still matches what
  downstream users expect
- confirm a few high-traffic conversion paths behave correctly after packaging
  changes, dependency updates, or Bazel patching

The scope intentionally stays small and asset-free so the checks remain fast,
deterministic, and suitable for routine Nix builds.
"""

import dataclasses
import os

import numpy as np

import mediapipe as mp
from mediapipe.tasks.python.components.containers import bounding_box
from mediapipe.tasks.python.components.containers import category
from mediapipe.tasks.python.components.containers import category_c
from mediapipe.tasks.python.components.containers import rect_c
from mediapipe.tasks.python.core import base_options


def check_image_round_trip():
    """Verify the highest-value runtime path: Python <-> native image handling.

    This gives the package a meaningful end-to-end signal that the bundled
    shared library loads, accepts NumPy-backed image data, and returns data to
    Python correctly. If this breaks, most downstream vision usage is already
    compromised even if plain imports still succeed.
    """

    pixels = np.arange(18, dtype=np.uint8).reshape((2, 3, 3))
    image = mp.Image(mp.ImageFormat.SRGB, pixels)

    assert image.width == 3
    assert image.height == 2
    assert image.channels == 3
    assert image.image_format == mp.ImageFormat.SRGB
    assert not image.uses_gpu()
    assert not image.is_empty()
    np.testing.assert_array_equal(image.numpy_view(), pixels)


def check_base_options_conversion():
    """Exercise the common task configuration bridge.

    MediaPipe tasks rely on ctypes conversion from Python objects into the C
    layer. This check is a cheap proxy for ABI and packaging compatibility:
    it catches cases where the installed Python bindings no longer match the
    packaged native interfaces or expected field layout.
    """

    options = base_options.BaseOptions(
        model_asset_buffer=b"abc",
        delegate=base_options.BaseOptions.Delegate.CPU,
    )
    c_options = options.to_ctypes()

    assert c_options.model_asset_path is None
    assert c_options.model_asset_buffer == b"abc"
    assert c_options.model_asset_buffer_count == 3
    assert c_options.delegate == base_options.BaseOptions.Delegate.CPU
    assert hasattr(c_options, "model_asset_buffer_count")


def check_container_conversions():
    """Validate lightweight result containers used across task APIs.

    These conversions are inexpensive to test, require no model assets, and
    still cover a broad slice of the Python package surface that downstream
    applications consume when reading task results.
    """

    box = bounding_box.BoundingBox.from_ctypes(
        rect_c.RectC(left=4, top=5, right=14, bottom=25)
    )
    assert dataclasses.asdict(box) == {
        "origin_x": 4,
        "origin_y": 5,
        "width": 10,
        "height": 20,
    }

    converted_category = category.Category.from_ctypes(
        category_c.CategoryC(
            index=7,
            score=0.5,
            category_name=b"hand",
            display_name=b"Hand",
        )
    )
    assert dataclasses.asdict(converted_category) == {
        "index": 7,
        "score": 0.5,
        "display_name": "Hand",
        "category_name": "hand",
    }


def check_package_exports():
    """Confirm the user-facing package contract exposed by nixpkgs.

    The package assembly here is custom, so this guards against regressions
    where installation succeeds but the expected top-level exports or packaged
    version metadata are missing from the final output.
    """

    assert mp.__version__ == os.environ["EXPECTED_MEDIAPIPE_VERSION"]
    assert mp.tasks.BaseOptions is base_options.BaseOptions


check_image_round_trip()
check_base_options_conversion()
check_container_conversions()
check_package_exports()
