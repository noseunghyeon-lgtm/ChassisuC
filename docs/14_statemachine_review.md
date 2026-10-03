# 상태머신 고도화 점검 (Review & Hardening)

> `src/build_chassis_controller.m` 코어 상태머신을 전수 점검해 **놓친 부분·공백**을 정리하고
> 고도화 방향을 제시한다. 중요도: 🔴 심각(안전/기능 공백) · 🟡 중간 · 🟢 개선.

---

## 1. 발견된 공백

### 🔴 G1. E-Stop 미연결 (우선순위 0인데 전이 없음)
- `estop_active` 입력은 정의됐으나 **어떤 전이의 가드에도 쓰이지 않음**.
- §3 우선순위 0(최우선)인데 **구현 공백**. 결과 상태는 C01(미정)이라도, 최소한
  **E-Stop 수신 시 즉시 안전상태로 가는 전이 자리**가 있어야 한다.
- **조치**: E-Stop → 전용 안전처리. 임시로 `estop_active` 시 S5(제동) 또는 S6 로 가는
  **최우선(ExecutionOrder=0) 전이**를 각 운용 상태에 추가하되 결과상태는 TBD 주석.

### 🔴 G2. INIT 상한시간(타임아웃) 전이 누락
- 정본 §3.1: "자기진단 실패 **또는 상한 시간 초과** → S6".
- 현재: `INIT→S1`(selftest_done) / `INIT→S6`(fault)만. **타임아웃→S6 없음**.
- 자기진단이 끝나지 않으면 **INIT 에 영구 체류** 위험.
- **조치**: `init_timeout` 입력(또는 로컬 타이머) 추가 → `INIT→S6` 가드에 OR.

### 🟡 G3. S5(통신두절)에서 AEBS 진입 불가
- T11(AEBS)은 S1/S2/S3 에서만. S5 체류 중 AEBS 판정이 서도 **무시**됨.
- 통신두절로 제동 중이어도 전방 충돌 위험 시 AEBS 가 추가 개입해야 하는지 **정책 확인 필요**.
- (S5 는 이미 최대제동이라 실익이 적을 수 있음 — 설계 의도 확인)

### 🟡 G4. during 액션(지속 로직) 전무
- 로컬 변수 `heartbeat_timer_ms`, `tick_overrun`, `state_integrity_ok`, `prev_state_before_s4`
  중 **타이머/자기진단 로직이 어디서도 수행되지 않음**(prev_state 만 전이 액션에서 사용).
- §8 자기진단(틱지연·무결성·워치독·천이이력)이 **미구현**.
- **조치**: 차트 레벨 `during` 또는 전용 함수 상태에서 매 틱 수행.

### 🟡 G5. heartbeat_age_ms 산출 주체 불명확
- 가드가 `heartbeat_age_ms > 400` 를 쓰지만, 이 값을 **누가 증가/리셋**하는지 상태머신에 없음.
- 전처리(§12 AliveCounter 정체감시)에서 산출한다면 **입력으로 명시**, 내부 산출이면 during 필요.
- **조치**: 전처리 산출로 확정(§12와 일치) → 주석 명확화.

### 🟡 G6. 금지천이 "시도 감지→DTC" 미구현
- §7: 정의되지 않은 상태값 → 즉시 S6, 금지천이 시도 시 `sw_defect_dtc` 발행.
- 현재는 금지천이를 **생성 안 함**으로 차단만. **런타임 감지→DTC 로직은 없음**.
- **조치**: 차트 레벨 감시(상태 enum 범위 검사) 추가.

### 🟢 G7. S4+S5 동시성립 플래그 미설정
- `dual_s4s5_flag` 출력 선언만, **설정 로직 없음**. §3 "동시 성립 시 별도 비트".
- **조치**: during 에서 `(aebs_flag && hb_timeout)` 시 플래그 set.

### 🟢 G8. fault_suspect(의심) 처리 없음
- §6-3: 「의심」 구간은 상태 불변·원격명령만 제한. `fault_suspect` 입력 선언만, 미사용.
- **조치**: during 에서 `fault_suspect` 시 `remote_cmd_lock` 또는 명령제한.

### 🟢 G9. INIT 서브상태(GA→GS→EPS) 미구현
- 개념설계·§12-1 의 기어계통 준비 시퀀스가 코어엔 없음(단일 INIT). `gear_ready` 입력으로 추상화.
- 코어 범위상 OK 이나, 상세화 시 INIT composite 로 확장 여지.

---

## 2. 우선 조치 (이번 반영)

| 공백 | 조치 | 반영 |
| --- | --- | --- |
| G1 E-Stop | `estop_active` 최우선(순위 0) 전이 — S1~S5 각각 → S6(임시). 결과상태 C01 TBD | ✅ 반영 |
| G2 INIT 타임아웃 | `init_timeout` 입력 추가 + `INIT→S6` 가드에 OR | ✅ 반영 |
| G4/G5 during | 차트 during: dual flag·fault_suspect 실동작 + 자기진단 골격(주석) | ✅ 반영 |
| G7 dual flag | during 에서 `aebs_flag && hb_timeout` 시 set | ✅ 반영 |
| G8 fault_suspect | during 에서 `remote_cmd_lock` set | ✅ 반영 |

**반영 세부 (이번 커밋):**
- E-Stop 전이 5건(S1~S5 → S6, ExecutionOrder=0 최우선). 결과상태는 C01 확정 시 교체.
- `INIT→S6` 가드 = `fault_critical_confirmed || init_timeout`.
- 차트 레벨 `during`: `dual_s4s5_flag` 설정, `fault_suspect→remote_cmd_lock`, 자기진단(G4)·범위감시(G6) TODO 골격.
- 정적검토: 데이터 61개 이름 중복 없음, E-Stop 5전이 확인.

> G3(S5 AEBS), G6(DTC 감시 상세), G9(INIT 서브상태)는 **정책/상세 확인 후** 반영.

---

## 3. 남은 확인 질문 (사용자)
1. **G1**: E-Stop 결과 상태는? (S5 제동? S6? E-Stop 전용 상태?) — C01
2. **G2**: INIT 자기진단 상한시간 수치? — SRS-SYS-039
3. **G3**: S5(통신두절 제동 중) AEBS 추가 개입 필요?
4. **G6**: 금지천이 시도·상태 enum 범위이탈 → S6 즉시 전이 추가할지?
