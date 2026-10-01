# 상태 카드 (State Cards) — 상태 중심 뷰

> 전이표(`01`)·서브시스템 매트릭스(`04`)·데이터(`02`)를 **상태별로 재조립**한 뷰.
> 전이표(01)=전이 중심(구현·검증용), 본 문서=상태 중심(리뷰·이해용). 둘은 상호 교차검증.
> 명칭은 명칭 사전(`00_glossary.md`) 정본을 따른다.
>
> **구성:** 각 상태 = H2 섹션. 하위 4블록(정의 / 할 일 / 진입 / 이탈) + 필요시 금지·미해결.
> 진입/이탈 **둘 다** 기재(각 카드 자기완결). 같은 천이가 두 카드에 중복 등장하며, 수정 시 양쪽 반영.

---

## S0 — Sleep (`SLEEP`, CAN=0)

**상태 정의:**
IG-OFF. 상시전원 대상만 생존하고 나머지는 무여자. 암전류 관리 구간.

**해당 State에서 해야 할 일 (서브시스템 동작):**

| 서브시스템 | 동작 |
| --- | --- |
| Brake Actuator (BA) | 무여자, 캠 원점 |
| Gear (GS/GA/GL) | 마지막 위치 유지. IG-OFF 시퀀스 완료 후 **P→N** |
| Accel Control Unit | 순정 직결 |
| Steering Control Unit (SU) | 순정 직결 |
| FSM uC | OFF |
| 발행 | `veh_state_code = 0` |

**진입 조건 (들어오는 천이):**

| From | 조건 (Guard) | 비고 |
| --- | --- | --- |
| S1 | `ig_key == IG_OFF` | **S0 진입은 S1에서만** (§6-5). S2·S3 는 S2→S1 경유 후 |
| S6 | IG-OFF 재기동 + `dtc_cleared` | S6 비가역 이탈 경로 |

**이탈 조건 (나가는 천이):**

| To | 조건 (Guard) | 비고 |
| --- | --- | --- |
| INIT | `wake_source \|\| ig_key == IG_ON` | Wakeup (T01) |

**미해결:** `S0_ENTRY_DELAY`(진입 지연) `[TBD]` — 「전원/Wake-up」.

---

## S1 — Manual (`MANUAL`, CAN=1)

**상태 정의:**
운전자 탑승 수동 운전. 원격 액추에이터(제동·가속·조향)는 무여자 또는 백드라이브 허용.
예외 — 순정 레버(GL) 철거로 Chassis uC·변속기어릴레이(GL Relay)는 **여자 유지** (§1.3).

**해당 State에서 해야 할 일 (서브시스템 동작):**

| 서브시스템 | 동작 |
| --- | --- |
| Brake Actuator (BA) | 무여자, 운전자 페달 직접 조작 (답력 규정치 이하) |
| Gear (GS/GL Relay/GL) | 운전자 GS 조작 → Chassis uC → GL Relay → **GL 활성** (순정 레버 철거로 우회 불가, §1.3) |
| Accel Control Unit | 순정 직결 |
| Steering Control Unit (SU) | 순정 직결 |
| FSM uC | 운전자 조작 가능 |
| 발행 | `veh_state_code = 1`, `remote_cmd_lock = false` |

**진입 조건 (들어오는 천이):**

| From | 조건 (Guard) | 비고 |
| --- | --- | --- |
| INIT | `selftest_done && gear_ready` | 자기진단 완료 (T02). 실패처리 `[TBD]` §12-3 |
| S2 | `mode_req == REQ_TO_S1 && cam_at_origin` | 원격 해제 (T06). 캠 원점 복귀 실패 시 무여자 금지 |
| S4 | AEBS 해제 && 직전상태 S1 | AEBS 복귀 (T12) |

**이탈 조건 (나가는 천이):** *(우선순위 순 — 위가 먼저 평가)*

| To | 조건 (Guard) | 우선순위 | 비고 |
| --- | --- | --- | --- |
| S6 | `fault_critical_confirmed \|\| fault_threatens_control` | 1 | 유인 S6 — 최대제동 **금지**, 원격잠금+경고 ⚠️정책 TBD(§6-2) |
| S4 | `ttc_s < AEBS_BRAKE_TTC_S` | 2 | AEBS 개입 (T11). 직전상태=S1 보관 |
| S2 | `interlock_ok(6조건 AND) && mode_req == REQ_TO_S2` | 3 | 원격 진입 (T05). 6조건: `arm_*` |
| S0 | `ig_key == IG_OFF` | 4 | IG-OFF (T04). S0 진입은 S1에서만 |

