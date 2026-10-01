# Chassis uC (ChassisController) 개념설계

> 범위: 시스템 아키텍처 기준으로 **Chassis uC 가 S0~S6 각 상태에서 수행하는 역할**과,
> **연결된 컴포넌트와의 상호작용**을 정리한다. 구현(Simulink/.slx)은 범위 밖(개념설계).
> 상태 정의 정본: 「차량 전체 상태천이 §3」, 구현 설계: 「전체 관리 프로세스 §2」.

---

## 1. 시스템 컨텍스트 — Chassis uC 의 연결

시스템 아키텍처 다이어그램에서 읽은 Chassis uC 의 경계와 연결.

```
                 ┌─────────────┐   ┌──────────────────┐
                 │   Router    │   │ Control Computer │──(원격명령/상태)
                 └─────────────┘   └──────────────────┘
                        │                   │
         ┌──────────────────────┐           │
         │ Video Streaming Comp.│           │
         └──────────────────────┘           │
                        │                   │
            ┌───────────▼───────────────────▼───────────┐
   PDU ───▶ │              Chassis uC (상태 단일 소유)      │ ◀┄┄▶ FSM uC (S6만 참조)
            └───┬────┬────┬────┬────┬────┬────┬──────────┘
                │    │    │    │    │    │    │
            Remote  Gear Accel Gear Steer Brake Chassis
            Panel   Shift Ctrl Actu  Ctrl  Actu (차체/
            (RMC)   Selector    ator  Unit  ator  차속)
```

### 1.1 연결 상대별 역할 (방향 = Chassis uC 기준)

| 상대 | 계층 | 방향 | 역할 |
| --- | --- | --- | --- |
| **Control Computer** | 상위 | in/out | 원격 명령 수신, `Chassis uC Status1`(상태) 발행 → RS |
| **Video Streaming Computer** | 상위 | in/out | **Heartbeat 상호 감시** — 각 컴포넌트가 유기적으로 동작 중인지 판단하는 목적. 영상 스트리밍 경로이자 생존 감시 링크 |
| **Router** | 상위 | — | 네트워크 백본 (Chassis uC 와 직접 로직 결합 없음) |
| **FSM uC** | 동급 | ⇄ (점선) | **S6 항목만** 공유. Chassis uC 가 상태 소유, FSM uC 는 참조 (§2) |
| **E-Stop 소스** | — | in | **Hardwire 또는 CAN** 으로 Chassis uC 가 수신·판단. 우선순위 0(최우선) |
| **PDU** | 전원 | in | 전원 공급. Wake/Sleep·암전류 관리와 연계 |
| **Remote Panel (RP)** | 하위 | in | 원격 조작 입력. S1→S2 진입 2단 조작(⚠️ Q-56). ※ RP≠RMC(리모컨) |
| **Gear Shift Selector (GS)** | 하위 | in/out | 운전자 기어 선택(S1), Handshake(§12-1) |
| **Accel Control Unit** | 하위 | out | 가속 제어 (S2~ 0고정/원격추종) |
| **Gear Actuator (GA)** | 하위 | out | 기어 액추에이터 급전·위치제어 |
| **Steering Control Unit (SU)** | 하위 | out | 조향 제어 (ServoUnit). ⚠️ Q-76 (S5/S6 거동) |
| **Brake Actuator** | 하위 | out | 제동 캠 제어. 캠 위치 정합(§4) |
| **Chassis** | 하위 | in | 차속·차체 상태 피드백 |

> **핵심(§2):** 하위 모듈은 상태를 **읽기만** 하고, Chassis uC 에 **「천이 요청」·「고장 보고」만** 올린다.
> 상태를 바꾸는 주체는 Chassis uC 단일 인스턴스뿐이다.

---

## 2. 컴포넌트별 상호작용 (신호 수준)

기존 데이터 딕셔너리(`02`) 신호를 컴포넌트에 귀속시킨 것.

| 컴포넌트 | Chassis uC 가 받는 것(in) | Chassis uC 가 주는 것(out) |
| --- | --- | --- |
| Control Computer | 원격 명령, `mode_req`, Heartbeat(`heartbeat_ok/age`) | `veh_state_code`(Status1), `dual_s4s5_flag`, `remote_cmd_lock` |
| FSM uC | (S6 상태 참조 요청) | S6 발행 공유 |
| PDU | 전원/`wake_source` | — |
| Remote Panel (RP) | `arm_rmc_2stage`*, `arm_rs_mutual_auth` | (조작 피드백) |
| Gear Shift Selector | 운전자 기어 선택, `gear_ready`(Handshake) | 실렉터 LED/릴레이 정합(§12-1 5단계) |
| Accel Control Unit | — | 가속 지령(0고정/원격) |
| Gear Actuator | 기어 위치/단수 | 급전·위치 지령(GA) |
| Steering Control Unit | 조향 상태 | 조향 지령(중립/원격/각 유지) |
| Brake Actuator | `cam_at_origin`, `pedal_pos` | 제동 캠 지령(위치0/최대제동) `brake_req_src_state` |
| Chassis | `vehicle_speed`, 차체 상태 | — |

---

## 3. 상태별(S0~S6) Chassis uC × 컴포넌트 역할 매트릭스 ★핵심

각 상태에서 Chassis uC 가 각 컴포넌트에 대해 수행하는 역할.
(`04_state_subsystem_matrix.md` 의 서브시스템 동작을 "Chassis uC 가 무엇을 하는가" 관점으로 재서술)

