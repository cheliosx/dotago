"""程序化生成 UI 氛围贴图（不依赖 Pillow，只用标准库）。
输出：assets/img/grain.png  —— 可平铺的颗粒噪点
      assets/img/vignette.png —— 屏幕暗角
"""
import math
import os
import random
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "img")
os.makedirs(OUT, exist_ok=True)
random.seed(20261109)


def png(path, w, h, pixel_fn):
    raw = bytearray()
    for y in range(h):
        raw.append(0)  # filter: none
        for x in range(w):
            raw.extend(pixel_fn(x, y))
    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))
    header = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    blob = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
            + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(blob)
    print("wrote", path, len(blob), "bytes")


# 多倍频值噪声
def value_noise(w, h, cells):
    grid = [[random.random() for _ in range(cells + 1)] for _ in range(cells + 1)]
    def sample(x, y):
        fx = x / w * cells
        fy = y / h * cells
        ix, iy = int(fx), int(fy)
        tx, ty = fx - ix, fy - iy
        tx = tx * tx * (3 - 2 * tx)
        ty = ty * ty * (3 - 2 * ty)
        a = grid[iy][ix] * (1 - tx) + grid[iy][ix + 1] * tx
        b = grid[iy + 1][ix] * (1 - tx) + grid[iy + 1][ix + 1] * tx
        return a * (1 - ty) + b * ty
    return sample


def make_grain(w=256, h=256):
    n1 = value_noise(w, h, 8)
    n2 = value_noise(w, h, 32)
    n3 = value_noise(w, h, 96)
    def px(x, y):
        v = 0.55 * n1(x, y) + 0.3 * n2(x, y) + 0.15 * n3(x, y)
        speck = 0.6 if random.random() > 0.985 else 0.0
        a = int(max(0.0, min(1.0, v * 0.7 + speck)) * 46)
        warm = 226 + int(v * 24)
        return (min(255, warm), min(255, warm - 8), min(255, warm - 28), a)
    png(os.path.join(OUT, "grain.png"), w, h, px)


def make_vignette(w=512, h=320):
    def px(x, y):
        nx = (x / w - 0.5) * 2.0
        ny = (y / h - 0.5) * 2.0
        d = min(1.0, math.sqrt(nx * nx * 0.85 + ny * ny * 1.15) / 1.35)
        a = int(max(0.0, (d - 0.34) / 0.66) ** 1.7 * 165)
        return (4, 6, 12, a)
    png(os.path.join(OUT, "vignette.png"), w, h, px)


if __name__ == "__main__":
    make_grain()
    make_vignette()
