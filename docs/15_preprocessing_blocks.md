# 전처리 블록 라이브러리 (Preprocessing Blocks)

> CAN raw 데이터를 상태머신 논리 입력으로 변환하는 **단위 블록(MATLAB Function)** 모음.
> 각 블록은 Simulink MATLAB Function 블록으로 그대로 사용 가능하며, Stateflow 앞단에 배치한다.
> 상세 설계 근거: `12_can_preprocessing.md`. 구현: `src/preproc/`.

```
[CAN raw] → [전처리 블록들 (10ms)] → [상태머신 논리 입력]
```

---

## 블록 목록

| 블록 (src/preproc/) | 입력 | 출력 | 역할 |
| --- | --- | --- | --- |
| `CheckHeartbeat.m` | mc_raw, msg_valid, reset | **hb_ok, hb_age_ms, stale** (bool/u16) | MC 정체 감시 → 생존 판정 (SRS-SYS-007, 400ms) |
| `CheckCRC.m` | frame_bytes | **crc_ok** (bool) | CRC-8 J1850 무결성 점검 (Issue #6) |
| `ArbitrateEStop.m` | hw_estop, estop_cc, estop_vc | **estop_active** (bool) | E-Stop 3경로 OR 중재 (HW+CC+VC) |
| `ArbitrateModeReq.m` | opmode_cc, opmode_vc | **mode_req, system_check_request** | 모드 중재(CC 우선, 불일치→점검요청) C20 |
| `ValidateHoldLast.m` | raw, invalid_val, reset | **value_out, valid** | Invalid 수신 시 마지막 유효값 유지 |
| `ScalePhys.m` | raw, factor, offset | **phys** (double) | raw→물리값 (factor/offset) 135건 |
| `DetectRemoteReengage.m` | u8_MODE_MN, Chassis_Op_Mode, reset | **remote_reengage_ok, mn_reengaged, vc_reengaged** (bool) | AEBS 해제용 2중화 Remote 재진입 엣지검출 (HW&&VC, Manual 경유, AND) — S4→S2 |
| `CalcCRC8_J1850.m` (src/) | data_bytes | crc (u8) | CRC 계산 코어 (CheckCRC 가 호출) |

---

## 1. Heartbeat 점검 — `CheckHeartbeat`

```
입력:  mc_raw(MC 0~15), msg_valid(유효프레임?), reset
출력:  hb_ok(bool), hb_age_ms(u16), stale(bool)
로직:  MC 가 변하면 age=0, 정체/미수신이면 age += 10ms(틱)
       hb_ok = age<=400ms,  stale = age>400ms
```
- **MC(Message Counter) 정체**로 두절을 판정 (DB엔 age 신호가 없고 AliveCounter만 있음).
- 원격(CC) HB: 400ms → S5 전이. 영상(VC) HB: 상실 시 경고만(TIMEOUT 다르면 인스턴스 분리).
- 검증: MC 증가 시 age=0, 정체 42~44틱(420~440ms)에서 stale=true 확인 완료.

## 2. CRC 점검 — `CheckCRC`
```
입력:  frame_bytes (마지막 바이트 = 수신 CRC)
출력:  crc_ok(bool)
로직:  computed = CalcCRC8_J1850(앞 전체);  crc_ok = (computed == 수신 CRC)
```
- CRC-8 SAE J1850 (poly 0x1D, init/xorout 0xFF). 범위=CRC 뺀 앞 전체.
- 검증: 정상 프레임 true, 손상 프레임 false 확인 완료.

## 3. E-Stop 중재 — `ArbitrateEStop`
```
estop_active = hw_estop OR (estop_cc==7) OR (estop_vc==7)   % 안전측 OR
```
- 3경로 중 하나라도 ESTOP(7)이면 작동. Invalid(0)/None(1)은 미작동.

## 4. 모드 중재 — `ArbitrateModeReq` (C20)
```
if CC==VC: CC 채택
elif CC!=Invalid: CC 채택 + system_check_request=true   % 불일치 → 점검요청
else: VC 채택
map: 1(Manual)->REQ_TO_S1, 2(RS)->REQ_TO_S2
```

## 5. 유효성/holdlast — `ValidateHoldLast`
```
raw==invalid_val → valid=false, 마지막 유효값 hold
else → valid=true, 값 갱신
```
- Invalid(0)/101(페달)/7(Fault) 등 특수값 수신 시 안전하게 이전값 유지.

## 6. 스케일 변환 — `ScalePhys`
```
phys = raw*factor + offset
```
- 예: 차속 raw×0.5[kph], 조향 raw×0.1-800[deg].

## 7. AEBS 해제 2중화 재진입 — `DetectRemoteReengage` (S4→S2)
```
입력:  u8_MODE_MN(HW 모드 1:Manual/2:Remote), Chassis_Op_Mode(VC 0:Inv/1:Manual/2:RS), reset
출력:  remote_reengage_ok(bool), mn_reengaged(bool), vc_reengaged(bool)
HW:  u8_MODE_MN==Manual → mn_reset_armed=TRUE; mn_reset_armed && ==Remote → mn_reengaged=TRUE(latch)
VC:  Chassis_Op_Mode==1  → vc_reset_armed=TRUE; vc_reset_armed && ==2     → vc_reengaged=TRUE(latch)
합성: remote_reengage_ok = mn_reengaged && vc_reengaged        % AND (OR 아님)
```
- AEBS 는 차속 0까지 완전정지(조기 해제 없음). 해제는 **VC 가 Remote→Manual→Remote** 조작을 거쳐야 함.
- 2중화 두 경로(차량 HW · VC CAN)를 **각각 독립**으로 Manual 경유 엣지 시퀀스 요구 → 둘 다 완료(AND)해야 유효.
- `reset`(=S4 진입, `~s4_active`) 시 `mn/vc_reset_armed`·`mn/vc_reengaged` 모두 FALSE 초기화 →
  새 AEBS 이벤트마다 2단 조작 재요구.
- 검증: Python 동치 테스트 `tools/verify_remote_reengage.py` 10케이스 전부 통과
  (엣지 시퀀스/AND/독립 타이밍/latch 유지/reset 재요구/Invalid noop).

---

## 데이터 흐름 예시 (원격 명령 메시지 RS_Chassis_Command1)

```
CAN frame(0CFF50CC, 8B)
  ├─ CheckCRC(frame) ─────────────> crc_ok ─┐
  ├─ MC 추출 → CheckHeartbeat ────> hb_ok ──┤ (and) → frame_valid
  ├─ Op_Mode_CC ─┐                          │
  │              ├─ ArbitrateModeReq ──> mode_req, system_check_request
  │  Op_Mode_VC ─┘  (VC 메시지와 함께)
  ├─ Vehicle_Velocity → ScalePhys(×0.5) → vehicle_speed
  └─ Gear_Position_CC → ValidateHoldLast(invalid=7) → gear, valid
```
→ `frame_valid` 통과한 신호만 상태머신 가드가 소비.

---

## 미해결 / 확장 포인트
- 영상 HB 경고 임계시간(C13): 현재 TIMEOUT=400 고정 → 영상용은 파라미터화 필요.
- `ValidateHoldLast` 다중신호: persistent 단일 → 신호별 인스턴스 또는 배열화.
- 디바운스 블록(노이즈 제거): 필요 시 N틱 연속 조건 블록 추가.
- MC 10회 연속 실패 stale(C23): CheckCRC/CheckHeartbeat 와 결합한 stale 카운터 블록으로 확장.

---

## 단일 진입점 — `PreprocessInputs.m` (ASW heading)

ASW raw 신호(struct `asw.*`) → Stateflow 입력(struct `sf.*`) 변환의 **단일 진입점**.
입력 struct 필드명 = **ASW heading**(IGN_ON, VC_Net_Level, u8_HW_Fault, u8_Gear_Status 등),
출력 struct 필드명 = Stateflow 입력 포트명. Simulink: Bus(ASW)→MATLAB Function→Bus(SF in).

핵심 변환:
- `aebs_flag = (u8_AEBS==7)`, `fault_critical_confirmed = (u8_HW_Fault!=0)`
- `actuators_neutral = (u8_Gear_Status==6)`, `arm_gear_park_or_neutral = gear∈{0,6}`
- `estop_active = estop_hw OR estop_can`, `takeover_req = steer OR estop OR MN`
- `heartbeat_ok = ~VC_Communication_Fault`, `manual_switch_req = (u8_MODE_MN==Manual)`
- `remote_reengage_ok = DetectRemoteReengage(u8_MODE_MN, Chassis_Op_Mode, ~s4_active)` (AEBS 해제 2중화, S4→S2)
- 검증: Python 동치 테스트 통과(fault/neutral/estop/takeover + remote_reengage 케이스).

---

## 간소화 결정 (사용자 확정) — 신규 블록 미생성

복잡한 신규 전처리 블록을 만들지 않고 **단순 연산/직접 입력**으로 처리:

| 당초 신규 블록 안 | 확정 |
| --- | --- |
| `ComputeFaultBits` (4 Fault → bitfield) | **미생성** — ASW 가 `u8_HW_Fault`(4 Fault bitfield) 를 직접 제공. `fault_critical_confirmed = (u8_HW_Fault != 0)`, 컴포넌트는 비트로 판별 |
| `ComputeNeutral` | **미생성** — `actuators_neutral = (u8_Gear_Status == 6)` 직접 판정 |
| `ComputeInterlock` | **삭제** — arm_* 는 각 신호에서 직접(speed/gear/net_link_count) |

→ 전처리 블록은 기존 6개(CheckHeartbeat/CheckCRC/ArbitrateEStop/ArbitrateModeReq/ValidateHoldLast/ScalePhys)
  + 위 단순 연산만. 블록 추가 없음.
