# Stateflow 입력 재설계 — ASW 실제 신호 기준

> 입력을 (A)실제 외부입력 / (B)전처리 파생 / (C)내부신호 / (X)제거 로 재분류.
> ASW 매핑(docs/20) + 사용자 확정 반영. 목표: ASW heading 과 1:1 일치.

---

## 1. 재분류 결과

### (A) 실제 외부 입력 — Stateflow 입력 포트로 유지
| Stateflow 입력 | ASW/CAN 신호 | 비고 |
| --- | --- | --- |
| `ig_key` | `IGN_ON` | enum→bool 재정의 검토 |
| `vc_net_level` | `VC_Net_Level` | ✅ |
| `aebs_flag` | `u8_AEBS` | u8→bool(==7) |
| `mode_req` | `u8_Req_Remote_Mode` | enum 매핑 |
| `vehicle_speed` | `f_VehicleSpeed` | ✅ |
| `pedal_pos` | `u8_APP` | ✅ |
| `u8_gear_status` | `u8_Gear_Status` | 🆕 (0:P,1:L,2:2,3:3,4:NC,5:D,6:N,7:R) |
| `vc_comm_fault` | `VC_Communication_Fault` | heartbeat 대체 |
| `vc_net_link_count` | `VC_Net_Link_Count` | 🆕 인증 판단용 |
| `brk_status_pos` | `BRK_Status.Position` | 🆕 캠 원점 판단 |
| `estop_hw` | HW ESTOP | 🆕 하드와이어 |
| `estop_can` | CAN ESTOP (RS_E_STOP2) | 🆕 |
| `fault_accel` | AccelPedal Fault | 🆕 치명고장 |
| `fault_brake` | Brake Motor Fault | 🆕 |
| `fault_gear_actu` | Gear Actuator Fault | 🆕 |
| `fault_gear_sel` | Gear Selector Fault | 🆕 |
| `manual_switch_req` | `u8_MODE_MN` | ⚠️ 주체 확인 |
| `tx_ign` | Tx IGN | 🆕 selftest 판단 |
| 명령값 4개 | `u8_Req_Gear/Brake/Throttle`, `u16_Req_Steering` | 제어경로(별도) |

### (B) 전처리 파생 — 입력 아님, 전처리 블록이 계산
| 파생 플래그 | 계산식 |
| --- | --- |
| `estop_active` | `estop_hw OR estop_can` (동일 레벨 OR) |
| `fault_critical_confirmed` | `fault_accel OR fault_brake OR fault_gear_actu OR fault_gear_sel` |
| `actuators_neutral` | `u8_Gear_Status == 6(N)` (현재 기어 중립) |
| `cam_at_origin` | `BRK_Status.Position == 원점` |
| `arm_speed_zero` | `f_VehicleSpeed <= 임계` (혼합) |
| `arm_gear_park_or_neutral` | `u8_Gear_Status ∈ {0(P), 6(N)}` |
| `arm_rs_mutual_auth` | `VC_Net_Link_Count` 기반 (연결 수립) |
| `gear_ready` | Gear Status Normal (판단 가능) |
| `heartbeat_ok` | `!VC_Communication_Fault` |
| `selftest_done` | `Tx IGN` 기반 |

### (C) 내부 신호 — 차트 내부 로컬 (입력 아님)
| 신호 | 처리 |
| --- | --- |
| `wake_source` | IGN_ON 에 통합 or 내부 |
| `first_valid_cmd` | 원격 명령 수신 내부 판정 |

### (X) 제거
| 제거 | 이유 |
| --- | --- |
| `heartbeat_age_ms` | `VC_Communication_Fault` 로 대체 |
| `init_timeout` | **삭제 확정** (#25) |
| `fault_suspect` | ❓ 실제 신호 없음 — 확인 후 제거 검토 |
| `fault_threatens_control` | ❓ 실제 신호 없음 — 확인 후 제거 검토 |
| `takeover_req` | ❓ 운전자 개입 감지원 미정 — 확인 |
| `dtc_cleared` | ❓ 진단 모듈 — 확인 |
| `arm_rmc_2stage` | ✅ **제거 확정 — 2단조작 포기** (Q-56). 인터록 4→3조건 |

---

## 2. `arm_rmc_2stage` (2단 조작) — 설명

- **의도**: 원격 진입 시 오조작 방지용 2단계 버튼(1단 준비→3초내 2단 확정).
- **문제(Q-56)**: 현 Remote Panel 토폴로지(K31 MODE_MN / K34 MODE_RM)로는
  "같은 버튼 2단"이 **전기적으로 불가**. 1단 감지 핀 없음 → 3초 자동해제도 불가.
- **설계안도 "성립 불가"로 등재**, 기아 합의 대기.
- **→ 결정 필요**: (a) 2단조작 포기(제거) / (b) 다른 방식 / (c) bypass(항상 true).

---

## 3. 재설계 효과

- Stateflow **입력 포트**: 실제 외부 입력(A)만 → ASW/CAN/HW 신호와 1:1.
- 파생(B)·내부(C)는 전처리/차트 내부로 → 입력에서 제외.
- 제거(X)로 불필요 입력 삭제.
- **결과**: 모호한 입력 사라지고 heading 명확.

---

## 4. 남은 확인
1. `fault_suspect`, `fault_threatens_control` — 실제 신호 있나? (없으면 제거)
2. `takeover_req` — 운전자 개입(조향/제동)을 어느 신호로 감지? (테이크오버 B안)
3. `dtc_cleared` — S6 이탈용, 진단 신호 있나?
4. ~~`arm_rmc_2stage`~~ ✅ **제거 확정 (2단조작 포기)** — 인터록 3조건
5. `manual_switch_req`(u8_MODE_MN) vs 차량실내 Manual 스위치 — 주체 확정
6. `ig_key` enum → `IGN_ON` bool 로 축소해도 되나? (START 위치 안 쓰나?)
