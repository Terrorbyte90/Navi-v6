#!/usr/bin/env python3
"""Generate Navi app icon - light, elegant design with compass/navigation theme."""

import math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SIZE = 1024

def lerp_color(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(len(c1)))

def create_navi_icon(size=1024):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Background gradient: soft white to light sky blue
    bg = Image.new("RGBA", (size, size))
    bg_draw = ImageDraw.Draw(bg)
    top_col    = (245, 248, 255, 255)   # near-white with cool tint
    bottom_col = (210, 228, 255, 255)   # soft sky blue
    for y in range(size):
        t = y / size
        col = lerp_color(top_col, bottom_col, t)
        bg_draw.line([(0, y), (size, y)], fill=col)

    # Rounded corners mask
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    r = int(size * 0.2275)  # iOS corner radius ratio
    mask_draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=255)
    img.paste(bg, (0, 0), mask)

    draw = ImageDraw.Draw(img)

    # --- Subtle compass rose / star element ---
    cx, cy = size // 2, size // 2

    # Outer glow ring
    glow_r = int(size * 0.36)
    for i in range(30, 0, -1):
        alpha = int(18 * (i / 30))
        col = (150, 190, 240, alpha)
        draw.ellipse(
            [cx - glow_r - i*2, cy - glow_r - i*2,
             cx + glow_r + i*2, cy + glow_r + i*2],
            outline=col, width=1
        )

    # Inner delicate circle
    ring_r = int(size * 0.36)
    draw.ellipse(
        [cx - ring_r, cy - ring_r, cx + ring_r, cy + ring_r],
        outline=(170, 205, 245, 180), width=int(size * 0.007)
    )

    # Compass cardinal points (N, E, S, W) as subtle triangles
    spoke_len_long  = int(size * 0.22)
    spoke_len_short = int(size * 0.14)
    spoke_w = int(size * 0.022)

    for angle_deg, is_north in [(90, True), (270, False), (0, False), (180, False)]:
        angle = math.radians(angle_deg)
        # long spike
        x_tip = cx + math.cos(angle) * spoke_len_long
        y_tip = cy - math.sin(angle) * spoke_len_long
        x_base1 = cx + math.cos(angle + math.pi/2) * spoke_w
        y_base1 = cy - math.sin(angle + math.pi/2) * spoke_w
        x_base2 = cx + math.cos(angle - math.pi/2) * spoke_w
        y_base2 = cy - math.sin(angle - math.pi/2) * spoke_w

        col = (90, 145, 220, 200) if is_north else (160, 190, 230, 140)
        draw.polygon(
            [(x_tip, y_tip), (x_base1, y_base1), (x_base2, y_base2)],
            fill=col
        )

    # Diagonal minor spokes
    for angle_deg in [45, 135, 225, 315]:
        angle = math.radians(angle_deg)
        x_tip = cx + math.cos(angle) * spoke_len_short
        y_tip = cy - math.sin(angle) * spoke_len_short
        x_base1 = cx + math.cos(angle + math.pi/2) * (spoke_w * 0.55)
        y_base1 = cy - math.sin(angle + math.pi/2) * (spoke_w * 0.55)
        x_base2 = cx + math.cos(angle - math.pi/2) * (spoke_w * 0.55)
        y_base2 = cy - math.sin(angle - math.pi/2) * (spoke_w * 0.55)
        draw.polygon(
            [(x_tip, y_tip), (x_base1, y_base1), (x_base2, y_base2)],
            fill=(180, 205, 235, 120)
        )

    # Center dot
    dot_r = int(size * 0.025)
    draw.ellipse(
        [cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r],
        fill=(90, 145, 220, 230)
    )

    # --- "Navi" text ---
    # Try Optima, then Avenir Next, then fallback
    font_paths = [
        "/System/Library/Fonts/Optima.ttc",
        "/System/Library/Fonts/Avenir Next.ttc",
        "/System/Library/Fonts/HelveticaNeue.ttc",
    ]
    font = None
    font_size = int(size * 0.28)
    for fp in font_paths:
        try:
            font = ImageFont.truetype(fp, font_size)
            break
        except Exception:
            continue
    if font is None:
        font = ImageFont.load_default()

    text = "Navi"
    # Measure text
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]

    # Position text below center (compass rose is centered, text slightly below)
    tx = cx - tw // 2 - bbox[0]
    ty = cy - th // 2 - bbox[1] + int(size * 0.06)

    # Text shadow (soft, offset down-right)
    shadow_offset = int(size * 0.012)
    draw.text(
        (tx + shadow_offset, ty + shadow_offset),
        text, font=font,
        fill=(120, 160, 210, 80)
    )

    # Main text: deep blue, slightly transparent for elegance
    draw.text(
        (tx, ty), text, font=font,
        fill=(45, 90, 175, 245)
    )

    # Apply very slight blur to glow elements only - done by blending
    # Final slight vignette
    vignette = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    v_draw = ImageDraw.Draw(vignette)
    for i in range(60, 0, -1):
        alpha = int(40 * ((60 - i) / 60) ** 2)
        v_draw.rectangle([i, i, size - i - 1, size - i - 1], outline=(0, 0, 80, 0))

    # Subtle top highlight
    highlight = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    h_draw = ImageDraw.Draw(highlight)
    h_r = int(size * 0.45)
    h_draw.ellipse(
        [cx - h_r, cy - size * 0.7, cx + h_r, cy + h_r * 0.3],
        fill=(255, 255, 255, 28)
    )
    img = Image.alpha_composite(img, highlight)

    return img


