#!/usr/bin/env python3
"""
Nạp file .swu lên board qua SSH, không cần web UI hay HMI.

Tool chạy trên Host:
  1. Đọc trạng thái board xem SWUpdate có đang chạy không và dung lượng /data còn trống không.
  2. scp file vào /data/upload.
  3. ssh chạy 09-swupdate-args, script này chọn slot inactive rồi gọi swupdate.
  4. Reboot, chờ board chạy lại và in version, slot mới.

Ví dụ:
  python3 swu_push.py release/sensornode-image-swu-bbb-sensornode-0.1.5.swu
  python3 swu_push.py fw.swu --host bbb-sensornode.local --no-reboot
"""

import argparse
import os
import re
import shlex
import subprocess
import sys
import time

DEFAULT_HOST = os.environ.get("SENSORNODE_HOST", "192.168.137.100")
UPLOAD_DIR = "/data/upload"
UPLOAD_NAME = "swu-push.swu"
SWUPDATE_TOOL = "/usr/bin/09-swupdate-args"

VERSION_RE = re.compile(rb'\bversion\s*=\s*"([^"]*)"')

STATE_SCRIPT = """
echo "version=$(cat /etc/sw-versions 2>/dev/null)"
echo "slot=$(sed -n 's/.*sensornode\\.slot=\\([AB]\\).*/\\1/p' /proc/cmdline)"
fw_printenv active_slot ustate 2>/dev/null
echo "boot_id=$(cat /proc/sys/kernel/random/boot_id)"
echo "busy=$(pidof swupdate >/dev/null && echo 1 || echo 0)"
echo "free_kb=$(df -Pk {dir} 2>/dev/null | awk 'NR==2{{print $4}}')"
"""


class PushError(Exception):
    pass


def log(msg):
    print("[swu-push] " + msg, flush=True)


def swu_version(path):
    """Version trong sw-description"""
    with open(path, "rb") as f:
        head = f.read(64 * 1024)
    if len(head) < 110 or head[:6] not in (b"070701", b"070702"):
        raise PushError("%s is not a .swu (cpio newc) file" % path)
    size = int(head[54:62], 16)
    namesize = int(head[94:102], 16)
    if head[110:110 + namesize - 1] != b"sw-description":
        raise PushError("first entry of %s is not sw-description" % path)
    start = (110 + namesize + 3) // 4 * 4
    m = VERSION_RE.search(head[start:start + size])
    return m.group(1).decode("utf-8", "replace") if m else None


class Ssh:
    def __init__(self, args):
        self.target = "%s@%s" % (args.user, args.host)
        opts = ["-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=15"]
        if args.identity:
            opts += ["-i", args.identity]
        if args.no_host_check:
            # Board flash lại là đổi host key, bỏ qua known_hosts để không bị chặn.
            opts += ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=" + os.devnull, "-o", "LogLevel=ERROR"]
        else:
            opts += ["-o", "StrictHostKeyChecking=accept-new"]
        self.ssh = ["ssh", "-p", str(args.port)] + opts
        self.scp = ["scp", "-P", str(args.port)] + opts

    def output(self, command, quiet=False):
        """Chạy lệnh, trả về (exit code, stdout)."""
        result = subprocess.run(self.ssh + [self.target, command], stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL if quiet else None,
                                universal_newlines=True)
        return result.returncode, result.stdout

    def stream(self, command):
        """Chạy lệnh, output hiện thẳng ra terminal. Có tty thì Ctrl-C dừng cả lệnh trên board."""
        tty = ["-t"] if sys.stdin.isatty() and sys.stdout.isatty() else ["-T"]
        return subprocess.run(self.ssh + tty + [self.target, command]).returncode

    def copy(self, local, remote):
        if subprocess.run(self.scp + [local, "%s:%s" % (self.target, remote)]).returncode != 0:
            raise PushError("scp failed")


def board_state(ssh, upload_dir, quiet=False):
    rc, out = ssh.output(STATE_SCRIPT.format(dir=shlex.quote(upload_dir)), quiet=quiet)
    if rc != 0:
        return None
    return dict(line.split("=", 1) for line in out.splitlines() if "=" in line)


def describe(state):
    return "version %s, slot %s, active_slot %s, ustate %s" % (
        state.get("version") or "?", state.get("slot") or "?", state.get("active_slot") or "?",
        state.get("ustate") or "?")


