#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# 同步 NVIDIA/auto-ontology 的 main 到本 fork 的自定义分支。
# 只做 fetch / 检查 / merge，不自动 push，不自动处理冲突。
set -euo pipefail

BRANCH="custom/qwen-dashscope"
HOT_FILES=(
  "auto_ontology/utils/llm_invoke.py"
  "auto_ontology/utils/embedding.py"
  "auto_ontology/utils/rerank.py"
)

usage() {
  cat <<'EOF'
用法: ./customization/sync-upstream.sh [--check | --merge]

  --check   只 fetch upstream 并报告：领先多少提交、热点文件是否被改动、与本分支的差异
  --merge   fetch upstream，然后把 upstream/main 合并进当前检出的自定义分支
            （默认也更新本地 main 镜像；有冲突时停下来交给人工解决）
  无参数    等同 --check

remote 约定:
  upstream  https://github.com/NVIDIA/auto-ontology.git   (只读)
  origin    https://github.com/<YOUR-ACCOUNT>/auto-ontology.git
见 customization/README.md 第 4 节。
EOF
}

MODE="${1:---check}"
case "$MODE" in
  --check|--merge) ;;
  -h|--help) usage; exit 0 ;;
  *) echo "未知参数: $MODE" >&2; usage; exit 2 ;;
esac

git rev-parse --is-inside-work-tree >/dev/null
if ! git remote get-url upstream >/dev/null 2>&1; then
  echo "缺少 upstream remote，请先执行：" >&2
  echo "  git remote add upstream https://github.com/NVIDIA/auto-ontology.git" >&2
  exit 1
fi

echo "==> git fetch upstream"
git fetch upstream --prune

BASE=$(git merge-base HEAD upstream/main)
echo "==> 当前分支: $(git branch --show-current)"
echo "==> 与 upstream/main 的共同祖先: ${BASE:0:12}"
echo "==> 上游新增提交数: $(git rev-list --count HEAD..upstream/main)"
echo "==> 本分支自定义提交数: $(git rev-list --count upstream/main..HEAD)"

echo "==> 上游是否改动了本次定制的热点文件:"
CHANGED=0
for f in "${HOT_FILES[@]}"; do
  if ! git diff --quiet "$BASE" upstream/main -- "$f"; then
    echo "    [CHANGED] $f"
    CHANGED=1
  else
    echo "    [same]    $f"
  fi
done

if [ "$MODE" = "--check" ]; then
  echo "==> 检查完成，未做任何合并。"
  if [ "$CHANGED" -eq 1 ]; then
    echo "    提示：上游改动了热点文件，合并时请按 README 第 6 节处理冲突。"
  fi
  exit 0
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "工作区不干净，请先提交或 stash 后再合并。" >&2
  exit 1
fi

CURRENT=$(git branch --show-current)
if [ "$CURRENT" != "$BRANCH" ]; then
  echo "当前分支是 $CURRENT，--merge 需要在 $BRANCH 上执行。" >&2
  exit 1
fi

echo "==> 更新本地 main 镜像"
git checkout main
git merge --ff-only upstream/main
git checkout "$BRANCH"

echo "==> git merge main"
if git merge main; then
  echo "==> 合并完成。请执行 README 第 5 节验证清单，然后："
  echo "      git push origin main"
  echo "      git push origin $BRANCH"
else
  echo "==> 合并出现冲突，已停下。解决后执行 git commit。" >&2
  echo "     冲突处理原则见 customization/README.md 第 6 节" >&2
  exit 1
fi
