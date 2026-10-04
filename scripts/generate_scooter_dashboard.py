#!/usr/bin/env python3
"""Generate the reusable Roblox dashboard and a front-view SVG from one design."""

import json
from pathlib import Path
import subprocess
import tempfile
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets" / "scooter"
DESIGN = {
    "width": 1.85, "height": 0.74, "depth": 0.24, "corner": 0.12,
    "canvas": [1000, 400],
    "case": "#1b2432", "rim": "#344152", "glass": "#080f19",
    "white": "#f2f8ff", "cyan": "#3ddcf0", "red": "#ff4654",
    "brand": "KuKirin",
    "purple": "#aa88ff", "battery_percent": 67, "battery_bars": 6,
    "digit_width": 112, "digit_gap": 20,
}
SEGMENTS = {
    "A": (16, 0, 80, 12), "B": (96, 16, 12, 82),
    "C": (96, 114, 12, 82), "D": (16, 200, 80, 12),
    "E": (4, 114, 12, 82), "F": (4, 16, 12, 82),
    "G": (16, 100, 80, 12),
}
DIGITS = {"0": "ABCDEF", "4": "BCFG", "7": "ABC"}


def color(hex_value):
    return [int(hex_value[i:i + 2], 16) / 255 for i in (1, 3, 5)]


def node(class_name, properties=None, **children):
    return {"$className": class_name, "$properties": properties or {}, **children}


def frame(x, y, z, matrix=None):
    return [x, y, z, *(matrix or [1, 0, 0, 0, 1, 0, 0, 0, 1])]


def part(size, cframe, tint, class_name="Part"):
    return node(class_name, {
        "Size": size, "CFrame": cframe, "Color": color(tint),
        "Material": "SmoothPlastic", "Anchored": True, "Massless": True,
        "CanCollide": False, "CanTouch": False, "CanQuery": False,
        "CastShadow": False, "TopSurface": "Smooth", "BottomSurface": "Smooth",
        "Attributes": {"ScooterDecoration": {"Bool": True}},
    })


def octagon(prefix, width, height, depth, cut, z, tint):
    result = {
        prefix + "Horizontal": part([width, height - 2 * cut, depth], frame(0, 0, z), tint),
        prefix + "Vertical": part([width - 2 * cut, height, depth], frame(0, 0, z), tint),
    }
    # Wedge thickness runs along X. Its right-angle corner is at -Y, +Z;
    # the basis places it at the inside of each clipped housing corner.
    for sx in (-1, 1):
        for sy in (-1, 1):
            matrix = [0, 0, -sx, 0, sy, 0, sx * sy, 0, 0]
            result[f"{prefix}Corner{sx}_{sy}"] = part(
                [depth, cut, cut], frame(sx * (width - cut) / 2,
                                       sy * (height - cut) / 2, z, matrix),
                tint, "WedgePart")
    return result


def ui_frame(x, y, width, height, tint, transparency=0):
    return node("Frame", {
        "Position": {"UDim2": [[0, int(x)], [0, int(y)]]}, "Size": {"UDim2": [[0, int(width)], [0, int(height)]]},
        "BackgroundColor3": color(tint), "BackgroundTransparency": transparency,
        "BorderSizePixel": 0,
    })


def label(text, x, y, width, height, size, tint, transparency=0):
    return node("TextLabel", {
        "Text": text, "Position": {"UDim2": [[0, x], [0, y]]}, "Size": {"UDim2": [[0, width], [0, height]]},
        "BackgroundTransparency": 1, "TextColor3": color(tint),
        "TextTransparency": transparency, "TextSize": size, "Font": "GothamBold",
    })


