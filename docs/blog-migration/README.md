# Jenkins 部署文档 → blog `_posts` 迁移产物

本目录是把仓库内 [`docs/deployment/`](../deployment/) 下的 Jenkins 部署文档，
按 Jekyll `_posts` 规范转换后的成品，目的地是另一个仓库：

> https://github.com/20083017/20083017.github.io（`master` 分支）

由于 Copilot 任务沙箱只能改动当前仓库 `20083017/jenkins-cli`，无法直接向 blog
仓库推送或开 PR，因此先把转换好的文件落到这里，由你（或后续任务）一次性同步。

## 产物结构

```
docs/blog-migration/
├── _posts/
│   └── jenkins/                       # ← Jenkins 架构目录（Jekyll 仍按 _posts 平铺识别，子目录仅用于物理归类）
│       ├── 2026-04-26-jenkins-deployment-overview.md
│       ├── 2026-04-26-jenkins-proxy-and-lb-primer.md
│       ├── 2026-04-26-jenkins-topology.md
│       ├── 2026-04-26-jenkins-design.md
│       ├── 2026-04-26-jenkins-deploy-aliyun-ack.md
│       ├── 2026-04-26-jenkins-deploy-idc-lan.md
│       ├── 2026-04-26-jenkins-checklist.md
│       └── 2026-04-26-jenkins-faq.md
├── assets/
│   └── jenkins/
│       └── intake-template.yaml       # 不是文章，作为附件资源
└── convert.py                         # 重新生成全部产物的脚本
```

每篇 post 的 Front Matter：

```yaml
---
layout: post
title: "..."
date: 2026-04-26 10:00:00 +0800
categories: [jenkins, 架构]
tags: [jenkins, 架构, ...]
description: "..."
slug: jenkins-xxx
---
```

跨文档链接已统一改写为 Jekyll Liquid 标签 `{% post_url 2026-04-26-jenkins-xxx %}`，
对 `intake-template.yaml` 的引用改写为 `/assets/jenkins/intake-template.yaml`。
这样不依赖目标 blog 仓库的 `permalink` 配置。

## 同步到 blog 仓库的步骤

在你本机执行（假设两个仓库的本地路径如下，按需替换）：

```bash
SRC=~/work/20083017/jenkins-cli/docs/blog-migration
DST=~/work/20083017/20083017.github.io

cd "$DST"
git checkout master
git pull --ff-only origin master
git checkout -b chore/migrate-jenkins-deployment-docs

mkdir -p _posts/jenkins assets/jenkins
cp "$SRC"/_posts/jenkins/*.md            _posts/jenkins/
cp "$SRC"/assets/jenkins/intake-template.yaml assets/jenkins/

git add _posts/jenkins assets/jenkins
git commit -m "docs(jenkins): migrate deployment guides to _posts/jenkins"
git push -u origin chore/migrate-jenkins-deployment-docs

# 然后在 GitHub UI 或 gh 上开 PR：
gh pr create --base master \
  --title "docs(jenkins): migrate deployment guides to _posts/jenkins" \
  --body "Migrated from 20083017/jenkins-cli docs/deployment. See PR in source repo for details."
```

## 校验建议

1. 在 blog 仓库根目录起本地 Jekyll：`bundle exec jekyll serve`，访问 `/jenkins/`
   或 `/categories/jenkins/`（取决于你的 `_config.yml` 与主题），确认 8 篇文章可见。
2. 点开"总览"那篇，逐一点击文档地图里的链接，确认 `{% post_url ... %}` 渲染后
   都不是 404。
3. 点开 `intake-template.yaml` 链接，确认能下载到 YAML。

## 重新生成

如果之后又改了 `docs/deployment/` 下的文档，只需在本仓库根目录跑：

```bash
python3 docs/blog-migration/convert.py
```

会按相同规则覆盖生成所有产物。

## 注意事项

- 我**没有**删除 `docs/deployment/` 原始文件——`jk` CLI 自身的部署手册仍然留在
  本仓库里，blog 只是发布镜像。如果你希望本仓库改用"Source-of-truth 在 blog"
  的模式，可以再起一个任务专门做删除/重定向。
- 文章日期统一用 `2026-04-26`（执行日）。如果需要按文档真实创建日，可以在
  `convert.py` 的 `MAPPING` 里逐项指定 `date`。
- `categories: [jenkins, 架构]` 中含中文。多数 Jekyll 主题没问题，但如果你的
  主题对 category URL 做了 slugify，可能渲染成 `/jenkins/%E6%9E%B6%E6%9E%84/`。
  介意可以把第二个 category 改成 `architecture`。
