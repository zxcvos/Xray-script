"""Run with: python3 -m unittest discover -s tests -v"""

import fcntl
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "tool" / "geodata.sh"


@unittest.skipUnless(shutil.which("flock") and shutil.which("sha256sum"),
                     "requires Linux flock and sha256sum")
class GeodataTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.assets = self.root / "assets"
        self.assets.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.remote = self.root / "remote"
        self.remote.mkdir()
        self.config = self.root / "config.json"
        self.config.write_text('{"routing": "unchanged"}')
        self.old = {"geoip.dat": b"old PRIVATE CN", "geosite.dat": b"old ADS"}
        self.new = {"geoip.dat": b"new PRIVATE CN", "geosite.dat": b"new ADS"}
        for name, data in self.old.items():
            (self.assets / name).write_bytes(data)
            (self.assets / name).chmod(0o644)
        self.publish(self.new)
        self.install_command("curl", r'''
set -eu
fail=0
while (($#)); do
    case "$1" in
        --fail) fail=1; shift ;;
        --output) output=$2; shift 2 ;;
        --retry|--connect-timeout|--max-time) shift 2 ;;
        --*) shift ;;
        *) url=$1; shift ;;
    esac
done
name=${url##*/}
if [[ "$name" == latest ]]; then
    printf '{"tag_name":"test-release"}' > "$output"
    exit 0
fi
[[ "$url" == */releases/download/test-release/* ]] || exit 1
if [[ "$name" == "${HTTP_ERROR_FILE:-}" ]]; then
    printf '<html>504 Gateway Time-out</html>' > "$output"
    ((fail)) && exit 22
    exit 0
fi
command cp "$TEST_ROOT/remote/$name" "$output"
''')
        self.install_command("xray", r'''
set -eu
[[ "$1 $2 $3" == 'run -test -config' ]]
[[ "$4" == "$XRAY_CONFIG" ]]
printf '%s\n' "$XRAY_LOCATION_ASSET" >> "$TEST_ROOT/validation.log"
grep -q PRIVATE "$XRAY_LOCATION_ASSET/geoip.dat" || exit 23
grep -q ADS "$XRAY_LOCATION_ASSET/geosite.dat" || exit 23
if [[ ${CHANGE_CONFIG:-0} == 1 ]]; then echo changed >> "$XRAY_CONFIG"; fi
''')
        self.install_command("systemctl", r'''
set -eu
printf '%s\n' "$*" >> "$TEST_ROOT/systemctl.log"
if [[ "$1" == restart ]]; then
    if [[ ${FAIL_RESTART:-0} == 1 && ! -e "$TEST_ROOT/restart-failed" ]]; then
        touch "$TEST_ROOT/restart-failed"
        exit 1
    fi
    if [[ ${FAIL_STARTUP:-0} == 1 && ! -e "$TEST_ROOT/startup-failed" ]]; then
        touch "$TEST_ROOT/startup-failed" "$TEST_ROOT/inactive"
    else
        command rm -f "$TEST_ROOT/inactive"
    fi
    exit 0
fi
[[ "$*" == '-q is-active xray' ]]
[[ ! -e "$TEST_ROOT/inactive" ]]
''')
        self.install_command("logger", "exit 0")
        self.install_command("sleep", "exit 0")
        self.env = dict(os.environ, TEST_ROOT=str(self.root),
                        XRAY_DIR=str(self.assets), XRAY_CONFIG=str(self.config),
                        XRAY_BIN=str(self.bin / "xray"),
                        PATH=str(self.bin) + os.pathsep + os.environ["PATH"])

    def install_command(self, name, body):
        path = self.bin / name
        path.write_text("#!/usr/bin/env bash\n" + body + "\n")
        path.chmod(0o755)

    def publish(self, data):
        for name, content in data.items():
            (self.remote / name).write_bytes(content)
            digest = hashlib.sha256(content).hexdigest()
            (self.remote / (name + ".sha256sum")).write_text(f"{digest}  {name}\n")

    def run_update(self, **env):
        return subprocess.run(["bash", str(SCRIPT)], env=dict(self.env, **env),
                              text=True, capture_output=True)

    def assert_assets(self, expected):
        for name, content in expected.items():
            self.assertEqual((self.assets / name).read_bytes(), content)
            self.assertEqual((self.assets / name).stat().st_mode & 0o777, 0o644)
        self.assertEqual(list(self.assets.glob(".geodata.*")), [self.assets / ".geodata.lock"])

    def restarts(self):
        path = self.root / "systemctl.log"
        return path.read_text().splitlines().count("restart xray") if path.exists() else 0

    def test_http_504_preserves_both_files_without_restart(self):
        for name in ("geoip.dat", "geosite.dat", "geosite.dat.sha256sum"):
            with self.subTest(name=name):
                self.assertNotEqual(self.run_update(HTTP_ERROR_FILE=name).returncode, 0)
                self.assert_assets(self.old)
                self.assertEqual(self.restarts(), 0)

    def test_bad_checksum_preserves_both_files_without_restart(self):
        (self.remote / "geoip.dat").write_bytes(b"damaged PRIVATE CN")
        self.assertNotEqual(self.run_update().returncode, 0)
        self.assert_assets(self.old)
        self.assertEqual(self.restarts(), 0)

    def test_checksummed_but_incompatible_data_is_rejected(self):
        self.publish(dict(self.new, **{"geoip.dat": b"missing private entry"}))
        self.assertNotEqual(self.run_update().returncode, 0)
        self.assert_assets(self.old)
        self.assertEqual(self.restarts(), 0)

    def test_config_change_during_validation_aborts_update(self):
        self.assertNotEqual(self.run_update(CHANGE_CONFIG="1").returncode, 0)
        self.assert_assets(self.old)
        self.assertEqual(self.restarts(), 0)

    def test_success_replaces_both_files_and_restarts_once(self):
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_assets(self.new)
        self.assertEqual(self.restarts(), 1)
        self.assertEqual(self.config.read_text(), '{"routing": "unchanged"}')
        location = (self.root / "validation.log").read_text().strip()
        self.assertNotEqual(location, str(self.assets))

    def test_restart_failure_restores_previous_files(self):
        self.assertNotEqual(self.run_update(FAIL_RESTART="1").returncode, 0)
        self.assert_assets(self.old)
        self.assertEqual(self.restarts(), 2)

    def test_second_file_install_failure_restores_both_files(self):
        self.install_command("mv", r'''
set -eu
[[ "$1" == -f ]] && shift
if [[ ${1##*/} == geosite.dat && ! -e "$TEST_ROOT/move-failed" ]]; then
    touch "$TEST_ROOT/move-failed"
    exit 1
fi
/bin/mv -f "$@"
''')
        self.assertNotEqual(self.run_update().returncode, 0)
        self.assert_assets(self.old)
        self.assertEqual(self.restarts(), 0)

    def test_concurrent_update_leaves_files_untouched(self):
        with (self.assets / ".geodata.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_update()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assert_assets(self.old)
            self.assertEqual(self.restarts(), 0)

    def test_failed_startup_restores_previous_files(self):
        self.assertNotEqual(self.run_update(FAIL_STARTUP="1").returncode, 0)
        self.assert_assets(self.old)
        self.assertEqual(self.restarts(), 2)
        self.assertFalse((self.root / "inactive").exists())

    def test_inactive_service_is_not_started_and_update_returns_success(self):
        (self.root / "inactive").touch()
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_assets(self.new)
        self.assertEqual(self.restarts(), 0)

    def test_unchanged_files_do_not_restart_service(self):
        self.publish(self.old)
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_assets(self.old)
        self.assertEqual(self.restarts(), 0)


if __name__ == "__main__":
    unittest.main()