**금지 천이:** (해당 없음 — S1 은 S3 로 직접 못 감, S2 경유)

**미해결:** 유인 S6 대응정책(C03/M04), INIT→S1 실패처리(C08).

---

## S2 — Remote-Armed (`REMOTE_ARMED`, CAN=2)

**상태 정의:**
RS 인증 완료·액추에이터 여자 완료. 아직 원격 명령을 수용하지 않는 **대기(무장)** 상태.
무인 모드. **유일한 원격 재진입 관문** — S3 이탈도 S4·S5 해제도 전부 S2 를 거친다.

**해당 State에서 해야 할 일 (서브시스템 동작):**

| 서브시스템 | 동작 |
| --- | --- |
| Brake Actuator (BA) | 여자, **위치 0 유지**, 제동 명령 미수용 |
| Gear (GS/GA) | 여자. **기어 변경 명령 거부** |
| Accel Control Unit | 0 고정 |
| Steering Control Unit (SU) | **중립 유지** |
| FSM uC | 대기, 방수총 방향 조종 가능 |
| Remote Panel (RP) | 2단 조작 수신(S2→S3 진입조건) |
| 발행 | `veh_state_code = 2` |

**진입 조건 (들어오는 천이):**

| From | 조건 (Guard) | 비고 |
| --- | --- | --- |
| S1 | `interlock_ok(6조건 AND) && mode_req == REQ_TO_S2` | 원격 진입 (T05). 캠 위치 정합 포함 |
| S3 | `mode_req == REQ_TO_S2 && vehicle_speed <= STANDSTILL_SPEED` | 세션 종료 (T08). 차속0 미달 시 S3 유지 |
| S5 | `heartbeat_ok && vehicle_speed <= STANDSTILL_SPEED` | 통신 복구 (T10). **S5→S3 직접 금지** |
| S4 | AEBS 해제 && 직전상태 S2 또는 S3 | AEBS 복귀 (T12). 직전 S3 이어도 S2 로 (§6-4) |

**이탈 조건 (나가는 천이):** *(우선순위 순)*

| To | 조건 (Guard) | 우선순위 | 비고 |
| --- | --- | --- | --- |
| S6 | `fault_critical_confirmed` | 1 | 치명고장 확정 (T13) |
| S5 | `heartbeat_age_ms > HEARTBEAT_TIMEOUT_MS` | 2 | HB 400ms 초과 (T09) |
| S4 | `ttc_s < AEBS_BRAKE_TTC_S` | 3 | AEBS 개입 (T11). 직전상태=S2 보관 |
| S3 | `actuators_neutral && first_valid_cmd` | 4 | 원격 추종 개시 (T07). 중립 미확인 시 금지 |
| S1 | `mode_req == REQ_TO_S1 && cam_at_origin` | 5 | 원격 해제 (T06) |

**미해결:** RP 2단 조작 핀 부재(C07/Q-56), STANDSTILL_SPEED(C05).

---

## S3 — Remote-Active (`REMOTE_ACTIVE`, CAN=3) — 서브상태 Normal/Degraded

**상태 정의:**
원격 명령 추종 중. 정상 원격 주행 상태. 무인 모드.
**통신 네트워크 레벨(`vc_net_level`, 0~10)에 따라 서브상태 분기:**
- `S3_Normal` (net 5~10): 정상 추종
- `S3_Degraded` (net 2~4): **통신 열화 → 속도 제한 10 kph + LED 점멸**
- net 0~1 → `S5`(Stop) 로 이탈
워치독 리셋 후 **S3 로 자동 복귀하지 않는다**(§8).

**해당 State에서 해야 할 일 (서브시스템 동작):**

| 서브시스템 | S3_Normal | S3_Degraded |
| --- | --- | --- |
| Brake (BA) | 원격 추종 | 원격 추종(제한) |
| Gear (GS/GA) | 원격 추종(차속0 시*) | 동일 |
| Accel | 원격 추종 | **속도 제한 10 kph** (`speed_limit_active`) |
| Steering (SU) | 원격 추종 | 원격 추종 |
| FSM uC | 원격 추종 | 원격 추종 |
| LED | — | **점멸** (`degraded_led_blink`) |
| 발행 | `veh_state_code = 3` | `= 3` (서브상태) |

