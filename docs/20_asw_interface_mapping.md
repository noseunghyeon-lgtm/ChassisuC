# ASW ↔ Stateflow 입력 매핑 (heading 일치)

> ASW 가 제공하는 입력 신호(9개)를 Stateflow 상태머신 입력과 대조.
> 목적: heading 일치 + 상태머신에 실제 필요한 입력 확정.

---

## 1. ASW 제공 신호 (9개) → Stateflow 대응

| ASW 신호 | 타입(접두사) | Stateflow 입력 | 매핑 | 비고 |
| --- | --- | --- | --- | --- |
| `IGN_ON` | (bool/u8) | `ig_key` 또는 `wake_source` | 🔶 **형식 다름** | ASW는 ON 단일 bit, Stateflow는 enum(OFF/ON/START) |
| `VC_Communication_Fault` | (bool) | `heartbeat_ok` | 🔶 **반전** | Fault=1 ↔ ok=0. age_ms 대체 가능성 |
| `VC_Net_Level` | u8 (0~10) | `vc_net_level` | ✅ 직결 | 이름만 대문자 차이 |
| `u8_AEBS` | u8 | `aebs_flag` | 🔶 u8→bool | AEBS==7 → true 변환 |
| `u8_Req_Remote_Mode` | u8 | `mode_req` | 🔶 매핑 | 1:Manual/2:RS → ModeReq enum |
| `u8_Req_Gear_Position` | u8 | **(명령값)** | ⚠️ **가드 아님** | 원격 주행 명령 — §2 참조 |
| `u8_Req_Brake_Position` | u8 | **(명령값)** | ⚠️ **가드 아님** | 원격 주행 명령 |
| `u16_Req_Steering_Angle` | u16 | **(명령값)** | ⚠️ **가드 아님** | 원격 주행 명령 |
| `u8_Req_Throttle_Position` | u8 | **(명령값)** | ⚠️ **가드 아님** | 원격 주행 명령 |

---

## 2. ★ 핵심 발견 — ASW 신호의 성격 구분

ASW 9개 중 상태머신이 쓰는 것은 **5개뿐**이고, `u8_Req_*` 4개는 **제어 명령값**이다:

### (A) 상태머신 입력 (천이 판정용) — 5개
`IGN_ON`, `VC_Communication_Fault`, `VC_Net_Level`, `u8_AEBS`, `u8_Req_Remote_Mode`
→ 상태머신 가드가 소비.

### (B) 원격 주행 명령값 (제어 추종용) — 4개
`u8_Req_Gear_Position`, `u8_Req_Brake_Position`, `u16_Req_Steering_Angle`, `u8_Req_Throttle_Position`
→ **상태머신 천이 조건이 아님.** S3(원격 주행)에서 **액추에이터가 추종하는 명령값**.
→ 상태머신은 "지금 명령을 따를지 말지"(S3 여부)만 정하고, 실제 명령 추종은 **제어 블록**(상태머신 밖)이 담당.
→ 단, S2→S3 "첫 유효명령"(`first_valid_cmd`)·중립확인(`actuators_neutral`) 판정의 **입력 소스**로는 쓰임.

> **결론**: `u8_Req_*` 4개는 상태머신 **입력 포트가 아니라 제어 경로**로 가야 한다.
> 상태머신엔 이들에서 **파생된 플래그**(first_valid_cmd, actuators_neutral)만 들어온다.

---

## 3. ASW 에 없는 Stateflow 입력 — 어디서 오나? (갭)

현재 Stateflow 26개 중 ASW 9개에 **대응이 없는 입력들**. 소스 확정 필요:

| Stateflow 입력 | ASW에 없음 → 소스? |
| --- | --- |
| `estop_active` | HW E-Stop + RS_E_STOP2(별도 경로). ASW 경유 아님? |
| `heartbeat_age_ms` | VC_Communication_Fault 로 대체? 아니면 전처리 산출 |
| `fault_critical_confirmed`/`suspect`/`threatens_control` | 「진단」 모듈 → ASW 경유? |
| `takeover_req` | 운전자 개입 감지 — 어느 신호로? |
| `manual_switch_req` | RS 수동전환 요청 — u8_Req_Remote_Mode 로 통합? |
| `vehicle_speed` | Chassis_Status2(순정 CAN) — ASW 경유? |
| `cam_at_origin` | BRK_Status — ASW 경유? |
| `actuators_neutral`/`first_valid_cmd` | u8_Req_* 에서 파생(전처리) |
| `arm_rs_mutual_auth`/`arm_rmc_2stage`/`arm_speed_zero`/`arm_gear_park_or_neutral` | 인터록 — 어느 신호로? |
| `gear_ready`/`selftest_done`/`init_timeout`/`dtc_cleared` | 내부/진단 |
| `wake_source` | IGN_ON 으로 통합? |

