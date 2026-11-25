"""The heartbeat loop's PID file, and a liveness check that never kills.

``os.kill(pid, 0)`` is the POSIX idiom for "does this process exist?", but on
Windows ``os.kill`` with any signal other than CTRL_C_EVENT/CTRL_BREAK_EVENT
calls TerminateProcess — the "check" would kill the loop it was checking. So
Windows asks the kernel instead (OpenProcess + GetExitCodeProcess).

A PID file can outlive its loop (a crash, a reboot) and name whatever process
later got that number, so the running loop also holds an OS lock on
data/sellbird.lock. The OS drops the lock when the loop dies, however it dies:
a live PID with nobody holding the lock is not Sellbird, and is never signalled.
"""

import builtins;

import operator;

import from jaclang.comptime { target }

import logging;

import os;

import sys;

import time;

import from pathlib { Path }

glob logger: any;

glob PID_FILE: any;

glob LOCK_FILE: any;

glob _PROCESS_QUERY_LIMITED_INFORMATION: any;

glob _STILL_ACTIVE: any;

glob _ERROR_ACCESS_DENIED: any;

with entry {
    logger = logging.getLogger("sellbird.pidfile");

    PID_FILE = PROJECT_ROOT / "data" / "sellbird.pid";
    LOCK_FILE = PROJECT_ROOT / "data" / "sellbird.lock";

    _PROCESS_QUERY_LIMITED_INFORMATION = 4096;
    _STILL_ACTIVE = 259;
    _ERROR_ACCESS_DENIED = 5;
}

def _pid_alive_windows(pid: builtins.int) -> builtins.bool;

"""True if a process with this PID is running. Never signals or kills it."""
def pid_alive(pid: builtins.int) -> builtins.bool;

def read_pid(path: Path | None = None) -> builtins.int | None;

"""Record this process as the running loop (best effort)."""
def write_pid_file(path: Path | None = None) -> None;

"""Remove the PID file — only if it still names this process, so a loop
    exiting late never erases a newer loop's record."""
def remove_pid_file(path: Path | None = None) -> None;

"""Take an exclusive lock on ``handle`` without waiting."""
def _try_lock(handle) -> builtins.bool;

def _unlock(handle) -> None;

"""Take the loop lock for this process's lifetime, or None if another
    loop already holds it. Keep the returned handle open while running."""
def hold_loop_lock(path: Path | None = None) -> any;

def release_loop_lock(handle) -> None;

"""True while some Sellbird loop holds the lock. Probing never keeps it."""
def loop_lock_held(path: Path | None = None) -> builtins.bool;
