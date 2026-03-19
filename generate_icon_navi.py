#!/usr/bin/env python3
"""
Generate premium Navi app icon — dark theme, bold NAVI text, glowing orb.
Matches the in-app ThinkingOrb aesthetic.
"""

import math
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SIZE = 1024

BASE = "/Users/tedsvard/Library/Mobile Documents/com~apple~CloudDocs/Navi-v6"
IOS_DIR = f"{BASE}/EonCode/iOS/Assets.xcassets/AppIcon.appiconset"
MAC_DIR = f"{BASE}/EonCode/macOS/Assets.xcassets/AppIcon.appiconset"


def lerp_color(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(len(c1)))


def create_navi_icon(size=1024):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # ── Background: deep dark gradient (matches app dark mode) ──────────
    # Dark navy top → very dark navy bottom
    bg = Image.new("RGBA", (size, size))
    bg_draw = ImageDraw.Draw(bg)
    top_col    = (14, 16, 28, 255)   # near-black with blue tint
    bottom_col = (8, 10, 20, 255)    # even darker
    for y in range(size):
        t = y / size
        col = lerp_color(top_col, bottom_col, t)
        bg_draw.line([(0, y), (size, y)], fill=col)

    # Rounded corners mask (iOS standard ratio ~22.75%)
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    r = int(size * 0.2275)
    mask_draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=255)
    img.paste(bg, (0, 0), mask)

    draw = ImageDraw.Draw(img)
    cx, cy = size // 2, int(size * 0.42)   # orb center slightly above midpoint

    # ── Outer ambient glow (soft orange, matches accentNavi #C4825A) ─────
    accent_rgb = (196, 130, 90)
    for i in range(80, 0, -3):
        alpha = int(6 * (i / 80) ** 1.5)
        r_glow = int(size * 0.28) + i * 3
        draw.ellipse(
            [cx - r_glow, cy - r_glow, cx + r_glow, cy + r_glow],
            outline=(*accent_rgb, alpha), width=1
        )

    # ── Main orb layers ──────────────────────────────────────────────────
    # Layer 1: large blurred background circle
    orb_r = int(size * 0.22)
    orb_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    orb_draw = ImageDraw.Draw(orb_layer)
    orb_draw.ellipse(
        [cx - orb_r, cy - orb_r, cx + orb_r, cy + orb_r],
        fill=(*accent_rgb, 35)
    )
    orb_layer = orb_layer.filter(ImageFilter.GaussianBlur(radius=int(size * 0.04)))
    img = Image.alpha_composite(img, orb_layer)

    # Layer 2: slightly smaller, more opaque
    orb_layer2 = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    orb2_draw = ImageDraw.Draw(orb_layer2)
    orb2_r = int(size * 0.17)
    orb2_draw.ellipse(
        [cx - orb2_r, cy - orb2_r, cx + orb2_r, cy + orb2_r],
        fill=(*accent_rgb, 70)
    )
    orb_layer2 = orb_layer2.filter(ImageFilter.GaussianBlur(radius=int(size * 0.025)))
    img = Image.alpha_composite(img, orb_layer2)

    # Layer 3: bright core
    draw = ImageDraw.Draw(img)
    core_r = int(size * 0.10)
    draw.ellipse(
        [cx - core_r, cy - core_r, cx + core_r, cy + core_r],
        fill=(*accent_rgb, 200)
    )

    # Layer 4: bright specular highlight (top-left of orb)
    hl_r = int(size * 0.06)
    hl_off = int(size * 0.04)
    draw.ellipse(
        [cx - hl_off - hl_r, cy - hl_off - hl_r,
         cx - hl_off + hl_r, cy - hl_off + hl_r],
        fill=(255, 240, 225, 130)
    )

    # ── "NAVI" text — bold, uppercase, premium ───────────────────────────
    font_candidates = [
        # Bold system fonts
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial Bold.ttf",
        "/System/Library/Fonts/SFNSDisplay-Bold.otf",
    ]

    text = "NAVI"
    font_size = int(size * 0.285)
    font = None

    # Try to load bold variant
    for fp in font_candidates:
        try:
            f = ImageFont.truetype(fp, font_size)
            font = f
            break
        except Exception:
            continue
    if font is None:
        font = ImageFont.load_default()

    # Measure
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]

    # Position: centered horizontally, below orb
    tx = cx - tw // 2 - bbox[0]
    ty = int(size * 0.64) - bbox[1]   # in lower third

    # Text glow (soft orange)
    glow_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_layer)
    glow_draw.text((tx, ty), text, font=font, fill=(*accent_rgb, 120))
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(radius=int(size * 0.022)))
    img = Image.alpha_composite(img, glow_layer)

    # Main text: bright white with slight warm tint
    draw = ImageDraw.Draw(img)
    draw.text((tx, ty), text, font=font, fill=(245, 240, 235, 255))

    # ── Subtle radial vignette (darker edges) ────────────────────────────
    vig_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    vig_draw = ImageDraw.Draw(vig_layer)
    for i in range(1, 50):
        alpha = int(40 * (i / 50) ** 2)
        vig_draw.rounded_rectangle(
            [i * 3, i * 3, size - i * 3 - 1, size - i * 3 - 1],
            radius=max(0, r - i * 4),
            outline=(0, 0, 0, 0)
        )

    # Apply mask again for clean rounded corners
    final = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    final.paste(img, (0, 0), mask)

    return final


