# Atomic Workflow — Step-by-Step Guide

Atomic NETCONF (Atomic Config Replace) for IOS XE 26.1.1+ using Ansible and NETCONF. Two parallel workflows: **CLI text** (recommended) and **YANG/XML**.

---

## TL;DR — Full Workflow on a Lab Pod

Copy-paste, top to bottom, from inside the pod's home directory:

```bash
# Clone the repo
git clone https://github.com/jeremycohoe/iosxe-atomic-netconf-ansible.git
cd iosxe-atomic-netconf-ansible/atomic-netconf-ansible

# One-time: install collections
ansible-galaxy collection install -r requirements.yml

# 1. Verify the device is ready
ansible-playbook -i inventory/hosts.yml playbooks/01_precheck.yml

# 2. Capture the current running config as your starting point
ansible-playbook -i inventory/hosts.yml playbooks/05_baseline_capture_cli.yml

# 3. Edit the desired config (this is the full target config for the device)
${EDITOR:-vi} configs/desired/c9300x-lab.cfg

# 4. Preview the change — never touches the device
ansible-playbook -i inventory/hosts.yml playbooks/07_diff_preview_cli.yml

# 5. Commit the change (atomic config replace + save to startup)
ansible-playbook -i inventory/hosts.yml playbooks/06_atomic_push_cli.yml -e dry_run=false

# 6. Verify — should report "Desired matches running (no diff)"
ansible-playbook -i inventory/hosts.yml playbooks/07_diff_preview_cli.yml
```

The rest of this document walks through each step in detail.

---

## Prerequisites

### Device Configuration

Enable these features on each IOS XE device:

```
conf t
  netconf-yang
  netconf-yang feature candidate-datastore
  yang-interfaces feature atomic-config
end
write memory
```

> **IOS XE 26.1.1+** is required. On this release, crypto certificates are abstracted out of the native model — no special handling needed.

### Lab Pod Setup (from GitHub)

```bash
# 1. Clone the repository
git clone https://github.com/jeremycohoe/iosxe-atomic-netconf-ansible.git
cd iosxe-atomic-netconf-ansible/atomic-netconf-ansible

# 2. Confirm Ansible is available (lab pods normally ship with it)
ansible --version

# 3. Install the required Ansible Galaxy collections
ansible-galaxy collection install -r requirements.yml
```

If Ansible is not installed on the pod, install it once with:

```bash
python3 -m pip install --user ansible ncclient lxml xmltodict paramiko
```

### Developer Workstation Setup (Optional)

Only needed if you are working on the toolkit itself rather than running it on a pod:

```bash
git clone <repo-url> && cd <repo>/atomic-netconf-ansible
python3 -m venv .venv
source .venv/bin/activate
pip install ansible ncclient lxml xmltodict paramiko netmiko
ansible-galaxy collection install -r requirements.yml
```

---

## Inventory & Credentials (Pre-Configured)

The toolkit ships ready to run in any standard lab pod. From the pod's VM the lab switch is reachable directly at `10.1.1.5` on port 830.

**Inventory** (`inventory/hosts.yml`):

```yaml
all:
  children:
    access_switches:
      hosts:
        c9300x-lab:
          ansible_host: 10.1.1.5
          ansible_port: 830
    iosxe:
      children:
        access_switches:
```

**Credentials** (`inventory/group_vars/all/vault.yml`):

```yaml
ansible_user: admin
ansible_password: Cisco123
```

No edits required for the standard lab environment.

> Optional: encrypt the vault for shared-environment hygiene with
> `ansible-vault encrypt inventory/group_vars/all/vault.yml`, then append
> `--ask-vault-pass` to every `ansible-playbook` command.

---

## CLI Workflow (Playbooks 05–07)

Work with familiar IOS CLI config text. Recommended for most users.

```
01_precheck ──▶ 05_baseline_capture_cli ──▶ Edit desired .cfg ──▶ 07_diff_preview_cli ──▶ 06_atomic_push_cli
```

### Step 1: Pre-Check

Verify NETCONF connectivity, candidate datastore, and atomic config support:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/01_precheck.yml
```

All tasks should show `ok`. If any fail, check the device prerequisites above.

### Step 2: Capture Baseline

Pull the running config as CLI text:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/05_baseline_capture_cli.yml
```

