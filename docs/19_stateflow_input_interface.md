# Stateflow Input 데이터 정리 — ASW 인터페이스

> ChassisuC 상태머신(`build_chassis_controller.m`)의 Input 데이터를 ASW 인터페이싱 기준으로 정리.
> **사용/미사용 분류**, 명칭·타입 정합, 제거 후보를 제시해 heading(인터페이스 헤더) 일치를 돕는다.

---

## 1. 전체 Input (29개) — 사용 분류

범례: ✅ 상태머신 가드/during 에서 사용 · ⚠️ 현재 미사용(제거 후보) · 🔵 전처리 경유(간접)

| # | 입력명 | 타입 | 사용 | 쓰이는 곳 | ASW 조치 |
| --- | --- | --- | --- | --- | --- |
| 1 | `ig_key` | Enum IgKey | ✅ | S0→INIT, S1→S0, S6→S0 | 유지 |
| 2 | `wake_source` | boolean | ✅ | S0→INIT | 유지 |
| 3 | `heartbeat_ok` | boolean | ✅ | S5→S2 | 유지 |
| 4 | `heartbeat_age_ms` | uint16 | ✅ | S2/S3→S5, during | 유지 |
| 5 | `video_hb_ok` | boolean | ⚠️ | **미사용** (영상 HB 경고는 상태천이 없음) | **제거 후보** → 경고는 ASW/HMI 측에서 |
| 6 | `vc_net_level` | uint8 | ✅ | S3→S5(Stop), S5→S2 | 유지 |
| 7 | `cc_net_level` | uint8 | ⚠️ | **미사용** (C19: 외부서 net_level 산출, 보조모니터) | **제거 후보** (외부 산출로 종결) |
| 8 | `aebs_flag` | boolean | ✅ | S1/S2/S3→S4, S4 복귀, during | 유지 |
| 9 | `ttc_s` | single | ⚠️ | **미사용** (C22: aebs_flag 로 대체, 참고용만) | **제거 후보** |
| 10 | `fault_critical_confirmed` | boolean | ✅ | INIT/S1~S5→S6 | 유지 |
| 11 | `fault_suspect` | boolean | ✅ | during (명령제한) | 유지 |
| 12 | `fault_threatens_control` | boolean | ✅ | S1→S6 (유인 제어위협) | 유지 |
| 13 | `estop_active` | boolean | ✅ | S1~S5→S6 (최우선) | 유지 |
| 14 | `actuators_neutral` | boolean | ✅ | S2→S3 | 유지 (※ 세분화 검토) |
| 15 | `first_valid_cmd` | boolean | ✅ | S2→S3 | 유지 |
| 16 | `takeover_req` | boolean | ✅ | S3→S1 (테이크오버 B) | 유지 |
| 17 | `manual_switch_req` | boolean | ✅ | S3→S2 (안전정지) | 유지 |
| 18 | `mode_req` | Enum ModeReq | ✅ | S1↔S2, S3→S2 | 유지 |
| 19 | `vehicle_speed` | single | ✅ | S3→S2, S5→S2 | 유지 |
| 20 | `pedal_pos` | single | ⚠️ | **미사용** (캠 정합은 액션=설계문서, 코어 가드엔 없음) | **보류** — 이양 액션 구현 시 필요 |
| 21 | `cam_at_origin` | boolean | ✅ | S2→S1 | 유지 |
| 22 | `arm_rs_mutual_auth` | boolean | ✅ | S1→S2 (인터록①) | 유지 |
| 23 | `arm_rmc_2stage` | boolean | ✅ | S1→S2 (인터록②) ⚠️Q-56 | 유지 |
| 24 | `arm_speed_zero` | boolean | ✅ | S1→S2 (인터록③) | 유지 |
| 25 | `arm_gear_park_or_neutral` | boolean | ✅ | S1→S2 (인터록④) | 유지 |
| 26 | `gear_ready` | boolean | ✅ | INIT→S1 | 유지 |
| 27 | `selftest_done` | boolean | ✅ | INIT→S1 | 유지 |
| 28 | `init_timeout` | boolean | ✅ | INIT→S6 | 유지 |
| 29 | `dtc_cleared` | boolean | ✅ | S6→S0 | 유지 |

---

## 2. 제거/보류 후보 (ASW 인터페이스에서 뺄 것)

| 입력 | 판정 | 근거 | 권고 |
| --- | --- | --- | --- |
| `video_hb_ok` | **제거** | 영상 HB 상실은 상태천이 없음(경고만, C12). 상태머신 입력 불필요 | ASW→HMI 경고 로직에서 처리, 상태머신 IN에서 삭제 |
| `cc_net_level` | **제거** | net_level 산출이 외부(C19/C18 종결). 상태머신은 `vc_net_level`(통합값)만 수신 | 삭제. 통합 net_level 하나만 입력 |
| `ttc_s` | **제거** | AEBS는 `aebs_flag`로 판정(C22). TTC 원시값 상태머신 미사용 | 삭제 (참고용 주석만) |
| `pedal_pos` | **보류** | 코어 가드엔 없으나 S1→S2 캠 위치정합 **액션**에서 필요(§5). 액션 구현 시 사용 | 액션 포함 범위면 유지, 코어만이면 제거 |

> **제거 3 + 보류 1.** 제거하면 Input **29 → 26개**.

---

## 3. 명칭 정합 — ASW ↔ Stateflow heading

ASW 측 신호명과 맞추기 위한 매핑 틀 (ASW 명칭은 사용자가 채워주세요):

| Stateflow 입력 | 제안 ASW 신호명(예시) | CAN 소스(DB) | 비고 |
| --- | --- | --- | --- |
| `ig_key` | ? | — (KEYON 핀 K24) | enum IgKey |
| `heartbeat_age_ms` | ? | CC_AliveCounter(1CFF90CC) | 전처리 산출 |
| `vc_net_level` | ? | VC_Net_Level(1CFF90BC) | 외부 산출 수신 |
| `aebs_flag` | ? | AEBS_AA/AB(RS_E_STOP1/2) | OR 중재 |
| `estop_active` | ? | E_STOP_AA/AB + HW | OR 중재 |
| `mode_req` | ? | Chassis_Op_Mode_CC/VC | 중재(C20) |
| `vehicle_speed` | ? | Vehicle_Velocity(18FF71EF) | ×0.5 kph |
| `fault_critical_confirmed` | ? | *_Status==7 | 「진단」 디바운스 |
| `arm_*` (4) | ? | 인터록 조건별 | — |

> **작업 방식**: ASW 측 실제 신호명을 위 표 "제안 ASW 신호명"에 채워 주시면,
> Stateflow 입력명을 그에 맞춰 **일괄 리네임**하거나, 매핑 레이어(전처리)에서 연결하겠습니다.

---

## 4. 다음 결정 (사용자)

1. **제거 3건**(`video_hb_ok`, `cc_net_level`, `ttc_s`) 삭제할까요?
2. **`pedal_pos`**: 코어만 생성(제거) vs 이양 액션 포함(유지)?
3. **명칭 정합 방식**:
   - (a) Stateflow 입력명을 **ASW 명칭으로 리네임**
   - (b) 전처리/매핑 레이어에서 **ASW↔Stateflow 연결**(이름 유지)
4. ASW 측 신호명 목록을 주시면 §3 표를 채워 heading 일치.
