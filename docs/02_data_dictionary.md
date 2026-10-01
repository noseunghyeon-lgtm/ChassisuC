# 원격 차량 제어 Top StateMachine — 데이터 딕셔너리

> Stateflow 차트의 입력(Input)·출력(Output)·로컬(Local)·파라미터(Parameter)·상수(Constant) 정의.
> 확정값은 실수치, 미확정은 `[TBD]` + 소관으로 표기하며 임의 수치를 넣지 않는다.
> 평가 주기: **10 ms** (제동 제어 루프 틱, 문서 §2).

---

## 1. 상태 열거형 (Enum: `VehState`)

| 이름 | 값 | 비고 |
| --- | --- | --- |
| `SLEEP` (S0) | 0 | |
| `MANUAL` (S1) | 1 | 유인 수동 주행 |
| `REMOTE_READY` (S2) | 2 | 원격 준비·대기 |
| `REMOTE_ACTIVE` (S3) | 3 | 원격 주행 |
| `AEBS` (S4) | 4 | AEBS 제동 개입 |
| `SAFE_STOP` (S5) | 5 | Heartbeat 상실 |
| `FAULT_SAFE` (S6) | 6 | 치명 고장 |
| `INIT` | **255** | ⚠️ TBD_INIT_ENCODING — CAN §2.2 (§10) 확정 시 교체 |

---

## 2. 입력 (Inputs) — 모듈/센서 → 상태 머신

| 이름 | 타입 | 단위/범위 | 의미 | 출처 |
| --- | --- | --- | --- | --- |
| `ig_key` | enum `IgKey` | OFF/ON/START | 키 위치 | 운전자 입력 (§12) |
| `wake_source` | boolean | 0/1 | Wakeup 트리거 | 「전원/Wake-up」 |
| `heartbeat_ok` | boolean | 0/1 | **원격(명령) Heartbeat** 정상 수신 — Control Computer | Control Computer/RS |
| `heartbeat_age_ms` | uint16 | ms | 마지막 유효 원격 Heartbeat 경과시간 → S5 판정 | 통신 스택 |
| `video_hb_ok` | boolean | 0/1 | **영상 Heartbeat** 정상 수신 — Video Streaming Computer. 상실 시 **경고만(상태천이 없음)** | Video Streaming Computer |
| `vc_net_level` | uint8 | 0~10 | **통신 네트워크 레벨** (CAN). 0~1=Stop(S5), 2~4=Degradation(S3_Degraded), 5~10=정상(S3_Normal) ✅확정 | VC(영상컴퓨터)/CAN. 판단로직 Ideation 예정(C18) |
| `ttc_s` | single | s | Time-To-Collision | AEBS (SRS-SYS-003) |
| `fault_critical_confirmed` | boolean | 0/1 | **치명 고장 확정** 신호 | 「진단」 §4 |
| `fault_suspect` | boolean | 0/1 | 치명 고장 **의심**(상태 불변, 명령제한) | 「진단」 §4 |
| `fault_threatens_control` | boolean | 0/1 | 고장이 운전자 제어 위협(캠 고착 등) | 「안전」 (§6-2) |
| `estop_active` | boolean | 0/1 | E-Stop 작동 | 「안전」 (우선순위 0) |
| `interlock_ok` | boolean | 0/1 | ⚠️ **LEGACY** — "인터록 4조건" 뭉침. 아래 6조건 AND(`arm_*`)로 **대체**. §4 원문(4조건) vs 다이어그램(6조건) 불일치 → 정본 확정 필요 (점검표 M01) | §4 T05 |
| `actuators_neutral` | boolean | 0/1 | 전 조작기 중립 | §4 T07 |
| `first_valid_cmd` | boolean | 0/1 | 첫 유효 원격명령 수신 | §4 T07 |
| `mode_req` | enum `ModeReq` | NONE/TO_S1/TO_S2/TO_S3 | 모드 전환 요청 | 「원격/수동 전환」 |
| `vehicle_speed` | single | km/h | 차속 | 차량 |
| `pedal_pos` | single | % (0~100) | 가속/제동 페달 위치 | §4 캠 정합 |
| `cam_at_origin` | boolean | 0/1 | 제동 캠 원점 복귀 완료 | §4 T06 |
| **— S1→S2 진입 6조건 (interlock, 모두 AND) —** | | | **다이어그램 「S1→S2 진입 조건 — 6개 전부 AND」** | |
| `arm_rs_mutual_auth` | boolean | 0/1 | ① RS 상호인증 성공 | SRS-SYS-013 |
| `arm_rmc_2stage` | boolean | 0/1 | ② Remote Panel(RMC) 2단 조작 완료 | SRS-SYS-018 ⚠️ Q-56: 현 패널 토폴로지로 1단 감지핀 없음 |
| `arm_speed_zero` | boolean | 0/1 | ③ 차속 0 | SRS-SYS-006 |
| `arm_brake_pedal` | boolean | 0/1 | ④ 브레이크 답력 확인 | SRS-SYS-005 |
| `arm_brake_remote_set` | boolean | 0/1 | ⑤ 브레이크 원격 설정 완료 | SRS-SYS-013 |
| `arm_gear_park` | boolean | 0/1 | ⑥ 기어 P | 다이어그램(SRS 미인용) |
| `gear_ready` | boolean | 0/1 | 기어계통 준비완료(§12-1 2~6) | Chassis uC |
| `selftest_done` | boolean | 0/1 | INIT 자기진단 완료 | SRS-SYS-039 |
| `dtc_cleared` | boolean | 0/1 | DTC 클리어 완료(S6 이탈) | SRS-SYS-037 |

