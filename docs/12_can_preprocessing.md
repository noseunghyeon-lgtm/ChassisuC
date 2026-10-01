# CAN 전처리 로직 설계 (CAN raw → Stateflow 입력)

> CAN DB(`DB_ChassisuC.xlsx`)의 raw 신호를 Stateflow 가 소비하는 **논리 입력**으로 변환하는
> 전처리 계층 설계. Stateflow 는 "깨끗한 논리값"만 받고, 물리변환·유효성·타임아웃·중재는 전처리가 담당한다.
> 매핑은 `11_can_signal_mapping.md`, 입력 정의는 `02_data_dictionary.md`.

```
[CAN raw 신호]         [전처리 (10ms)]                       [Stateflow 입력]
  ├ 스케일/오프셋 ──────> 물리값 변환
  ├ 유효성(Invalid/Fault) ─> 유효 플래그 + holdlast
  ├ AliveCounter ────────> 정체 감시 → age/ok
  ├ 다중소스(CC/VC/HW) ──> OR/중재
  └ 디바운스 ────────────> 안정화된 논리값          ──────────> 가드 평가
```

---

## 1. 전처리 블록별 설계

### 1.1 스케일/오프셋 (raw → 물리값)
DB의 `Factor`·`Offset` 적용. 예:
- `Vehicle_Velocity`: `phys = raw × 0.5` [kph] (0~127.5)
- `Steering_Angle_Position`: `phys = raw × 0.1 − 800` [deg] (−800~800)
- 대부분 신호: Factor=1, Offset=0 (그대로)

### 1.2 유효성 검사 (Invalid/Fault 값 처리)
많은 신호가 `0:Invalid`, `7:Fault`, `101:Invalid`(페달) 등 **특수값**을 가짐.
- **Invalid 수신 시**: 해당 입력을 "미확정"으로 두고 **마지막 유효값 holdlast** + `valid=false` 플래그.
- **Fault 수신 시**: 해당 서브시스템 fault 로 계상(단 치명 확정은 「진단」 디바운스 후).

예: `Gear_Position_CC = 7(Fault)` → 기어 명령 무시, fault 보고.

### 1.3 Heartbeat / Alive 감시 (타임아웃 → age/ok)
DB는 `heartbeat_age_ms`를 직접 주지 않음. 대신 **AliveCounter(0~15 롤오버)** 사용:
- `CC_AliveCounter`, `VC_AliveCounter` (0~15 순환)
- **전처리**: 매 수신마다 카운터 증가 확인. **N 틱 동안 카운터 정체 → 통신 두절 판정**.
  - `heartbeat_age_ms` = (카운터 마지막 변화 이후 경과시간)
  - `heartbeat_ok` = (age ≤ 400ms) — SRS-SYS-007
  - `video_hb_ok` = VC AliveCounter 정체 아님 (상실 시 경고만, 천이 없음)
- 메시지 주기 20ms(Net_Status) → 400ms = 약 20프레임 미수신.

### 1.4 통신 네트워크 레벨 (degradation 판정)
- `vc_net_level` = `VC_Net_Level` (0~10). **범위검사** 후 그대로 전달.
  - 0~1 → S5(Stop), 2~4 → S3_Degraded, 5~10 → S3_Normal
- `CC_Net_Level` 도 존재 — degradation 판정은 **VC 기준**(사용자 확정), CC는 보조 모니터.
  - ⚠️ CC/VC net level 중재 규칙은 미확정(C19 신규).

### 1.5 E-Stop 다중소스 중재 (HW + CC + VC)
E-Stop 은 **3경로**: HW(하드와이어) + `E_STOP_AA`(CC) + `E_STOP_AB`(VC).
- `estop_active = HW_estop OR (E_STOP_AA==7) OR (E_STOP_AB==7)` — **OR 중재** (하나라도 ESTOP이면 작동).
- 각 경로 `0:Invalid`는 무시(미수신 취급). 디바운스로 노이즈 제거.
- ⚠️ HW와 CAN 중재 세부(우선순위, 불일치 처리)는 C15 — 「안전」.

