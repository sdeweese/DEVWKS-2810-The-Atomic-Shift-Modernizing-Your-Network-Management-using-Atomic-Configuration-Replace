# IOS XE Atomic Config Replace — Ansible Framework

Ansible playbooks for performing **atomic config replace** on Cisco IOS XE devices running **26.1.1+**. Supports both CLI text and YANG/XML workflows.

This toolkit (`atomic-netconf-ansible`) replaces the entire device configuration atomically — it either fully succeeds or fully rolls back. No partial config states. No risk of half-applied changes.

---

## How It Works

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Your Workstation                         │
│                                                                 │
│  configs/desired/           Ansible            NETCONF (830)    │
│  ┌──────────────┐      ┌────────────┐      ┌────────────────┐  │
│  │ hostname.cfg  │─────▶│  Playbook  │─────▶│  IOS XE Device │  │
│  │ (CLI text)    │      │  (06/07)   │  SSH │  26.1.1+       │  │
│  └──────────────┘      └────────────┘      └────────────────┘  │
│                              │                     │            │
│  configs/baseline/           │              ┌──────┴──────┐     │
│  ┌──────────────┐            │              │  Candidate  │     │
│  │ baseline.cfg  │           │              │  Datastore  │     │
│  │ (reference)   │           │              └──────┬──────┘     │
│  └──────────────┘            │                     │            │
│                              │               commit (atomic)    │
│  configs/backups/            │                     │            │
│  ┌──────────────┐            │              ┌──────┴──────┐     │
│  │ pre_atomic_*.cfg │◀──────────┘              │   Running   │     │
│  │ (auto backup) │                          │   Config    │     │
│  └──────────────┘                           └─────────────┘     │
└─────────────────────────────────────────────────────────────────┘
```

### Atomic Workflow — Step by Step

```
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│ Precheck │────▶│ Baseline │────▶│   Edit   │────▶│ Preview  │────▶│   Push   │
│          │     │ Capture  │     │ Desired  │     │  (diff)  │     │  (atomic)   │
│ 01       │     │ 05       │     │ .cfg     │     │ 07       │     │ 06       │
└──────────┘     └──────────┘     └──────────┘     └──────────┘     └──────────┘
  Verify           Pull              Make            Stage to         Stage to
  NETCONF,         running           your            candidate,       candidate,
  candidate,       config as         changes          diff vs         diff, then
  atomic-cfg       CLI text                          running,         COMMIT +
                                                     discard          save
                                                     (safe)           (atomic)
```

### What Happens on the Device

1. **Stage** — Desired config is pushed to the **candidate datastore** using `config-ios-cli-trans` with `<do-commit>false</do-commit>`. Running config is untouched.
2. **Diff** — Candidate is compared against running using `get-modelled-config-clis` on both datastores. You see exactly what will change.
3. **Commit** (live push only) — Candidate is atomically committed to running. All-or-nothing — if any part fails, the entire transaction rolls back.
4. **Save** — Running config is written to startup.

> **Dry run** (default): Steps 1–2 only, then discard. The device is never modified.

---

## Prerequisites

### IOS XE Device Requirements

| Requirement | Detail |
|---|---|
| **IOS XE version** | 26.1.1 or later |
| **NETCONF** | Enabled and reachable on port 830 |
| **Candidate datastore** | Explicitly enabled (not on by default) |
| **Atomic config** | Feature flag enabled |
| **Credentials** | Local user with privilege 15 |

Enable on each device:

```
conf t
  netconf-yang
  netconf-yang feature candidate-datastore
  yang-interfaces feature atomic-config
end
write memory
```

> After enabling candidate datastore, NETCONF restarts automatically (~60 seconds). Wait before testing connectivity.

### Workstation Requirements

| Component | Version | Purpose |
|---|---|---|
| Python | 3.10+ | Runtime |
| Ansible | 2.15+ | Automation framework |
| ncclient | 0.6.13+ | NETCONF client (used by Ansible netconf plugin) |
| lxml | any | XML parsing (ncclient dependency) |
| paramiko | any | SSH transport for NETCONF |
| xmltodict | any | XML parsing helpers |

### Install on a Lab Pod (from GitHub)

```bash
# 1. Clone the repository
git clone https://github.com/jeremycohoe/iosxe-atomic-netconf-ansible.git
cd iosxe-atomic-netconf-ansible/atomic-netconf-ansible

# 2. Confirm Ansible is available (lab pods normally ship with it)
ansible --version

# 3. Install the required Ansible collections
ansible-galaxy collection install -r requirements.yml
```

If `ansible` is not installed on the pod, install it once with:

```bash
python3 -m pip install --user ansible ncclient lxml xmltodict paramiko
```

### Install Dependencies (Developer Workstation)

Only needed if you are working on the toolkit itself (not for lab pod users):

```bash
# Create Python virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install Python packages
pip install ansible ncclient lxml xmltodict paramiko netmiko

