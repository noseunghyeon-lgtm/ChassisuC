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

### 1.4 통신 네트워크 레벨 중재 (degradation 판정) — C19 설계

두 네트워크 레벨 신호 존재: `VC_Net_Level`(영상컴퓨터), `CC_Net_Level`(제어컴퓨터). 둘 다 0~10.

**중재 대상(= 무엇을 중재하나):** "degradation/stop 판정에 쓸 **단일 net_level** 을 두 값에서 어떻게 뽑을까".

**제안 중재 규칙 (보수적 — min 채택):**
```
net_level_eff = min(VC_Net_Level, CC_Net_Level)   % 둘 중 나쁜 쪽 기준(안전측)
  단, 어느 한쪽이 0(No Link)이면 그 링크는 두절로 간주
vc_net_level(Stateflow 입력) = net_level_eff
```
- 근거: 원격주행은 **명령(CC)과 영상(VC)이 모두** 건강해야 안전. 더 나쁜 쪽이 성능을 제한해야 함.
- 0~1 → S5(Stop), 2~4 → S3_Degraded, 5~10 → S3_Normal (경계는 확정값).
- ⚠️ **확인 필요**: min 채택이 맞는지, 아니면 VC 단독 기준이고 CC는 모니터만인지 — 사용자 확정(C19).
  - 대안 A: `min(VC,CC)` (위, 보수적)
  - 대안 B: VC 단독(명령 링크 CC 상실은 **S5 heartbeat 경로**로 별도 처리) ← 사용자가 "영상=VC" 라 했으므로 유력
  - 대안 C: 가중/우선순위

### 1.5 E-Stop 다중소스 중재 (HW + CC + VC)
E-Stop 은 **3경로**: HW(하드와이어) + `E_STOP_AA`(CC) + `E_STOP_AB`(VC).
- `estop_active = HW_estop OR (E_STOP_AA==7) OR (E_STOP_AB==7)` — **OR 중재** (하나라도 ESTOP이면 작동).
- 각 경로 `0:Invalid`는 무시(미수신 취급). 디바운스로 노이즈 제거.
- ⚠️ HW와 CAN 중재 세부(우선순위, 불일치 처리)는 C15 — 「안전」.

### 1.6 AEBS 입력 (플래그 방식)
TTC 원시값이 아니라 CC/VC 가 판정한 **AEBS 플래그**로 수신:
- `aebs_flag = (AEBS_AA==7) OR (AEBS_AB==7)`
- → Stateflow 가드를 `ttc_s < 0.8` 대신 **`aebs_flag`** 로 변경 (11 §3).

### 1.7 모드 요청 중재 (CC + VC 2경로) — C20 설계
`Chassis_Op_Mode_CC`, `Chassis_Op_Mode_VC` 둘 다 존재 (0:Invalid, 1:Manual, 2:RS).

**중재 대상(= 무엇을 중재하나):** CC와 VC가 **서로 다른 모드를 요청**할 때 어느 것을 `mode_req`로 삼을지.
가능한 불일치: (CC=RS, VC=Manual), (한쪽 Invalid), (둘 다 RS) 등.

**제안 중재 규칙 (안전측 — 원격진입은 합의 필요, 해제는 단독 가능):**
```
% 원격 진입(→RS)은 양쪽 합의 필요(오작동 방지), 수동 복귀(→Manual)는 한쪽만으로도 허용(안전측)
if (CC==Manual) or (VC==Manual):   mode_req = TO_S1   % 한쪽이라도 Manual 요구 → 수동 복귀
elif (CC==RS) and (VC==RS):        mode_req = TO_S2   % 둘 다 RS 여야 원격 진입
else:                              mode_req = NONE    % 불일치/Invalid → 요청 없음(현 상태 유지)
```
- 근거: **원격 진입은 보수적으로(둘 다 동의)**, **수동 복귀는 적극적으로(하나만 요구해도)** — 안전 방향.
- Invalid(0)는 미수신 취급 → NONE.
- ⚠️ **확인 필요**: CC/VC 중 **마스터 지정**이 있는지(예: CC가 주, VC는 보조). 있으면 규칙 단순화(C20).
- DB Op_Mode는 2단계(Manual/RS)뿐 → **RS 내부 S2/S3 구분은 Chassis uC 내부 상태**(조작기 중립·첫 유효명령)가 결정.

### 1.8 CRC / Message Counter 검증 (E2E 보호) — C23 알고리즘

안전 관련 명령·이벤트 메시지에 **E2E 보호** 필드 존재:
- `MC_*` (Message Counter, 4bit, 0~15 순환) — 매 송신마다 +1
- `CRC_*` (8bit) — 메시지 데이터 체크섬

위치 (DB 확인): `RS_Chassis_Command1(0CFF50CC)` → MC bit52, CRC bit56 /
`RS_E_STOP1(AA)` → MC bit20, CRC bit24 / Command2·E_STOP2 동일 패턴.

