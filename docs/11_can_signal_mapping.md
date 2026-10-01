# CAN 신호 ↔ Stateflow 입력 매핑 (DB-ChassisuC 기준)

> `DB_ChassisuC.xlsx`(CAN DB)의 신호를 Chassis uC 상태머신의 **논리 입력/출력**(데이터 딕셔너리 `02`)에 매핑.
> 모든 신호는 Intel(little-endian) 바이트 오더. 전처리 로직은 `12_can_preprocessing.md` 참조.

---

## 0. DB 요약 (상태머신 관련 메시지)

| CAN ID | 메시지 | 방향 | 주기 | 용도 |
| --- | --- | --- | --- | --- |
| `AA` | RS_E_STOP1 | CC → Chassis uC | Event | E-Stop/AEBS (CC 경로) |
| `AB` | RS_E_STOP2 | VC → Chassis uC | Event | E-Stop/AEBS (VC 경로) |
| `1CFF90CC` | CC_Net_Status | CC → Chassis uC | 20ms | CC 통신레벨·Alive |
| `1CFF90BC` | VC_Net_Status | VC → Chassis uC | 20ms | **VC 통신레벨·Alive (degradation)** |
| `0CFF50CC` | RS_Chassis_Command1 | CC → Chassis uC | 10ms | 원격명령(모드/기어/가감속/조향) |
| `0CFF60BC` | RS_Chassis_Command2 | VC → Chassis uC | 10ms | 원격명령(VC 경로) |
| `18FF70EF` | Chassis_Status1 | Chassis uC → VC | 10ms | 상태 발행(모드/기어/가감속/조향 FB) |
| `18FF73EF` | Chassis_Operation_Status | Chassis uC → VC | 10ms | **상태머신 상태(S0~S6) 발행** |
| `18FF82EA` | FSM_uC_Status | FSM uC → Chassis uC | 10ms | **FSM 상태머신(S6 참조)** |
| `18FF74EF` | Chassis_uC_Status | Chassis uC → FSM uC | 10ms | **S6 공유(Chassis→FSM)** |
| `2968`/`2969` | GA_Status / BRK_Status | GA/BA → Chassis uC | Cyclic | 액추에이터 상태·에러코드 |
| `2C68`/`2C69` | GA_WU / BRK_WU | GA/BA → Chassis uC | Event | 액추에이터 Wakeup |
| `18A`/`70A` | TxPDO1 / GS_Status | GearSelector → Chassis uC | — | 기어 실렉터(CANopen) |
| `18FEF10B` | CCVS1_CAR | Chassis → Chassis uC | 100ms | 차속(순정) |
| `18FF0513` 등 | EPS01/02 | EPS → Chassis uC | 10ms | 조향 상태 |

> ★ **상태머신 상태(S0~S6)가 DB에 이미 정의됨** — ValueTable: `1:S0, 2:S1, 3:S2, 4:S3, 5:S4, 6:S5, 7:S6`.
> 즉 **발행 코드가 DB 확정**이다. (단, 우리 설계의 `veh_state_code`는 0~6, DB는 1~7+Invalid=0 → **오프셋 +1 주의**, §3 참조)

---

## 1. 입력 매핑 (CAN → Stateflow 논리 입력)

| Stateflow 입력(02) | CAN 신호 | 메시지 | ValueTable/스케일 | 전처리 |
| --- | --- | --- | --- | --- |
| `estop_active` | `E_STOP_AA` ∥ `E_STOP_AB` | RS_E_STOP1/2 | 7:ESTOP, 1:None, 0:Invalid | **OR 중재 + HW** |
| (AEBS 트리거) | `AEBS_AA` ∥ `AEBS_AB` | RS_E_STOP1/2 | 7:AEBS, 1:None | OR 중재 |
| `vc_net_level` | `VC_Net_Level` | VC_Net_Status | 0:NoLink, 1:Worst..10:Best | 범위검사 |
| (CC 통신레벨) | `CC_Net_Level` | CC_Net_Status | 0~10 | 범위검사 |
| `heartbeat_ok`/`age` | `CC_AliveCounter` | CC_Net_Status | 0~15 롤오버 | **Alive 정체 감시** |
| `video_hb_ok` | `VC_AliveCounter` | VC_Net_Status | 0~15 롤오버 | Alive 정체 감시 |
| `mode_req` | `Chassis_Op_Mode_CC`/`_VC` | RS_Chassis_Command1/2 | 1:Manual, 2:RS | 매핑 |
| `vehicle_speed` | `Vehicle_Velocity` | Chassis_Status2 | ×0.5 kph (0~127.5) | 스케일 |
| (차속 순정) | `CCVS1_CAR` 차속 | CCVS1_CAR | — | 교차검증 |
| `fault_critical_confirmed` | `*_Actuator_Status`=7(Fault) | Chassis_Status3 | 7:Fault | **「진단」 디바운스 후** |
| (기어 작동상태) | `Gear_Actuator_Status` | Chassis_Status3 | 1:Normal,4:Warn,7:Fault | 유효성 |
| (제동 작동상태) | `Brake_Actuator_Status` | Chassis_Status3 | 1/4/7 | 유효성 |
| (조향 작동상태) | `Steering_Control_Unit_Status` | Chassis_Status3 | 1/4/7 | 유효성 |
| `gear_ready` | `GA_Status`/`GS_Status` | GA_Status/GS | WU_ErrorCode=0 Normal | Handshake |
| `cam_at_origin` | `BRK_Status` (ZeroSet 응답) | BRK_Status | — | 캠 원점 확인 |
| `ttc_s` | (AEBS 판정은 CC/VC 측) | RS_E_STOP1/2 | AEBS 플래그로 수신 | — |

