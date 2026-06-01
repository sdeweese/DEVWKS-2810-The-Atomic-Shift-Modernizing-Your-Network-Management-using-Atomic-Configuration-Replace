# set-c9300x-target.sh Usage

This guide explains how to use `set-c9300x-target.sh` to quickly switch what `c9300x-lab.cfg` points to.

## What It Does

The script updates this symlink:

- `configs/desired/c9300x-lab.cfg`

This lets playbooks that reference `c9300x-lab.cfg` switch between pod-specific day files without renaming any configuration files.

The script is pod-aware and always allows these baseline targets for the detected pod:
- `POD-##-day0.cfg`
- `POD-##-day1.cfg`

It also supports future files such as `POD-##-day2.cfg`, `POD-##-day3.cfg`, and other `dayX` variants.

It blocks selecting another pod's file.

## Script Location

- `set-c9300x-target.sh`

## Prerequisites

Run commands from inside `atomic-netconf-ansible`:

```bash
cd /home/auto/iosxe-atomic-netconf-ansible/atomic-netconf-ansible
```

Ensure executable bit is set (one-time):

```bash
chmod +x set-c9300x-target.sh
```

Create a pod-id file on the host (recommended):

```bash
echo "POD-13" > ~/PODID
```

Supported pod-id formats:
- `POD-13`
- `POD13`
- `13`

Pod range is `1` through `30`.

If needed, you can override detection per command with `POD_ID=...`.

## Command Modes

### 1) List available targets

```bash
./set-c9300x-target.sh --list
```

Shows:
- Current target of `c9300x-lab.cfg`
- Detected pod
- Only allowed files for that pod (day0/day1)

### 2) Show detected pod information

```bash
./set-c9300x-target.sh --pod-info
```

Shows:
- Detected pod number
- Derived VLAN mapping (`pod + 20`)
- Derived peer pod mapping (`pod + 20`)
- Allowed target filenames

### 3) Set target directly

```bash
./set-c9300x-target.sh POD-13-day0.cfg
./set-c9300x-target.sh POD-13-day1.cfg
./set-c9300x-target.sh day0
./set-c9300x-target.sh day1
./set-c9300x-target.sh day2
./set-c9300x-target.sh 0
./set-c9300x-target.sh 1
./set-c9300x-target.sh 2
```

Direct set is validated against the detected pod. Cross-pod targets are rejected.

Numeric shortcut behavior:
- `0` maps to `POD-##-day0.cfg`
- `1` maps to `POD-##-day1.cfg`
- `2` maps to `POD-##-day2.cfg`

Example: if detected pod is `POD-07`, then:

```bash
./set-c9300x-target.sh 1
```

sets:

```text
configs/desired/c9300x-lab.cfg -> POD-07-day1.cfg
```

### 4) Interactive picker

```bash
./set-c9300x-target.sh
```

Prompts you with exactly two options for the current pod: day0 and day1.
If more `dayX` files exist for the pod, they are automatically included in the list.

## Verify Current Target

```bash
ls -l configs/desired/c9300x-lab.cfg
```

Example output:

```text
configs/desired/c9300x-lab.cfg -> POD-13-day1.cfg
```

## Typical Workflow

```bash
# 1) Pick which desired config to use
./set-c9300x-target.sh day1

# 2) Confirm target
ls -l configs/desired/c9300x-lab.cfg

# 3) Run atomic push
ansible-playbook -i inventory/hosts.yml playbooks/06_atomic_push_cli.yml -e dry_run=false
```

## Optional Catalog Folder Strategy

Recommended for large environments with all pod files present on every host:
- Keep all pod files in `configs/pod-targets/`.
- Keep `configs/desired/` minimal.
- Let the script copy only local pod `dayX` files into `configs/desired/` when missing.

The script already supports this automatically when `configs/pod-targets/` exists.

You can override the catalog location:

```bash
CATALOG_DIR=/path/to/pod-targets ./set-c9300x-target.sh --list
```

## Notes

- The script only manages the symlink in `configs/desired/`.
- It does not edit any config file contents.
- If the target file does not exist for the detected pod, the script exits with an error.
