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
    parser.add_argument("--arcade-only", action="store_true", help="Run smooth arcade height regressions")
    parser.add_argument("--runtime-only", action="store_true", help="Run scooter tuning, profile and garage contracts")
    args = parser.parse_args()
    if not args.luau:
        parser.error("pass --luau /path/to/luau or install the official Luau CLI")
    root = Path(__file__).resolve().parent.parent
    paths = [
        "ReplicatedStorage/Shared/ScooterConfig",
        "ReplicatedStorage/Shared/Scooter/ScooterConfig",
        "ReplicatedStorage/Shared/Scooter/ScooterPhysics",
        "ReplicatedStorage/Shared/Scooter/ScooterDashboardConfig",
        "ReplicatedStorage/Shared/Scooter/ScooterDashboard",
        "ReplicatedStorage/Shared/UI/Scope",
        "ReplicatedStorage/Shared/Shop/ShopConfig",
        "ReplicatedStorage/Shared/Activity/ActivityConfig",
        "ReplicatedStorage/Shared/Phone/PhoneConfig",
        "ServerScriptService/Scooter/ScooterInventory",
        "ServerScriptService/Scooter/ScooterUpgradeService",
        "ServerScriptService/Scooter/ScooterUpgradeVisuals",
        "ServerScriptService/Scooter/ScooterEffects",
        "ServerScriptService/Scooter/ScooterInput",
        "ServerScriptService/Scooter/ScooterRig",
        "ServerScriptService/Scooter/ScooterG4Cables",
        "ServerScriptService/Scooter/ScooterServer",
        "ServerScriptService/Scooter/ScooterRigGeometry",
        "ServerScriptService/Scooter/ScooterCollision",
        "ServerScriptService/Scooter/ScooterSuspension",
        "ServerScriptService/Scooter/DevScooterSuspension",
        "ServerScriptService/Scooter/DevScooterFrontMount",
        "ServerScriptService/Scooter/DevScooterRepair",
        "ServerScriptService/Scooter/ScooterBrakeLight",
        "ServerScriptService/Scooter/ScooterHeadlight",
        "ServerScriptService/Scooter/ScooterTerrain",
        "ServerScriptService/Scooter/ScooterArcadeSteps",
        "ServerScriptService/Scooter/ScooterImpact",
        "ServerScriptService/Scooter/ScooterScrape",
        "ServerScriptService/Scooter/DevScooterAssembler",
        "ServerScriptService/Scooter/DevScooterDashboard",
        "ServerScriptService/Scooter/ScooterWorkflow",
        "ServerScriptService/Activity/PlayerDataService",
        "ServerScriptService/Activity/ProfilePersistence",
        "ReplicatedStorage/Shared/Activity/EconomyConfig",
        "ServerScriptService/Shop/PremiumService",
        "ReplicatedStorage/Shared/ScooterUpgradeCatalog",
        "ReplicatedStorage/Shared/ScooterUpgradeStats",
        "ReplicatedStorage/Shared/ScooterCustomPaint",
        "ReplicatedStorage/Shared/ScooterCustomConfig",
        "ServerScriptService/Scooter/GarageService",
    ]
    source = "local SOURCES = {}\n"
    for path in paths:
        module = root / "src" / f"{path}.luau"
        if module.exists():
            source += f"SOURCES[ {literal(path)} ] = {literal(module.read_text())}\n"
    source += (root / "tests" / "support" / "roblox_mock.luau").read_text()
    if args.arcade_only:
        source += "\n" + (root / "tests" / "scooter_arcade_steps.spec.luau").read_text()
    else:
        # Legacy doubles exercise the retained physical controller. Native Play
        # covers collision masks, articulation and the new production controller.
        source += '\nloadModule("ReplicatedStorage/Shared/ScooterConfig").ArcadeSteps.Enabled = false\n'
        source += "\n" + (root / "tests" / "scooter.spec.luau").read_text()
    source += "\n" + (root / "tests" / "support" / "scooter_animation_mock.luau").read_text()
    for spec in ["scooter_visuals.spec.luau", "scooter_repair.spec.luau", "scooter_suspension.spec.luau", "scooter_front_mount.spec.luau", "scooter_handling.spec.luau", "scooter_stability.spec.luau", "scooter_dashboard.spec.luau", "scooter_terrain.spec.luau", "scooter_scrape.spec.luau"]:
        if args.runtime_only:
            break
        if args.arcade_only:
            break
        source += "\ndo\n" + (root / "tests" / spec).read_text() + "\nend\n"
    with tempfile.TemporaryDirectory(prefix="scooter-tests-") as directory:
        bundle = Path(directory) / "run.luau"
        bundle.write_text(source)
        result = subprocess.run([args.luau, str(bundle)], cwd=root, check=False)
        raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
