# Stateflow Input 데이터 정리 — ASW 인터페이스 (v0.7 기준)

> ChassisuC 상태머신 Input 을 ASW 인터페이싱 기준으로 정리.
> **★ v0.7 변경**: Control Computer(CC) **삭제 → Video Computer(VC) 통합** (DBC `KIA_ADUS_CAN_v0_7.dbc`).
> CC 경로 신호 제거, 모드/E-Stop/net 중재 단순화.

---

## 0. v0.7 아키텍처 변경 요약

| 구분 | v0.6 (CC+VC) | v0.7 (VC 통합) |
| --- | --- | --- |
| 노드 | Control Computer + Video Computer | **Video_Computer 만** |
| E-Stop | RS_E_STOP1(AA,CC) + RS_E_STOP2(AB,VC) | **RS_E_STOP2(AB) 만** |
| Net | CC_Net_Status + VC_Net_Status | **VC_Net_Status 만** |
| 명령 | RS_Chassis_Command1(CC)+2(VC) | **RS_Chassis_Command 1개** |
| 모드 | Op_Mode_CC + Op_Mode_VC (중재) | **Chassis_Op_Mode 1개 (중재 불필요)** |
| 신규 | — | Chassis_Status4 (Reject 신호들) |

> 상태머신 발행: `Chassis_State_Machine_Status` = Chassis_Status3 bit24 (ADR-0039). 1:S0..7:S6, 0:Invalid.

---

## 1. 최종 Input (26개) — ASW 인터페이스

범례: 모든 항목 상태머신 가드/during 에서 사용(✅). CAN 소스는 v0.7 DBC.

| # | 입력명 | 타입 | 쓰임 | CAN 소스 (v0.7) |
| --- | --- | --- | --- | --- |
| 1 | `ig_key` | Enum IgKey | S0↔INIT↔S1↔S0 | KEYON 핀(K24) |
| 2 | `wake_source` | boolean | S0→INIT | Wake |
| 3 | `heartbeat_ok` | boolean | S5→S2 | VC_AliveCounter |
| 4 | `heartbeat_age_ms` | uint16 | S2/S3→S5, during | VC_AliveCounter(전처리 산출) |
| 5 | `vc_net_level` | uint8 | S3→S5, S5→S2 | VC_Net_Status.VC_Net_Level |
| 6 | `aebs_flag` | boolean | →S4, S4복귀, during | RS_E_STOP2.AEBS_AB |
| 7 | `fault_critical_confirmed` | boolean | →S6 | *_Status==Fault (「진단」) |
| 8 | `fault_suspect` | boolean | during(명령제한) | 「진단」 |
| 9 | `fault_threatens_control` | boolean | S1→S6 | 「안전」 |
| 10 | `estop_active` | boolean | →S6 최우선 | HW + RS_E_STOP2.E_STOP_AB |
| 11 | `actuators_neutral` | boolean | S2→S3 | 조작기 데드존(전처리) |
| 12 | `first_valid_cmd` | boolean | S2→S3 | RS_Chassis_Command |
| 13 | `takeover_req` | boolean | S3→S1(테이크오버 B) | 조향/제동 개입(전처리) |
| 14 | `manual_switch_req` | boolean | S3→S2(안전정지) | RS 수동전환 요청 |
| 15 | `mode_req` | Enum ModeReq | S1↔S2, S3→S2 | RS_Chassis_Command.Chassis_Op_Mode |
| 16 | `vehicle_speed` | single | S3→S2, S5→S2 | Chassis_Status2.Vehicle_Velocity |
| 17 | `cam_at_origin` | boolean | S2→S1 | BRK_Status |
| 18 | `arm_rs_mutual_auth` | boolean | S1→S2 ① | 인증(SRS-SYS-013) |
| 19 | `arm_rmc_2stage` | boolean | S1→S2 ② | Remote Panel(⚠️Q-56) |
| 20 | `arm_speed_zero` | boolean | S1→S2 ③ | 차속0 |
| 21 | `arm_gear_park_or_neutral` | boolean | S1→S2 ④ | 기어 P/N |
| 22 | `gear_ready` | boolean | INIT→S1 | GA/GS_Status |
| 23 | `selftest_done` | boolean | INIT→S1 | 자기진단 |
| 24 | `init_timeout` | boolean | INIT→S6 | 타이머(SRS-039) |
| 25 | `dtc_cleared` | boolean | S6→S0 | 「진단」 |
| 26 | `pedal_pos` | single | (이양 액션 §5) | APP(가속페달) |

> `pedal_pos`는 코어 가드엔 없고 **S1→S2 캠 정합 액션**에서 쓰임. 이양 액션 범위면 유지, 코어만이면 제거 가능.

---

## 2. v0.7 로 제거된 입력 (29→26)

| 제거 입력 | 이유 |
| --- | --- |
| `video_hb_ok` | 영상 HB 상실=경고만(상태천이 없음, C12). ASW/HMI 측 처리 |
| `cc_net_level` | **CC_Net_Status 삭제**(v0.7). net_level 은 VC 단독 |
| `ttc_s` | AEBS=`aebs_flag` 판정(C22). TTC 원시값 미사용 |

**연쇄 변경 (전처리/출력):**
- `ArbitrateEStop`: HW+CC+VC(3경로) → **HW+VC(2경로)**
- `ArbitrateModeReq`: CC/VC 중재 → **단일 소스 매핑**(중재 폐기)
- 출력 `system_check_request` **제거** (CC/VC 불일치 없음 → C20 폐기)

---

## 3. 명칭 정합 — ASW ↔ Stateflow

ASW 측 신호명을 아래에 채워주시면 리네임 or 매핑 레이어로 heading 일치:

| Stateflow 입력 | ASW 신호명(채워주세요) | 비고 |
| --- | --- | --- |
| `ig_key` | ? | |
| `heartbeat_age_ms` | ? | VC_AliveCounter 전처리 |
| `vc_net_level` | ? | 외부 산출 수신 |
| `aebs_flag` | ? | AEBS_AB |
| `estop_active` | ? | HW+AB |
| `mode_req` | ? | Chassis_Op_Mode |
| `vehicle_speed` | ? | ×0.5 kph |
| `fault_critical_confirmed` | ? | |
| `arm_*` (4) | ? | 인터록 |
| ... (전체 26개) | ? | |

---

## 4. 결정 사항
1. **제거 3건** 확정 반영 (v0.7 CC 삭제 근거) ✅
2. `pedal_pos`: 이양 액션 포함 여부 → 유지/제거
3. 명칭 정합: (a) ASW명으로 리네임 vs (b) 매핑 레이어
4. ASW 신호명 목록 공유 → §3 완성 → heading 일치