def flatten(img_rgba, px):
    flat = Image.new("RGB", (px, px), (14, 16, 28))
    resized = img_rgba.resize((px, px), Image.LANCZOS)
    flat.paste(resized, (0, 0), resized)
    return flat


def save_all_sizes(base_img):
    os.makedirs(IOS_DIR, exist_ok=True)
    os.makedirs(MAC_DIR, exist_ok=True)

    ios_sizes = [
        ("Icon-20@1x.png",    20),
        ("Icon-20@2x.png",    40),
        ("Icon-20@3x.png",    60),
        ("Icon-29@1x.png",    29),
        ("Icon-29@2x.png",    58),
        ("Icon-29@3x.png",    87),
        ("Icon-40@1x.png",    40),
        ("Icon-40@2x.png",    80),
        ("Icon-40@3x.png",   120),
        ("Icon-60@2x.png",   120),
        ("Icon-60@3x.png",   180),
        ("Icon-76@1x.png",    76),
        ("Icon-76@2x.png",   152),
        ("Icon-83.5@2x.png", 167),
        ("Icon-1024.png",   1024),
    ]

    mac_sizes = [
        ("Icon-16.png",     16),
        ("Icon-16@2x.png",  32),
        ("Icon-32.png",     32),
        ("Icon-32@2x.png",  64),
        ("Icon-128.png",   128),
        ("Icon-128@2x.png",256),
        ("Icon-256.png",   256),
        ("Icon-256@2x.png",512),
        ("Icon-512.png",   512),
        ("Icon-512@2x.png",1024),
    ]

    for filename, px in ios_sizes:
        out = flatten(base_img, px)
        out.save(os.path.join(IOS_DIR, filename), "PNG", optimize=True)
        print(f"  iOS {filename} ({px}px)")

    for filename, px in mac_sizes:
        out = flatten(base_img, px)
        out.save(os.path.join(MAC_DIR, filename), "PNG", optimize=True)
        print(f"  Mac {filename} ({px}px)")

    print("\n✓ Alla ikoner genererade!")


if __name__ == "__main__":
    print("Genererar Navi premium-ikon (mörkt tema, NAVI-text)…")
    icon = create_navi_icon(SIZE)
    preview_path = f"{BASE}/navi_icon_preview_v2.png"
    icon.save(preview_path)
    print(f"Förhandsvisning: {preview_path}")
    save_all_sizes(icon)
