#!/usr/bin/env python3
"""Convert docs/deployment/*.md into Jekyll _posts under docs/blog-migration/.

Run from repo root:
    python3 docs/blog-migration/convert.py
"""
from __future__ import annotations

import re
import shutil
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "docs" / "deployment"
OUT_POSTS = REPO / "docs" / "blog-migration" / "_posts" / "jenkins"
OUT_ASSETS = REPO / "docs" / "blog-migration" / "assets" / "jenkins"

DATE = "2026-04-26"

# old filename -> (slug, title, description, tags)
MAPPING = {
    "README.md": (
        "jenkins-deployment-overview",
        "Jenkins + jk 平台部署文档总览",
        "Jenkins 控制器 + jk 客户端 落地参考的入口与文档地图。",
        ["jenkins", "架构", "部署", "总览"],
    ),
    "proxy-and-lb-primer.md": (
        "jenkins-proxy-and-lb-primer",
        "代理与负载均衡入门：VIP / L4 / L7 / Nginx 速记",
        "5 分钟入门 VIP、L4 LB、L7 反向代理与 Nginx 在 Jenkins 接入侧的角色。",
        ["jenkins", "架构", "网络", "负载均衡", "nginx"],
    ),
    "topology.md": (
        "jenkins-topology",
        "Jenkins 部署拓扑：通用逻辑、阿里云 ACK、本地 IDC",
        "Jenkins 控制器与 Agent 的逻辑拓扑，以及阿里云 ACK 与本地 IDC 两种落地形态。",
        ["jenkins", "架构", "拓扑"],
    ),
    "design.md": (
        "jenkins-design",
        "Jenkins 平台设计：HA / 权限 / 备份 / 网络 / 合规 / LDAP",
        "Jenkins 平台关键设计决策：高可用、RBAC、备份恢复、网络分层、合规与 LDAP 接入。",
        ["jenkins", "架构", "设计", "HA", "LDAP"],
    ),
    "deploy-aliyun-ack.md": (
        "jenkins-deploy-aliyun-ack",
        "在阿里云 ACK 上部署 Jenkins 控制器",
        "基于阿里云 ACK（Kubernetes）部署 Jenkins 控制器与 Agent 的端到端手册。",
        ["jenkins", "架构", "部署", "kubernetes", "阿里云"],
    ),
    "deploy-idc-lan.md": (
        "jenkins-deploy-idc-lan",
        "在本地 IDC 局域网部署 Jenkins（VM + Docker Compose）",
        "基于 VM + Docker Compose 在本地 IDC 落地 Jenkins 控制器的实践手册。",
        ["jenkins", "架构", "部署", "docker", "idc"],
    ),
    "checklist.md": (
        "jenkins-checklist",
        "Jenkins 上线检查清单：交付 / 安全 / 合规",
        "Jenkins 平台上线前后的交付、安全与合规检查项清单。",
        ["jenkins", "架构", "checklist", "安全", "合规"],
    ),
    "faq.md": (
        "jenkins-faq",
        "Jenkins 部署 FAQ：域名 vs IP、外置 DB、任务可见性",
        "Jenkins 部署阶段最常被问到的几个问题与建议答案。",
        ["jenkins", "架构", "faq"],
    ),
}

# old md file -> new post filename (without extension), used for link rewrite
LINK_REWRITE = {
    old: f"{DATE}-{meta[0]}" for old, meta in MAPPING.items()
}

# Special handling for intake-template.yaml (asset, not a post).
INTAKE_SRC = SRC / "intake-template.yaml"
INTAKE_DST_REL = "/assets/jenkins/intake-template.yaml"


def front_matter(slug: str, title: str, description: str, tags: list[str]) -> str:
    tags_yaml = "[" + ", ".join(tags) + "]"
    return (
        "---\n"
        "layout: post\n"
        f'title: "{title}"\n'
        f"date: {DATE} 10:00:00 +0800\n"
        "categories: [jenkins, 架构]\n"
        f"tags: {tags_yaml}\n"
        f'description: "{description}"\n'
        f"slug: {slug}\n"
        "---\n\n"
    )


LINK_RE = re.compile(r"\]\(\s*\.?/?([A-Za-z0-9_\-]+\.(?:md|yaml))(#[^)\s]*)?\s*\)")


def rewrite_links(text: str) -> str:
    def repl(m: re.Match) -> str:
        target = m.group(1)
        anchor = m.group(2) or ""
        if target == "intake-template.yaml":
            return f"]({INTAKE_DST_REL}{anchor})"
        if target in LINK_REWRITE:
            post = LINK_REWRITE[target]
            # Use Liquid post_url so it survives any permalink config.
            return "](" + "{% post_url " + post + " %}" + anchor + ")"
        return m.group(0)

    return LINK_RE.sub(repl, text)


def convert_one(src_name: str) -> Path:
    slug, title, description, tags = MAPPING[src_name]
    src_path = SRC / src_name
    raw = src_path.read_text(encoding="utf-8")

    # Drop the original H1 (first `# ...` line) since title is in Front Matter.
    lines = raw.splitlines()
    out_lines: list[str] = []
    h1_dropped = False
    for line in lines:
        if not h1_dropped and line.lstrip().startswith("# "):
            h1_dropped = True
            continue
        out_lines.append(line)
    body = "\n".join(out_lines).lstrip("\n")
    body = rewrite_links(body)

    fm = front_matter(slug, title, description, tags)
    out_path = OUT_POSTS / f"{DATE}-{slug}.md"
    out_path.write_text(fm + body + ("\n" if not body.endswith("\n") else ""), encoding="utf-8")
    return out_path


def main() -> None:
    OUT_POSTS.mkdir(parents=True, exist_ok=True)
    OUT_ASSETS.mkdir(parents=True, exist_ok=True)

    written: list[Path] = []
    for name in MAPPING:
        written.append(convert_one(name))

    # Copy intake template as asset.
    if INTAKE_SRC.exists():
        shutil.copy2(INTAKE_SRC, OUT_ASSETS / INTAKE_SRC.name)

    rel = lambda p: p.relative_to(REPO)
    print("Wrote posts:")
    for p in written:
        print(f"  - {rel(p)}")
    print(f"  - {rel(OUT_ASSETS / INTAKE_SRC.name)}")


if __name__ == "__main__":
    main()