**서브상태 간 천이:**

| 전이 | 조건 | 비고 |
| --- | --- | --- |
| `S3_Normal → S3_Degraded` | `vc_net_level` 2~4 | 통신 열화 |
| `S3_Degraded → S3_Normal` | `vc_net_level` ≥ 5 | 감도 호전 시 해제 |

**진입 조건 (들어오는 천이):**

| From | 조건 (Guard) | 비고 |
| --- | --- | --- |
| S2 | `actuators_neutral && first_valid_cmd` | 유일한 진입 경로 (T07) → S3_Normal |
| S4 | (복귀 없음) | **S4→S3 직접 복귀 안 함** — 직전 S3 이어도 S2 로 (§6-4) |

**이탈 조건 (나가는 천이):** *(우선순위 순)*

| To | 조건 (Guard) | 우선순위 | 비고 |
| --- | --- | --- | --- |
| S6 | `fault_critical_confirmed` | 1 | 치명고장 확정 (T13) |
| S5 | `vc_net_level <= 1` \|\| `heartbeat_age_ms > HEARTBEAT_TIMEOUT_MS` | 2 | **Stop**: net 0~1 또는 HB 초과 (T09) |
| S4 | `ttc_s < AEBS_BRAKE_TTC_S` | 3 | AEBS 개입 (T11). 직전상태=S3 보관 |
| S2 | `mode_req == REQ_TO_S2 && vehicle_speed <= STANDSTILL_SPEED` | 4 | 세션 종료 (T08). 차속0 미달 시 S3 유지 |

**금지 천이:** `S3 → S1` 직접 **금지** (반드시 S2 경유, §7). 시도 시 SW결함 DTC.

**미해결:** 차속0(C05), LED 점멸주기(C17 일부), VC_Net_Level 판단로직(C18, Ideation).

---

## S4 — AEBS-Override (`AEBS_OVERRIDE`, CAN=4)

**상태 정의:**
AEBS 가 제동을 강제 점유. 원격 제동·가속 명령보다 우선. 무인 모드.
`S4`·`S5` 배타 아님 — 동시 성립 시 제동 요구는 **두 요구원의 최댓값**.

**해당 State에서 해야 할 일 (서브시스템 동작):**

| 서브시스템 | 동작 |
| --- | --- |
| Brake Actuator (BA) | **최대 제동**, 원격 제동 명령과 비교해 **큰 값 채택** |
| Gear (GS/GA) | 변경 거부, 현 위치 유지 |
| Accel Control Unit | **0 강제** |
| Steering Control Unit (SU) | 원격 명령 유지 |
| FSM uC | 영향 없음 |
| 발행 | `veh_state_code = 4`. 진입 시 `prev_state_before_s4` 보관 |

**진입 조건 (들어오는 천이):**

| From | 조건 (Guard) | 비고 |
| --- | --- | --- |
| S1 | `ttc_s < AEBS_BRAKE_TTC_S` {prev=S1} | T11 |
| S2 | `ttc_s < AEBS_BRAKE_TTC_S` {prev=S2} | T11 |
| S3 | `ttc_s < AEBS_BRAKE_TTC_S` {prev=S3} | T11 |

**이탈 조건 (나가는 천이):** *(우선순위 순)*

| To | 조건 (Guard) | 우선순위 | 비고 |
| --- | --- | --- | --- |
| S6 | `fault_critical_confirmed` | 1 | 치명고장 확정 (T13) |
| S1 | `ttc_s >= AEBS_BRAKE_TTC_S && prev == S1` | 2 | 복귀 (T12). 직전 S1 |
| S2 | `ttc_s >= AEBS_BRAKE_TTC_S && (prev == S2 \|\| prev == S3)` | 3 | 복귀 (T12). **직전 S3 이어도 S2** (§6-4) |

**미해결:** AEBS 진입소스 "임의"→S1/S2/S3 로 좁히기(M03).

---

## S5 — Comm-Loss Brake (`COMM_LOSS_BRAKE`, CAN=5)

**상태 정의:**
Heartbeat(명령 링크) 타임아웃으로 통신 단절 판정. 비상 제동 유지. 무인 모드.
`S5` 는 S2·S3 에서만 진입. 영상 HB 상실은 S5 아님(경고등만).

**해당 State에서 해야 할 일 (서브시스템 동작):**

