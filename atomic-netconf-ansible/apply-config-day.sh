#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path


REPO_DIR = Path(__file__).resolve().parent
TARGETS_DIR = REPO_DIR / "configs" / "pod-targets"
LINK_DIR = REPO_DIR / "configs" / "desired"
LINK_NAME = "c9300x-lab.cfg"
DAYS = (0, 1, 2)
POD_DISCOVERY_CMD = "cat ~/PODID"
ANSIBLE_CMD = [
    "ansible-playbook",
    "-i",
    "inventory/hosts.yml",
    "playbooks/06_atomic_push_cli.yml",
    "-e",
    "dry_run=false",
]


def current_target() -> str:
    link_path = LINK_DIR / LINK_NAME
    if link_path.is_symlink():
        return link_path.readlink().as_posix()
    if link_path.exists():
        return "(exists, but is not a symlink)"
    return "(missing)"


def list_targets() -> None:
    print(f"Current {LINK_NAME} target: {current_target()}")
    print()
    print(f"Pod day files currently staged in {LINK_DIR}:")

    desired_files = sorted(
        p.name for p in LINK_DIR.glob("*.cfg") if p.is_file() and p.name != LINK_NAME
    )
    if not desired_files:
        print("  (none yet — run the script to populate)")
    else:
        for idx, filename in enumerate(desired_files, start=1):
            print(f"  {idx:2d}) {filename}")

    print()
    print(f"All available pod source files in {TARGETS_DIR}:")

    cfg_files = sorted(p.name for p in TARGETS_DIR.glob("*.cfg") if p.is_file())

    if not cfg_files:
        print("  (none found)")
        return

    for idx, filename in enumerate(cfg_files, start=1):
        print(f"  {idx:2d}) {filename}")


def parse_pod_id(raw: str) -> str:
    value = raw.strip().upper()
    if not value:
        raise ValueError("PODID must not be empty.")
    if "/" in value or "\\" in value:
        raise ValueError("PODID contains invalid path separator characters.")

    # Normalize to unpadded form: POD-03 -> POD-3, POD3 -> POD-3, 3 -> POD-3
    import re
    match = re.match(r"^POD-?(\d{1,2})$", value) or re.match(r"^(\d{1,2})$", value)
    if match:
        value = f"POD-{int(match.group(1))}"
    return value


def discover_pod_id() -> str:
    try:
        result = subprocess.run(
            ["bash", "-lc", POD_DISCOVERY_CMD],
            check=True,
            capture_output=True,
            text=True,
            cwd=REPO_DIR,
        )
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(
            f"POD discovery command failed: {POD_DISCOVERY_CMD} (exit code {exc.returncode})."
        ) from exc

    pod_source = result.stdout.strip()
    if not pod_source:
        raise ValueError(
            f"POD discovery command returned no output: {POD_DISCOVERY_CMD}."
        )

    pod = parse_pod_id(pod_source)
    print(f"Detected PODID: {pod}", file=sys.stderr, flush=True)
    return pod


def sync_pod_files(pod: str, force: bool = False) -> list[tuple[str, str]]:
    """Copy POD-N-day{0,1,2}.cfg from pod-targets/ into desired/.

    Copies a file when it is missing in desired/ OR when the pod-targets/
    source is newer than the copy in desired/. Pass force=True to always
    refresh all three day files. Returns a list of (filename, status) tuples
    in DAYS order.
    """
    LINK_DIR.mkdir(parents=True, exist_ok=True)
    results: list[tuple[str, str]] = []
    for day in DAYS:
        filename = f"{pod}-day{day}.cfg"
        src = TARGETS_DIR / filename
        dst = LINK_DIR / filename
        if not src.is_file():
            results.append((filename, "source missing"))
            continue

        if force:
            shutil.copy2(src, dst)
            results.append((filename, "refreshed"))
        elif not dst.exists():
            shutil.copy2(src, dst)
            results.append((filename, "copied (new)"))
        elif src.stat().st_mtime > dst.stat().st_mtime:
            shutil.copy2(src, dst)
            results.append((filename, "copied (updated)"))
        else:
            results.append((filename, "up-to-date"))
    return results


