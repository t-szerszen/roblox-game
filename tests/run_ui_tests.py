#!/usr/bin/env python3
"""Run UI layout, cleanup and input-lock contracts with the official Luau CLI."""

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
    modules = [
        "ReplicatedStorage/Shared/UI/Theme",
        "ReplicatedStorage/Shared/UI/Scope",
        "ReplicatedStorage/Shared/UI/Layout",
        "ReplicatedStorage/Shared/Shop/ShopConfig",
        "ReplicatedStorage/Shared/Shop/PreviewConfig",
        "StarterPlayer/StarterPlayerScripts/UI/ModalInput",
        "StarterPlayer/StarterPlayerScripts/UI/Navigation",
    ]
    source = "local SOURCES = {}\n"
    for module in modules:
        source += f"SOURCES[ {literal(module)} ] = {literal((root / 'src' / f'{module}.luau').read_text())}\n"
    source += (root / "tests/support/ui_mock.luau").read_text()
    source += "\n" + (root / "tests/ui.spec.luau").read_text()
    with tempfile.TemporaryDirectory(prefix="ui-tests-") as directory:
        bundle = Path(directory) / "run.luau"
        bundle.write_text(source)
        result = subprocess.run([args.luau, str(bundle)], cwd=root, check=False)
        raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