**검증 알고리즘 (프레임 수신 시, 전처리 단계):**

**(1) MC(Message Counter) 연속성**
```
expected_mc = (last_mc + 1) mod 16
if received_mc == expected_mc:        mc_ok = true
elif received_mc == last_mc:          mc_ok = false  % 중복/정체(freshness 실패)
else:                                 mc_ok = false  % 누락/점프
last_mc = received_mc
% N회 연속 실패 시 해당 메시지 "stale" → 유효성 false
```

**(2) CRC(체크섬) — AUTOSAR E2E Profile 계열 권장**
```
% 8bit CRC. 다항식은 DB/통신규격 확정 필요(아래 TBD).
% 권장: CRC-8-SAE J1850 (poly 0x1D, init 0xFF, xorout 0xFF) — AUTOSAR E2E Profile 1/2 계열
computed = crc8( data_bytes_except_crc, poly=0x1D, init=0xFF )
crc_ok = (computed == received_crc)
```

**(3) 종합 유효성**
```
frame_valid = mc_ok AND crc_ok AND (signal in range) AND (value != Invalid)
if not frame_valid:  해당 프레임 폐기 → 마지막 유효값 holdlast + valid=false
```

- 상태머신은 **`frame_valid` 통과한 값만** 소비 (오염된 명령으로 천이 금지).
- E-Stop 은 **fail-safe**: CRC 실패해도 ESTOP 쪽으로 안전하게(수신 실패 자체를 위험으로) 처리할지는 「안전」 확정.
- ⚠️ **확인 필요(C23)**: CRC 다항식/init/xor, MC 연속 실패 임계 N, CRC 계산에 포함되는 바이트 범위
  (Data ID 포함 여부 — AUTOSAR E2E는 Data ID를 CRC에 섞음). 통신/안전 규격 확정 필요.

---

## 2. 전처리 → Stateflow 인터페이스 (요약표)

| Stateflow 입력 | 전처리 산출 방법 |
| --- | --- |
| `estop_active` | HW ∥ E_STOP_AA==7 ∥ E_STOP_AB==7, 디바운스 (E2E 통과분) |
| `aebs_flag` (C22) | AEBS_AA==7 ∥ AEBS_AB==7 |
| `vc_net_level` | **중재(C19)**: min(VC,CC) 또는 VC단독 → 0~10 |
| `cc_net_level` | CC_Net_Level, 보조 모니터 |
| `heartbeat_ok`/`age` | CC_AliveCounter 정체감시 → age, ok(≤400ms) |
| `video_hb_ok` | VC_AliveCounter 정체감시 |
| `mode_req` | **중재(C20)**: Op_Mode_CC/VC → NONE/TO_S2/TO_S1 |
| `vehicle_speed` | Vehicle_Velocity × 0.5 [kph] |
| `fault_critical_confirmed` | *_Status==7(Fault) → 「진단」 디바운스 |
| `gear_ready` | GA/GS WU_ErrorCode==0 && Handshake |
| `cam_at_origin` | BRK ZeroSet 응답 확인 |
| (전제) `frame_valid` | **CRC+MC(C23)** 통과 — 모든 명령/이벤트 메시지 |

---

## 3. 구현 형태 제안

**전처리는 Stateflow 밖(모델 상위)에서 수행** 권장:
- **(a) Simulink 서브시스템** — CAN Unpack(스케일/오프셋 자동) + MATLAB Function(유효성/age/중재) → Stateflow 입력 포트로.
- **(b) MATLAB Function 블록** — 한 함수에서 raw struct 받아 논리 입력 struct 반환.

→ Stateflow 는 **순수 상태 로직**만, 전처리는 분리 (관심사 분리 + 테스트 용이).
CAN Unpack 은 DBC 로 자동 생성 가능 → **DB를 DBC(.dbc)로 export** 하면 Vector/MATLAB CAN 툴에서 바로 사용.

---

## 4. DB 반영 신규 미해결

| ID | 항목 | 상태 | 소관 |
| --- | --- | --- | --- |
| ~~C21~~ ✅ | 상태 발행코드 — DB Value Table 매칭 | **해소** — S0=1..S6=7, Invalid=0 (02 §1 반영) | 설계 통일 |
| ~~C22~~ ✅ | AEBS: TTC → 플래그 | **해소** — 가드 `aebs_flag` 로 전환 (스크립트 반영) | 설계 반영 |
| 🔶 C19 | CC/VC net level 중재 | 설계안 제시(min vs VC단독) — **방식 확정 필요** | 시스템 |
| 🔶 C20 | 모드요청 CC/VC 2경로 중재 | 설계안 제시(진입=합의, 복귀=단독) — **마스터 지정 확인** | 「원격/수동 전환」 |
| 🔶 C23 | CRC/MC E2E 검증 | 알고리즘 제시(CRC-8 J1850, MC 순환) — **다항식/범위/임계 확정** | 통신/안전 |