> **질문**: ASW 가 상태머신에 주는 입력이 **이 9개가 전부**인가요?
> 아니면 9개는 "원격 명령 계열"만이고, E-Stop/진단/인터록/차속 등은 **다른 인터페이스**로 들어오나요?

---

## 4. 제안 — heading 일치 방향

### 4-1. 상태머신 입력을 ASW 명칭 체계로 리네임 (대응되는 5개)
| Stateflow(현재) | → ASW 명칭 |
| --- | --- |
| `vc_net_level` | `VC_Net_Level` |
| `aebs_flag` | `u8_AEBS`(→bool 전처리) 또는 `AEBS` |
| `ig_key`/`wake_source` | `IGN_ON` 기반 재정의 |
| `heartbeat_ok` | `VC_Communication_Fault`(반전) |
| `mode_req` | `u8_Req_Remote_Mode` |

### 4-2. u8_Req_* 4개 → 제어 경로로 분리
상태머신 입력에서 빼고, **S3 추종 제어 블록**의 입력으로. 상태머신엔 파생 플래그만.

---

## 5. 확인 질문 (heading 확정용)
1. **ASW 입력이 이 9개가 전부**인가요? (E-Stop/진단/인터록/차속은 별도?)
2. `IGN_ON` — bool 단일인가요? (Stateflow enum IgKey 를 bool 로 축소?)
3. `VC_Communication_Fault` vs `heartbeat_ok`/`age_ms` — ASW가 fault bool 하나만 주나요?
4. `u8_Req_*` 4개를 **제어 경로로 분리**하는 데 동의하시나요?
5. 인터록(arm_*)·takeover·manual_switch 는 어느 ASW 신호로 들어오나요?

---

## 6. 번호 순서 매핑 (누적) — 사용자 제공분

> Stateflow 입력 #번호에 ASW 신호를 순서대로 매핑. (받는 대로 갱신)

| # | Stateflow 입력 | ASW 신호 | 상태 |
| --- | --- | --- | --- |
| 1 | `ig_key` | `IGN_ON` | 🔶 enum→bool |
| 3 | `heartbeat_ok` | `VC_Communication_Fault` | 🔶 반전 |
| 5 | `vc_net_level` | `VC_Net_Level` | ✅ |
| 6 | `aebs_flag` | `u8_AEBS` | 🔶 u8→bool |
| 14 | `manual_switch_req` | `u8_MODE_MN` | ⚠️ **확인**: 원격자 요청 vs 차량실내 Manual 스위치(K31)? |
| 15 | `mode_req` | `u8_Req_Remote_Mode` | 🔶 enum |
| 16 | `vehicle_speed` | `f_VehicleSpeed` | ✅ (single=f) |
| 17 | `pedal_pos` | `u8_APP` | ✅ (가속페달) |

**명령값(상태머신 외, 제어 경로):**
`u8_Req_Gear_Position`, `u8_Req_Brake_Position`, `u16_Req_Steering_Angle`, `u8_Req_Throttle_Position`

**미매핑 (ASW 신호 대기):**
#2 wake_source, #4 heartbeat_age_ms, #7~9 fault_*, #10 estop_active,
#11 actuators_neutral, #12 first_valid_cmd, #13 takeover_req,
#18 cam_at_origin, #19~22 arm_*, #23 gear_ready, #24 selftest_done, #25 init_timeout, #26 dtc_cleared

> ⚠️ #14 `u8_MODE_MN`: 핀맵 K31=MODE_MN(차량실내 Manual 스위치)과 동명. 원격자 수동전환(`manual_switch_req`)과
> 주체가 다를 수 있음 — 확인 필요.