def resize_png(img, size):
    return img.resize((size, size), Image.LANCZOS)


def save_all_sizes(base_img):
    import os

    ios_dir = "/Users/tedsvard/Library/Mobile Documents/com~apple~CloudDocs/Navi v2/EonCode/iOS/Assets.xcassets/AppIcon.appiconset"
    mac_dir = "/Users/tedsvard/Library/Mobile Documents/com~apple~CloudDocs/Navi v2/EonCode/macOS/Assets.xcassets/AppIcon.appiconset"

    os.makedirs(ios_dir, exist_ok=True)
    os.makedirs(mac_dir, exist_ok=True)

    # iOS/iPad sizes: (filename, actual_pixel_size)
    ios_sizes = [
        ("Icon-20@2x.png",   40),
        ("Icon-20@3x.png",   60),
        ("Icon-29@2x.png",   58),
        ("Icon-29@3x.png",   87),
        ("Icon-40@2x.png",   80),
        ("Icon-40@3x.png",  120),
        ("Icon-60@2x.png",  120),
        ("Icon-60@3x.png",  180),
        ("Icon-76@1x.png",   76),
        ("Icon-76@2x.png",  152),
        ("Icon-83.5@2x.png",167),
        ("Icon-1024.png",  1024),
    ]

    # Mac sizes
    mac_sizes = [
        ("Icon-16.png",    16),
        ("Icon-16@2x.png", 32),
        ("Icon-32.png",    32),
        ("Icon-32@2x.png", 64),
        ("Icon-128.png",   128),
        ("Icon-128@2x.png",256),
        ("Icon-256.png",   256),
        ("Icon-256@2x.png",512),
        ("Icon-512.png",   512),
        ("Icon-512@2x.png",1024),
    ]

    # Convert to RGB with white background for PNG (no alpha for iOS/Mac icons)
    def flatten(img_rgba, size):
        flat = Image.new("RGBA", (size, size), (255, 255, 255, 255))
        resized = img_rgba.resize((size, size), Image.LANCZOS)
        flat.paste(resized, (0, 0), resized)
        return flat.convert("RGB")

    for filename, px in ios_sizes:
        out = flatten(base_img, px)
        out.save(os.path.join(ios_dir, filename), "PNG", optimize=True)
        print(f"  iOS: {filename} ({px}x{px})")

    for filename, px in mac_sizes:
        out = flatten(base_img, px)
        out.save(os.path.join(mac_dir, filename), "PNG", optimize=True)
        print(f"  Mac: {filename} ({px}x{px})")

    print("\nAll icons generated!")


if __name__ == "__main__":
    print("Generating Navi icon...")
    icon = create_navi_icon(SIZE)
    # Save preview
    icon.save("/Users/tedsvard/Library/Mobile Documents/com~apple~CloudDocs/Navi v2/navi_icon_preview.png")
    print("Preview saved.")
    save_all_sizes(icon)
