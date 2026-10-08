#!/usr/bin/env python3
"""Build the reusable neutral territory flag; never modifies a Studio map."""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'assets' / 'territory' / 'TerritoryFlag.rbxmx'
IDENTITY = [1, 0, 0, 0, 1, 0, 0, 0, 1]
NEUTRAL = [180 / 255, 185 / 255, 195 / 255]


def part(size, position, color, *, shape='Block', matrix=None, tint=False, **properties):
    return {'$className': 'Part', '$properties': {
        'Size': size, 'CFrame': [*position, *(matrix or IDENTITY)],
        'Color': color, 'Material': 'SmoothPlastic', 'Shape': shape,
        'Anchored': True, 'CanCollide': False, 'CanTouch': False,
        'CanQuery': False, 'TopSurface': 'Smooth', 'BottomSurface': 'Smooth',
        **({'Attributes': {'TerritoryTint': {'Bool': True}}} if tint else {}),
        **properties,
    }}


def model():
    vertical_cylinder = [0, -1, 0, 1, 0, 0, 0, 0, 1]
    children = {
        'Anchor': part([0.1, 0.1, 0.1], [0, 0, 0], NEUTRAL,
                       Transparency=1, CastShadow=False),
        'Foot': part([0.35, 3, 3], [0, 0.175, 0], [0.24, 0.27, 0.31],
                     shape='Cylinder', matrix=vertical_cylinder, Material='Concrete'),
        'Pole': part([14, 0.32, 0.32], [0, 7.35, 0], [0.68, 0.73, 0.8],
                     shape='Cylinder', matrix=vertical_cylinder, Material='Metal'),
        'Finial': part([0.58, 0.58, 0.58], [0, 14.4, 0], [0.83, 0.86, 0.91], shape='Ball', Material='Metal'),
    }
    # A shallow folded silhouette reads from both sides without per-frame animation.
    for index, z in enumerate([0.0, 0.14, 0.25, 0.13, -0.02, -0.11]):
        children[f'Cloth_{index + 1}'] = part(
            [1.12, 3.5 - index * 0.07, 0.1], [0.73 + index * 1.1, 12.25, z],
            NEUTRAL, tint=True, Material='Fabric', CastShadow=False)
    return {'$className': 'Model', **children}


def main():
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='territory-flag-') as directory:
        project = Path(directory) / 'flag.project.json'
        project.write_text(json.dumps({'name': 'TerritoryFlag', 'tree': model()}))
        subprocess.run(['rojo', 'build', str(project), '--output', str(OUTPUT)], check=True)
    print(f'Generated {OUTPUT.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
