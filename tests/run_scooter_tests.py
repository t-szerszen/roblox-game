#!/usr/bin/env python3
"""Execute the real scooter modules with a small Roblox service test double."""

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
        parser.error("pass --luau /path/to/luau or install the official Luau CLI")
    root = Path(__file__).resolve().parent.parent
    paths = [
        "ReplicatedStorage/Shared/ScooterConfig",
        "ReplicatedStorage/Shared/Scooter/ScooterConfig",
        "ReplicatedStorage/Shared/Scooter/ScooterPhysics",
        "ReplicatedStorage/Shared/Scooter/ScooterAnimationMath",
        "ReplicatedStorage/Shared/Shop/ShopConfig",
        "ReplicatedStorage/Shared/Activity/ActivityConfig",
        "ReplicatedStorage/Shared/Phone/PhoneConfig",
        "ServerScriptService/Scooter/ScooterInput",
        "ServerScriptService/Scooter/ScooterRig",
        "ServerScriptService/Scooter/ScooterServer",
        "ServerScriptService/Scooter/ScooterRigGeometry",
        "ServerScriptService/Scooter/ScooterCollision",
        "ServerScriptService/Scooter/ScooterSuspension",
        "ServerScriptService/Scooter/DevScooterSuspension",
        "ServerScriptService/Scooter/DevScooterFrontMount",
        "ServerScriptService/Scooter/DevScooterRepair",
        "ServerScriptService/Scooter/ScooterBrakeLight",
        "ServerScriptService/Scooter/DevScooterAssembler",
        "ServerScriptService/Scooter/ScooterWorkflow",
        "StarterPlayer/StarterPlayerScripts/ScooterRiderPose",
        "StarterPlayer/StarterPlayerScripts/ScooterAnimator",
        "ServerScriptService/Activity/PlayerDataService",
        "ServerScriptService/Scooter/GarageService",
    ]
    source = "local SOURCES = {}\n"
    for path in paths:
        module = root / "src" / f"{path}.luau"
        if module.exists():
            source += f"SOURCES[ {literal(path)} ] = {literal(module.read_text())}\n"
    source += (root / "tests" / "support" / "roblox_mock.luau").read_text()
    source += "\n" + (root / "tests" / "scooter.spec.luau").read_text()
    source += "\n" + (root / "tests" / "support" / "scooter_animation_mock.luau").read_text()
    source += "\n" + (root / "tests" / "scooter_animation.spec.luau").read_text()
    source += "\n" + (root / "tests" / "scooter_leg_states.spec.luau").read_text()
    for spec in ["scooter_visuals.spec.luau", "scooter_repair.spec.luau", "scooter_suspension.spec.luau", "scooter_front_mount.spec.luau", "scooter_handling.spec.luau", "scooter_stability.spec.luau"]:
        source += "\ndo\n" + (root / "tests" / spec).read_text() + "\nend\n"
    with tempfile.TemporaryDirectory(prefix="scooter-tests-") as directory:
        bundle = Path(directory) / "run.luau"
        bundle.write_text(source)
        result = subprocess.run([args.luau, str(bundle)], cwd=root, check=False)
        raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
