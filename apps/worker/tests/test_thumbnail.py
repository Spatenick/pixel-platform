from __future__ import annotations

import io

import pytest
from PIL import Image

from worker.thumbnail import InvalidImageError, make_thumbnail


def _image_bytes(size=(1200, 800), mode="RGB", fmt="PNG") -> bytes:
    buf = io.BytesIO()
    color = (10, 120, 200, 128) if mode == "RGBA" else (10, 120, 200)
    Image.new(mode, size, color).save(buf, format=fmt)
    return buf.getvalue()


def _open(data: bytes) -> Image.Image:
    return Image.open(io.BytesIO(data))


def test_longest_side_is_capped_and_aspect_ratio_kept():
    thumb = _open(make_thumbnail(_image_bytes((1200, 800)), max_px=256))
    assert thumb.format == "JPEG"
    assert thumb.size == (256, 171)


def test_small_images_are_not_upscaled():
    thumb = _open(make_thumbnail(_image_bytes((100, 50)), max_px=256))
    assert thumb.size == (100, 50)


def test_transparency_is_flattened_for_jpeg():
    thumb = _open(make_thumbnail(_image_bytes(mode="RGBA"), max_px=128))
    assert thumb.mode == "RGB"


@pytest.mark.parametrize("fmt", ["PNG", "JPEG", "GIF", "WEBP"])
def test_supported_input_formats(fmt):
    mode = "P" if fmt == "GIF" else "RGB"
    assert _open(make_thumbnail(_image_bytes((300, 300), mode=mode, fmt=fmt))).format == "JPEG"


def test_garbage_is_a_permanent_error():
    with pytest.raises(InvalidImageError):
        make_thumbnail(b"definitely not an image")