# Install Ansible Galaxy collections
ansible-galaxy collection install -r requirements.yml
```

### Network Connectivity

The workstation (your pod VM) must reach the lab switch on **TCP port 830** (NETCONF over SSH). In the standard lab pod environment the switch is directly reachable at `10.1.1.5` — the inventory is already configured for this.

| Scenario | Setup |
|---|---|
| **In-pod (default)** | Inventory already points at `10.1.1.5:830` — no changes needed |
| **Direct access (other)** | Edit `inventory/hosts.yml` and set `ansible_host` to the device management IP |
| **Via VPN** | No special config — just ensure port 830 is reachable |

---

## Project Structure

```
atomic-netconf-ansible/
├── ansible.cfg                              # Ansible settings (YAML output, timeouts)
├── requirements.yml                         # Ansible Galaxy dependencies
├── README.md                                # This file
│
├── inventory/
│   ├── hosts.yml                            # Pre-configured: c9300x-lab @ 10.1.1.5
│   └── group_vars/
│       ├── all/
│       │   ├── vars.yml                     # Connection settings, config paths
│       │   └── vault.yml                    # Credentials (admin/Cisco123 by default)
│       └── access_switches/
│           └── vars.yml                     # Group-specific overrides
│
├── playbooks/
│   ├── 01_precheck.yml                      # Verify device readiness
│   ├── 02_baseline_capture.yml              # Capture running config (YANG/XML)
│   ├── 03_atomic_push.yml                      # atomic push (YANG/XML)
│   ├── 04_diff_preview.yml                  # Diff preview (YANG/XML)
│   ├── 05_baseline_capture_cli.yml          # Capture running config (CLI text)
│   ├── 06_atomic_push_cli.yml                  # atomic push (CLI) — includes before/after capture
│   └── 07_diff_preview_cli.yml              # Diff preview (CLI)
│
├── configs/
│   ├── baseline/<hostname>/baseline.cfg     # Reference configs (auto-generated, don't edit)
│   ├── desired/<hostname>.cfg               # Desired configs (EDIT THESE)
│   └── backups/<hostname>/                  # Pre/post-commit backups (auto-generated)
│       ├── pre_atomic_*.cfg                    #   Running config before commit
│       └── post_atomic_*.cfg                   #   Running config after commit
│
└── docs/
    └── quickstart.md                        # Detailed step-by-step walkthrough
```

---

## Quick Start

All commands are run from inside the extracted `atomic-netconf-ansible/` directory.

### 1. Inventory & Credentials (Pre-Configured)

The toolkit ships ready to run in any lab pod:

- **Inventory** (`inventory/hosts.yml`): one host `c9300x-lab` at `10.1.1.5:830`
- **Credentials** (`inventory/group_vars/all/vault.yml`): `admin` / `Cisco123`

No edits required for the standard lab environment. If you want to encrypt the vault:

```bash
ansible-vault encrypt inventory/group_vars/all/vault.yml
# then append --ask-vault-pass to every ansible-playbook command
```

### 2. Verify Device Readiness

```bash
ansible-playbook -i inventory/hosts.yml playbooks/01_precheck.yml
```

Checks: NETCONF connectivity, candidate datastore, atomic config support, IOS XE version.

### 3. Capture Baseline

```bash
ansible-playbook -i inventory/hosts.yml playbooks/05_baseline_capture_cli.yml
```

Creates two files per device:
- `configs/baseline/<hostname>/baseline.cfg` — Reference copy (don't edit)
- `configs/desired/<hostname>.cfg` — **Your working copy (edit this)**

### 4. Edit Desired Config

Open `configs/desired/<hostname>.cfg` and make your changes using standard IOS CLI:

```diff
 interface TenGigabitEthernet1/0/1
+  description UPLINK-TO-DIST-SW
   shutdown
   switchport access vlan 30
 exit
```

> **This file is the complete device config.** Atomic config replace does a full replace — anything you remove from this file will be removed from the device. Keep all physical interfaces.

### 5. Preview Changes (Safe)

```bash
ansible-playbook -i inventory/hosts.yml playbooks/07_diff_preview_cli.yml
```

Stages to candidate, diffs against running, then **discards**. Device is never modified. Output shows unified diff:

```
+ (lines being added)
- (lines being removed)
  (unchanged context)
```

### 6. Push Changes

```bash
# Dry run (default) — stage, diff, discard. Same as preview but also creates backup.
ansible-playbook -i inventory/hosts.yml playbooks/06_atomic_push_cli.yml

