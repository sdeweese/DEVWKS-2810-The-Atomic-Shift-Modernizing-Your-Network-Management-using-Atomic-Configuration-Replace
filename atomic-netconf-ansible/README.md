# The Atomic Shift: Modernizing Your Network Management using Atomic Configuration Replace (ACR)
This workshop is designed for the Cisco Live Las Vegas 2026 DEVWKS-2810 workshop!

To learn more about Atomic Configuration replace and for the device credentials to access this lab environment, please see your instructor.


Ansible playbooks for performing **atomic config replace** on Cisco IOS XE devices running **26.1.1+**. Supports two parallel workflows that both run over NETCONF:

- **CLI-RPC workflow** (recommended): send IOS CLI text via the `Cisco-IOS-XE-cli-rpc` YANG model (`config-ios-cli-trans` / `get-modelled-config-clis`).
- **YANG/XML workflow**: send native YANG/XML via standard NETCONF `edit-config` with `operation="replace"`.

Both workflows use the candidate datastore and atomic commit, with no SSH/CLI pushes involved. This lab focuses on the first (CLI RPC). For full details, see the GitHub Repository for this project: https://github.com/jeremycohoe/iosxe-atomic-netconf-ansible

This toolkit (`atomic-netconf-ansible`) replaces the entire device configuration atomically. It either fully succeeds or keeps the current config on the device. No partial config states. No risk of half-applied changes.


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

### Atomic Workflow Step by Step

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

1. **Stage**: Desired config is pushed to the **candidate datastore** using `config-ios-cli-trans` with `<do-commit>false</do-commit>`. Running config is untouched.
2. **Diff**: Candidate is compared against running using `get-modelled-config-clis` on both datastores. You see exactly what will change.
3. **Commit** (live push only): Candidate is atomically committed to running. All-or-nothing behavior applies. If any part fails, the entire transaction rolls back.
4. **Save**: Running config is written to startup.

> **Dry run** (default): Steps 1 and 2 only, then discard. The device is never modified.

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

After enabling candidate datastore, NETCONF restarts automatically (~60 seconds). Wait before testing connectivity.

### Workstation Requirements

| Component | Version | Purpose |
|---|---|---|
| Python | 3.10+ | Runtime |
| Ansible | 2.15+ | Automation framework |
| ncclient | 0.6.13+ | NETCONF client (used by Ansible netconf plugin) |
| lxml | any | XML parsing (ncclient dependency) |
| paramiko | any | SSH transport for NETCONF |
| xmltodict | any | XML parsing helpers |

### Lab Environment Setup

Note: Your instructor will give you a unique pod number, IP, and credentials to complete this lab. 

1. On the laptop provided, Open Visual Studio Code. In the bottom left corner, select the button that has two arrows facing each other. 

2. After clicking that button, a pop up should appear at the top of your Visual Studio Code window. Select the "Connect to Host" option from the dropdown menu.

3. SSH to your unique pod using the credentials provided by your instructor in this format `ssh auto@<YOUR_POD_IP>`. Example: `ssh auto@10.1.1.5`

4. Navigate to the `atomic-netconf-ansible` directory.

   ```bash
   # 1. Clone the repository (this has already been done for you in the lab pod)
   #git clone https://github.com/jeremycohoe/iosxe-atomic-netconf-ansible.git
   cd iosxe-atomic-netconf-ansible/atomic-netconf-ansible

   # 2. Confirm Ansible is available (lab pods normally ship with it)
   ansible --version

   # 3. Install the required Ansible collections
   ansible-galaxy collection install -r requirements.yml
   ```


### Network Connectivity

The workstation (your pod VM) must reach the lab switch on **TCP port 830** (NETCONF over SSH). In the standard lab pod environment the switch is directly reachable at `10.1.1.5`, and the inventory is already configured for this.

