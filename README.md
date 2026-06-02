# DEVWKS-2810: The Atomic Shift

Workshop assets for **Cisco Live Las Vegas 2026 — DEVWKS-2810: The Atomic Shift: Modernizing Your Network Management using Atomic Configuration Replace (ACR)**.

This repository demonstrates how to perform a full **atomic configuration replace** on Cisco IOS XE 26.1.1+ devices using Ansible over NETCONF — with no SSH/CLI push, candidate datastore staging, and all-or-nothing commit behavior.

## Repository Layout

```text
.
├── README.md                    # (this file — overview only)
└── atomic-netconf-ansible/      # All workshop content lives here
    ├── README.md                # Full workshop guide — START HERE
    ├── playbooks/
    ├── inventory/
    ├── configs/
    ├── scripts/
    └── docs/
```

## Get Started

All instructions, prerequisites, lab steps, and reference material are in the workshop folder:

**FULL WORKSHOP GUIDE: [atomic-netconf-ansible/README.md](atomic-netconf-ansible/README.md)**

Additional docs:

- [Quickstart walkthrough](atomic-netconf-ansible/docs/quickstart.md)
- [Jinja pod generation workflow](atomic-netconf-ansible/docs/jinja-pod-workflow.md)
- [`set-c9300x-target.sh` helper reference](atomic-netconf-ansible/docs/set-c9300x-target.md)

## Reference

- [Cisco IOS XE 26.1 Programmability Guide](https://www.cisco.com/c/en/us/td/docs/ios-xml/ios/prog/configuration/26x/26x-programmability-cg.html)
- Upstream project: <https://github.com/jeremycohoe/iosxe-atomic-netconf-ansible>
