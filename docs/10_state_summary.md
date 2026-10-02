# 상태 종합 정리 (S0~S6) — 정의 · 역할 · 천이

> 각 상태의 **① 상태 정의 · ② 해당 State에서 해야 할 일(역할) · ③ 천이 조건**을 종합 정리.
> 명칭 사전(`00_glossary.md`) 정본 기준. 상세 전이는 `01`, 상태 카드는 `08`, 그림은 `09` 참조.
> `[TBD]`·⚠️ = 미확정.

---

## 한눈 요약

| 상태 | 명칭 | 유·무인 | 가역성 | 한 줄 역할 |
| --- | --- | --- | --- | --- |
| S0 | Sleep | — | — | 전원 off, 암전류 관리 |
| INIT | Initialization | — | — | 부팅 자기진단, 원격 거부 |
| S1 | Manual | 유인 | — | 운전자 수동 운전 |
| S2 | Remote-Armed | 무인 | 가역 | 원격 무장·대기(명령 미수용) |
| S3 | Remote-Active | 무인 | 가역 | 원격 주행 (서브: Normal / **Degraded**=통신열화) |
| S4 | AEBS-Override | 무인 | 가역 | AEBS 강제 제동 |
| S5 | Comm-Loss Brake | 무인 | 가역 | 통신두절 비상 제동 |
| S6 | Fault Safe State | — | **비가역** | 치명고장 안전정지 |

---

## S0 — Sleep

**① 상태 정의**
IG-OFF 상태. 상시전원 대상만 생존하고 나머지는 무여자. 암전류(dark current) 관리 구간.

**② 해당 State에서 해야 할 일**
- 발행: `veh_state_code = 0`, `remote_cmd_lock = true`
- Brake(BA): 무여자, 캠 원점
- Gear(GS/GA/GL): 마지막 위치 유지, IG-OFF 시퀀스 완료 후 **P→N**
- Accel / Steering(SU): 순정 직결
- FSM uC: OFF
- 저전력 유지, Wake 소스 대기

**③ 천이 조건**
- 들어옴: `S1→S0`(IG_OFF, S1에서만), `S6→S0`(IG_OFF 재기동 + DTC 클리어)
- 나감: `S0→INIT`(wake_source 또는 IG_ON)
- 미해결: S0 진입 지연 `[TBD]`(「전원/Wake-up」)

---

## INIT — Initialization

**① 상태 정의**
IG-ON 직후 부팅 자기진단 구간. S1 도 S6 도 아니다. 통과 시 S1, 실패/시간초과 시 S6.

**② 해당 State에서 해야 할 일**
- 발행: `veh_state_code = 255`(⚠️ TBD 인코딩), `remote_cmd_lock = true`
- **모든 원격 천이 요청 거부**(§6-1)
- **기어계통 준비 시퀀스 GA→GS→EPS**(§12-1): 기어 액추에이터 급전→단수확인→실렉터 Handshake→조향 Wakeup
- 자기진단 전 항목 수행(SRS-SYS-039)

**③ 천이 조건**
- 들어옴: `S0→INIT`
- 나감: `INIT→S1`(selftest_done && gear_ready), `INIT→S6`(치명고장 확정)
- 미해결: INIT 인코딩(C02), INIT→S1 실패처리(C08)

---

## S1 — Manual

**① 상태 정의**
운전자 탑승 **유인 수동 운전**. 원격 액추에이터(제동·가속·조향)는 무여자 또는 백드라이브 허용.
**예외**: 순정 레버(GL) 철거로 Chassis uC·변속기어릴레이(GL Relay)는 **여자 유지**(§1.3).

**② 해당 State에서 해야 할 일**
- 발행: `veh_state_code = 1`, `remote_cmd_lock = false`
- Brake(BA): 무여자, 운전자 페달 직접 조작(답력 규정치 이하)
- Gear: 운전자 **GS 조작 → Chassis uC → GL Relay → GL 활성**(순정 레버 철거로 우회 불가)
- Accel / Steering(SU): 순정 직결
- FSM uC: 운전자 조작 가능

**③ 천이 조건** *(나감은 우선순위 순)*
- 들어옴: `INIT→S1`, `S2→S1`(원격 해제, cam_at_origin), `S4→S1`(AEBS 해제·직전 S1)
- 나감:
  1. `S1→S6` 치명고장/제어위협 — **유인: 최대제동 금지 + 원격기능 잠금 + 원격모드 진입불가** ✅C03
  2. `S1→S4` AEBS(TTC<0.8s)
  3. `S1→S2` 원격 진입(interlock 6조건 AND)
  4. `S1→S0` IG-OFF