| Scenario | Setup |
|---|---|
| **In-pod (default)** | Inventory already points at `10.1.1.5:830`, so no changes are needed |
| **Direct access (other)** | Edit `inventory/hosts.yml` and set `ansible_host` to the device management IP |
| **Via VPN** | No special config is required; ensure port 830 is reachable |

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
│   ├── 05_baseline_capture_cli.yml          # Capture running config (CLI-RPC: get-modelled-config-clis)
│   ├── 06_atomic_push_cli.yml               # Atomic push (CLI-RPC: config-ios-cli-trans), includes before/after capture
│   └── 07_diff_preview_cli.yml              # Diff preview (CLI-RPC)
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
- `configs/baseline/<hostname>/baseline.cfg`: Reference copy (don't edit)
- `configs/desired/<hostname>.cfg`: **Your working copy (edit this)**

### 4. Edit Desired Config

Open `configs/desired/<hostname>.cfg` and make your changes using standard IOS CLI:

```diff
 interface TenGigabitEthernet1/0/1
+  description UPLINK-TO-DIST-SW
   shutdown
   switchport access vlan 30
 exit
```

> **This file is the complete device config.** Atomic config replace does a full replace. Anything you remove from this file will be removed from the device. Keep all physical interfaces.

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
# Dry run (default): stage, diff, discard. Same as preview but also creates backup.
# ansible-playbook -i inventory/hosts.yml playbooks/06_atomic_push_cli.yml

# Live push: stage, diff, COMMIT, save to startup.
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

## Day 0 → Day 1 → Day 2 → Day 0 Cycle with `apply-day-config.sh`

Once your baseline is captured and you're comfortable with the preview/push flow, the lab includes a helper that rotates the active desired config between three checkpoint files and runs the live atomic push for you:

- `configs/desired/POD-<id>-day0.cfg` — clean baseline (starting state)
- `configs/desired/POD-<id>-day1.cfg` — day-1 additions (e.g., interface descriptions, VLANs)
- `configs/desired/POD-<id>-day2.cfg` — day-2 additions (e.g., OSPF, extra NTP servers)

Your POD id comes from `cat ~/PODID` (e.g. `POD-13`). The script:

1. Repoints the symlink `configs/desired/c9300x-lab.cfg` → `POD-<id>-day<N>.cfg`
2. Runs `ansible-playbook -i inventory/hosts.yml playbooks/06_atomic_push_cli.yml -e dry_run=false`

See [apply-day-config-readme.md](apply-day-config-readme.md) for full options (`--list`, `--no-run`).

### One-time setup

```bash
cd /home/auto/iosxe-atomic-netconf-ansible/atomic-netconf-ansible
chmod +x apply-day-config.sh
```

### What you'll see when you run it

The script prints the symlink update, then streams the full `ansible-playbook` output (the same output you'd see running the playbook by hand):

```text
$ ./apply-day-config.sh
Detected PODID: POD-13
Which day would you like to rotate to? (Simply type the number and then press ENTER)
0) Day0
1) Day1
2) Day2
Please Enter 0, 1, or 2: 1
Updated: c9300x-lab.cfg -> POD-13-day1.cfg
Running Ansible full-replace playbook...
Command: ansible-playbook -i inventory/hosts.yml playbooks/06_atomic_push_cli.yml -e dry_run=false

PLAY [Atomic config push (CLI-RPC)] ********************************************
TASK [Gathering Facts] *********************************************************
...
TASK [Show diff] ***************************************************************
...
TASK [Commit candidate to running] *********************************************
changed: [c9300x-lab]

PLAY RECAP *********************************************************************
c9300x-lab : ok=12   changed=1    unreachable=0    failed=0    skipped=0
```

If the `PLAY RECAP` line shows `failed=0`, the atomic commit succeeded and the device's running config now matches `POD-13-day1.cfg`.

### Walk the lifecycle

Run the script once per stage and pick the day at the prompt. After each commit, optionally re-run the diff preview to confirm the device matches the new desired state.

**Stage 1 — Apply Day 0 (baseline)**

```bash
./apply-day-config.sh
# When prompted, enter: 0
```

Result: device is reset to the clean POD baseline. Hostname becomes `cat9300x-day0` (or equivalent for your pod).

**Stage 2 — Apply Day 1 (add interface/VLAN config)**

```bash
./apply-day-config.sh
# When prompted, enter: 1
```

Result: Day-1 deltas are atomically applied on top of the running config. Hostname becomes `cat9300x-day1`.

**Stage 3 — Apply Day 2 (add routing + NTP)**

```bash
./apply-day-config.sh
# When prompted, enter: 2
```

Result: OSPF process, additional NTP servers, and other day-2 deltas are atomically applied. Hostname becomes `cat9300x-day2`.

**Stage 4 — Roll back to Day 0**

```bash
./apply-day-config.sh
# When prompted, enter: 0
```

Result: full atomic replace back to the clean baseline. Day-1 and Day-2 additions are removed in a single transaction — no partial state, no reboot.

### Useful flags

```bash
./apply-day-config.sh --list      # show all available POD-*-day*.cfg targets
./apply-day-config.sh --no-run    # repoint the symlink only; skip the Ansible push
```

### Verify between stages (optional but recommended)

```bash
ansible-playbook -i inventory/hosts.yml playbooks/07_diff_preview_cli.yml
```

Expected after each `apply-day-config.sh` run: `Desired matches running (no diff)`.

### If something goes wrong

Ansible reports the failure in its standard `PLAY RECAP` (`failed=1`) and the script exits non-zero. Because this is an **atomic** replace, a failed push leaves the device on its previous running config — you'll never end up in a half-applied state.

Troubleshooting checklist:

1. Confirm POD id: `cat ~/PODID`
2. Confirm target exists: `ls configs/desired/POD-*-day*.cfg`
3. Check device reachability: `ansible-playbook -i inventory/hosts.yml playbooks/01_precheck.yml`
4. Preview the diff: `ansible-playbook -i inventory/hosts.yml playbooks/07_diff_preview_cli.yml`
5. Re-run verbosely: `ansible-playbook -vvv -i inventory/hosts.yml playbooks/06_atomic_push_cli.yml -e dry_run=false`
6. Common payload issues in `configs/desired/POD-*-dayN.cfg`:
   - close blocks with `exit`, **not** `end`
   - do **not** include `netconf-yang` or `restconf` (those are day-0 bootstrap, already on the device)

### Tips

- Payload files (`POD-*-dayN.cfg`) must use `exit` to close every config block. `end` is rejected by the NETCONF CLI-RPC parser.
- Do **not** put `netconf-yang` or `restconf` inside these payloads. Those are day-0 bootstrap commands and are already enabled on the device.
- Each run produces `pre_atomic_*.cfg` and `post_atomic_*.cfg` snapshots under `configs/backups/c9300x-lab/` for audit.
- If the device ever drifts, just `./apply-day-config.sh` → `0` to snap it back to baseline in a single transaction.

---

## Playbook Reference

### CLI-RPC Workflow (Recommended)

Work with familiar IOS CLI text. The payload is delivered over NETCONF using the `Cisco-IOS-XE-cli-rpc` YANG model (`config-ios-cli-trans` to push, `get-modelled-config-clis` to read). No SSH/CLI session is opened against the device.

| # | Playbook | Purpose | Modifies Device? |
|---|---|---|---|
| 01 | `01_precheck.yml` | Verify NETCONF, candidate, atomic support | No |
| 05 | `05_baseline_capture_cli.yml` | Pull running config as CLI text via CLI-RPC | No |
| 07 | `07_diff_preview_cli.yml` | Stage to candidate via CLI-RPC, diff, discard | No |
| 06 | `06_atomic_push_cli.yml` | Full config replace via CLI-RPC | **Dry run: No** / Live: **Yes** |


## Troubleshooting

| Problem | Solution |
|---|---|
| NETCONF connection refused | Verify `netconf-yang` is enabled; check port 830 reachability |
| NETCONF connection timeout | Increase `command_timeout` in `ansible.cfg`; verify network path to the switch |
| Precheck fails on candidate | Run `netconf-yang feature candidate-datastore` on device; wait 60s for NETCONF restart |
| Precheck fails on atomic config | Run `yang-interfaces feature atomic-config` on device |
| "Sync is in progress" error | Device busy with previous RPC. Wait 30s and retry |
| `get-modelled-config-clis` slow | Normal. This RPC is heavy. Allow 30-60s per device |
| Diff shows unexpected reordering | YANG normalization reorders some CLI. Focus on `+`/`-` lines |
| Diff shows no changes | Desired config already matches running |
| Push commit fails | Running config is untouched (atomic rollback). Check error message and fix desired config |


## Reference

- [Cisco IOS XE 26.1 Programmability Guide](https://www.cisco.com/c/en/us/td/docs/ios-xml/ios/prog/configuration/26x/26x-programmability-cg.html)
- YANG model: `Cisco-IOS-XE-cli-rpc` (revision 2026-02-01, v1.3.0)
- Detailed walkthrough: [docs/quickstart.md](docs/quickstart.md)
- Jinja pod generation workflow: [docs/jinja-pod-workflow.md](docs/jinja-pod-workflow.md)

## Congrats! You've completed the Atomic Config Replace Workshop!!