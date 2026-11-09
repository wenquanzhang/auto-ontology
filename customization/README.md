# 自定义分支：Qwen3.8-Flash / 阿里云百炼适配

本目录记录本 fork 相对于 NVIDIA 上游的本地定制，以及**长期可持续同步上游 main** 的分支方案。
上游仓库不接受外部 PR（`CONTRIBUTING.md`），因此定制只保留在自己的 fork 中，通过定期合并上游来跟进。

## 1. 分支拓扑

```
upstream  https://github.com/NVIDIA/auto-ontology.git   (只读，禁止 push)
   └── main                     上游官方主线，持续更新

origin    https://github.com/<YOUR-ACCOUNT>/auto-ontology.git  (可写)
   ├── main                     upstream/main 的纯镜像，永不放自定义提交
   ├── custom/qwen-dashscope    长生命周期自定义分支 ← 日常使用的分支
   └── tag upstream-base/2026-11-09
                                本次定制的基线（c447003f），用于度量与回退
```

约定：

- `origin/main` 只做快进镜像，**不在上面直接提交**。这样任何时刻 `git diff origin/main..custom/qwen-dashscope` 都能精确看到"我们改了什么"。
- 所有定制提交只落在 `custom/qwen-dashscope`。该分支**永不删除、永不 force-push**（除非团队一致同意变基）。
- 用 `merge` 而不是 `rebase` 合并上游：保留冲突解决的历史，且不需要强推。
- 每次同步前打一个 `upstream-base/<日期>` tag，便于回答"当前基于上游哪个版本"。

## 2. 本次定制内容

| 文件 | 改动 | 与上游冲突的概率 |
|---|---|---|
| `auto_ontology/utils/llm_invoke.py` | `_build_client()` 按 `base_url` 识别 DashScope 并走 `ChatOpenAI`；百炼分支不传 `max_tokens`、传 `temperature=0` 与 `enable_thinking=false` | 高（LLM 客户端是活跃改动区） |
| `auto_ontology/utils/embedding.py` | 新增 `dimensions` 字段与 `__post_init__`；按端点切换 `text_type` / NVIDIA `input_type` 私有字段；百炼批量与并发默认值 | 中 |
| `auto_ontology/utils/rerank.py` | `_ranking_url()` / `_scores()` 增加 `/reranks`（DashScope 复数路径）判定 | 低 |
| `customization/` | 本文档、环境变量样例、同步脚本 | 无（新增目录，上游不会碰） |

设计原则：**改动全部由端点字符串驱动，不写死模型名，不改上游默认值**。回退时只需改 `.env`，无需回滚代码；
将来若上游原生支持 OpenAI 兼容端点，可以整批丢弃本分支的代码改动。

## 3. 配置（不入库）

`.env` 已被 `.gitignore` 忽略。需要的 12 个字段见 `customization/env.qwen-dashscope.example`，
**复制后填入真实 Key，切勿提交**。四个 triplet 缺任一字段都会回落到 `DEFAULT_MODELS_*`（NVIDIA），
出现"一半打百炼、一半打 NVIDIA"的隐蔽故障。

维度约束：`vdb/postgres.py` 把向量列定义为 `halfvec(2048)`。百炼 `text-embedding-v4` 默认 1024，
必须显式 `dimensions=2048`（代码已通过 `__post_init__` 自动补）。**更换 embedding 模型后必须重建向量库**：

```
POST /semantic/reset            # 删除语义节点与语义层向量，并触发全量重编
重启 ingestion-service          # DataScheduler 启动轮会用新模型重建 data_objects_layer
```

## 4. 同步上游的标准流程

推荐频率：每月一次，或上游发布重要版本时。可先用脚本只看差异：

```bash
./customization/sync-upstream.sh --check
```

正式同步：

```bash
# 1. 确认工作区干净，并记录当前基线
git status --short
git tag upstream-base/$(date +%Y-%m-%d) upstream/main

# 2. 镜像主线
git fetch upstream
git checkout main
git merge --ff-only upstream/main
git push origin main

# 3. 合并进自定义分支
git checkout custom/qwen-dashscope
git merge main          # 或 ./customization/sync-upstream.sh --merge

# 4. 解决冲突（见下节）后，跑验证清单（第 5 节）

# 5. 推送
git push origin custom/qwen-dashscope
```

也可以直接 `git merge upstream/main`，省略本地 `main` 镜像；保留镜像的好处是随时能比较。

## 5. 每次同步后的验证清单

1. `python -c "from auto_ontology.utils.model_config import resolve; ..."` 确认四个 triplet 仍指向百炼。
2. `get_embed_params().dimensions == 2048`，`_ranking_url()` 命中 `/reranks`。
3. 一次真实的 `with_structured_output`（任取 `semantic/models.py` 中的 schema）→ 200 且可解析。
4. 一次真实的 `embed_texts(..., "query")` → 返回 2048 维；一次 `rerank_hits()` → 分数有限。
5. 触发一次增量语义编译，确认日志无 `Unexpected error processing table`。
6. 若上游改了 `vdb` 维度、embedding 协议或 `semantic/models.py` 的 schema，需要重新评估第 2、5 项。

**若上游在这三个文件里做了重构**：优先把我们的逻辑迁移到新结构上，而不是保留旧代码；
每次合并冲突的解决方式记在 `customization/CHANGELOG.md`，便于下次判断。

## 6. 冲突热点与处理原则

上游最可能改动 `llm_invoke.py`（模型默认值、重试、结构化输出方法）。处理顺序：

1. 先读上游新版本的函数签名与分支条件，判断它是否已经原生支持 OpenAI 兼容端点；
2. 若已支持 → **删除我们的分支代码**，只保留 `.env` 配置和文档；
3. 若未支持 → 保留"按 base_url 判定"的最小改动，把上游新增的参数一并合入 `kwargs`；
4. `embedding.py` 的 `__post_init__` 与 `embed_texts()` 两处要一起看，避免上游新增字段被我们的 `request` dict 丢失；
5. `rerank.py` 只需保证 `/reranks` 仍被识别为 v1 协议。

## 7. 回退

- 只回退模型：恢复 `.env` 的 12 个字段为 NVIDIA 值，并**按 NVIDIA 模型重建向量库**（`POST /semantic/reset` + 重启 ingestion）。代码无需改动。
- 回退代码：`git revert <commit>` 或 `git diff main..custom/qwen-dashscope > /tmp/patch` 后在新分支上重放。
- 数据库快照位置（本机，不入库）：`../.auto-ontology-backup/`。

## 8. 明确不入库的内容

`.env`、任何含 API Key 的文件、数据库 dump、Docker 构建状态目录、本地临时文件。
本目录的 `env.qwen-dashscope.example` 只有占位符。