- 미해결: 유인 S6 정책(C03/M04)

---

## S2 — Remote-Armed

**① 상태 정의**
RS 인증 완료·액추에이터 여자 완료. 아직 원격 명령을 수용하지 않는 **대기(무장)** 상태. 무인.
**유일한 원격 재진입 관문** — S3 이탈도, S4·S5 해제도 전부 S2 를 거친다.

**② 해당 State에서 해야 할 일**
- 발행: `veh_state_code = 2`
- Brake(BA): 여자, **위치 0 유지**, 제동 명령 미수용
- Gear: 여자, **기어 변경 명령 거부**
- Accel: 0 고정
- Steering(SU): **중립 유지**
- FSM uC: 대기, 방수총 방향 조종 가능
- Remote Panel(RP): 2단 조작 수신(S3 진입 조건)

**③ 천이 조건** *(나감은 우선순위 순)*
- 들어옴: `S1→S2`(진입 6조건), `S3→S2`(세션종료·차속0), `S5→S2`(복구·차속0), `S4→S2`(AEBS 해제·직전 S2/S3)
- 나감:
  1. `S2→S6` 치명고장 확정
  2. `S2→S5` HB 400ms 초과
  3. `S2→S4` AEBS
  4. `S2→S3` 추종 개시(중립 && 첫 유효명령)
  5. `S2→S1` 원격 해제(cam_at_origin)
- 미해결: RP 2단조작 핀 부재(C07/Q-56), 차속0 임계(C05)

**S1→S2 진입 6조건 (모두 AND):** ① RS 상호인증 ② RP 2단 조작 ③ 차속 0 ④ 브레이크 답력 ⑤ 브레이크 원격 설정 ⑥ 기어 P

---

## S3 — Remote-Active (서브상태: Normal / Degraded)

**① 상태 정의**
원격 명령 추종 중. **정상 원격 주행** 상태. 무인.
통신 네트워크 레벨(`vc_net_level`, 0~10)에 따라 **2개 서브상태**로 동작:
- **S3_Normal** — Net Level 5~10: 정상 원격 추종
- **S3_Degraded** — Net Level 2~4: **통신 열화 → 속도 제한(10 kph) + LED 점멸**

워치독 리셋 후 **S3 로 자동 복귀하지 않는다**(§8) — 반드시 INIT 부터 재시작.

**② 해당 State에서 해야 할 일**

*S3_Normal:*
- 발행: `veh_state_code = 3`
- Brake / Accel / Steering: 모두 **원격 명령 추종**
- Gear: 원격 기어 명령 추종(**차속 0 조건 만족 시에만** ⚠️)
- FSM uC: 원격 명령 추종

*S3_Degraded (통신 열화):*
- **속도 제한 10 kph** 활성 (`speed_limit_active`, `DEGRADED_SPEED_LIMIT=10`)
- **LED 점멸** (`degraded_led_blink`) → 원격 스테이션 / 내부 LED (점멸주기 `[TBD]`)
- 그 외 원격 추종은 유지 (제한된 성능으로)

**③ 천이 조건** *(나감은 우선순위 순)*
- 들어옴: `S2→S3`(유일 경로: 중립 && 첫 유효명령) → S3_Normal 진입
- 서브상태 간:
  - `S3_Normal → S3_Degraded`: `vc_net_level` 2~4
  - `S3_Degraded → S3_Normal`: `vc_net_level` 회복(5 이상, ⚠️TBD)
- 나감:
  1. `S3→S6` 치명고장 확정
  2. `S3→S5` **`vc_net_level` 0~1 (Stop)** 또는 HB 400ms 초과
  3. `S3→S4` AEBS
  4. `S3→S2` 세션종료(차속0)
- **금지**: `S3→S1` 직접(반드시 S2 경유, §7)
- 미해결: 차속0 조건(C05), LED 점멸주기(C17 일부). (C18 net_level은 외부 수신으로 종결)

---

## S4 — AEBS-Override

**① 상태 정의**
AEBS 가 제동을 강제 점유. 원격 제동·가속 명령보다 우선. 무인.
`S4`·`S5` 배타 아님 — 동시 성립 시 제동 요구는 **두 요구원의 최댓값**.

