"""Pure image logic -- no AWS, no DB -- so it's trivial to unit test."""

from __future__ import annotations

import io

from PIL import Image, ImageOps, UnidentifiedImageError

# Refuse decompression bombs (a tiny file that expands to gigapixels).
Image.MAX_IMAGE_PIXELS = 50_000_000


class InvalidImageError(Exception):
    """The input isn't a decodable image. Retrying won't help."""


def make_thumbnail(data: bytes, max_px: int = 256, quality: int = 85) -> bytes:
    """Return a JPEG no larger than max_px on its longest side."""
    try:
        with Image.open(io.BytesIO(data)) as img:
            img = ImageOps.exif_transpose(img)  # respect phone camera rotation
            img.thumbnail((max_px, max_px))
            if img.mode not in ("RGB", "L"):
                # JPEG has no alpha channel; flatten onto white
                background = Image.new("RGB", img.size, (255, 255, 255))
                rgba = img.convert("RGBA")
                background.paste(rgba, mask=rgba.split()[-1])
                img = background
            out = io.BytesIO()
            img.save(out, format="JPEG", quality=quality, optimize=True)
            return out.getvalue()
    except (UnidentifiedImageError, Image.DecompressionBombError, OSError) as exc:
        raise InvalidImageError(str(exc)) from exc