| 서브시스템 | 동작 |
| --- | --- |
| Brake Actuator (BA) | **최대 제동 유지** |
| Gear (GS/GA) | 마지막 위치 유지 (SRS-SYS-028) |
| Accel Control Unit | **0 강제** |
| Steering Control Unit (SU) | 마지막 각 유지 ⚠️ **Q-76 종속** |
| FSM uC | 영향 없음 |
| 발행 | `veh_state_code = 5`, S4+S5 동시 시 `dual_s4s5_flag` |

**진입 조건 (들어오는 천이):**

| From | 조건 (Guard) | 비고 |
| --- | --- | --- |
| S2 | `heartbeat_age_ms > HEARTBEAT_TIMEOUT_MS` | T09 |
| S3 | `heartbeat_age_ms > HEARTBEAT_TIMEOUT_MS` | T09 |

**이탈 조건 (나가는 천이):** *(우선순위 순)*

| To | 조건 (Guard) | 우선순위 | 비고 |
| --- | --- | --- | --- |
| S6 | `fault_critical_confirmed` | 1 | 치명고장 확정 (T13) |
| S2 | `heartbeat_ok && vehicle_speed <= STANDSTILL_SPEED` | 2 | 통신 복구 (T10). **S2 경유 필수** |

**금지 천이:** `S5 → S3` 직접 **금지** (반드시 S2 경유, §7 · SRS-SYS-023).

**미해결:** Q-76 조향(C06), STANDSTILL_SPEED(C05).

---

## S6 — Fault Safe State (`FAULT_SAFE_STATE`, CAN=6)

**상태 정의:**
안전중요도 치명 등급 고장 **확정**. 제동 유지 후 전 원격 입력 차단. **비가역** 상태
(IG-OFF 재기동 + DTC 클리어로만 이탈). ⚠️ 라벨 "검출"→"확정" (M02, §6-3 디바운스).

**해당 State에서 해야 할 일 (서브시스템 동작):**

| 서브시스템 | 동작 |
| --- | --- |
| Brake Actuator (BA) | **최대 제동 후 유지** ⚠️ **유인(S1) 진입 시 차등** — 최대제동 금지(§6-2) |
| Gear (GS/GA) | 변경 금지, 현 위치 유지 |
| Accel Control Unit | **0 강제** |
| Steering Control Unit (SU) | 마지막 각 유지 ⚠️ **Q-76 종속** |
| FSM uC | 정지. **S6 공유**(Chassis uC → FSM uC) |
| 발행 | `veh_state_code = 6`, `remote_cmd_lock = true` |

**진입 조건 (들어오는 천이):**

| From | 조건 (Guard) | 비고 |
| --- | --- | --- |
| INIT | `fault_critical_confirmed` | 자기진단 중 치명고장 (T03) |
| S1 (유인) | `fault_critical_confirmed \|\| fault_threatens_control` | T14 — 최대제동 **금지** ⚠️정책 TBD |
| S2/S3/S4/S5 (무인) | `fault_critical_confirmed` | T13 — 최대제동 후 유지 |

**이탈 조건 (나가는 천이):**

| To | 조건 (Guard) | 비고 |
| --- | --- | --- |
| S0 | `ig_key == IG_OFF && dtc_cleared` | 비가역 이탈 (T15). DTC 클리어 경로 `[TBD]` |

**금지 천이:** `S6` 에서 **원격 이탈 불가** (§7). 물리적 개입(IG-OFF 재기동) 필수.

**미해결:** 유인 S6 정책(C03/M04), 디바운스 N·T(C04), Q-76(C06), DTC클리어(C10), FSM uC S6 공유 프로토콜(C14).

---

## 부록 — INIT (Initialization, CAN=255 TBD)

**상태 정의:**
IG-ON 직후 부팅 자기진단 구간. S1 도 S6 도 아니며, 통과 시 S1, 실패/시간초과 시 S6.
이 구간 **모든 원격 천이 요청 거부**(§6-1).

**해당 State에서 해야 할 일:** 기어계통 준비 시퀀스 **GA→GS→EPS**(§12-1), 자기진단(SRS-SYS-039).

**진입:** S0 → INIT (`wake_source || ig_key==IG_ON`, T01).
**이탈:** INIT→S1 (`selftest_done && gear_ready`, T02) / INIT→S6 (`fault_critical_confirmed`, T03).
**미해결:** INIT 인코딩 255(C02), INIT→S1 실패처리(C08).

