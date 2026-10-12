#!/usr/bin/env python3
"""Run police/traffic integration contracts; physics and visuals require Studio."""
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
    paths = [f'ServerScriptService/Police/{name}' for name in (
        'PoliceConfig', 'PoliceStateMachine', 'PolicePursuitController',
        'TrafficViolationDetector', 'PoliceService', 'PoliceDebugService')]
    paths += [f'ServerScriptService/Traffic/{name}' for name in (
        'TrafficConfiguration', 'TrafficTypes', 'Trajectory', 'RoadNetwork',
        'VehicleLifecycle', 'VehicleController', 'IntersectionManager')]
    source = 'local SOURCES = {}\n'
    for path in paths:
        source += f'SOURCES[ {literal(path)} ] = {literal((root / "src" / f"{path}.luau").read_text())}\n'
    stubs = {
        'ReplicatedStorage/Shared/Scooter/ScooterConfig': 'return {StudsPerKmH=1.6}',
        'ServerScriptService/Scooter/ScooterServer': '''local api={states={}}
function api.GetRidingState(player) return api.states[player] end
return api''',
        'ServerScriptService/Combat/CombatService': 'return {IsInSafeZone=function() return false end}',
        'ServerScriptService/Traffic/VehicleAdapter': 'return {}',
        'ServerScriptService/Traffic/TrafficSensors': '''return {Frame=function(p,d,size)
return {Position=p+Vector3.yAxis*(size.Y/2+0.3),LookVector=d} end}''',
        'ServerScriptService/Police/PoliceVehicleAdapter': 'return {Signals=function() end}',
        'ServerScriptService/Police/PoliceSpawner': 'return {Target=function() return 2 end}',
        'ServerScriptService/Police/PoliceOfficerController': 'return {}',
        'ServerScriptService/Police/ArrestService': 'return {}',
    }
    for path, stub in stubs.items():
        source += f'SOURCES[ {literal(path)} ] = {literal(stub)}\n'
    source += (root / 'tests/support/roblox_mock.luau').read_text()
    source += '\n' + (root / 'tests/police_traffic.spec.luau').read_text()
    with tempfile.TemporaryDirectory(prefix='police-traffic-tests-') as directory:
        bundle = Path(directory) / 'run.luau'
        bundle.write_text(source)
        raise SystemExit(subprocess.run([args.luau, str(bundle)], cwd=root).returncode)


if __name__ == '__main__':
    main()