def build_menu(filenames: list[str]) -> list[tuple[int, str]]:
    """Assign selection keys to filenames.

    Files whose name contains ``dayN`` use ``N`` as their key (so day0->0,
    day1->1, etc.) and are listed first in ascending day order. Any other
    files are appended after with incremental keys starting at
    ``max(day#)+1`` (or 0 if no day files).
    """
    day_files: list[tuple[int, str]] = []
    other_files: list[str] = []
    for fn in filenames:
        match = re.search(r"day(\d+)", fn, re.IGNORECASE)
        if match:
            day_files.append((int(match.group(1)), fn))
        else:
            other_files.append(fn)

    day_files.sort(key=lambda kv: kv[0])
    entries: list[tuple[int, str]] = list(day_files)
    next_key = (max(k for k, _ in day_files) + 1) if day_files else 0
    for fn in sorted(other_files):
        entries.append((next_key, fn))
        next_key += 1
    return entries


def set_target(target_file: str) -> None:
    if target_file == LINK_NAME:
        raise ValueError(f"Target cannot be {LINK_NAME} itself.")

    target_path = LINK_DIR / target_file
    if not target_path.is_file():
        raise FileNotFoundError(f"File not found: {target_path}")

    LINK_DIR.mkdir(parents=True, exist_ok=True)
    link_path = LINK_DIR / LINK_NAME
    if link_path.exists() or link_path.is_symlink():
        if link_path.is_dir() and not link_path.is_symlink():
            raise IsADirectoryError(f"Cannot replace directory: {link_path}")
        link_path.unlink()

    # Relative symlink within desired/ so it survives moves of the repo
    link_path.symlink_to(Path(target_file))
    print(f"Updated: {LINK_NAME} -> {current_target()}")


def run_ansible_push() -> None:
    print("Running Ansible full-replace playbook...")
    print("Command:", " ".join(ANSIBLE_CMD))
    try:
        subprocess.run(ANSIBLE_CMD, cwd=REPO_DIR, check=True)
    except FileNotFoundError as exc:
        raise RuntimeError(
            "ansible-playbook was not found in PATH. Install Ansible or activate the correct environment."
        ) from exc
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(f"Ansible playbook failed with exit code {exc.returncode}.") from exc


def interactive_select(skip_ansible_run: bool, force_refresh: bool = False) -> None:
    pod = discover_pod_id()

    # print(f"Syncing {pod} day files into configs/desired/ ...", file=sys.stderr, flush=True)
    sync_results = sync_pod_files(pod, force=force_refresh)

    staged = [(fn, status) for fn, status in sync_results if (LINK_DIR / fn).is_file()]
    if not staged:
        raise FileNotFoundError(
            f"No day files available for {pod} in {LINK_DIR} (sources missing in {TARGETS_DIR})."
        )

    menu = build_menu([fn for fn, _ in staged])

    print("", file=sys.stderr, flush=True)
    print(
        "Which day would you like to rotate to? (Type the number and press ENTER)",
        file=sys.stderr,
        flush=True,
    )
    for key, fn in menu:
        print(f"  {key}) {fn}", file=sys.stderr, flush=True)

    valid_keys = {key: fn for key, fn in menu}
    valid_display = ", ".join(str(k) for k in valid_keys)
    sys.stderr.write(f"Please enter {valid_display}: ")
    sys.stderr.flush()
    raw = input().strip()
    try:
        choice = int(raw)
    except ValueError as exc:
        raise ValueError(f"Invalid selection {raw!r}. Valid options: {valid_display}.") from exc
    if choice not in valid_keys:
        raise ValueError(f"Invalid selection {choice}. Valid options: {valid_display}.")

    target_file = valid_keys[choice]
    set_target(target_file)

    print("", file=sys.stderr, flush=True)
    print(f"Starting config replace using {target_file} ...", file=sys.stderr, flush=True)
    print("", file=sys.stderr, flush=True)

    if not skip_ansible_run:
        run_ansible_push()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Update c9300x-lab.cfg symlink based on POD ID and day selection.",
    )
    parser.add_argument("--list", action="store_true", help="List available .cfg targets")
    parser.add_argument(
        "--no-run",
        action="store_true",
        help="Update symlink only and skip running Ansible playbook",
    )
    parser.add_argument(
        "--refresh",
        action="store_true",
        help="Force re-copy of POD-N-day{0,1,2}.cfg from pod-targets/ into desired/ even if up-to-date",
    )
    return parser


def main() -> int:
    if not TARGETS_DIR.is_dir():
        print(f"Error: expected directory does not exist: {TARGETS_DIR}", file=sys.stderr)
        return 1

    parser = build_parser()
    args = parser.parse_args()

    try:
        if args.list:
            list_targets()
            return 0

        interactive_select(skip_ansible_run=args.no_run, force_refresh=args.refresh)
        return 0
    except (ValueError, FileNotFoundError, IsADirectoryError, RuntimeError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())