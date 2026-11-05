#!/usr/bin/env python3
"""生成 AppIcon.icns：深色圆角底 + 指针拼出的 24"""
import math, os, subprocess, tempfile
from PIL import Image, ImageDraw, ImageFilter

G = {
 0:[[90,180],[180,270],[0,180],[0,180],[0,90],[0,270]],1:[[225,225],[180,180],[225,225],[0,180],[225,225],[0,0]],
 2:[[90,90],[180,270],[90,180],[0,270],[0,90],[270,270]],3:[[90,90],[180,270],[90,90],[0,270],[90,90],[0,270]],
 4:[[180,180],[180,180],[0,90],[180,270],[225,225],[0,0]],5:[[90,180],[270,270],[0,90],[180,270],[90,90],[0,270]],
 6:[[90,180],[270,270],[0,180],[180,270],[0,90],[0,270]],7:[[90,90],[180,270],[225,225],[0,180],[225,225],[0,0]],
 8:[[90,180],[180,270],[0,90],[0,270],[0,90],[0,270]],9:[[90,180],[180,270],[0,90],[0,180],[90,90],[0,270]],
}

S, SS = 1024, 2            # 画布 / 超采样倍数
BOARD = 824                # macOS 网格里图形占 824/1024
BG = (22, 22, 24, 255)
INK = (247, 246, 243, 255)
TEXT = "24"

px = S * SS
img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
ox = (px - BOARD * SS) // 2

# 底板 + 阴影
sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
ImageDraw.Draw(sh).rounded_rectangle(
    [ox, ox + 22, ox + BOARD * SS, ox + BOARD * SS + 22], radius=190 * SS, fill=(0, 0, 0, 80))
img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(30)))
d.rounded_rectangle([ox, ox, ox + BOARD * SS, ox + BOARD * SS], radius=190 * SS, fill=BG)
d.rounded_rectangle([ox, ox, ox + BOARD * SS, ox + BOARD * SS], radius=190 * SS,
                    outline=(255, 255, 255, 22), width=3 * SS)

# 指针比例照网页版：针长 0.475 格、针粗 0.094 格
rows, gapr = 3, 0.08
face = (BOARD * SS * 0.86) / (rows + (rows - 1) * gapr)
pitch = face * (1 + gapr)
n = len(TEXT)
total_w = (n * 2 - 1) * pitch + face          # 每位数字占 2 列
x0 = (px - total_w) / 2
y0 = (px - (rows * face + (rows - 1) * face * gapr)) / 2
hw = 0.094 * face
for di, ch in enumerate(TEXT):
    for k in range(6):
        cx = x0 + di * 2 * pitch + (k % 2) * pitch + face / 2
        cy = y0 + (k // 2) * pitch + face / 2
        for a in G[int(ch)][k]:
            th = math.radians(a)
            ex = cx + math.sin(th) * 0.475 * face
            ey = cy - math.cos(th) * 0.475 * face
            d.line([cx, cy, ex, ey], fill=INK, width=int(round(hw)))
            for p in ((cx, cy), (ex, ey)):
                r = hw / 2
                d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=INK)

big = img.resize((S, S), Image.LANCZOS)
big.save("AppIcon-1024.png")

with tempfile.TemporaryDirectory() as tmp:
    iconset = os.path.join(tmp, "AppIcon.iconset")
    os.makedirs(iconset)
    for size in (16, 32, 64, 128, 256, 512):
        big.resize((size, size), Image.LANCZOS).save(f"{iconset}/icon_{size}x{size}.png")
        big.resize((size * 2, size * 2), Image.LANCZOS).save(f"{iconset}/icon_{size}x{size}@2x.png")
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", "AppIcon.icns"], check=True)
print("AppIcon.icns", os.path.getsize("AppIcon.icns"), "bytes")