> AEBS 는 TTC 원시값이 아니라 **CC/VC 가 판정한 결과(`AEBS_AA/AB` 플래그)**로 들어온다.
> → 우리 가드의 `ttc_s < 0.8` 대신 **`aebs_flag` (AEBS=7)** 로 전이하도록 조정 필요(§3 반영).

---

## 2. 출력 매핑 (Stateflow → CAN)

| Stateflow 출력(02) | CAN 신호 | 메시지 | 비고 |
| --- | --- | --- | --- |
| `veh_state_code` | `Chassis_State_Machine_Status_VC` | Chassis_Operation_Status | **1:S0..7:S6** (오프셋 주의) |
| (S6 공유) | `Chassis_State_Machine_Status_FSM` | Chassis_uC_Status | FSM uC 로 S6 전달 |
| (모드 발행) | `Chassis_Op_Mode_Status` | Chassis_Status1 | 1:Manual, 2:RS |
| `brake_req_src_state` | `BRK_Pos_CMD` | BRK_Pos_CMD(469) | 제동 지령 |
| (기어 지령) | `GA_Pos_CMD` | GA_Pos_CMD(468) | 기어 지령 |
| (조향 지령) | EPS01/02 (EPSI) | 18FF00FE 등 | 조향 지령 |
| `speed_limit_*` | (가감속 지령 제한) | BRK/Throttle | Degradation 시 |

> **FSM uC 의 S6 공유 메커니즘 확정**: Chassis uC → `Chassis_uC_Status`(18FF74EF)의
> `Chassis_State_Machine_Status_FSM` 로 **push**, FSM uC → `FSM_uC_Status`(18FF82EA)의
> `FSM_State_Machine_Status` 로 자기 상태 회신. (C14 해소 — push 방식)

---

## 3. DB 반영으로 조정 필요한 설계 포인트 ★

| 항목 | 기존 설계 | DB 실제 | 조치 |
| --- | --- | --- | --- |
| **상태 발행 코드** ✅ | 0:S0 ~ 6:S6 | **1:S0 ~ 7:S6** (0=Invalid) | ✅ **해소(C21)**: enum을 DB에 맞춤(S0=1..S6=7, INIT=Invalid=0) |
| **AEBS 입력** ✅ | `ttc_s < 0.8s` | CC/VC 가 판정한 **AEBS 플래그** | ✅ **해소(C22)**: 가드를 `aebs_flag` 로 변경 |
| **E-Stop** | 단일 `estop_active` | **CC(AA)+VC(AB) 2경로** + HW | OR 중재 전처리 |
| **Heartbeat** | `heartbeat_age_ms` | **AliveCounter(0~15 롤오버)** | 카운터 정체 → age 환산 |
| **통신레벨** | `vc_net_level` | VC + **CC 도 Net_Level 있음** | 둘 다 반영? (degradation은 VC 기준) |
| **모드 2경로** | `mode_req` | CC·VC 각각 Op_Mode | 중재 규칙 필요 |
| **Op Mode** | S1~S3 세분 | DB는 **1:Manual, 2:RS** (2단계) | RS 내 S2/S3 구분은 내부 상태 |

> ⚠️ 특히 **상태 코드 오프셋(+1)** 과 **AEBS 플래그 방식**은 전이 가드에 직접 영향 →
> `build_chassis_controller.m` 갱신 필요 (다음 단계).
