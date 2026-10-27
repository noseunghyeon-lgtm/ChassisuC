# 최종 Stateflow 입력 리스트 (확정) — ASW heading 일치

> 6가지 재분류 확정 반영. Stateflow 입력 = **실제 외부 입력(A)**만. 파생(B)은 전처리, 내부(C)는 로컬.
> 치명고장은 4bit 필드로 받아 컴포넌트 판별(무결성).

---

## 1. 최종 Stateflow 입력 포트 (A — 외부 입력)

| # | Stateflow 입력 | 타입 | ASW/CAN/HW 신호 | 비고 |
| --- | --- | --- | --- | --- |
| 1 | `ign_on` | boolean | `IGN_ON` | enum→bool 축소(확정 6) |
| 2 | `vc_net_level` | uint8 | `VC_Net_Level` | 0~10 |
| 3 | `vc_net_link_count` | uint8 | `VC_Net_Link_Count` | 인증 판단 |
| 4 | `vc_comm_fault` | boolean | `VC_Communication_Fault` | heartbeat 대체 |
| 5 | `aebs_flag` | boolean | `u8_AEBS` | ==7 → true |
| 6 | `mode_req` | enum ModeReq | `u8_Req_Remote_Mode` | 원격모드 요청 |
| 7 | `vehicle_speed` | single | `f_VehicleSpeed` | |
| 8 | `pedal_pos` | single | `u8_APP` | 가속페달 |
| 9 | `u8_gear_status` | uint8 | `u8_Gear_Status` | 0:P,1:L,2:2,3:3,4:NC,5:D,6:N,7:R |
| 10 | `brk_status_pos` | single | `BRK_Status.Position` | 캠 원점 판단 |
| 11 | `estop_hw` | boolean | HW ESTOP | 하드와이어 |
| 12 | `estop_can` | boolean | CAN ESTOP (RS_E_STOP2) | |
| 13 | `fault_bits` | uint8 | 4개 HW Fault (bitfield) | **bit0:Accel, bit1:Brake, bit2:GearActu, bit3:GearSel** (확정 1) |
| 14 | `u8_MODE_MN` | uint8 | `u8_MODE_MN` (K31 MODE_MN / K34 MODE_RM 전처리) | 차량 HW 수동/원격 모드값. **1:Manual 2:Remote**. (기존 bool "Manual 스위치" → uint8 모드값으로 승격) |
| 15 | `steer_intervention` | boolean | 조향 개입 감지 | takeover용(확정 2) |
| 16 | `tx_ign` | boolean | Tx IGN | selftest 판단 |
| 17 | `Chassis_Op_Mode` | uint8 | CAN `RS_Chassis_Command.Chassis_Op_Mode` (VC 송신, 4bit) | VC 운용모드. **0:Invalid 1:Manual 2:RS(Remote)**. AEBS 해제 2중화 VC 경로 |
| 18 | `s4_active` | boolean | 상태머신 S4 활성 (내부→전처리 피드백) | 재진입 latch 리셋용(S4 진입 시 초기화) |

> 명령값(제어 경로, 상태머신 외): `u8_Req_Gear/Brake/Throttle`, `u16_Req_Steering`.

---

## 2. 전처리 파생 (B) — 입력 아님, 전처리가 계산

| 파생 플래그 | 계산식 |
| --- | --- |
| `estop_active` | `estop_hw OR estop_can` (동일 레벨 OR, 확정) |
| `fault_critical_confirmed` | `fault_bits != 0` (4bit 중 하나라도) |
| `fault_component` | `fault_bits` 그대로 전달 (어느 컴포넌트 — 무결성/DTC용) |
| `actuators_neutral` | `u8_gear_status == 6(N)` |
| `cam_at_origin` | `brk_status_pos == 원점` |
| `arm_speed_zero` | `vehicle_speed <= 임계` |
| `arm_gear_park_or_neutral` | `u8_gear_status ∈ {0(P),6(N)}` |
| `arm_rs_mutual_auth` | `vc_net_link_count` 기반(연결 수립) |
| `gear_ready` | gear status Normal |
| `heartbeat_ok` | `!vc_comm_fault` |
| `selftest_done` | `tx_ign` 기반 |
| `takeover_req` | `steer_intervention OR estop_active OR (u8_MODE_MN==Manual)` (확정 2) |
| `manual_switch_req` | `u8_MODE_MN == Manual` (차량 HW Manual 위치) |
| `remote_reengage_ok` | `DetectRemoteReengage(u8_MODE_MN, Chassis_Op_Mode, reset=~s4_active)` — 2중화 Remote 재진입. 두 경로 각각 Manual 경유 후 Remote 복귀(latch) → **AND**. S4→S2 정상이탈 조건 |

---

