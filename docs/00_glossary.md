# 명칭 사전 (Glossary / Naming Convention) — 정본

> 본 프로젝트의 **단일 명칭 정본**이다. 모든 문서·다이어그램·코드·CAN 신호는 이 사전을 따른다.
> 이름 충돌·불일치가 발견되면 이 사전이 우선하며, 사전에 없는 용어는 여기에 먼저 등재한다.
> 형식: **정본 영어명 / 정본 한국어명 / 표 내 약칭**. 약칭 미정은 `—`.

---

## 1. 컴포넌트 (시스템 아키텍처)

| 정본 명칭 (영어) | 정본 명칭 (한국어) | 약칭 |
| --- | --- | --- |
| Router | 라우터, 통신 단말기 | — |
| Video Streaming Computer / Video Computer | 영상 컴퓨터, 영상 스트리밍 컴퓨터 | VSC, VC, COM1 |
| Control Computer | 제어 컴퓨터 | CC, COM2 |
| Chassis uC / Chassis Controller | 구동부 제어 컨트롤러 | CHSSuC |
| FSM uC / FSM Controller | 소방특장 제어 컨트롤러 | FSMuC |
| PDU | 전원분배장치 | — |
| Remote Station / Portable Remote Station / Portable Station | 포터블 원격스테이션, 포터블 스테이션 | RS |
| RS Control Computer | RS 제어 컴퓨터 | RSCC |
| RS Video Computer | RS 영상 컴퓨터 | RSVC |
| RS uC | RS 제어 컨트롤러 | RSuC |
| Remocon | 리모컨 | RMC |

### 1.2 액추에이터 · 입력장치 · 센서 (정본 — 사용자 제공표)

| 정본 명칭 (영어) | 정본 명칭 (한국어) | 약칭 |
| --- | --- | --- |
| Remote Panel | 원격패널, 원격조종패널 | RP |
| Gear Shift Lever | 변속기어레버 | GL |
| Gear Shift Selector / Gear Selector / Gray-Hill Selector | 변속기어실렉터 | GS, GH |
| Gear Shift Lever Relay | 변속기어릴레이, 변속기어레버릴레이 | — |
| Gear Actuator | 기어 액추에이터 | GA |
| Brake Actuator | 브레이크 액추에이터 | BA |
| Accel Control Unit | 가속페달제어유닛, 가속페달제어 시스템 | — |
| RC Filter | RC필터, 가속페달용 RC필터 | RCF |
| Steering Control Unit / ServoUnit | 조향제어유닛, 조향할퀴제어 시스템, 서보유닛 | SU |
| Chassis | 차량제어, 차량정보 | — |
| Radar Sensor | 레이더 | — |

> 소방특장(FSM) 측 센서/장치(Fire Gun Camera, Heat Camera, Water Pressure Sensor,
> Heat Flux Sensor, Fire Control Panel, Fire Gun Joystick 등)는 FSM uC 소관으로
> Chassis uC 상태머신과 직접 결합이 적어 별도 등재 보류. 필요 시 추가.

> ✅ **Remote Panel(RP) ≠ Remocon(RMC)** 확정 — RP는 원격조종패널, RMC는 리모컨으로 별개 장치.

---

## 2. 상태 (S0~S6) — ★상태 명칭 통일 정본

| 상태 ID | 정본 명칭 (영어) | 정본 명칭 (한국어) | 코드 식별자 (enum) | CAN 발행코드 |
| --- | --- | --- | --- | --- |
| `S0` | Sleep | 슬립 | `SLEEP` | 0 |
| `INIT` | Initialization | 초기화 (부팅 자기진단) | `INIT` | 255 (TBD) |
| `S1` | Manual | 수동 운전 | `MANUAL` | 1 |
| `S2` | Remote-Armed | 원격 준비(무장) | `REMOTE_ARMED` | 2 |
| `S3` | Remote-Active | 원격 주행 | `REMOTE_ACTIVE` | 3 |
| `S4` | AEBS-Override | AEBS 오버라이드 | `AEBS_OVERRIDE` | 4 |
| `S5` | Comm-Loss Brake | 통신두절 제동 | `COMM_LOSS_BRAKE` | 5 |
| `S6` | Fault Safe State | 고장 안전상태 | `FAULT_SAFE_STATE` | 6 |

**명칭 통일 규칙:**
- **상태 ID**(`S0`~`S6`, `INIT`) = 진짜 정본. 모든 자료가 공유 (이미 일치).
- **표시명**(영/한) = 문서·다이어그램·HMI 에 사용.
- **코드 식별자** = enum/변수. 표시명을 `UPPER_SNAKE_CASE` 로 기계 변환 (하이픈→언더스코어).
- **CAN 발행코드**(0~6) = 불변. 식별자 리네임해도 영향 없음.

**이전 식별자 → 정본 (리네임 매핑):**
| 이전(초안) | 정본 | 비고 |
| --- | --- | --- |
| `REMOTE_READY` | `REMOTE_ARMED` | S2 |
| `AEBS` | `AEBS_OVERRIDE` | S4 |
| `SAFE_STOP` | `COMM_LOSS_BRAKE` | S5 |
| `FAULT_SAFE` | `FAULT_SAFE_STATE` | S6 (접미사 통일) |

---

## 3. 약어 (Abbreviations)

| 약어 | 전개 | 비고 |
| --- | --- | --- |
| AEBS | Advanced Emergency Braking System | 긴급제동 |
| HB | Heartbeat | 생존 감시 |
| EPS | Electric Power Steering | 조향 |
| GA / GS | Gear Actuator / Gear Shift Selector | 기어 계통 |
| DTC | Diagnostic Trouble Code | 고장 코드 |
| TTC | Time-To-Collision | 충돌까지 시간 |
| FTTI | Fault Tolerant Time Interval | 결함 허용 시간 |
| TBD | To Be Determined | 미확정 |

---

## 4. 적용 상태

- [ ] 상태 식별자 리네임을 전 문서·스크립트에 반영 (§2 매핑: `REMOTE_READY→REMOTE_ARMED` 등)
- [x] "Remote Panel vs RMC" 동일성 확인 → **별개 확정** (RP=원격조종패널, RMC=리모컨)
- [ ] 신호명 `arm_rmc_2stage` 검토 — 2단 조작 장치는 **RP**인데 신호명은 `rmc` → `arm_rp_2stage` 로 변경 검토
- [ ] `GL`(Gear Shift Lever) 확정 반영 — 기존 문서의 "GL-\*" 표기를 "GL(변속기어레버)"로 명확화
- [ ] 신호(데이터) 명명 규칙 — 별도 결정 대기 (상태명 통일 후)

> ⚠️ **GL / GS / GA / GL Relay 관계 (정본표에서 확정)**: 운전자가 **GS(실렉터)** 조작 →
> Chassis uC → **GL Relay(변속기어릴레이)** → **GL(변속기어레버)** 활성, 그리고 **GA(기어 액추에이터)**
> 가 실제 기어 위치 제어. 기존 문서의 "GL-\*"는 이 GL(변속기어레버)을 가리킴.

> 이 사전은 자료가 추가될 때마다 갱신한다. 신규 용어는 **먼저 여기 등재 후** 다른 문서에서 사용.