---

## 3. 출력 (Outputs) — 상태 머신 → CAN/모듈

| 이름 | 타입 | 의미 | 발행 |
| --- | --- | --- | --- |
| `veh_state` | enum `VehState` | 현재 발행 상태 | `Chassis uC Status1` (10ms) |
| `veh_state_code` | uint8 | 발행 코드값(0~6, INIT=255) | VEH_STS.SystemState |
| `dual_s4s5_flag` | boolean | S4+S5 동시성립 플래그 | ⚠️ TBD_DUAL_FLAG_BIT — CAN §2.2 |
| `brake_req_src_state` | single | 상태머신이 요구하는 제동량 | → 「제동 명령 중재」 |
| `remote_cmd_lock` | boolean | 원격 입력 차단 여부 | S6/INIT 등 |
| `fault_reason_code` | uint16 | 천이 실패/고장 사유 코드 | DTC 연계 |
| `sw_defect_dtc` | boolean | 금지천이 시도 등 SW 결함 DTC | §7 |
| `video_hb_warn` | boolean | **영상 HB 상실 경고등** → 원격 스테이션 HMI (상태천이 없음) | → Control Computer/RS HMI |
| `speed_limit_active` | boolean | **속도 제한 활성** (S3_Degraded) | → 가속/제동 제어 |
| `speed_limit_value` | single | 제한 속도값 = **10 km/h** (`DEGRADED_SPEED_LIMIT`) ✅확정 | Degradation 시 적용 |
| `degraded_led_blink` | boolean | **Degradation LED 점멸** → 원격 스테이션 / 내부 LED | → RS HMI / 차량 LED |

---

## 4. 로컬 변수 (Local)

| 이름 | 타입 | 의미 |
| --- | --- | --- |
| `prev_state_before_s4` | enum `VehState` | S4 진입 직전 상태 보관 (§6-4 복귀용) |
| `heartbeat_timer_ms` | uint16 | Heartbeat 미수신 누적 시간 |
| `fault_debounce_cnt` | uint16 | 치명 고장 확정 디바운스 카운터 |
| `tick_overrun` | boolean | 10ms 틱 지연 감지 (§8) |
| `state_integrity_ok` | boolean | 상태변수 이중화(정·역 보수) 비교 결과 |
| `transition_log` | struct[N] | 천이 이력(시각·사유·요청원) (§8, SRS-SYS-040) |

---

## 5. 파라미터 · 타이머 · 상수 (§5)