**② 해당 State에서 해야 할 일**
- 발행: `veh_state_code = 4`. 진입 시 `prev_state_before_s4` 보관
- Brake(BA): **최대 제동**, 원격 제동 명령과 비교해 **큰 값 채택**
- Gear: 변경 거부, 현 위치 유지
- Accel: **0 강제**
- Steering(SU): 원격 명령 유지
- FSM uC: 영향 없음

**③ 천이 조건** *(나감은 우선순위 순)*
- 들어옴: `S1/S2/S3→S4`(TTC<0.8s, 직전상태 보관)
- 나감:
  1. `S4→S6` 치명고장 확정
  2. `S4→S1` 해제·직전 S1
  3. `S4→S2` 해제·직전 S2 또는 **S3(→S2 로 복귀, §6-4)**
- 미해결: AEBS 진입소스 "임의"→S1/S2/S3 로 좁히기(M03)

---

## S5 — Comm-Loss Brake (Stop 시퀀스)

**① 상태 정의**
통신 **완전 두절**(`vc_net_level` 0~1) 또는 Heartbeat 타임아웃 시의 **정지(Stop) 시퀀스**. 무인.
S3 의 Degradation(S3_Degraded)에서 통신이 더 악화되면 여기로 진입하는 **최후 안전상태**.
S2·S3 에서만 진입. **영상 HB 상실은 S5 아님**(원격 스테이션 경고등만).

**② 해당 State에서 해야 할 일**
- 발행: `veh_state_code = 5`, S4+S5 동시 시 `dual_s4s5_flag`
- Brake(BA): **최대 제동 유지**
- Gear: 마지막 위치 유지(SRS-SYS-028)
- Accel: **0 강제**
- Steering(SU): **홀드 — EPS 제어 안 함, 내력(조향 토크) 미발생** ✅C06
- FSM uC: 영향 없음

**③ 천이 조건** *(나감은 우선순위 순)*
- 들어옴: `S2/S3→S5` (`vc_net_level` 0~1 **또는** HB 400ms 초과). S3_Degraded 에서 악화 시 포함
- 나감:
  1. `S5→S6` 치명고장 확정
  2. `S5→S2` 통신 복구 && 차속0(**S2 경유 필수**)
- **금지**: `S5→S3` 직접(반드시 S2 경유, §7·SRS-SYS-023)
- 미해결: 차속0 임계(C05). (C06 Q-76 ✅해소: 홀드·EPS 제어 안 함)

---

## S6 — Fault Safe State

**① 상태 정의**
안전중요도 치명 등급 고장 **확정**(검출 아님, §6-3 디바운스). 제동 유지 후 전 원격 입력 차단.
**비가역** — IG-OFF 재기동 + DTC 클리어로만 이탈.

**② 해당 State에서 해야 할 일**
- 발행: `veh_state_code = 6`, `remote_cmd_lock = true`
- Brake(BA): **최대 제동 후 유지** — 단 **유인(S1) 진입 시: 최대제동 금지, 원격기능만 잠금, 원격모드 진입 불가** ✅C03
- Gear: 변경 금지, 현 위치 유지
- Accel: **0 강제**
- Steering(SU): **홀드 — EPS 제어 안 함, 내력 미발생** ✅C06
- FSM uC: 정지. **S6 공유**(Chassis uC → FSM uC)

**③ 천이 조건**
- 들어옴:
  - `INIT→S6`(자기진단 중 치명고장)
  - `S1(유인)→S6`(치명고장/제어위협 — **최대제동 금지 + 원격기능만 잠금 + 원격모드 진입불가** ✅C03)
  - `S2/S3/S4/S5(무인)→S6`(치명고장 — 최대제동 후 유지)
- 나감: `S6→S0`(IG-OFF 재기동 + DTC 클리어)
- **금지**: 원격 이탈 불가(§7) — 물리적 개입 필수
- 미해결: 디바운스 N·T(C04), DTC클리어(C10). (C03 유인정책·C06 Q-76·C14 FSM공유 ✅해소)

---

## 공통 — 우선순위 평가 (§3, Chassis uC 단독 관리)

모든 상태에서 나가는 천이는 아래 순서로 평가:

**E-Stop(0, [TBD]) > 치명고장 S6(1) > HB상실 S5(2) > AEBS S4(3) > 모드전환(4)**

- S4+S5 동시: 발행은 상위(S5), 제동은 최댓값 중재
- E-Stop: Hardwire/CAN 수신, 결과 상태 `[TBD]`(「안전」)
