#!/usr/bin/env python3
"""Run a real harness CLI in a pty with a fixed 50x160 grid (tmux is not
installed on this host, so this stands in for the lab tmux pane only).

Usage: pty-primary.py <ctl-dir> <cwd> <cmd...>
Keys: drop a file into <ctl-dir>/in/ ; its bytes are written to the pty.
Output: <ctl-dir>/raw.log (all pty bytes), <ctl-dir>/pid (child pid).
"""
import fcntl, os, pty, select, struct, sys, termios, time

ctl, cwd, cmd = sys.argv[1], sys.argv[2], sys.argv[3:]
os.makedirs(os.path.join(ctl, "in"), exist_ok=True)
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 160, 0, 0))
pid = os.fork()
if pid == 0:
    os.setsid()
    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
    for fd in (0, 1, 2):
        os.dup2(slave, fd)
    os.close(master)
    os.close(slave)
    os.chdir(cwd)
    os.execvp(cmd[0], cmd)
os.close(slave)
open(os.path.join(ctl, "pid"), "w").write(str(pid))
raw = open(os.path.join(ctl, "raw.log"), "ab", buffering=0)
while True:
    r, _, _ = select.select([master], [], [], 0.2)
    if r:
        try:
            data = os.read(master, 65536)
        except OSError:
            break
        if not data:
            break
        raw.write(b"[%d]" % int(time.time() * 1000) if False else b"")
        raw.write(data)
    for name in sorted(os.listdir(os.path.join(ctl, "in"))):
        p = os.path.join(ctl, "in", name)
        os.write(master, open(p, "rb").read())
        os.unlink(p)
    done, _ = os.waitpid(pid, os.WNOHANG)
    if done:
        break
