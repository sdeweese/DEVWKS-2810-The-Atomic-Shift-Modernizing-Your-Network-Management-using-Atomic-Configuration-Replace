# AGENT.md — atomic Toolkit (Distributable Package)

## What This Is

Clean, self-contained Ansible framework for Atomic Config Replace on IOS XE 26.1.1+ devices. Pre-configured for the standard lab pod environment: one switch `c9300x-lab` at `10.1.1.5:830`, credentials `admin`/`Cisco123`. Identical across all lab pods — no per-pod customization required.

## Directory Structure

```
ansible.cfg                              # Ansible settings
requirements.yml                         # Galaxy collection dependencies
inventory/
  hosts.yml                              # Pre-configured: c9300x-lab @ 10.1.1.5
  group_vars/all/vars.yml                # Connection settings, config paths
  group_vars/all/vault.yml               # Credentials (admin/Cisco123 by default)
  group_vars/access_switches/vars.yml    # Group-specific overrides
playbooks/
  01_precheck.yml                        # Verify device readiness
  02_baseline_capture.yml                # Capture running config (YANG/XML)
  03_atomic_push.yml                     # Atomic push (YANG/XML edit-config, operation=replace)
  04_diff_preview.yml                    # Diff preview (YANG/XML)
  05_baseline_capture_cli.yml            # Capture running config (CLI-RPC: get-modelled-config-clis)
  06_atomic_push_cli.yml                 # Atomic push (CLI-RPC: config-ios-cli-trans) — includes before/after capture
  07_diff_preview_cli.yml                # Diff preview (CLI-RPC)
configs/
  baseline/                              # Auto-generated baseline configs
  desired/                               # User-edited desired configs
  backups/                               # Auto-generated pre/post-commit backups
docs/
  quickstart.md                          # Step-by-step walkthrough
scripts/
  tunnel.sh                              # Maintainer-only SSH tunnel helper (not for users)
```

> **Note on `scripts/tunnel.sh`** — This is a maintainer-only helper for working on the toolkit/scripts architecture from outside a lab pod (e.g., forwarding NETCONF over a jump host during development). Lab pod users never need it: the switch is directly reachable at `10.1.1.5:830` from inside the pod. Do not surface this script in user-facing docs.

## Config Path Resolution

Paths in `group_vars/all/vars.yml` are relative to `playbook_dir` (which is `playbooks/`):

```yaml
config_backup_dir: "{{ playbook_dir }}/../configs/backups"
config_baseline_dir: "{{ playbook_dir }}/../configs/baseline"
config_desired_dir: "{{ playbook_dir }}/../configs/desired"
```

If you move playbooks to a different depth, update these paths.

## Playbook Conventions

- All playbooks target the `iosxe` host group.
- Push playbooks (`03`, `06`) default to `dry_run: true`. Pass `-e dry_run=false` to commit.
- Preview playbooks (`04`, `07`) always discard — they never modify the device.
- All CLI RPC playbooks use `<do-commit>false</do-commit>` to stage to candidate only.
- Desired config files are per-hostname: `configs/desired/<inventory_hostname>.cfg` (CLI) or `.xml` (YANG).

## Key RPC Details

### config-ios-cli-trans

- YANG model: `Cisco-IOS-XE-cli-rpc`
- `<do-commit>false</do-commit>` — stages to candidate only (running untouched)
- `<do-commit>true</do-commit>` (default if omitted) — stages AND auto-commits to running
- `<operation>full-replace</operation>` — replaces entire config atomically

### get-modelled-config-clis

- Same YANG model. Heavy operation — 30-60s per device is normal.
- `<datastore>running</datastore>` or `<datastore>candidate</datastore>`
- `06_atomic_push_cli.yml` calls this RPC for: BEFORE backup (running), candidate/running diff, and AFTER capture (running post-commit). Full configs are displayed in the log and saved as `pre_atomic_*.cfg` / `post_atomic_*.cfg`.

## User Setup Checklist

For the standard lab pod environment, no setup is required — the toolkit is pre-configured. The full workflow is:

1. Run `01_precheck.yml` to verify connectivity
2. Run `05_baseline_capture_cli.yml` to capture baseline and create desired config
3. Edit `configs/desired/c9300x-lab.cfg`
4. Run `07_diff_preview_cli.yml` to preview
5. Run `06_atomic_push_cli.yml -e dry_run=false` to push

For non-standard environments (different IP, additional devices, encrypted vault), update `inventory/hosts.yml` and/or `inventory/group_vars/all/vault.yml` before step 1.

## When Editing Playbooks

- Playbooks use `ansible.netcommon.netconf_rpc` for all NETCONF operations.
- RPC responses need XML tag stripping (regex_replace chain) to extract CLI text.
- Use `stdout_lines` in `debug` messages for readable diff output (YAML callback escapes newlines in strings).
- The `ansible_command_timeout: 300` in vars.yml is critical — `get-modelled-config-clis` is slow.