| 상태 | Control Computer | FSM uC | Brake Actuator | Gear(Selector/Actu) | Accel | Steering | Remote Panel |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **S0** Sleep | Status=S0, 저전력 | S6 아님 통지 | 무여자 지령 | 마지막 위치, IG-OFF 후 P→N | 순정 직결 | 순정 직결 | 비활성 |
| **INIT** | Status=INIT*, 원격 거부 | — | (자기진단) | **GA→GS→EPS 준비 시퀀스** | — | Wakeup | 요청 무시 |
| **S1** Manual | Status=S1 | S6 아님 | 무여자(운전자 조작) | 운전자 선택→릴레이 **GL-\*** 여자유지 | 순정 직결 | 순정 직결 | — |
| **S2** Remote-Armed | Status=S2, 명령 미수용 | — | 여자·위치0 유지 | 여자·변경거부 | 0 고정 | 중립 유지 | **2단 조작 수신**(진입조건) |
| **S3** Remote-Active | Status=S3, 명령 추종 | — | 원격 제동 추종 | 원격 추종(차속0 시*) | 원격 추종 | 원격 추종 | 원격 입력 |
| **S4** AEBS-Override | Status=S4 | 영향없음 | **최대제동**(원격과 max) | 변경거부·현위치 | **0 강제** | 원격 유지 | — |
| **S5** Comm-Loss | Status=S5(동시비트) | 영향없음 | **최대제동 유지** | 마지막 위치 | **0 강제** | 마지막 각 ⚠️Q-76 | 입력 무시 |
| **S6** Fault Safe | Status=S6, 원격 차단 | **S6 공유** | **최대제동 후 유지** ⚠️유인차등 | 변경금지·현위치 | **0 강제** | 마지막 각 ⚠️Q-76 | 입력 차단 |

\* INIT 발행코드 255(TBD), S3 Gear "차속0 시에만"(TBD_STANDSTILL_SPEED), Q-76 = 조향 거동 미확정.

---

## 4. Chassis uC 가 하는 일 / 하지 않는 일 (책임 경계)

| 한다 (Chassis uC 소관) | 하지 않는다 (타 소관) |
| --- | --- |
| 상태 **단일 소유** 및 S0~S6 발행(10ms) | 제동량 **max 중재** → 「제동 명령 중재」 |
| **모든 모드의 우선순위(Priority) 단독 관리**(E-Stop>S6>S5>S4>모드) ★확정 | 치명고장 **확정 디바운스** → 「진단」§4 |
| **E-Stop 수신·판단**(Hardwire 또는 CAN) ★확정 | — |
| **Heartbeat 감시**: Control Computer(원격) + Video Streaming Computer(생존) ★확정 | Heartbeat **임계값 결정** → SRS-SYS-007 |
| 진입/이탈 **액션 시퀀스**(§4) 지휘 | 모듈 내부 제어 로직 → 각 모듈 |
| 금지천이 원천차단·SW결함 DTC(§7) | Heartbeat **임계값 결정** → SRS-SYS-007 |
| 자기진단(틱지연·무결성·이력·워치독, §8) | AEBS **판정** → AEBS(SRS-SYS-003) |
| 모듈의 **천이요청·고장보고 수신** | 상태 **변경 권한을 모듈에 위임** (금지) |

---

## 5. 1틱(10ms) 동작 개념

```
수집(센서·모듈 입력)
  → 자기진단(틱지연/무결성 §8)
  → 우선순위 평가(§3: E-Stop > S6 > S5 > S4 > 모드전환)
  → 천이 판정(가드 §2 전이표, 금지천이 차단 §7)
  → 진입/이탈 액션 시퀀스(§4)
  → 상태 발행(Chassis uC Status1 → Control Computer, FSM uC 에 S6 공유)
```

---

## 6. 미해결(개념설계 관점 재배치)

### ✅ 이번에 확정된 사항
- **우선순위 관리**: 모든 모드 Priority 를 Chassis uC 가 **단독** 관리.
- **E-Stop 입력 경로**: Hardwire 또는 CAN 으로 Chassis uC 가 수신·판단 (우선순위 0). *단, 결과 상태는 「안전」 소관 TBD(C01).*
- **Video Streaming Computer**: 영상 경로이자 **Heartbeat 상호 감시** 링크. 컴포넌트 생존 판단 목적.
- **영상 Heartbeat 상실 대응 확정**: `S5` 를 유발하지 **않고**, **원격 스테이션 경고등**(`video_hb_warn`)만 발생. 상태천이 없음(AEBS 경고와 동일 성격). → **두 Heartbeat 심각도 분리**: 명령 HB 상실=S5(안전조치), 영상 HB 상실=경고(HMI).

### ⚠️ 남은/신규 미해결
| 항목 | Chassis uC 관점 영향 |
| --- | --- |
| **🆕 Heartbeat 임계값(영상)** | 영상 HB 상실 **판정 시간**이 Control HB(400ms)와 같은가 다른가 (경고 발생 임계) |
| **FSM uC S6 공유 메커니즘** | 점선 연결의 **신호/프로토콜 미정의** — Chassis uC push vs FSM uC poll? |
| **E-Stop 결과 상태(C01)** | 입력 경로는 확정, **어느 상태로 보낼지**(S5? S6? 전용?)는 「안전」 소관 |
| **E-Stop 전송 매체 선택** | Hardwire **and/or** CAN — 둘 다인지 택일인지, 다중화 시 중재 규칙 |
| Q-76 (조향) | S5/S6 에서 Steering Control Unit 에 줄 지령 미확정 |
| RMC 2단 조작(Q-56) | Remote Panel 핀 부재로 S2 진입조건 성립성 위협 |
