#!/usr/bin/env python3
"""Run actual gang, territory, combat and phone server modules with controlled service doubles."""
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
    paths = [
        "ReplicatedStorage/Shared/Gang/GangConfig", "ReplicatedStorage/Shared/Gang/GangTypes",
        "ReplicatedStorage/Shared/Gang/TerritoryConfig", "ReplicatedStorage/Shared/Combat/CombatConfig",
        "ReplicatedStorage/Shared/ScooterConfig", "ReplicatedStorage/Shared/Scooter/ScooterConfig",
        "ReplicatedStorage/Shared/CharacterConfig", "ReplicatedStorage/Shared/Activity/ActivityConfig",
        "ReplicatedStorage/Shared/Phone/PhoneConfig", "ReplicatedStorage/Shared/Shop/ShopConfig",
        "ServerScriptService/Gang/GangNames", "ServerScriptService/Gang/GangService",
        "ServerScriptService/Gang/GangRequests", "ServerScriptService/Combat/CombatService",
        "ServerScriptService/Territory/TerritoryCapture", "ServerScriptService/Territory/TerritoryRewards",
        "ServerScriptService/Territory/TerritoryService", "ServerScriptService/Activity/PlayerDataService",
        "ServerScriptService/Phone/PhoneServer.server",
    ]
    source = "local SOURCES = {}\n"
    for path in paths:
        source += f"SOURCES[ {literal(path)} ] = {literal((root / 'src' / f'{path}.luau').read_text())}\n"
    for path in ["support/roblox_mock.luau", "support/gang_mock.luau", "gang.spec.luau"]:
        source += "\n" + (root / "tests" / path).read_text()
    with tempfile.TemporaryDirectory(prefix="gang-tests-") as directory:
        bundle = Path(directory) / "run.luau"
        bundle.write_text(source)
        result = subprocess.run([args.luau, str(bundle)], cwd=root, check=False)
        raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