def gui():
    children = {
        "HeaderAccent": ui_frame(52, 49, 34, 5, DESIGN["cyan"]),
        "Header": label("SPEED", 92, 30, 122, 42, 22, DESIGN["cyan"]),
        "Brand": label(DESIGN["brand"], 748, 28, 195, 52, 33, DESIGN["cyan"]),
        "Unit": label("km/h", 720, 213, 148, 50, 32, DESIGN["white"]),
        "Brake": label("(!)  BRAKE", 54, 311, 200, 44, 27, DESIGN["red"], 0.84),
        "Mode": label("SPORT", 766, 311, 165, 44, 30, DESIGN["purple"]),
        "BatteryPercent": label(f'{DESIGN["battery_percent"]}%', 570, 311, 92, 44, 26, DESIGN["white"]),
    }
    battery = ui_frame(354, 322, 178, 26, DESIGN["glass"], 1)
    filled = round(DESIGN["battery_bars"] * DESIGN["battery_percent"] / 100)
    for index in range(DESIGN["battery_bars"]):
        battery[f"Bar{index + 1}"] = ui_frame(index * 32, 0, 18, 26, DESIGN["white"],
                                            0 if index < filled else 0.85)
    children["Battery"] = battery
    for index in range(1, 4):
        x = DESIGN["canvas"][0] / 2 - DESIGN["digit_width"] / 2
        x += (index - 3) * (DESIGN["digit_width"] + DESIGN["digit_gap"])
        digit = ui_frame(x, 91, DESIGN["digit_width"], 212, DESIGN["glass"], 1)
        # The simplified battery stays at 67%; only server speed/mode/brake change.
        digit["$properties"]["Visible"] = index == 3
        for name, (x, y, width, height) in SEGMENTS.items():
            digit[name] = ui_frame(x, y, width, height, DESIGN["white"],
                                   0 if name in DIGITS["0"] else 0.95)
            digit[name]["Corners"] = node("UICorner", {"CornerRadius": {"UDim": [0, 3]}})
        children[f"Digit{index}"] = digit
    return node("SurfaceGui", {
        "Face": "Front", "SizingMode": "FixedSize", "CanvasSize": DESIGN["canvas"],
        "AlwaysOnTop": False, "LightInfluence": 0, "Brightness": 1.15,
        "MaxDistance": 65, "ClipsDescendants": True,
    }, **children)


def model():
    w, h, d, c = (DESIGN[k] for k in ("width", "height", "depth", "corner"))
    children = octagon("Case", w, h, d, c, 0, DESIGN["case"])
    children.update(octagon("Rim", w - 0.04, h - 0.04, 0.028, c - 0.02,
                           -d / 2 - 0.01, DESIGN["rim"]))
    children.update(octagon("Glass", w - 0.095, h - 0.095, 0.016, c - 0.025,
                           -d / 2 - 0.029, DESIGN["glass"]))
    screen = part([w - 0.105, h - 0.105, 0.01], frame(0, 0, -d / 2 - 0.04), DESIGN["glass"])
    screen["$properties"]["Transparency"] = 1
    screen["DashboardGui"] = gui()
    children["DisplaySurface"] = screen
    children["Mount"] = part([0.46, 0.14, 0.22], frame(0, -h / 2 - 0.045, 0.035), DESIGN["case"])
    return node("Model", **children)


