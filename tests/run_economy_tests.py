#!/usr/bin/env python3
"""Run real economy, persistence, shop and reward logic with controlled services."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile
from run_traffic_tests import literal


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--luau', default=shutil.which('luau'))
    args = parser.parse_args()
    if not args.luau:
        parser.error('pass --luau /path/to/luau')
    root = Path(__file__).resolve().parents[1]
    paths = [
        'ReplicatedStorage/Shared/ScooterConfig', 'ReplicatedStorage/Shared/ScooterCustomConfig',
        'ReplicatedStorage/Shared/ScooterUpgradeCatalog', 'ReplicatedStorage/Shared/Phone/PhoneConfig',
        'ReplicatedStorage/Shared/Activity/ActivityConfig', 'ReplicatedStorage/Shared/Activity/EconomyConfig',
        'ReplicatedStorage/Shared/Shop/ShopConfig',
        'ServerScriptService/Activity/ProfilePersistence', 'ServerScriptService/Activity/PlayerDataService',
        'ServerScriptService/Activity/RewardMath', 'ServerScriptService/Activity/ActivityService',
        'ServerScriptService/Shop/PremiumService', 'ServerScriptService/Shop/ShopService',
        'ServerScriptService/Territory/TerritoryRewards',
        'ServerScriptService/Scooter/ScooterCosmetics', 'ServerScriptService/Scooter/ScooterEffects',
        'ReplicatedStorage/Shared/ScooterCustomPaint', 'ReplicatedStorage/Shared/Scooter/ScooterConfig',
    ]
    source = 'local SOURCES = {}\n'
    for path in paths:
        source += f'SOURCES[ {literal(path)} ] = {literal((root / "src" / f"{path}.luau").read_text())}\n'
    source += (root / 'tests/support/roblox_mock.luau').read_text()
    source += '\n' + (root / 'tests/economy.spec.luau').read_text()
    with tempfile.TemporaryDirectory(prefix='economy-tests-') as directory:
        bundle = Path(directory) / 'run.luau'
        bundle.write_text(source)
        raise SystemExit(subprocess.run([args.luau, str(bundle)], cwd=root).returncode)


if __name__ == '__main__':
    main()
