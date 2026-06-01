#!/usr/bin/env python3
"""Render POD-##-dayX config files from a single source config using Jinja2.

The script converts source VLAN tokens into Jinja placeholders:
- Vlan<source_vlan> -> Vlan{{ pod_vlan }}
- vlan <source_vlan> -> vlan {{ pod_vlan }}

Then it renders POD-01..POD-30 files where pod_vlan = pod_number + 20.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

try:
    from jinja2 import Environment
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "Jinja2 is required. Install with: python3 -m pip install jinja2"
    ) from exc


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Render pod configs from one source file")
    parser.add_argument(
        "--source",
        required=True,
        help="Source config file (for example configs/pod-targets/POD-13-day1.cfg)",
    )
    parser.add_argument(
        "--source-pod",
        type=int,
        default=13,
        help="Pod number of source file. Default: 13",
    )
    parser.add_argument(
        "--pod-start",
        type=int,
        default=1,
        help="First pod to render. Default: 1",
    )
    parser.add_argument(
        "--pod-end",
        type=int,
        default=30,
        help="Last pod to render. Default: 30",
    )
    parser.add_argument(
        "--day-label",
        default=None,
        help="Optional day label override (for example day1, day2). Auto-detected by default.",
    )
    parser.add_argument(
        "--output-dir",
        default="configs/pod-targets",
        help="Output directory for rendered files. Default: configs/pod-targets",
    )
    parser.add_argument(
        "--template-out",
        default=None,
        help="Optional path to write generated Jinja template",
    )
    return parser.parse_args()


def detect_day_label(source_path: Path, override: str | None) -> str:
    if override:
        return override
    match = re.search(r"POD-\d+-(day[^.]+)\.cfg$", source_path.name)
    if not match:
        raise SystemExit(
            "Could not infer day label from filename. Use --day-label (for example day1)."
        )
    return match.group(1)


def build_template(source_text: str, source_vlan: int) -> str:
    template = source_text
    template = template.replace(f"Vlan{source_vlan}", "Vlan{{ pod_vlan }}")
    template = template.replace(f"vlan {source_vlan}", "vlan {{ pod_vlan }}")
    return template


def main() -> int:
    args = parse_args()

    if args.source_pod < 1 or args.source_pod > 30:
        raise SystemExit("--source-pod must be in range 1..30")
    if args.pod_start < 1 or args.pod_start > 30 or args.pod_end < 1 or args.pod_end > 30:
        raise SystemExit("--pod-start and --pod-end must be in range 1..30")
    if args.pod_start > args.pod_end:
        raise SystemExit("--pod-start cannot be greater than --pod-end")

    source_path = Path(args.source).resolve()
    if not source_path.is_file():
        raise SystemExit(f"Source file not found: {source_path}")

    day_label = detect_day_label(source_path, args.day_label)
    source_vlan = args.source_pod + 20

    source_text = source_path.read_text(encoding="utf-8")
    template_text = build_template(source_text, source_vlan)

    if args.template_out:
        template_path = Path(args.template_out)
        template_path.parent.mkdir(parents=True, exist_ok=True)
        template_path.write_text(template_text, encoding="utf-8")

    env = Environment(autoescape=False)
    template = env.from_string(template_text)

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    rendered_count = 0
    for pod in range(args.pod_start, args.pod_end + 1):
        pod_vlan = pod + 20
        rendered = template.render(pod_num=pod, pod_num_padded=f"{pod:02d}", pod_vlan=pod_vlan)
        out_name = f"POD-{pod:02d}-{day_label}.cfg"
        (output_dir / out_name).write_text(rendered, encoding="utf-8")
        rendered_count += 1

    print(
        f"Rendered {rendered_count} files into {output_dir} from {source_path.name} "
        f"using source VLAN {source_vlan}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