def preview():
    """Draw the same segment layout in a scalable front-view review artifact."""
    scene = model()
    cx, cy, scale = 700, 422, 600

    def outline(width, height, cut, fill, stroke, stroke_width):
        left, right = cx - width / 2, cx + width / 2
        top, bottom = cy - height / 2, cy + height / 2
        points = [(left + cut, top), (right - cut, top), (right, top + cut),
                  (right, bottom - cut), (right - cut, bottom), (left + cut, bottom),
                  (left, bottom - cut), (left, top + cut)]
        path = "M" + " L".join(f"{x:g} {y:g}" for x, y in points) + " Z"
        return f'<path d="{path}" fill="{fill}" stroke="{stroke}" stroke-width="{stroke_width}"/>'

    mount = scene["Mount"]["$properties"]
    mw, mh = (v * scale for v in mount["Size"][:2])
    mount_x = cx + mount["CFrame"][0] * scale - mw / 2
    mount_y = cy - mount["CFrame"][1] * scale - mh / 2
    sw, sh = (v * scale for v in scene["DisplaySurface"]["$properties"]["Size"][:2])
    svg = ['<svg xmlns="http://www.w3.org/2000/svg" width="1400" height="850" viewBox="0 0 1400 850">',
           '<rect width="1400" height="850" fill="#101720"/>',
           '<text x="140" y="92" fill="#f2f8ff" font-family="sans-serif" font-size="30">Licznik hulajnogi — projekt 02</text>',
           '<text x="140" y="130" fill="#94a4b8" font-family="sans-serif" font-size="18">Wyśrodkowana prędkość · hamulec · bateria 67% · ECO / SPORT</text>',
           f'<rect x="{mount_x:g}" y="{mount_y:g}" width="{mw:g}" height="{mh:g}" rx="6" fill="{DESIGN["case"]}"/>',
           outline(DESIGN["width"] * scale, DESIGN["height"] * scale,
                   DESIGN["corner"] * scale, DESIGN["case"], DESIGN["rim"], 4),
           outline((DESIGN["width"] - 0.095) * scale, (DESIGN["height"] - 0.095) * scale,
                   (DESIGN["corner"] - 0.025) * scale, DESIGN["glass"], DESIGN["rim"], 2),
           f'<g transform="translate({cx - sw / 2:g} {cy - sh / 2:g}) scale({sw / DESIGN["canvas"][0]:g} {sh / DESIGN["canvas"][1]:g})">']
    ui = gui()

    def draw_ui(name, item, offset_x=0, offset_y=0):
        p = item["$properties"]
        x = offset_x + p["Position"]["UDim2"][0][1]
        y = offset_y + p["Position"]["UDim2"][1][1]
        width, height = p["Size"]["UDim2"][0][1], p["Size"]["UDim2"][1][1]
        rgb = p.get("TextColor3", p.get("BackgroundColor3"))
        tint = "#" + "".join(f"{round(channel * 255):02x}" for channel in rgb)
        if item["$className"] == "TextLabel":
            svg.append(f'<text x="{x + width / 2}" y="{y + height / 2}" fill="{tint}" text-anchor="middle" dominant-baseline="central" font-family="sans-serif" font-weight="700" font-size="{p["TextSize"]}">{escape(p["Text"])}</text>')
        else:
            svg.append(f'<rect x="{x}" y="{y}" width="{width}" height="{height}" fill="{tint}" opacity="{1 - p["BackgroundTransparency"]}"/>')
        for child_name, child in item.items():
            if not child_name.startswith("$"):
                draw_ui(child_name, child, x, y)

    for name, item in ui.items():
        if not name.startswith("$") and not name.startswith("Digit"):
            draw_ui(name, item)
    stride = DESIGN["digit_width"] + DESIGN["digit_gap"]
    left = DESIGN["canvas"][0] / 2 - (2 * DESIGN["digit_width"] + DESIGN["digit_gap"]) / 2
    for index, digit in enumerate("47"):
        for name, (x, y, width, height) in SEGMENTS.items():
            opacity = 1 if name in DIGITS[digit] else 0.05
            svg.append(f'<rect x="{left + index * stride + x}" y="{91 + y}" width="{width}" height="{height}" rx="3" fill="{DESIGN["white"]}" opacity="{opacity}"/>')
    svg += ['</g>', '<text x="140" y="785" fill="#94a4b8" font-family="sans-serif" font-size="18">Podgląd: 47 km/h, SPORT, bateria 67% i aktywny hamulec.</text>', '</svg>']
    (OUTPUT / "dashboard-preview.svg").write_text("\n".join(svg) + "\n")


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="scooter-dashboard-") as directory:
        project = Path(directory) / "dashboard.project.json"
        project.write_text(json.dumps({"name": "ScooterDashboard", "tree": model()}))
        subprocess.run(["rojo", "build", str(project), "--output",
                        str(OUTPUT / "ScooterDashboard.rbxmx")], check=True)
    preview()


if __name__ == "__main__":
    main()