def check_ready(state, size):
    if state.get("busy") == "1":
        raise PushError("swupdate is already running on the board (otad or web install?)")
    if state.get("ustate") == "1":
        if state.get("slot") == state.get("active_slot"):
            raise PushError("board is in a trial boot that is not committed yet, wait for ota-confirm-boot")
        raise PushError("an update is already installed and waits for reboot")
    free = state.get("free_kb", "")
    if not free.isdigit():
        raise PushError("upload dir not found on board")
    if int(free) * 1024 < size + 4 * 1024 * 1024:
        raise PushError("not enough space: %s KiB free, need %d KiB" % (free, size // 1024))


def wait_for_board(ssh, upload_dir, old_boot_id, expected, timeout):
    log("waiting for board to come back (up to %ds)" % timeout)
    deadline = time.monotonic() + timeout
    while True:
        time.sleep(5)
        state = board_state(ssh, upload_dir, quiet=True)
        if state and state.get("boot_id") not in (None, "", old_boot_id):
            break
        if time.monotonic() > deadline:
            raise PushError("board did not come back over ssh")

    log("board: " + describe(state))
    if expected and state.get("version") != expected:
        raise PushError("board runs %s, expected %s (rolled back?)" % (state.get("version"), expected))
    if state.get("ustate") == "1":
        log("trial boot, ota-confirm-boot commits it once the health check passes")


def main():
    parser = argparse.ArgumentParser(description="Upload a .swu to the board over SSH and install it with swupdate.")
    parser.add_argument("swu", help="firmware file (.swu)")
    parser.add_argument("-H", "--host", default=DEFAULT_HOST, help="board address (default %(default)s, env SENSORNODE_HOST)")
    parser.add_argument("-u", "--user", default="root", help="ssh user (default %(default)s)")
    parser.add_argument("-p", "--port", type=int, default=22, help="ssh port (default %(default)s)")
    parser.add_argument("-i", "--identity", help="ssh private key")
    parser.add_argument("--upload-dir", default=UPLOAD_DIR, help="where to put the file on the board (default %(default)s)")
    parser.add_argument("--no-reboot", action="store_true", help="install only, reboot later")
    parser.add_argument("--no-wait", action="store_true", help="do not wait for the board after reboot")
    parser.add_argument("--wait-timeout", type=int, default=300, help="seconds to wait after reboot (default %(default)s)")
    parser.add_argument("--no-host-check", action="store_true", help="ignore known_hosts (board was reflashed)")
    args = parser.parse_args()

    try:
        if not os.path.isfile(args.swu):
            raise PushError("file not found: %s" % args.swu)
        version = swu_version(args.swu)
        size = os.path.getsize(args.swu)
        log("firmware %s, version %s" % (os.path.basename(args.swu), version or "?"))

        ssh = Ssh(args)
        log("connecting to %s" % ssh.target)
        state = board_state(ssh, args.upload_dir)
        if state is None:
            raise PushError("cannot read board state over ssh")
        log("board: " + describe(state))
        check_ready(state, size)

        remote = args.upload_dir.rstrip("/") + "/" + UPLOAD_NAME
        partial = remote + ".part"
        log("uploading %.1f MiB to %s" % (size / 1048576.0, remote))
        ssh.copy(args.swu, partial)
        if ssh.output("mv -f %s %s" % (shlex.quote(partial), shlex.quote(remote)))[0] != 0:
            raise PushError("cannot rename uploaded file")

        log("running %s" % SWUPDATE_TOOL)
        quoted = shlex.quote(remote)
        rc = ssh.stream("%s %s; rc=$?; rm -f %s; exit $rc" % (SWUPDATE_TOOL, quoted, quoted))
        if rc != 0:
            raise PushError("swupdate failed (exit %d)" % rc)
        log("install done")

        if args.no_reboot:
            log("not rebooting; the new slot is used after the next reboot")
            return 0
        log("rebooting board")
        ssh.output("systemctl reboot", quiet=True)
        if not args.no_wait:
            wait_for_board(ssh, args.upload_dir, state.get("boot_id"), version, args.wait_timeout)
        return 0
    except PushError as e:
        log("error: %s" % e)
        return 1
    except KeyboardInterrupt:
        log("interrupted")
        return 130


if __name__ == "__main__":
    sys.exit(main())
