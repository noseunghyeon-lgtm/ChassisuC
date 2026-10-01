# Mermaid 상태 다이어그램

> 상태 카드(`08`)·전이표(`01`)를 Mermaid 로 도식화. 명칭은 명칭 사전(`00_glossary.md`) 정본.
> GitHub/VSCode/mermaid.live 에서 렌더링된다.
> 전이 라벨의 `T##` 는 전이표(01) ID, 우선순위는 각 상태 이탈 평가 순서(§3).

---

## 1. 전체 상태 전이도 (Full State Diagram)

```mermaid
stateDiagram-v2
    direction TB

    [*] --> S0

    state "S0 · Sleep" as S0
    state "INIT · Initialization" as INIT
    state "S1 · Manual (유인)" as S1
    state "S2 · Remote-Armed" as S2
    state "S3 · Remote-Active" as S3
    state "S4 · AEBS-Override" as S4
    state "S5 · Comm-Loss Brake" as S5
    state "S6 · Fault Safe State" as S6

    S0   --> INIT : T01 wake / IG_ON
    INIT --> S1   : T02 selftest + gear_ready
    INIT --> S6   : T03 fault_confirmed
    S1   --> S0   : T04 IG_OFF

    S1   --> S2   : T05 interlock6 + REQ_TO_S2
    S2   --> S1   : T06 REQ_TO_S1 + cam_origin
    S2   --> S3   : T07 neutral + first_cmd
    S3   --> S2   : T08 REQ_TO_S2 + stop

    S2   --> S5   : T09 HB timeout
    S3   --> S5   : T09 net 0-1 / HB timeout
    S5   --> S2   : T10 HB_ok + stop

    S1   --> S4   : T11 AEBS
    S2   --> S4   : T11 AEBS
    S3   --> S4   : T11 AEBS
    S4   --> S1   : T12 prev=S1
    S4   --> S2   : T12 prev=S2 or S3

    S1   --> S6   : T14 fault manned
    S2   --> S6   : T13 fault
    S3   --> S6   : T13 fault
    S4   --> S6   : T13 fault
    S5   --> S6   : T13 fault
    S6   --> S0   : T15 IG_OFF + dtc_cleared

    note right of S6
      비가역: IG-OFF 재기동+DTC 클리어만 이탈
      유인(S1) 진입 시 최대제동 금지 (TBD §6-2)
    end note
    note right of S2
      유일한 원격 재진입 관문
    end note
```

---

## 2. 정상 운용 루프 (유인 ↔ 원격) — 핵심 흐름만

```mermaid
stateDiagram-v2
    direction LR

    state "S1 Manual" as S1
    state "S2 Remote-Armed" as S2
    state "S3 Remote-Active" as S3

    S1 --> S2 : 원격진입 interlock6
    S2 --> S1 : 원격해제 cam_origin
    S2 --> S3 : 추종개시 중립+첫명령
    S3 --> S2 : 세션종료 차속0

    note left of S1
      순정 레버(GL) 철거 →
      변속계통 여자 유지 (§1.3)
    end note
    note right of S3
      S3→S1 직접 금지 (S2 경유)
    end note
```

---

## 2.1 S3 통신 Degradation (서브상태)

```mermaid
stateDiagram-v2
    direction LR

    state S3 {
        [*] --> S3_Normal
        state "S3_Normal 정상 추종" as S3_Normal
        state "S3_Degraded 속도제한+LED점멸" as S3_Degraded

        S3_Normal --> S3_Degraded : net 2-4
        S3_Degraded --> S3_Normal : net 5-10
    }

    S3 --> S5 : net 0-1 (Stop)

    note right of S3_Degraded
      vc_net_level 2-4
      속도 제한 10kph + LED 점멸
    end note
    note right of S5
      완전 두절 → 정지 시퀀스
    end note
```

---

## 3. 안전 개입 계열 (S4 / S5 / S6)

```mermaid
stateDiagram-v2
    direction TB

    state "S2/S3 (원격)" as RUN
    state "S4 AEBS-Override" as S4
    state "S5 Comm-Loss Brake" as S5
    state "S6 Fault Safe" as S6

    RUN --> S4 : AEBS TTC 0.8s
    RUN --> S5 : HB timeout
    RUN --> S6 : 치명고장 확정
    S4  --> RUN : 해제(직전 S3→S2)
    S5  --> RUN : 복구+차속0 (S2로)
    S4  --> S6 : 치명고장
    S5  --> S6 : 치명고장

    note right of S6
      비가역
    end note
    note left of S4
      S4+S5 제동=최댓값 중재
      S5→S3 직접 금지
    end note
```

---

## 4. 우선순위 평가 순서 (§3) — 플로우차트

```mermaid
flowchart TD
    A["10ms tick 입력 수집"] --> P0{"E-Stop?"}
    P0 -->|Yes| ES["우선순위 0 · 결과상태 TBD"]
    P0 -->|No| P1{"치명고장 확정?"}
    P1 -->|Yes| S6["S6 발행"]
    P1 -->|No| P2{"HB timeout? (S2/S3)"}
    P2 -->|Yes| S5["S5 발행"]
    P2 -->|No| P3{"TTC 0.8s 미만?"}
    P3 -->|Yes| S4["S4 발행"]
    P3 -->|No| P4{"모드 전환 요청?"}
    P4 -->|Yes| MODE["S1 - S2 - S3"]
    P4 -->|No| HOLD["현 상태 유지"]
```

---

## 5. 시스템 컨텍스트 (Chassis uC 연결)

```mermaid
flowchart TB
    Router["Router"]
    VSC["Video Streaming Computer (VSC)"]
    CC["Control Computer (CC)"]
    CHSS["Chassis uC (CHSSuC)"]
    FSM["FSM uC (FSMuC)"]
    PDU["PDU 전원분배"]
    RS["Remote Station (RS)"]

    Router --- VSC
    Router --- CC
    CC --- CHSS
    VSC -. Heartbeat .- CHSS
    CHSS <-. S6 공유 .-> FSM
    PDU --> CHSS
    CC --- RS

    CHSS --> RP["Remote Panel (RP)"]
    CHSS --> GS["Gear Shift Selector (GS)"]
    CHSS --> GA["Gear Actuator (GA)"]
    CHSS --> ACU["Accel Control Unit"]
    CHSS --> SU["Steering Control Unit (SU)"]
    CHSS --> BA["Brake Actuator (BA)"]
    CHSS --> CHS["Chassis 차속/차체"]

    CHSS -. E-Stop HW/CAN .- ESTOP["E-Stop 소스"]
```

---

## 6. INIT 내부 시퀀스 (기어계통 준비, §12-1)

```mermaid
stateDiagram-v2
    direction LR
    [*] --> GA_prep
    state "Power_ON_GA 기어 액추에이터 급전·단수확인" as GA_prep
    state "Power_ON_GS 실렉터 Handshake" as GS_prep
    state "Power_ON_EPS 조향 Wakeup (TBD)" as EPS_prep

    GA_prep --> GS_prep : gear_ready
    GS_prep --> EPS_prep : handshake_ok
    EPS_prep --> [*] : selftest_done
```

---

> **범례**
> - 실선 화살표 = 상태 천이, 라벨 = `T## 조건`
> - `note` = 안전 규칙·미해결(TBD)
> - §5 컨텍스트: 실선=제어/명령, 점선=Heartbeat·S6공유·E-Stop
> - 금지 천이(S3→S1, S5→S3, S6 원격이탈)는 **화살표를 그리지 않음**으로 표현
