# Jinja Pod Generation Workflow

Use this workflow when you have one source config and want to regenerate all pod files by changing only pod-specific VLAN values.

## What It Changes

From the source file pod context (for example pod13 -> VLAN 33), it templates these patterns:
- `Vlan33` to `Vlan{{ pod_vlan }}`
- `vlan 33` to `vlan {{ pod_vlan }}`

Then renders pod files where:
- `pod_vlan = pod_number + 20`
- output naming is `POD-##-dayX.cfg`

## Script

- `scripts/render_pod_configs.py`

## Install Requirement

```bash
python3 -m pip install jinja2
```

## Example: Regenerate day1 for POD-01 to POD-30

```bash
python3 scripts/render_pod_configs.py \
  --source configs/pod-targets/POD-13-day1.cfg \
  --source-pod 13 \
  --pod-start 1 \
  --pod-end 30 \
  --output-dir configs/pod-targets
```

## Example: Build day2 from a single source file

```bash
python3 scripts/render_pod_configs.py \
  --source configs/pod-targets/POD-13-day2.cfg \
  --source-pod 13 \
  --pod-start 1 \
  --pod-end 30 \
  --output-dir configs/pod-targets
```

## Optional: Save Generated Template

```bash
python3 scripts/render_pod_configs.py \
  --source configs/pod-targets/POD-13-day1.cfg \
  --source-pod 13 \
  --template-out templates/pod-day1.j2 \
  --output-dir configs/pod-targets
```

## Verify

```bash
# Count generated files
find configs/pod-targets -maxdepth 1 -type f -name 'POD-*-day1.cfg' | wc -l

# Spot-check a pod mapping (pod16 -> vlan36)
grep -nE 'Vlan36|vlan 36' configs/pod-targets/POD-16-day1.cfg | head
```
