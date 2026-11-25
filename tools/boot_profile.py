#!/usr/bin/env python3
"""
Thu thập số liệu của lần boot hiện tại trên board qua SSH vào một thư mục trên host.

Thư mục boot-data/<ngày-giờ>[-label]/ gồm:
  systemd-analyze.txt    kernel / userspace / tổng
  critical-chain.txt     critical-chain của default target và critical-chain-<unit>.txt cho mỗi --unit
  blame.txt              systemd-analyze blame
  boot.svg               systemd-analyze plot
  journal.txt            journalctl -b -o short-monotonic
  dmesg.txt              dmesg
  info.txt               version, slot, cmdline, unit lỗi

Ví dụ:
  python3 boot_profile.py
  python3 boot_profile.py --label no-timesyncd --unit time-set.target --unit sensornode-ui.service
"""

import argparse
import datetime
import os
import re
import subprocess
import sys
import time

DEFAULT_HOST = os.environ.get("SENSORNODE_HOST", "192.168.137.100")

INFO_SCRIPT = """
echo "version: $(cat /etc/sw-versions 2>/dev/null)"
echo "boot_id: $(cat /proc/sys/kernel/random/boot_id)"
echo "uptime:  $(cut -d' ' -f1 /proc/uptime)s"
echo "cmdline: $(cat /proc/cmdline)"
echo "uname:   $(uname -a)"
fw_printenv active_slot ustate boot_count 2>/dev/null
echo
systemctl list-units --failed --no-pager --no-legend
"""


class ProfileError(Exception):
    pass


def log(msg):
    print("[boot-profile] " + msg, flush=True)


class Ssh:
    def __init__(self, args):
        self.target = "%s@%s" % (args.user, args.host)
        opts = ["-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=15"]
        if args.identity:
            opts += ["-i", args.identity]
        if args.no_host_check:
            opts += ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=" + os.devnull, "-o", "LogLevel=ERROR"]
        else:
            opts += ["-o", "StrictHostKeyChecking=accept-new"]
        self.ssh = ["ssh", "-p", str(args.port)] + opts

    def run(self, command, quiet=False, timeout=120):
        try:
            result = subprocess.run(self.ssh + [self.target, command], stdin=subprocess.DEVNULL,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
        except subprocess.TimeoutExpired:
            return 124, b""
        if result.returncode != 0 and not quiet:
            sys.stderr.write(result.stderr.decode("utf-8", "replace"))
        return result.returncode, result.stdout


def wait_boot_finished(ssh, timeout):
    """systemd-analyze báo lỗi tới khi boot xong, nên chờ tới khi nó trả lời được."""
    deadline = time.monotonic() + timeout
    while True:
        rc, out = ssh.run("systemd-analyze", quiet=True, timeout=30)
        if rc == 0:
            return out
        if time.monotonic() > deadline:
            raise ProfileError("boot did not finish within %ds (still running or ssh unreachable)" % timeout)
        time.sleep(3)


def main():
    parser = argparse.ArgumentParser(description="Collect boot timing data of the current boot over SSH.")
    parser.add_argument("-H", "--host", default=DEFAULT_HOST, help="board address (default %(default)s, env SENSORNODE_HOST)")
    parser.add_argument("-u", "--user", default="root", help="ssh user (default %(default)s)")
    parser.add_argument("-p", "--port", type=int, default=22, help="ssh port (default %(default)s)")
    parser.add_argument("-i", "--identity", help="ssh private key")
    parser.add_argument("-o", "--out", default="boot-data", help="parent output directory (default %(default)s)")
    parser.add_argument("-l", "--label", help="suffix for the folder name, e.g. what you changed")
    parser.add_argument("--unit", action="append", default=[], help="also save critical-chain of this unit (repeatable)")
    parser.add_argument("--timeout", type=int, default=300, help="seconds to wait for the boot to finish (default %(default)s)")
    parser.add_argument("--no-host-check", action="store_true", help="ignore known_hosts (board was reflashed)")
    args = parser.parse_args()

    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    name = stamp + ("-" + re.sub(r"[^\w.-]", "_", args.label) if args.label else "")
    out_dir = os.path.join(args.out, name)

    commands = {
        "critical-chain.txt": "systemd-analyze critical-chain --no-pager",
        "blame.txt": "systemd-analyze blame --no-pager",
        "boot.svg": "systemd-analyze plot",
        "journal.txt": "journalctl -b -o short-monotonic --no-pager",
        "dmesg.txt": "dmesg",
        "info.txt": INFO_SCRIPT,
    }
    for unit in args.unit:
        commands["critical-chain-%s.txt" % re.sub(r"[^\w.@-]", "_", unit)] = \
            "systemd-analyze critical-chain --no-pager '%s'" % unit

    ssh = Ssh(args)
    try:
        log("board %s, waiting for boot to finish" % ssh.target)
        outputs = {"systemd-analyze.txt": wait_boot_finished(ssh, args.timeout)}
        for name, command in commands.items():
            rc, out = ssh.run(command)
            if rc != 0:
                log("warning: %s failed (exit %d)" % (name, rc))
            outputs[name] = out
    except ProfileError as e:
        log("error: %s" % e)
        return 1
    except KeyboardInterrupt:
        log("interrupted")
        return 130

    os.makedirs(out_dir, exist_ok=True)
    for name, data in outputs.items():
        with open(os.path.join(out_dir, name), "wb") as f:
            f.write(data)
    sys.stdout.write(outputs["systemd-analyze.txt"].decode("utf-8", "replace"))
    log("saved to %s" % os.path.abspath(out_dir))
    return 0


if __name__ == "__main__":
    sys.exit(main())
