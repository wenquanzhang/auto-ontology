# 自定义改动台账

每次合并上游、或调整本地适配时追加一条。目的是下次遇到冲突时能快速判断"这段为什么存在、能不能删"。

## 2026-11-09 — 切换到阿里云百炼 Qwen3.8-Flash

- 上游基线：`c447003f`（tag `upstream-base/2026-11-09`）。
- 动机：NVIDIA `integrate.api.nvidia.com` 在国内访问出现间歇性 DNS / TLS 中断，
  导致语义编译表级静默失败；百炼同时提供 `json_schema` 严格结构化输出、
  2048 维 embedding 与 rerank，可把四个 triplet 全部国产化。
- 代码改动（3 个文件，均为"按端点分支、不改上游默认值"）：
  - `llm_invoke.py::_build_client()` — DashScope 走 `ChatOpenAI`；不传 `max_tokens`。
  - `embedding.py` — `EmbedParams.dimensions` + `__post_init__` 自动置 2048；
    `extra_body` 按端点用 `text_type` 或 NVIDIA 三件套。
  - `rerank.py` — `_ranking_url()` / `_scores()` 识别 `/reranks`。
- 配置改动：`.env` 12 个字段（不入库），样例见 `env.qwen-dashscope.example`。
- 数据改动：`POST /semantic/reset` + 重启 ingestion-service，重建两层向量库
  （`vdb.data_objects_layer` 890 行、`vdb.semantic_layer` 736 行，全部 2048 维）。
- 验证结果：72/72 表编译成功、0 表级异常、0 次 NVIDIA 端点调用；
  语义检索 Top5 余弦相似度 0.54–0.67 且语义相关；rerank 真实调用返回有限分数。
- 已知取舍：百炼 `qwen3-rerank` 仅在 `bridge_tables.py` 路径被调用，
  本轮无合适桥表，故只用真实 `rerank_hits()` 调用验证；SqlAttribute 为 0 属正常
  （无查询历史可归纳）。

## 2026-11-16 — 同步上游 main（无冲突）

- 上游基线：`c447003f` -> `62337897`（14 个提交，tag `upstream-base/2026-11-16`）。
- 流程：`git checkout main && git merge --ff-only upstream/main && git push origin main`，
  再 `git checkout custom/qwen-dashscope && git merge main`，合并提交 `fa7b085f`。
- 冲突：无。热点文件 `llm_invoke.py` / `embedding.py` / `rerank.py` 均未被上游这批提交触及；
  `customization/` 目录上游不存在同名路径。
- 上游本次主要带来：Postgres（`pg_constraint` 读取、跨 schema 外键、复合键）与 SQLite
  （隐式/大小写外键、生成列）外键解析修复；语义层增强（term families、95% 唯一性阈值、
  按数据值确认语义外键、未匹配外键列补 ColumnAttribute、自引用语义外键）；非拉丁字符
  Term 命名与 CSV 导出文件名的国际化修复；sqlglot 提取器保留无列引用源表；
  README 架构图改 Mermaid 并新增 `CODE_OF_CONDUCT.md`。
- 验证：`uv run ruff check auto_ontology/` 全部通过；
  `auto_ontology/utils/tests/test_{llm_invoke,embedding,embedding_rows,rerank,model_config}.py`
  合并前后结果一致（98 项中同样 3 项失败：`test_a_short_response_is_an_error_not_a_partial_batch`、
  `test_a_duplicated_index_is_an_error`、`test_blank_texts_are_not_sent`），
  确认是本地 `.env` 批量/并发配置下的既有问题，与本次合并无关，未修复，留给后续单独排查。

## 后续同步时的检查项

- 上游若原生支持 OpenAI 兼容端点 → 删掉 `llm_invoke.py` 的 DashScope 分支。
- 上游若改动 `halfvec` 维度 → 同步 `_DASHSCOPE_DIMENSIONS` 并重建向量库。
- 上游若改动 `semantic/models.py` 的 schema → 重跑严格结构化输出验证。
