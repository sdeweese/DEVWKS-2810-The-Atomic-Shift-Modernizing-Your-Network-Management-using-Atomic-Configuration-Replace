#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


REPO_DIR = Path(__file__).resolve().parent
TARGETS_DIR = REPO_DIR / "configs" / "pod-targets"
LINK_DIR = REPO_DIR / "configs" / "desired"
LINK_NAME = "c9300x-lab.cfg"
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
    print(f"Available .cfg files in {TARGETS_DIR}:")

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


def resolve_target_filename(pod: str, day: int) -> str:
    candidates = [
        f"{pod}-day{day}.cfg",
    ]

    for candidate in candidates:
        if (TARGETS_DIR / candidate).is_file():
            return candidate

    joined = ", ".join(candidates)
    raise FileNotFoundError(
        f"No target file found for POD {pod} day {day} in {TARGETS_DIR}. Checked: {joined}"
    )


def set_target(target_file: str) -> None:
    if target_file == LINK_NAME:
        raise ValueError(f"Target cannot be {LINK_NAME} itself.")

    target_path = TARGETS_DIR / target_file
    if not target_path.is_file():
        raise FileNotFoundError(f"File not found: {target_path}")

    LINK_DIR.mkdir(parents=True, exist_ok=True)
    link_path = LINK_DIR / LINK_NAME
    if link_path.exists() or link_path.is_symlink():
        if link_path.is_dir() and not link_path.is_symlink():
            raise IsADirectoryError(f"Cannot replace directory: {link_path}")
        link_path.unlink()

    # Relative symlink so it survives moves of the repo
    relative_target = Path("..") / TARGETS_DIR.name / target_file
    link_path.symlink_to(relative_target)
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


def interactive_select(skip_ansible_run: bool) -> None:
    pod = discover_pod_id()

    print("Which day would you like to rotate to? (Simply type the number and then press ENTER)", file=sys.stderr, flush=True)
    print("For Day0, type 0", file=sys.stderr, flush=True)
    print("For Day1, type 1", file=sys.stderr, flush=True)
    print("For Day2, type 2", file=sys.stderr, flush=True)
    sys.stderr.write("Please Enter 0, 1, or 2: ")
    sys.stderr.flush()
    day_input = input().strip()
    if day_input not in {"0", "1", "2"}:
        raise ValueError("Invalid selection. Please enter 0, 1, or 2.")

    day = int(day_input, 10)
    target_file = resolve_target_filename(pod, day)
    set_target(target_file)

    print("", file=sys.stderr, flush=True)
    print(f"Starting config replace for Day {day}...", file=sys.stderr, flush=True)
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

        interactive_select(skip_ansible_run=args.no_run)
        return 0
    except (ValueError, FileNotFoundError, IsADirectoryError, RuntimeError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