| 이름 | 값 | 단위 | 출처 / 상태 |
| --- | --- | --- | --- |
| `TICK_MS` | 10 | ms | 문서 §2 (확정) |
| `HEARTBEAT_TIMEOUT_MS` | 400 | ms | SRS-SYS-007 (확정) |
| `AEBS_BRAKE_TTC_S` | 0.8 | s | 정본 §3.3 (확정) |
| `AEBS_WARN_TTC_S` | 2.0 | s | 정본 §3.3, **상태천이 없음**·HMI 경고만 |
| `TWO_STAGE_TIMEOUT_S` | 3 | s | SRS-SYS-018 ⚠️ 현 패널 토폴로지로 성립 불가 (Q-56) |
| `INIT_ENCODING` | 255 | — | ⚠️ **TBD** — CAN §2.2 (§10) |
| `FAULT_DEBOUNCE_N` | `[TBD]` | 틱 | ⚠️ **TBD** — SRS-SYS-038 / 「진단」 §4 |
| `FAULT_DEBOUNCE_T` | `[TBD]` | ms | ⚠️ **TBD** — SRS-SYS-038 / 「진단」 §4 |
| `STANDSTILL_SPEED` | `[TBD]` | km/h | ⚠️ **TBD** — 「기어 변속 판단」 |
| `S0_ENTRY_DELAY` | `[TBD]` | ms | ⚠️ **TBD** — 「전원/Wake-up」 |
| `NET_LEVEL_STOP_MAX` | 1 | — | Net Level 0~1 → S5(Stop) |
| `NET_LEVEL_DEGRADED_MAX` | 4 | — | Net Level 2~4 → Degradation |
| `NET_LEVEL_NORMAL_MIN` | 5 | — | Net Level 5~10 → 정상(S3_Normal) ✅확정 |
| `DEGRADED_SPEED_LIMIT` | 10 | km/h | Degradation 최대속도 ✅확정 |
| `DEGRADED_LED_BLINK_HZ` | `[TBD]` | Hz | ⚠️ **TBD** — LED 점멸 주기 |
| `LOG_DEPTH_N` | `[TBD]` | 개 | 천이 이력 깊이 (SRS-SYS-040) |

### 5.1 추가 미해결 (이번 자료 반영)

| 항목 | 영향 | 소관 |
| --- | --- | --- |
| **Q-76 조향 거동** | S5·S6 의 Steering Control 동작이 "⚠ Q-76 종속"으로 매트릭스에 표기됨 — 통신 두절/치명고장 시 조향을 "마지막 각 유지"로 둘지 미확정 | Q-76 (조향 설계) |
| **S3 추종의 차속 0 조건** | 매트릭스 S3 Gear 가 "원격 기어 명령 추종(**차속 0 조건 만족 시에만**)" — 주행 중 기어 변경 금지 조건이 데이터로 미정의 | 「기어 변속 판단」 |
| **GL-\* 릴레이 정합** | S1 Gear 설명 "실렉터→Chassis uC→릴레이→GL-\*" — 릴레이 신호 세부 미정의 (§12-1 5단계와 연계) | §12-1 / Chassis uC |

---

## 6. 보조 열거형

**`IgKey`**: `IG_OFF`=0, `IG_ON`=1, `IG_START`=2
**`ModeReq`**: `REQ_NONE`=0, `REQ_TO_S1`=1, `REQ_TO_S2`=2, `REQ_TO_S3`=3

---

## 7. 데이터 흐름 요약

```
[입력]                          [상태머신 10ms]                 [출력]
heartbeat_ok/age ──┐                                    ┌──> veh_state / _code
ttc_s ─────────────┤                                    ├──> dual_s4s5_flag
fault_* ───────────┤──> [우선순위 평가 §3] ──> [천이] ──┤──> brake_req_src_state
estop_active ──────┤     0:E-Stop(TBD)                   ├──> remote_cmd_lock
mode_req ──────────┤     1:S6  2:S5  3:S4  4:모드         ├──> fault_reason_code
arm_* (6조건 AND) ─┘                                    └──> sw_defect_dtc
neutral/first_cmd ─> (S2→S3)
video_hb_ok ───────> [경고 로직, 천이 없음] ──────────────> video_hb_warn
```

### 7.1 상태천이를 유발하지 않는 대응 (HMI 경고 전용)

아래 신호는 **상태를 바꾸지 않고** 경고/제한만 수행한다. 「안전」 §2 대응표 성격(상태 불변 대응).

| 입력 | 대응 | 출력 | 성격 |
| --- | --- | --- | --- |
| `video_hb_ok=0` (영상 HB 상실) | 원격 스테이션 경고등 | `video_hb_warn` | 천이 없음 |
| `ttc_s <= AEBS_WARN_TTC_S` (2.0s) | AEBS 경고 (HMI) | (경고) | 천이 없음 (정본 §3.3) |
| `fault_suspect=1` (고장 의심) | 원격 명령 제한 | — | 천이 없음 (§6-3) |
```
