# 원격 차량 제어 Top StateMachine (Simulink/Stateflow)

설계 문서 「전체 관리 프로세스 / 1 — 상태 머신」의 구현 산출물입니다.
상태 정의·천이 조건의 **정본**은 「차량 전체 상태천이 §3」이며, 본 산출물은 그 정본을
SW로 구현하는 **평가 순서·진입/이탈 액션·금지 천이 감시**를 담습니다.

## 산출물 구성

| 파일 | 내용 |
| --- | --- |
| `docs/00_glossary.md` | **명칭 사전 (정본)** — 컴포넌트/상태/약어 통일. 모든 문서의 명칭 기준 |
| `docs/01_state_transition_table.md` | 전이표 (Event/Guard/Action), 평가 우선순위, 금지천이, 자기진단 |
| `docs/02_data_dictionary.md` | 입력/출력/로컬/파라미터/열거형 정의 (S1→S2 6조건 분해 포함) |
| `docs/03_transition_data_mapping.md` | 전이 ↔ 데이터 매핑 (T01~T15 신호 사용표, 역인덱스) |
| `docs/04_state_subsystem_matrix.md` | 상태별 서브시스템 동작 매트릭스 (Brake/Gear/Accel/Steering/FSM) |
| `docs/05_consistency_check.md` | **정합성 점검표** — 다이어그램↔전이표↔데이터 불일치/신규/미해결 추적 |
| `docs/06_state_definitions.md` | 상태 정의서 + **명칭 매핑**(정본 ↔ 코드 식별자) |
| `docs/07_chassis_controller_concept.md` | **Chassis uC 개념설계** — 시스템 컨텍스트, 컴포넌트 상호작용, 상태별 역할 매트릭스 |
| `docs/08_state_cards.md` | **상태 카드** — 상태 중심 뷰(정의/할일/진입/이탈), S0~S6+INIT |
| `docs/09_mermaid_diagrams.md` | **Mermaid 다이어그램** — 전체전이도/정상루프/안전개입/우선순위/컨텍스트/INIT |
| `docs/10_state_summary.md` | **상태 종합 정리 (S0~S6)** — 정의·역할·천이 통합. 처음 요청 형식 |
| `src/build_chassis_controller.m` | **★ Chassis uC 메인 Stateflow 생성 스크립트** (정본 명칭, 코어, S3=빈 composite) |
| `src/build_remote_control_fsm.m` | (구) 초기 생성 스크립트 — 옛 명칭. 참고용 |

## 상태 개요

```
        [*] → S0(SLEEP) → INIT → S1(MANUAL) ⇄ S2(REMOTE_READY) ⇄ S3(REMOTE_ACTIVE)
                           │        │              │  ↑              │
                           ↓        ↓              ↓  │(S2 경유)      ↓
                          S6      S4(AEBS)        S5(SAFE_STOP) ──────┘
                       (FAULT)   [복귀: S3→S2]
```

| 상태 | 의미 | 발행코드 |
| --- | --- | --- |
| `S0` SLEEP | 전원 오프/슬립 | 0 |
| `INIT` | 부팅 자기진단 (GA→GS→EPS 기어계통 준비) | **255 (TBD)** |
| `S1` MANUAL | 유인 수동 주행 | 1 |
| `S2` REMOTE_READY | 원격 준비·명령 대기 | 2 |
| `S3` REMOTE_ACTIVE | 원격 주행(명령 추종) | 3 |
| `S4` AEBS | AEBS 제동 개입 | 4 |
| `S5` SAFE_STOP | Heartbeat 상실 안전정지 | 5 |
| `S6` FAULT_SAFE | 치명 고장 Safe State(비가역) | 6 |

## 실행 방법 (MATLAB 필요)

```matlab
% MATLAB + Stateflow + Simulink 설치 환경에서
cd src
build_remote_control_fsm      % RemoteControlFSM.slx 생성
```

요구 툴박스: **Simulink**, **Stateflow**. 검증(Design Verifier)까지 하려면 Simulink Design Verifier 권장.

## 설계 핵심 반영 사항

- **평가 우선순위 (§3)**: `치명고장(S6) > Heartbeat(S5) > AEBS(S4) > 모드전환`.
  Stateflow 전이의 `ExecutionOrder`로 각 소스 상태에서 강제.
- **금지 천이 (§7)**: `S3→S1` 직접 / `S5→S3` 직접 / `S6` 원격 이탈 — **전이를 아예 생성하지 않아** 원천 차단.
- **캠 위치 정합 (§4)**: `S1→S2` 여자 시 페달 위치 정합, `S2→S1` 해제 시 캠 원점 복귀 확인 가드.
- **S4 복귀 규칙 (§6-4)**: 진입 직전 상태 보관, 단 직전이 `S3`면 `S2`로 복귀.
- **INIT 원격 거부 (§6-1)**: INIT entry에서 `remote_cmd_lock = true`.

## ⚠️ 검증 상태 (중요)

- 이 환경에는 **MATLAB/Stateflow가 없어 실제 실행·컴파일 검증을 수행하지 못했습니다.**
  스크립트는 Stateflow API 문법에 대한 **정적 검토**만 거쳤습니다.
- 실제 MATLAB 환경에서 최초 실행 시, 다음을 확인하세요:
  1. `Simulink.defineIntEnumType` 로 enum 등록 성공 여부
  2. `d.DataType = 'Enum: IgKey'` 표기가 사용 중인 MATLAB 릴리스에서 인식되는지
  3. `arrangeSystem` 자동 레이아웃 결과 (수동 정리 필요할 수 있음)
  4. 서브상태 기본 진입(default transition) 화살표 정상 생성 여부

## ⚠️ 반드시 사용자/타 문서 확정이 필요한 미해결 항목

스크립트는 아래 값을 **임의로 채우지 않았습니다**. `TBD_` 상수/주석으로 분리되어 있으며,
확정 시 해당 파라미터만 수정하면 됩니다.

| 항목 | 현재 처리 | 소관 |
| --- | --- | --- |
| E-Stop 결과 상태 (우선순위 0) | 미구현 (자리만) | 「안전」 (§10) |
| INIT 발행 코드 | 임시 `255` | CAN §2.2 (§10) |
| 치명 고장 확정 디바운스 N·T | `-1`(무효) placeholder | SRS-SYS-038 / 「진단」§4 |
| 정지 판정 임계 차속 | `-1`(무효) placeholder | 「기어 변속 판단」 |
| S0 진입 지연 / Wake source | `-1`(무효) placeholder | 「전원/Wake-up」 |
| **유인 S6 대응 정책** | entry 주석만, 최대제동 로직 미확정 | 「안전」 + **기아 합의** (§6-2) |
| INIT→S1 / S1→S0 실패 처리 | 성공 가드만, 실패 경로 없음 | §12-3, 사용자 확정 |
| S4+S5 동시성립 플래그 비트 | 출력 신호만 정의 | CAN §2.2 (§10) |
| DTC 클리어 경로 | 입력 신호만 정의 | SRS-SYS-037 |

> `TBD_*` 파라미터를 `-1`로 둔 이유: 안전 관련 가드가 확정 전에 **의도치 않게 참이 되는 것을 방지**하기 위함입니다. 예를 들어 `vehicle_speed <= TBD_STANDSTILL_SPEED(-1)`는 항상 거짓이 되어, 정지 판정 임계값이 확정되기 전에는 해당 천이가 발생하지 않습니다.
