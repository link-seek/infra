# Huawei CodeArts pipelines (project `AI4test`, region `cn-north-4`)

Infra-as-code backup of pipeline definitions. Source of truth is the
CodeArts console; this directory is a versioned backup + change log.
Edit here does NOT auto-apply — apply via console or `UpdatePipeline` API.

## Pipelines

| Pipeline | ID | Purpose |
|---|---|---|
| `franka-eval-pipeline` | `bc38ad5cbfe746c8b3d542665c387204` | Franka + LIBERO sim eval with video recording (`RENDER_VIDEO=true`, `RENDER_FPS=20`), results → `obs://so101-sim-pipeline/eval/franka_codearts/`, auto power-off ECS `7f39cb83` at the end |

## Runtime variables (`franka-eval-pipeline`)

| Name | Default | Secret |
|---|---|---|
| `BENCHMARKS` | `libero_spatial` | no |
| `EPISODES_PER_TASK` | `1` | no |
| `MODEL_CONFIG` | `smolvla_franka.yaml` | no |
| `HWC_AK` / `HWC_SK` | — | **yes** (same AK as 192.168.1.41 `~/.hcloud`) |
| `RENDER_VIDEO` | `true` | no |
| `IMAGE` | `.../link-seek/so101-eval:latest` | no |
| `MODEL_CHECKPOINT` | empty | no |
| `RENDER_FPS` | `20` | no |

## Job flow

`swr-login` → `fetch-scripts` → `run-eval` → `upload-obs` →
`stop-ecs-inline` → `verdict`, on custom agent pool
(`20fb0d5cb4414739b4a25f698267c6ed`, the `jushenzhineng-0002` ECS).

## History

* 2026-10-14: first backup (`franka-eval-pipeline.json`); deleted FG
  `eval-lifecycle` + `so101-eval-lifecycle`; watchdog TIMERs already DISABLED.
* 2026-10-14: smoke run #28 COMPLETED, 4/10 on libero_spatial, videos in OBS.