# Live push — stage, diff, COMMIT, save to startup.
ansible-playbook -i inventory/hosts.yml playbooks/06_atomic_push_cli.yml -e dry_run=false
```

The live push log includes:
- **BEFORE**: Full running config captured via `get-modelled-config-clis` before staging
- **DIFF**: Unified diff showing exactly what changes
- **AFTER**: Full running config captured via `get-modelled-config-clis` after commit
- Both before/after configs saved to `configs/backups/<hostname>/` as `pre_atomic_*.cfg` and `post_atomic_*.cfg`

### 7. Verify

Re-run preview to confirm no diff remains:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/07_diff_preview_cli.yml
```

Expected: `Desired matches running (no diff)`

---

## Playbook Reference

### CLI Workflow (Recommended)

Work with familiar IOS CLI text. Uses `config-ios-cli-trans` and `get-modelled-config-clis` RPCs.

| # | Playbook | Purpose | Modifies Device? |
|---|---|---|---|
| 01 | `01_precheck.yml` | Verify NETCONF, candidate, atomic support | No |
| 05 | `05_baseline_capture_cli.yml` | Pull running config as CLI text | No |
| 07 | `07_diff_preview_cli.yml` | Stage to candidate, diff, discard | No |
| 06 | `06_atomic_push_cli.yml` | Full config replace via CLI RPC | **Dry run: No** / Live: **Yes** |

### YANG/XML Workflow

Work with XML config files. Uses standard NETCONF `edit-config` with `operation="replace"`.

| # | Playbook | Purpose | Modifies Device? |
|---|---|---|---|
| 01 | `01_precheck.yml` | Verify NETCONF, candidate, atomic support | No |
| 02 | `02_baseline_capture.yml` | Pull running config as XML | No |
| 04 | `04_diff_preview.yml` | Stage to candidate, preview, discard | No |
| 03 | `03_atomic_push.yml` | Full config replace via edit-config | **Dry run: No** / Live: **Yes** |

---

## Multi-Device Usage

The default lab pod inventory contains a single switch (`c9300x-lab`), so the playbooks run against that one host automatically. If you extend the inventory with additional devices, target a subset with `--limit`:

```bash
# Single device
ansible-playbook -i inventory/hosts.yml playbooks/06_atomic_push_cli.yml --limit c9300x-lab

# Device group
ansible-playbook -i inventory/hosts.yml playbooks/06_atomic_push_cli.yml --limit access_switches

# Multiple devices
ansible-playbook -i inventory/hosts.yml playbooks/06_atomic_push_cli.yml --limit "c9300x-lab,switch-02"
```

Without `--limit`, playbooks run against **all devices** in the `iosxe` group.

---

## Technical Details

### How config-ios-cli-trans Works

The `<do-commit>` leaf controls whether the RPC auto-commits to running:

| `<do-commit>` value | Candidate | Running | Use case |
|---|---|---|---|
| `true` (default if omitted) | Written | **Also written** | Quick one-shot apply |
| `false` | Written | **Untouched** | Safe stage → diff → commit pattern |

All playbooks in this toolkit use `<do-commit>false</do-commit>` so that:
- Preview and dry-run can safely **stage → diff → discard**
- Live push explicitly **commits only after showing the diff**

### IOS XE 26.1.1+ Benefits

- **Crypto certificates** are abstracted out of the `<native>` YANG model — no filtering or special handling needed during baseline capture
- **Candidate datastore** support for safe stage-then-commit workflows
- **Atomic config** ensures all-or-nothing config replacement

---

## Troubleshooting

| Problem | Solution |
|---|---|
| NETCONF connection refused | Verify `netconf-yang` is enabled; check port 830 reachability |
| NETCONF connection timeout | Increase `command_timeout` in `ansible.cfg`; verify network path to the switch |
| Precheck fails on candidate | Run `netconf-yang feature candidate-datastore` on device; wait 60s for NETCONF restart |
| Precheck fails on atomic config | Run `yang-interfaces feature atomic-config` on device |
| "Sync is in progress" error | Device busy with previous RPC — wait 30s and retry |
| `get-modelled-config-clis` slow | Normal — this RPC is heavy. Allow 30–60s per device |
| Diff shows unexpected reordering | YANG normalization reorders some CLI — focus on `+`/`-` lines |
| Diff shows no changes | Desired config already matches running |
| Push commit fails | Running config is untouched (atomic rollback). Check error message and fix desired config |

---

## Reference

- [Cisco IOS XE Programmability Guide — Atomic Config Replace](https://www.cisco.com/c/en/us/td/docs/ios-xml/ios/prog/configuration/xe-26/prog-xe-26-book.html)
- YANG model: `Cisco-IOS-XE-cli-rpc` (revision 2026-02-01, v1.3.0)
- Detailed walkthrough: [docs/quickstart.md](docs/quickstart.md)
