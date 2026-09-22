# Specification Quality Checklist: core/ 与 save_data/ 审查重构

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-09-23
**Feature**: [spec.md](../spec.md)

## Content Quality

- [ ] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [ ] No implementation details leak into specification

## Notes

### 唯一的未通过项：实现细节（3 项中 2 项标为未通过）

这是**有意为之**，不是遗漏：

- 本功能是**对既有代码的重构**，不是新功能。规格若不点名 `save_data.apply_dict()`、
  `core/save_service.gd` 这类具体位置，就无法定义"改什么"，也无法在 `plan.md` 里建立任务边界。
- 上游 core 模板把"无实现细节"作为通用 Web 功能规格的默认要求；对一个 brownfield 重构套用同一条，
  会把规格压成无法执行的抽象描述。
- **没有**泄漏的：具体算法、类结构设计、拆分后的文件划分、函数签名 —— 这些全部留给 `plan.md`。

### 已完成的澄清（用户在写规格前已裁定，故无 NEEDS CLARIFICATION 残留）

| 决策 | 结论 | 影响 |
|---|---|---|
| 重构范围 | 仅 `core/` + `save_data/` | 排除 `ui/`、`entry/`、`addons/` |
| 重构深度 | 允许改存档契约与事件语义 | 触发 US2（负载契约）与 US4（版本策略） |
| 旧档兼容 | 允许不兼容，但只允许一次，且须同步修订宪法 | 触发 US4 的**MINOR 级**宪法修订先决条件（原要求保留 + 一次性例外） |

### 需要下游注意的两处硬约束

1. **US4 有阻塞性先决条件**：宪法原则 III 的修订 MUST 先完成，否则任何存档结构改动都与现行宪法冲突。
   这是 `/speckit-tasks` 排序时必须放在最前的任务。
2. **FR-001 要求基线先于改动采集**。若在采集基线前动了代码，"无回归"就无法判定，US1 会失效。

### 已知的规格边界（供 `/speckit-analyze` 复核）

- SC-007（"无 3 个以上不相关职责"）是**定性**判据，靠人工判断，不是脚本可测项 —— 已刻意如此，
  避免为它写一个脆弱的启发式检查。
- 本规格不含性能指标（Non-Goals 明确不做性能优化），因此没有帧预算相关的 SC。
