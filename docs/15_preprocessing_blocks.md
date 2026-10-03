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
