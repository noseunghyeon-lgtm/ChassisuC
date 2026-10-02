# 진행 요약 (Compact) — 원격 차량 제어 / Chassis uC

> 소방특장차량 원격제어 Top StateMachine(S0~S6) 설계. **개념설계 단계** (구현 .slx 는 보류).
> 상태 정의 정본: 「차량 전체 상태천이 §3」 / 구현 설계: 「전체 관리 프로세스 §2」.

## 산출물 (`/projects/sandbox`, zip: `RemoteControlFSM_design.zip`)

| 파일 | 내용 |
| --- | --- |
| `docs/01_state_transition_table.md` | 전이표 T01~T15, §3 우선순위, §7 금지천이, §8 자기진단 |
| `docs/02_data_dictionary.md` | 입력/출력/로컬/파라미터/enum. S1→S2 6조건, 영상HB, §7.1 무천이대응 |
| `docs/03_transition_data_mapping.md` | 전이↔데이터 매핑, 역인덱스 |
| `docs/04_state_subsystem_matrix.md` | 상태별 서브시스템(Brake/Gear/Accel/Steering/FSM) 동작 |
| `docs/05_consistency_check.md` | **정합성 점검표** — 불일치 M01~M04, 미해결 C01~C15 |
| `docs/06_state_definitions.md` | 상태 정의 + 명칭 매핑(정본↔코드식별자) |
| `docs/07_chassis_controller_concept.md` | **Chassis uC 개념설계** — 컨텍스트/상호작용/상태별 역할 |
| `src/build_remote_control_fsm.m` | .slx 자동생성 스크립트 (실행검증 안 됨, MATLAB 필요) |

## 상태 (S0~S6)
`S0`Sleep · `INIT` · `S1`Manual(유인) · `S2`Remote-Armed(대기) · `S3`Remote-Active(주행) ·
`S4`AEBS-Override · `S5`Comm-Loss Brake · `S6`Fault Safe(비가역). 발행코드 0~6, INIT=255(TBD).

## 핵심 설계 규칙 (확정)
- 우선순위: **E-Stop(0) > S6 > S5 > S4 > 모드전환** — Chassis uC **단독 관리**.
- S2 = 유일한 원격 재진입 관문. S3→S1 직접 금지(S2 경유). S6 비가역(IG-OFF 재기동+DTC).
- S4 해제 복귀: 직전 S1→S1, S2/S3→S2.
- 금지천이는 전이 미생성으로 원천차단.

## 아키텍처 확정 사항 (최근)
- **우선순위**: Chassis uC 단독 관리.
- **E-Stop**: Hardwire 또는 CAN 으로 Chassis uC 수신·판단 (결과상태는 TBD).
- **Heartbeat 2종**: Control Computer(명령) 상실→**S5** / Video Streaming(영상) 상실→**경고등만, 천이없음**.
- Chassis uC ↔ FSM uC: **S6만 공유**(점선). 하위모듈은 상태 읽기만+천이요청/고장보고.
- **S3 Degradation (신규)**: S3=서브상태 Normal/Degraded. `vc_net_level`(CAN 0~10) 기준 —
  0~1=S5(Stop), 2~4=Degraded(**속도제한 10kph**+LED점멸), 5~10=Normal. 감도 호전 시 해제.
  LED 점멸주기 TBD, 판단로직은 Ideation 예정(C18).

## 명칭 불일치 (해소: 다이어그램=정본, 코드식별자 매핑 병기)
S2 Remote-Armed=`REMOTE_READY` / S4 AEBS-Override=`AEBS` / S5 Comm-Loss Brake=`SAFE_STOP`.

## 미해결 — 다음에 확정 필요 (우선순위순)
1. **M01**: 원격 진입 조건 수 — 6조건(다이어그램) vs 4조건(§4 원문). 정본 확정 필요.
2. **C03/M04**: 유인(S1) S6 대응 — 최대제동 금지. 「안전」+**기아 합의**. 리드타임 최장.
3. **C06**: Q-76 조향 — S5/S6 조향 거동 미확정.
4. **M02/C04**: S6 "검출"→"확정" 라벨 + 디바운스 N·T.
5. **M03**: AEBS 진입소스 "임의"→S1/S2/S3 로 좁히기.
6. 기타: C01(E-Stop 결과상태), C02(INIT코드), C05(차속0 임계), C07(RMC 2단조작 Q-56),
   C13(영상HB 경고 임계시간 — **사용자가 추후 결정**), C14(FSM uC S6 공유 프로토콜),
   C15(E-Stop HW/CAN 중재), C08~C11.

## 구현 (Stateflow)
- `src/build_chassis_controller.m` — **Chassis uC 메인 FSM 생성 스크립트**.
  정본 명칭(REMOTE_ARMED 등), 전체 I/O(vc_net_level·arm_* 6신호·degradation 출력 포함),
  코어 전이 T01~T15 + ExecutionOrder 우선순위, 금지천이 미생성.
  **S3 = 빈 composite** (서브상태 Normal/Degraded는 사용자 작업). TBD는 placeholder.
  정적검토 OK(참조 식별자 전부 정의, 상태별 이탈 전이 수 = 상태카드 일치). MATLAB 실행검증은 미수행.

## GitHub (noseunghyeon-lgtm/ChassisuC)
- PR #1: design/chassis-controller-stateflow → main (설계 베이스라인, 열어두고 리뷰)
- DB_ChassisuC.xlsx 저장소에 있음. tools/parse_xlsx.py 로 파싱(stdlib).
- 리뷰 가이드: docs/REVIEW_CHECKLIST.md
- 핵심 미해결 Issue: #2(C03 유인S6), #3(C06 Q-76), #4(C19 net중재), #5(C20 모드중재), #6(C23 CRC/MC)
- 운영: 수정사항은 **같은 PR 브랜치에 업데이트**. 미해결 확정 시 반영.

## 다음 액션
- 사용자: S3 서브상태(Normal/Degraded) 직접 작업.
- Issue #2~#6 확정 → PR 브랜치 업데이트.
- VC_Net_Level 판단로직 Ideation(C18).
- 자료 추가 시 → `05_consistency_check.md` 틀에 누적 대조.
