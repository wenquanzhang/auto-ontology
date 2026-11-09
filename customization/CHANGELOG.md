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

## 后续同步时的检查项

- 上游若原生支持 OpenAI 兼容端点 → 删掉 `llm_invoke.py` 的 DashScope 分支。
- 上游若改动 `halfvec` 维度 → 同步 `_DASHSCOPE_DIMENSIONS` 并重建向量库。
- 上游若改动 `semantic/models.py` 的 schema → 重跑严格结构化输出验证。
