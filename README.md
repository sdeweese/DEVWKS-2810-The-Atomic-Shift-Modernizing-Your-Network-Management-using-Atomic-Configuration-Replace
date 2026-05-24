# iosxe-atomic-netconf-ansible

**Atomic configuration replacement for Cisco IOS XE 26.1.1+ over NETCONF.**

This repository provides tooling to perform *atomic* config operations against
Catalyst switches running IOS XE 26.1.1 and later. An atomic config push is
all-or-nothing: the entire target configuration is staged in the candidate
datastore, validated, then committed in a single transaction. If any part of
the commit fails, the running configuration is left untouched.

This repository provides an **Ansible toolkit** for atomic config replacement
on IOS XE 26.1.1+. A standalone Python reference implementation of the same
pattern lives in a separate repository:
[**cisco-ios-xe-atomic-config-replace**](https://github.com/jeremycohoe/cisco-ios-xe-atomic-config-replace).

| What you want | Where to go |
|---|---|
| Repeatable Ansible workflow (preview / diff / commit) | This repo — [`atomic-netconf-ansible/`](atomic-netconf-ansible/) |
| Single-script Python reference to embed in your own automation | [github.com/jeremycohoe/cisco-ios-xe-atomic-config-replace](https://github.com/jeremycohoe/cisco-ios-xe-atomic-config-replace) |

---

## Requirements

| Component | Version |
|---|---|
| Cisco IOS XE | **26.1.1 or later** |
| Ansible | 2.15+ |
| Python | 3.10+ |
| `ncclient` | 0.6.13+ |

### One-time device setup

Run these once on each switch before using the toolkit:

```
conf t
  netconf-yang
  netconf-yang feature candidate-datastore
  yang-interfaces feature atomic-config
end
write memory
```

NETCONF will restart automatically (about 60 seconds). Wait before testing
connectivity.

---

## Quick start (Ansible toolkit)

Clone the repo, change into the toolkit, install collections, and run the
precheck playbook:

```bash
git clone https://github.com/jeremycohoe/iosxe-atomic-netconf-ansible.git
cd iosxe-atomic-netconf-ansible/atomic-netconf-ansible

ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory/hosts.yml playbooks/01_precheck.yml
```

The toolkit ships pre-configured for the standard lab environment:

- Switch reachable at `10.1.1.5:830` (NETCONF)
- Credentials `admin` / `Cisco123` (demo lab — see security note below)

Edit `atomic-netconf-ansible/inventory/hosts.yml` and
`atomic-netconf-ansible/inventory/group_vars/all/vault.yml` if your environment
differs.

See [`atomic-netconf-ansible/README.md`](atomic-netconf-ansible/README.md) and
[`atomic-netconf-ansible/docs/quickstart.md`](atomic-netconf-ansible/docs/quickstart.md)
for the full workflow: precheck → baseline capture → edit desired config →
preview diff → commit.

---

---

## Repository layout

```
iosxe-atomic-netconf-ansible/
├── atomic-netconf-ansible/        # Ansible toolkit (primary, pod-ready)
│   ├── playbooks/                 # 01_precheck → 07_diff_preview_cli
│   ├── inventory/                 # Pre-configured for the lab environment
│   ├── configs/                   # baseline / desired / backups
│   ├── docs/quickstart.md         # Step-by-step user guide
│   ├── README.md
│   └── AGENT.md                   # Maintainer notes
│
├── README.md                      # This file
├── LICENSE                        # Apache 2.0
└── .gitignore
```

---

## Security note

The credentials shipped with this repository (`admin` / `Cisco123`) and the
target IP (`10.1.1.5`) are **demo-lab values only**. They are intentionally
published so that the toolkit can be cloned and run against a standard lab pod
without further configuration.

**Do not use these values for any non-lab device.** When deploying against a
real switch:

1. Change `ansible_user` and `ansible_password` in
   `atomic-netconf-ansible/inventory/group_vars/all/vault.yml`.
2. Encrypt the vault file with `ansible-vault encrypt` and supply
   `--ask-vault-pass` on the command line.
3. Update `ansible_host` in `atomic-netconf-ansible/inventory/hosts.yml`.

---

## License

This project is licensed under the **Apache License, Version 2.0**. See
[LICENSE](LICENSE) for the full text.

---

## Related projects

- [**cisco-ios-xe-atomic-config-replace**](https://github.com/jeremycohoe/cisco-ios-xe-atomic-config-replace)
  — standalone Python reference implementation of atomic config replace over
  NETCONF (single-script, MPL 2.0).