Creates:
- `configs/baseline/<hostname>/baseline.cfg` — Reference copy (don't edit)
- `configs/desired/<hostname>.cfg` — Working copy (**edit this one**)

### Step 3: Edit Desired Config

Open `configs/desired/<hostname>.cfg` and make your changes. Standard IOS CLI syntax.

**Example** — add an interface description:

```diff
 interface TenGigabitEthernet1/0/1
+  description UPLINK-TO-DIST
   shutdown
   switchport access vlan 30
 exit
```

> **This file is the complete device config.** Atomic config replace does a full replace — anything removed from this file gets removed from the device.

### Step 4: Preview Changes

See what would change **without touching the device**:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/07_diff_preview_cli.yml
```

This stages the desired config to the candidate datastore using `config-ios-cli-trans` with `<do-commit>false</do-commit>` (candidate only, running untouched), diffs candidate vs running, then discards.

### Step 5: Push (Dry Run)

```bash
ansible-playbook -i inventory/hosts.yml playbooks/06_atomic_push_cli.yml
```

Same as preview but also creates a backup. Still **discards without committing** (dry run is the default).

### Step 6: Push (Live)

```bash
ansible-playbook -i inventory/hosts.yml playbooks/06_atomic_push_cli.yml -e dry_run=false
```

This will:
1. Backup current running config (saved to `configs/backups/<hostname>/pre_atomic_*.cfg`)
2. Display the full **BEFORE** running config via `get-modelled-config-clis`
3. Stage desired CLI to candidate (full-replace, do-commit=false)
4. Diff candidate vs running
5. **Commit** candidate → running (atomic)
6. Capture and display the full **AFTER** running config via `get-modelled-config-clis` (saved to `post_atomic_*.cfg`)
7. **Save** running → startup

If the commit fails, the running config is untouched. The log output includes the complete before and after configs for audit review.

### Step 7: Verify

```bash
ansible-playbook -i inventory/hosts.yml playbooks/07_diff_preview_cli.yml
```

Expected: `Desired matches running (no diff)`

---

## YANG/XML Workflow (Playbooks 02–04)

Work with XML config files using standard NETCONF `edit-config` with replace semantics.

```
01_precheck ──▶ 02_baseline_capture ──▶ Edit desired .xml ──▶ 04_diff_preview ──▶ 03_atomic_push
```

### Steps

```bash
# Pre-check
ansible-playbook -i inventory/hosts.yml playbooks/01_precheck.yml

# Capture baseline (XML)
ansible-playbook -i inventory/hosts.yml playbooks/02_baseline_capture.yml

# Edit configs/desired/<hostname>.xml with your changes

# Preview changes (stages to candidate, shows CLI preview, discards)
ansible-playbook -i inventory/hosts.yml playbooks/04_diff_preview.yml

# Push — dry run (default)
ansible-playbook -i inventory/hosts.yml playbooks/03_atomic_push.yml

# Push — live
ansible-playbook -i inventory/hosts.yml playbooks/03_atomic_push.yml -e dry_run=false
```

---

## Multi-Device Targeting

The default lab pod inventory contains a single switch (`c9300x-lab`), so playbooks run against it automatically. If you extend the inventory with additional devices, target a subset with `--limit`:

```bash
# Single device
ansible-playbook -i inventory/hosts.yml playbooks/07_diff_preview_cli.yml \
  --limit c9300x-lab

# Device group
ansible-playbook -i inventory/hosts.yml playbooks/06_atomic_push_cli.yml \
  --limit access_switches

# Multiple devices
ansible-playbook -i inventory/hosts.yml playbooks/06_atomic_push_cli.yml \
  --limit "c9300x-lab,switch-02"
```

---

## Playbook Reference

| # | Playbook | Purpose | Modifies Device? |
|---|---|---|---|
| 01 | `01_precheck.yml` | Verify NETCONF, candidate, atomic support | No |
| 02 | `02_baseline_capture.yml` | Pull running config (XML) | No |
| 03 | `03_atomic_push.yml` | Atomic via YANG/XML edit-config | Dry run: No / Live: **Yes** |
| 04 | `04_diff_preview.yml` | Preview changes (XML workflow) | No |
| 05 | `05_baseline_capture_cli.yml` | Pull running config (CLI text) | No |
| 06 | `06_atomic_push_cli.yml` | Atomic via CLI RPC (config-ios-cli-trans) | Dry run: No / Live: **Yes** |
| 07 | `07_diff_preview_cli.yml` | Preview changes (CLI workflow) | No |

---

## How config-ios-cli-trans Works

The CLI workflow uses two RPCs from the `Cisco-IOS-XE-cli-rpc` YANG model:

- **`get-modelled-config-clis`** — Retrieves the running or candidate config as CLI text
- **`config-ios-cli-trans`** — Pushes CLI text to the candidate datastore

The key parameter is `<do-commit>`:

| `<do-commit>` value | Behavior |
|---|---|
| `true` (default, or omitted) | Stages to candidate AND auto-commits to running |
| `false` | Stages to candidate ONLY — running is untouched |

All playbooks use `<do-commit>false</do-commit>` so that:
- Preview/dry-run can safely stage → diff → discard
- Live push explicitly commits only after showing the diff

---

## Troubleshooting

| Problem | Solution |
|---|---|
| NETCONF connection timeout | Verify network path to the switch; increase `command_timeout` in `ansible.cfg` |
| "Sync is in progress" error | Device busy with previous RPC — wait 30s and retry |
| Candidate datastore not available | Run `netconf-yang feature candidate-datastore` on device; wait 60s |
| `get-modelled-config-clis` slow | Normal — this RPC is heavy, allow 30–60s per device |
| Diff shows unexpected changes | YANG normalization reorders some CLI — focus on `+`/`-` lines |
| Preview shows no diff | Desired config matches running (or was already applied) |

---

## File Layout

```
configs/
  baseline/<hostname>/baseline.cfg       # CLI baseline (don't edit)
  baseline/<hostname>/baseline.xml       # XML baseline (don't edit)
  desired/<hostname>.cfg                 # CLI working copy (edit for CLI workflow)
  desired/<hostname>.xml                 # XML working copy (edit for XML workflow)
  backups/<hostname>/                    # Auto-generated pre-push backups
```
