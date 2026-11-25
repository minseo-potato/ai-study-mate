"""기기 안에서 글자를 인식한다(외부로 보내지 않음). Windows 내장 OCR, 없으면 Tesseract를 쓴다."""
import asyncio
import io
import shutil
import subprocess
import sys

from PIL import Image, ImageOps

MAX_PIXELS = 80_000_000
TILE = 2600


class OcrUnavailable(Exception):
    pass


def _engine():
    from winrt.windows.globalization import Language
    from winrt.windows.media.ocr import OcrEngine
    engine = OcrEngine.try_create_from_language(Language("ko"))
    return engine or OcrEngine.try_create_from_user_profile_languages()


async def _windows(engine, image: Image.Image) -> str:
    from winrt.windows.graphics.imaging import BitmapAlphaMode, BitmapPixelFormat, SoftwareBitmap
    from winrt.windows.storage.streams import DataWriter
    writer = DataWriter()
    writer.write_bytes(image.convert("RGBA").tobytes("raw", "BGRA"))
    bitmap = SoftwareBitmap.create_copy_with_alpha_from_buffer(
        writer.detach_buffer(), BitmapPixelFormat.BGRA8, image.width, image.height, BitmapAlphaMode.IGNORE)
    result = await engine.recognize_async(bitmap)
    return "\n".join(line.text for line in result.lines)


def _tesseract(image: Image.Image) -> str:
    data = io.BytesIO()
    image.save(data, "PNG")
    done = subprocess.run(["tesseract", "-", "-", "-l", "kor+eng"], input=data.getvalue(),
                          capture_output=True, timeout=60)
    if done.returncode:
        raise OcrUnavailable("Tesseract 한국어 데이터가 필요해요.")
    return done.stdout.decode("utf-8", "replace")


def _prepare(image: Image.Image) -> list[Image.Image]:
    """회전을 바로잡고 크기를 맞춘다. 긴 캡처는 잘라서 인식한다."""
    image = ImageOps.exif_transpose(image)
    if image.mode in ("RGBA", "LA", "P"):  # 투명한 배경은 흰색으로 채운다.
        image = image.convert("RGBA")
        image = Image.alpha_composite(Image.new("RGBA", image.size, "white"), image)
    image = image.convert("RGB")
    short = min(image.size)
    scale = min(3.0, 1000 / short) if short < 1000 else min(1.0, TILE / image.width)
    if scale > 1 and image.width * scale > TILE:
        scale = max(1.0, TILE / image.width)
    if abs(scale - 1) > 0.02:
        image = image.resize((max(1, round(image.width * scale)), max(1, round(image.height * scale))), Image.LANCZOS)
    return [image.crop((0, top, image.width, min(top + TILE, image.height))) for top in range(0, image.height, TILE)]


def read_image(image: Image.Image) -> str:
    if image.width * image.height > MAX_PIXELS:
        raise ValueError("이미지가 너무 커요.")
    tiles = [t for t in _prepare(image) if min(t.size) >= 40]
    if sys.platform == "win32":
        try:
            engine = _engine()
        except (ImportError, OSError):
            engine = None
        if engine:
            async def run():
                return [await _windows(engine, t) for t in tiles]
            return "\n".join(asyncio.run(run())).strip()
    if shutil.which("tesseract"):
        return "\n".join(_tesseract(t) for t in tiles).strip()
    raise OcrUnavailable("이 서버에는 글자 인식 기능이 없어요.")


def read_bytes(data: bytes) -> str:
    with Image.open(io.BytesIO(data), formats=("PNG", "JPEG", "WEBP", "BMP", "GIF")) as image:
        return read_image(image)