### 1.6 AEBS 입력 (플래그 방식)
TTC 원시값이 아니라 CC/VC 가 판정한 **AEBS 플래그**로 수신:
- `aebs_flag = (AEBS_AA==7) OR (AEBS_AB==7)`
- → Stateflow 가드를 `ttc_s < 0.8` 대신 **`aebs_flag`** 로 변경 (11 §3).

### 1.7 모드 요청 중재 (CC + VC 2경로)
`Chassis_Op_Mode_CC`, `Chassis_Op_Mode_VC` 둘 다 존재 (1:Manual, 2:RS).
- 중재 규칙 필요: 어느 경로 우선? 둘 다 RS여야? ⚠️ C20 신규(「원격/수동 전환」).
- DB의 Op_Mode는 2단계(Manual/RS)뿐 → **RS 내부의 S2/S3 구분은 Chassis uC 내부 상태**가 결정.

### 1.8 CRC / Message Counter 검증
각 명령 메시지에 `CRC_*`, `MC_*`(Message Counter) 존재.
- **전처리에서 CRC 체크 + MC 연속성 확인** → 실패 시 프레임 폐기(유효성 false).
- 안전무결성(E2E 보호). 상태머신은 검증 통과한 프레임만 소비.

---

## 2. 전처리 → Stateflow 인터페이스 (요약표)

| Stateflow 입력 | 전처리 산출 방법 |
| --- | --- |
| `estop_active` | HW ∥ E_STOP_AA==7 ∥ E_STOP_AB==7, 디바운스 |
| `aebs_flag`(신규) | AEBS_AA==7 ∥ AEBS_AB==7 |
| `vc_net_level` | VC_Net_Level, 범위검사(0~10) |
| `heartbeat_ok`/`age` | CC_AliveCounter 정체감시 → age, ok(≤400ms) |
| `video_hb_ok` | VC_AliveCounter 정체감시 |
| `mode_req` | Op_Mode_CC/VC 중재 → NONE/TO_S2/TO_S1 |
| `vehicle_speed` | Vehicle_Velocity × 0.5 [kph] |
| `fault_critical_confirmed` | *_Status==7(Fault) → 「진단」 디바운스 |
| `gear_ready` | GA/GS WU_ErrorCode==0 && Handshake |
| `cam_at_origin` | BRK ZeroSet 응답 확인 |

---

## 3. 구현 형태 제안

**전처리는 Stateflow 밖(모델 상위)에서 수행** 권장:
- **(a) Simulink 서브시스템** — CAN Unpack(스케일/오프셋 자동) + MATLAB Function(유효성/age/중재) → Stateflow 입력 포트로.
- **(b) MATLAB Function 블록** — 한 함수에서 raw struct 받아 논리 입력 struct 반환.

→ Stateflow 는 **순수 상태 로직**만, 전처리는 분리 (관심사 분리 + 테스트 용이).
CAN Unpack 은 DBC 로 자동 생성 가능 → **DB를 DBC(.dbc)로 export** 하면 Vector/MATLAB CAN 툴에서 바로 사용.

---

## 4. DB 반영 신규 미해결

| ID | 항목 | 소관 |
| --- | --- | --- |
| C19 | CC/VC net level 중재 (degradation은 VC 기준이나 CC 보조) | 시스템 |
| C20 | 모드요청 CC/VC 2경로 중재 규칙 | 「원격/수동 전환」 |
| C21 | 상태 발행코드 오프셋 — 설계 0~6 vs DB 1~7(0=Invalid) | CAN/설계 통일 |
| C22 | AEBS: TTC 가드 → AEBS 플래그로 전환 (DB는 플래그만 제공) | 설계 반영 |
| C23 | CRC/MC E2E 검증 알고리즘 (CRC 다항식, MC 규칙) | 통신/안전 |