## 3. 내부 신호 (C) — 차트 로컬
| 신호 | 처리 |
| --- | --- |
| `wake_source` | `ign_on` 에 통합 |
| `first_valid_cmd` | 원격 명령 수신 내부 판정 |
| ~~`prev_state_before_s4`~~ | **폐기** — S4 이탈은 상태복귀가 아니라 `remote_reengage_ok`(2중화 Remote 재진입)으로 S2 단일 이탈. S4→S1 없음 |

---

## 4. 제거 (X) — 확정
| 제거 | 이유 |
| --- | --- |
| `fault_suspect` | 제거(확정 1) — fault_bits OR 로 대체 |
| `fault_threatens_control` | 제거(확정 1) |
| `dtc_cleared` | **삭제**(확정 3) — S6 이탈 조건 재검토 필요(§5) |
| `arm_rmc_2stage` | 삭제(2단조작 포기) |
| `init_timeout` | 삭제(이전 확정) |
| `heartbeat_age_ms` | vc_comm_fault 대체 |
| `ig_key`(enum) | `ign_on`(bool) 로 축소 |

---

## 5. ⚠️ 파생된 영향 — 확인 필요

1. **S6 이탈 조건**: 기존 `S6→S0 = ig_key==OFF && dtc_cleared` 였는데 **dtc_cleared 삭제** →
   S6 이탈을 **IGN_OFF 만으로** 할지, 다른 조건? (정본은 "IG-OFF 재기동+DTC 클리어" 요구)
2. **치명고장 bit 필드**: `fault_bits` uint8 로 받되 S6 진입은 `!=0`. 컴포넌트별 처리(어느 걸 S6, 어느 걸 경고)가
   다르면 추가 로직 필요 — 지금은 "하나라도 Fault면 S6"로 단순화.
3. **takeover 트리거**에 estop/MN스위치 포함 — E-Stop은 이미 최우선(S6)인데 takeover(S3→S1)와
   우선순위 충돌 가능. E-Stop(0) > takeover(4)라 E-Stop이 이기므로 OK, 단 의도 확인.

---

## 6. 인터페이스 경계 — ★ 방식 1 확정

```
[ASW raw 신호] → [전처리 블록 (src/preproc)] → [Stateflow 입력 = 파생 플래그] → 가드
     ↑                                              ↑
  heading 일치 대상                            현행 유지(변경 없음)
```

- **방식 1 확정**: ASW 는 raw 신호 제공 → **전처리가 파생 플래그 계산** → Stateflow 는 깨끗한 플래그만 입력.
- **heading 일치 대상 = 전처리 블록 입력** (= ASW raw 신호). Stateflow 입력 포트가 아님.
- **Stateflow 입력/가드는 현행 유지** — 재작성 불필요.

### 6-1. 경계별 역할
| 계층 | 입력 | 출력 | 책임 |
| --- | --- | --- | --- |
| **ASW** | — | raw 신호(§1 A열의 ASW/CAN 신호) | 신호 제공 |
| **전처리** (src/preproc) | ASW raw | 파생 플래그(§2) | 변환·OR·bit판별·중립판정 |
| **Stateflow** | 파생 플래그(§2) | 상태 발행 | 상태 로직만 |

### 6-2. heading 일치 = 전처리 입력을 ASW 와 맞춤 (간소화 확정)
전처리 블록(docs/15)의 **입력 인자명**을 ASW 신호명과 일치. 신규 블록 최소화:
- `CheckHeartbeat` → `VC_Communication_Fault` (또는 Alive)
- `ArbitrateEStop(hw, vc)` → `estop_hw`, `estop_can`
- **치명고장**: 신규 블록 없음 → **`u8_HW_Fault`** 입력 하나(ASW가 4 Fault bitfield 제공).
  `fault_critical_confirmed = (u8_HW_Fault != 0)`, 컴포넌트 판별은 비트 그대로 사용.
- **중립**: 신규 블록 없음 → **`actuators_neutral = (u8_Gear_Status == 6)`** 직접 판정.
- **인터록**: `ComputeInterlock` 블록 **삭제**. arm_* 는 각 신호에서 직접
  (`arm_speed_zero=f_VehicleSpeed<=임계`, `arm_gear_park_or_neutral=u8_Gear_Status∈{0,6}`,
  `arm_rs_mutual_auth=VC_Net_Link_Count` 기반).

### 6-3. Stateflow 입력은 유지 (파생 플래그)
현행 26개 입력에서 **확정된 제거분만** 반영:
- 제거: `fault_suspect`, `fault_threatens_control`(→fault OR), `dtc_cleared`, `init_timeout`, `arm_rmc_2stage`
- 유지: 나머지 파생 플래그(estop_active, fault_critical_confirmed, actuators_neutral, arm_*(3) 등)
- `ig_key`(enum) → `ign_on`(bool) 반영 여부는 전처리 경계라 Stateflow는 enum 유지 가능(택)
