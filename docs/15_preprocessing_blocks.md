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
| `DebounceFaultCritical.m` | fault_critical_raw, reset | **fault_critical_confirmed** (bool) | 치명고장 검출→확정 디바운스 100ms (C04) |
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

## 7. 치명고장 확정 디바운스 — `DebounceFaultCritical` (C04)
```
fault_critical_raw = accel_fault OR brake_fault OR gearactu_fault OR gearsel_fault  % u8_HW_Fault 4비트 OR
입력:  fault_critical_raw(bool), reset
출력:  fault_critical_confirmed(bool)
로직:  raw True → cnt++ (DEBOUNCE_TICKS 포화), raw False → cnt=0 (연속 지속 요구)
       confirmed = (cnt >= DEBOUNCE_TICKS)
```
- ✅ **C04 확정**: `DEBOUNCE_TICKS=10 × TICK_MS=10ms = 100ms` 연속 지속 시 확정(M02 "검출≠확정").
- 중간에 한 틱이라도 해제되면 카운터 리셋(연속 지속 요구). 래치 없음(현 틱 기준).
- 검증: `tools/verify_fault_debounce.py` 6개 시나리오 PASS (동치검증, MATLAB 미설치 환경).

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
- 영상 HB 경고 임계시간(C13): ✅ **종결** — 상태머신 범위 밖(HMI/경고 계층 소관). 영상 HB 는 상태천이를 유발하지 않는 경고 전용이므로 전처리/상태머신에 추가하지 않음.
- `ValidateHoldLast` 다중신호: persistent 단일 → 신호별 인스턴스 또는 배열화.
- 치명고장 확정 디바운스(C04): ✅ **반영** — `DebounceFaultCritical.m` (DEBOUNCE_TICKS=10 × TICK_MS=10ms = 100ms 연속 지속 시 확정).
- MC 10회 연속 실패 stale(C23): CheckCRC/CheckHeartbeat 와 결합한 stale 카운터 블록으로 확장.
