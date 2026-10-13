#!/usr/bin/env python3
"""Local regression for G4 shock presentation; does not connect to Studio."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

from run_traffic_tests import literal


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau", default=shutil.which("luau"))
    args = parser.parse_args()
    if not args.luau:
        parser.error("pass --luau /path/to/luau")
    root = Path(__file__).resolve().parents[1]
    paths = [
        "ReplicatedStorage/Shared/ScooterConfig",
        "ReplicatedStorage/Shared/Scooter/ScooterConfig",
        "ReplicatedStorage/Shared/UI/Scope",
        "ReplicatedStorage/Shared/Scooter/ScooterCompoundVisuals",
    ]
    source = "local SOURCES = {}\n"
    for path in paths:
        source += f"SOURCES[ {literal(path)} ] = {literal((root / 'src' / f'{path}.luau').read_text())}\n"
    for path in ("support/roblox_mock.luau", "support/scooter_animation_mock.luau", "scooter_g4_visuals.spec.luau"):
        source += "\n" + (root / "tests" / path).read_text()
    with tempfile.TemporaryDirectory(prefix="g4-visual-tests-") as directory:
        bundle = Path(directory) / "run.luau"
        bundle.write_text(source)
        raise SystemExit(subprocess.run([args.luau, str(bundle)], cwd=root).returncode)


if __name__ == "__main__":
    main()
