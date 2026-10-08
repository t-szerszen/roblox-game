#!/usr/bin/env python3
"""Execute production traffic graph, curve and reservation modules with vector doubles."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile


def literal(source: str) -> str:
    equals = "="
    while f"]{equals}]" in source:
        equals += "="
    return f"[{equals}[{source}]{equals}]"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau", default=shutil.which("luau"))
    args = parser.parse_args()
    if not args.luau:
        parser.error("pass --luau /path/to/luau")
    root = Path(__file__).resolve().parent.parent
    paths = [f"ServerScriptService/Traffic/{name}" for name in (
        "TrafficConfiguration", "TrafficTypes", "Trajectory", "RoadNetwork",
        "RoadNetworkData", "IntersectionManager")]
    source = "local SOURCES = {}\n"
    for path in paths:
        source += f"SOURCES[ {literal(path)} ] = {literal((root / 'src' / f'{path}.luau').read_text())}\n"
    source += (root / "tests/support/roblox_mock.luau").read_text()
    source += "\n" + (root / "tests/traffic.spec.luau").read_text()
    with tempfile.TemporaryDirectory(prefix="traffic-tests-") as directory:
        bundle = Path(directory) / "run.luau"
        bundle.write_text(source)
        result = subprocess.run([args.luau, str(bundle)], cwd=root, check=False)
        raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
