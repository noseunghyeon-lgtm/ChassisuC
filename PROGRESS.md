# 진행 요약 (PROGRESS) — ChassisuC 상태머신 + CAN 전처리

> 소방특장차량 원격제어 Chassis uC 설계. 상태머신(S0~S6+INIT) 개념설계 + CAN DB 반영 전처리 + 핀맵.
> repo: `noseunghyeon-lgtm/ChassisuC`. 상태 정의 정본: 「차량 전체 상태천이 §3」.

---

## 1. 산출물 (docs/)

| 문서 | 내용 |
| --- | --- |
| `00_glossary` | 명칭 사전(정본) — 컴포넌트/상태/약어 |
| `01_state_transition_table` | 전이표 T01~T15, §3 우선순위, §7 금지천이, §8 자기진단 |
| `02_data_dictionary` | 입력/출력/로컬/파라미터/enum (DB 반영) |
| `03_transition_data_mapping` | 전이↔데이터 매핑, 역인덱스 |
| `04_state_subsystem_matrix` | 상태별 서브시스템(Brake/Gear/Accel/Steering/FSM) 동작 |
| `05_consistency_check` | 정합성 점검표 — 불일치 M01~M04, 미해결 C01~C23 |
| `06_state_definitions` | 상태 정의 + 명칭 매핑 |
| `07_chassis_controller_concept` | Chassis uC 개념설계(컨텍스트/상호작용/역할) |
| `08_state_cards` | 상태 카드(상태 중심 뷰) |
| `09_mermaid_diagrams` | Mermaid 다이어그램 6종 |
| `10_state_summary` | 상태 종합정리(정의·역할·천이) |
| `11_can_signal_mapping` | CAN 신호 ↔ Stateflow 입출력 매핑 (DB 기반) |
| `12_can_preprocessing` | CAN 전처리 설계(스케일/유효성/HB/E-Stop/CRC·MC) |
| `13_bus_param_generation_direction` | CANDB→Simulink Bus/Param 생성 방향성(Start Bit 정렬) |
| `14_statemachine_review` | 상태머신 고도화 점검(G1~G9 공백) |
| `15_preprocessing_blocks` | 전처리 블록 라이브러리 인터페이스 |
| `16_gw1_chassisuc_pinmap` | **GW1(ChassisuC) 핀맵** (RC40_Pinmap.xlsx) |
| `REVIEW_CHECKLIST` | PR 리뷰 가이드 |

## 2. 코드 (src/)
- `build_chassis_controller.m` — Chassis uC 메인 Stateflow 생성(정본명칭, S3=빈 composite, E-Stop/INIT타임아웃/during 포함)
- `build_remote_control_fsm.m` — (구) 초기 스크립트
- `CalcCRC8_J1850.m` — CRC-8 SAE J1850 계산(poly 0x1D)
- `preproc/` — 전처리 블록: CheckHeartbeat, CheckCRC, ArbitrateEStop, ArbitrateModeReq, ValidateHoldLast, ScalePhys
- `tools/parse_xlsx.py` — xlsx 파서(stdlib)

## 3. 데이터
- `DB_ChassisuC.xlsx` — CAN DB (71 메시지 / 504 신호)
- `RC40_Pinmap.xlsx` — GW1(ChassisuC) 핀맵

---

## 4. 상태 (S0~S6) + 발행코드 (DB ValueTable 매칭, C21)
Invalid=0, `S0`SLEEP=1, `S1`MANUAL=2, `S2`REMOTE_ARMED=3, `S3`REMOTE_ACTIVE=4,
`S4`AEBS_OVERRIDE=5, `S5`COMM_LOSS_BRAKE=6, `S6`FAULT_SAFE_STATE=7. INIT=Invalid(0) 발행.

## 5. 확정 사항 (주요)
- 우선순위: E-Stop(0) > S6 > S5 > S4 > 모드. **Chassis uC 단독 관리**.
- E-Stop: Hardwire 또는 CAN(E_STOP_AA/AB) 3경로 OR 수신. 결과상태 C01 TBD(임시 S6).
- Heartbeat: Control(명령) 상실→S5 / Video(영상) 상실→경고만. **AliveCounter(MC) 정체 감시**.
- S3 degradation: `vc_net_level`(0~10, 외부 산출 수신). 0~1=S5(Stop)/2~4=Degraded(속도10kph+LED)/5~10=Normal.
- 유인 S6(C03): 최대제동 금지 + 원격기능만 잠금 + 원격모드 진입불가.
- 조향 Q-76(C06): S5/S6 홀드, EPS 제어 안 함(내력 미발생).
- 모드 중재(C20): CC 우선, 불일치 시 운영자 점검요청(system_check_request).
- net 중재(C19/C18): VC·CC 둘 다 활용, 산출은 외부. Chassis uC는 수신+범위검사.
- CRC(C23): CRC-8 SAE J1850(poly 0x1D, init/xorout 0xFF), 범위=CRC 뺀 앞 전체. MC 10회 실패 stale.
- AEBS(C22): TTC 아닌 aebs_flag(CC/VC AEBS==7) 방식.

## 6. 상태머신 고도화 (docs/14)
- E-Stop 전이(S1~S5, 순위0) 추가, INIT 타임아웃→S6, 차트 during(dual_s4s5_flag/fault_suspect/자기진단 골격).

## 7. 미해결 (남은 것)
- C01 E-Stop 결과상태(「안전」), C04 디바운스 N·T, C05 차속0 임계, C07 RMC핀(Q-56),
  C08 INIT실패처리, C09 동시플래그 비트, C10 DTC클리어, C11 S0지연, C13 영상HB시간,
  C15 E-Stop HW/CAN중재, C17 LED점멸주기. G3/G6/G9(상태머신 확인항목).

## 8. GitHub 이력
- PR #1,#7,#8,#9,#10 머지됨. Issue #2~#6(C03/C06/C19/C20/C23) 전부 해소·닫힘.
- 운영: 수정은 design 브랜치 → PR → main 머지.

## 9. 핀맵 (디버깅용, docs/16 + 메모리)
- GW1=ChassisuC: 입력7(K21/K22 Inhibit, K31/K34 MODE, K38/K39 APP, K24 KEYON),
  출력19(LED A03/A05/A19/A20/A31, IGN A33/K12/K14/K15/K16, 기어 K84~K87, APP K80/K81, 조향 K17).
- GW2=FSM uC(별개): 방수펌프/메인밸브/엔진시동 — 소방특장. 혼동 주의.

## 10. 다음 액션
- 핀맵 문서(16) PR 생성·머지.
- S3 서브상태(Normal/Degraded) 구현(사용자 영역).
- 남은 수치 확정(C04/C05/C13/C17).
