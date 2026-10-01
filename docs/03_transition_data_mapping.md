# 전이 ↔ 데이터 매핑 (Transition–Data Mapping)

> 각 상태 천이(T01~T15)가 **트리거·가드·액션**에서 사용하는 데이터 신호를 매핑한다.
> 데이터의 타입/단위/출처는 `02_data_dictionary.md`, 전이의 조건은 `01_state_transition_table.md` 참조.
> `[TBD]` 신호는 값 미확정 — 관련 가드는 확정 전까지 동작하지 않도록 설계됨(placeholder `-1`).

범례: **G**=Guard(가드/조건), **A**=Action(진입·이탈 액션), **I**=입력, **O**=출력, **L**=로컬

---

## 1. 전이별 데이터 사용표

| # | 천이 | 가드(Guard)에 쓰는 입력 | 액션(Action)에 쓰는 출력/로컬 | 미확정 |
| --- | --- | --- | --- | --- |
| T01 | `S0→INIT` | `wake_source`(I), `ig_key`(I) | `veh_state_code`(O), `remote_cmd_lock`(O) | — |
| T02 | `INIT→S1` | `selftest_done`(I), `gear_ready`(I) | `veh_state_code`(O), `remote_cmd_lock`(O) | 실패처리 `[TBD]` |
| T03 | `INIT→S6` | `fault_critical_confirmed`(I) | `veh_state_code`(O), `remote_cmd_lock`(O) | — |
| T04 | `S1→S0` | `ig_key`(I) | `veh_state_code`(O) | — |
| T05 | `S1→S2` | `interlock_ok`(I), `mode_req`(I), `pedal_pos`(I)* | `veh_state_code`(O) | — |
| T06 | `S2→S1` | `mode_req`(I), `cam_at_origin`(I) | `veh_state_code`(O), `remote_cmd_lock`(O) | — |
| T07 | `S2→S3` | `actuators_neutral`(I), `first_valid_cmd`(I) | `veh_state_code`(O) | — |
| T08 | `S3→S2` | `mode_req`(I), `vehicle_speed`(I) | `veh_state_code`(O) | `TBD_STANDSTILL_SPEED` |
| T09 | `S2/S3→S5` | `heartbeat_age_ms`(I) | `veh_state_code`(O), `brake_req_src_state`(O) | — |
| T10 | `S5→S2` | `heartbeat_ok`(I), `vehicle_speed`(I) | `veh_state_code`(O) | `TBD_STANDSTILL_SPEED` |
| T11 | `S1/S2/S3→S4` | `ttc_s`(I) | `veh_state_code`(O), `prev_state_before_s4`(L) | — |
| T12 | `S4→복귀` | `ttc_s`(I), `prev_state_before_s4`(L) | `veh_state_code`(O) | — |
| T13 | `무인→S6` | `fault_critical_confirmed`(I) | `veh_state_code`(O), `remote_cmd_lock`(O), `brake_req_src_state`(O) | — |
| T14 | `S1(유인)→S6` | `fault_critical_confirmed`(I), `fault_threatens_control`(I) | `veh_state_code`(O), `remote_cmd_lock`(O) | 유인 대응정책 `[TBD]` |
| T15 | `S6→S0` | `ig_key`(I), `dtc_cleared`(I) | `veh_state_code`(O) | DTC 클리어 경로 `[TBD]` |

\* `pedal_pos`는 T05 전이 자체의 가드는 아니나, `S1→S2` **진입 액션 시퀀스**(캠 위치 정합, §4)에서 소비된다.

---

## 2. 우선순위 평가에 쓰는 신호 (§3)

한 틱에서 여러 천이가 동시 성립할 때, 아래 신호가 `ExecutionOrder` 순으로 평가된다.

| 순위 | 결과 | 판정 신호 |
| --- | --- | --- |
| 0 | `[TBD]` E-Stop | `estop_active`(I) — 우선순위 0, 결과 상태 미정 |
| 1 | `S6` | `fault_critical_confirmed`(I) |
| 2 | `S5` | `heartbeat_age_ms`(I) > `HEARTBEAT_TIMEOUT_MS` |
| 3 | `S4` | `ttc_s`(I) < `AEBS_BRAKE_TTC_S` |
| 4 | 모드전환 | `mode_req`(I) |

> `fault_suspect`(I)는 상태를 바꾸지 않고 **원격 명령만 제한**하는 신호다(§6-3). 천이 가드가 아니라
> during 로직에서 소비된다 — 「의심」 구간은 상태 불변.

---

## 3. 상수·파라미터가 쓰이는 곳

| 상수/파라미터 | 값 | 사용 전이 |
| --- | --- | --- |
| `HEARTBEAT_TIMEOUT_MS` | 400 | T09 (S2/S3→S5) |
| `AEBS_BRAKE_TTC_S` | 0.8 | T11 (→S4), T12 (S4 해제) |
| `AEBS_WARN_TTC_S` | 2.0 | (상태천이 없음 — HMI 경고 전용) |
| `C_S0`~`C_S6` | 0~6 | 전 상태 entry (veh_state_code), T11/T12 (prev_state 비교) |
| `C_INIT` | 255 `[TBD]` | INIT entry |
| `TBD_STANDSTILL_SPEED` | -1(무효) | T08, T10 |
| `TBD_FAULT_DEBOUNCE_N` | -1(무효) | 「진단」§4 디바운스(외부), 확정 신호 소비 |
| `TBD_S0_ENTRY_DELAY` | -1(무효) | S0 진입 지연(외부 타이밍) |

---

## 4. 입력 신호별 — 어느 전이에서 소비되는가 (역인덱스)

| 입력 신호 | 소비 전이 |
| --- | --- |
| `ig_key` | T01, T04, T15 |
| `wake_source` | T01 |
| `heartbeat_ok` | T10 |
| `heartbeat_age_ms` | T09 |
| `ttc_s` | T11, T12 |
| `fault_critical_confirmed` | T03, T13, T14 |
| `fault_suspect` | (during — 상태 불변, 명령제한) |
| `fault_threatens_control` | T14 |
| `estop_active` | 우선순위 0 `[TBD]` |
| `interlock_ok` | T05 |
| `actuators_neutral` | T07 |
| `first_valid_cmd` | T07 |
| `mode_req` | T05, T06, T08 |
| `vehicle_speed` | T08, T10 |
| `pedal_pos` | T05 진입 액션(캠 정합) |
| `cam_at_origin` | T06 |
| `gear_ready` | T02 (및 INIT 서브상태 GA→GS) |
| `selftest_done` | T02 |
| `dtc_cleared` | T15 |

> **미사용 경고 없음** — 정의된 모든 입력이 최소 1개 전이/로직에서 소비된다.
> 단 `estop_active`는 우선순위 0의 결과 상태가 `[TBD]`라 현재 전이로 연결되지 않았다(자리만 확보).
