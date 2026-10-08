#!/usr/bin/env python3
"""Exercise production police evidence, state transitions, ownership and road routing."""
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
    paths = [f'ServerScriptService/Police/{n}' for n in (
        'PoliceConfig', 'PoliceStateMachine', 'PolicePursuitController', 'TrafficViolationDetector')]
    paths += [f'ServerScriptService/Traffic/{n}' for n in (
        'TrafficConfiguration', 'TrafficTypes', 'Trajectory', 'RoadNetwork', 'RoadNetworkData')]
    source = 'local SOURCES = {}\n'
    for path in paths:
        source += f'SOURCES[ {literal(path)} ] = {literal((root / "src" / f"{path}.luau").read_text())}\n'
    source += 'SOURCES["ServerScriptService/Scooter/ScooterServer"] = "return {}"\n'
    source += 'SOURCES["ServerScriptService/Combat/CombatService"] = "return {}"\n'
    source += (root / 'tests/support/roblox_mock.luau').read_text()
    source += '\nservices.Workspace={}\n'
    source += (root / 'tests/police.spec.luau').read_text()
    with tempfile.TemporaryDirectory(prefix='police-tests-') as directory:
        bundle = Path(directory) / 'run.luau'
        bundle.write_text(source)
        raise SystemExit(subprocess.run([args.luau, str(bundle)], cwd=root).returncode)


if __name__ == '__main__':
    main()
