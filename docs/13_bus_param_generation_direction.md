# CANDB → Simulink Bus/Param 생성 방향성 분석

> 목적: CANDB(`DB_ChassisuC.xlsx`) 기준으로 Simulink **Bus(신호 묶음)·Param(파라미터)** 를
> 생성하는 로직을 사용자가 추후 작성할 때, **후작업이 최소화되는 방향**을 제시한다.
> (실 MATLAB 시뮬레이션은 본 환경에 없어 미실행 → DB 정량 분석 기반 판단)

---

## 0. 핵심 이슈: 신호 생성 순서

- **증상**: Bus/신호가 **Signal Name 이름순**으로 생성됨 (예: `Battery_Status`(bit56)가 맨 앞).
- **DB 실측**: 71개 메시지 **전부 원본 행이 Start Bit 오름차순**으로 정렬돼 있음.
- **원인 추정**: 생성 로직이 신호를 **이름(알파벳)으로 정렬**하거나, Map/struct 키 순회가
  삽입순이 아닌 **키 정렬 순서**를 따름.
- **방향**: 생성 시 **Start Bit 기준 명시적 정렬** 후 Bus Element 추가. (아래 §2)

---

## 1. DB 정량 특성 (방향 판단 근거)

| 항목 | 실측 | 생성 로직 함의 |
| --- | --- | --- |
| 전체 신호 | 504개 / 71 메시지 | — |
| **Start Bit 정렬** | 원본 100% 오름차순 | 원본 순서 보존 or Start Bit 정렬이면 OK |
| Signal Name 중복 | 1건(`ParameterGroupNumber`) | 메시지 간 동일 이름 가능 → **Bus는 메시지 단위 네임스페이스** 필요 |
| Signal≠DBC Signal | 8건 (예: `Status_ThermalCAM`→`CC_Status_ThermalCAM`) | **DBC Signal(접두사 포함)** 이 전역 유일 → 이름 소스로 DBC Signal 권장 |
| 바이트 비정렬 신호 | 298건 (startbit/len 8의 배수 아님) | 비트필드 많음 → **CAN Unpack(비트 추출)** 필수, 단순 바이트 분해 불가 |
| 바이트 경계 교차 | 0건 | 다행히 한 신호가 바이트 경계를 "쪼개 넘지"는 않음 → Unpack 안전 |
| 스케일/오프셋 | 135건 | **물리값 변환(raw×factor+offset)** 필요 신호 다수 |
| Reserved 신호 | 22개 | Rsvd는 Bus 생성 **제외 옵션** 두면 모델 간결 |

---

## 2. 방향 A vs B — 후작업 비교

### 방향 A. 원본 행 순서 보존 (삽입순)
- Excel 행을 읽은 **순서 그대로** Bus Element 추가. DB가 이미 Start Bit 순이므로 결과도 Start Bit 순.
- 장점: 단순. DB가 정렬돼 있으니 추가 정렬 불필요.
- 위험: **DB가 재정렬/수기편집**되면 순서 깨짐. 생성 로직이 Map/dict로 중간 저장하면 키순서로 바뀜.

### 방향 B. Start Bit 기준 명시적 정렬 (권장) ✅
- 신호 수집 후 **`sortrows(signals, 'StartBit')`** 로 정렬한 뒤 Bus Element 추가.
- 장점: **입력 순서·자료구조와 무관하게 항상 Start Bit 순 보장**. DB 편집에 강건.
- 후작업 최소화: 이름순 버그 재발 방지. CAN Unpack 포트 순서와 Bus 순서가 일치.

> **판단: 방향 B 채택.** DB가 지금은 정렬돼 있어도(A로도 당장은 동작), 생성 로직 내부에서
> struct 배열을 거치며 이름순으로 바뀌는 것이 현재 증상이므로, **명시적 Start Bit 정렬**이
> 근본 해결이자 후작업(재정렬·검증) 최소화.

---

## 3. Bus/Param 생성 권장 규칙 (후작업 최소화)

1. **신호 순서**: 메시지별로 **Start Bit 오름차순 정렬** 후 Bus Element 생성. (핵심)
2. **이름 소스**: **DBC Signal 컬럼** 사용 (접두사 포함, 전역 유일). Signal Name 은 중복 위험.
   - 예: `Status_ThermalCAM` 대신 `CC_Status_ThermalCAM`.
3. **네임스페이스**: Bus 는 **메시지 단위**로 분리 (`Bus_<MessageName>`), Element 는 신호명.
   - 메시지 간 동일 신호명(`ParameterGroupNumber`) 충돌 회피.
4. **데이터타입**: 비트길이→타입 매핑
   - 1bit→boolean, 2~8bit→uint8, 9~16→uint16, 17~32→uint32. (len 분포상 대부분 커버)
5. **물리값(Param)**: Factor≠1 또는 Offset≠0 (135건) → `phys = raw*Factor + Offset`.
   - Param 으로 Factor/Offset/Min/Max/Unit 을 데이터 딕셔너리에 등록.
6. **Reserved 제외 옵션**: `Rsvd` 신호(22개)는 생성 **스킵 플래그**로 모델 간결화.
7. **비트 추출**: 298건이 바이트 비정렬 → **CAN Unpack 블록**(또는 비트 슬라이싱)으로 추출.
   경계 교차는 0건이라 표준 Unpack 으로 안전.
8. **엔디안**: DB 전부 **Intel(little-endian)** → Unpack 설정 일괄 LE.

---

## 4. 생성 로직 핵심 의사코드 (사용자 작성 시 참고)

```matlab
% 1) DB 로드 후 메시지별로 그룹화
for each message M:
    sigs = signals_of(M);
    % 2) ★ Start Bit 오름차순 정렬 (이름순 금지)
    sigs = sortrows(sigs, 'StartBit');
    % 3) Bus 생성 (메시지 단위 네임스페이스)
    elems = [];
    for s in sigs:
        if opt.skipReserved && contains(s.name,'Rsvd'); continue; end
        e = Simulink.BusElement;
        e.Name     = s.dbc_signal;          % 전역 유일 이름
        e.DataType = bitlen2type(s.bitlen);  % 1->boolean, <=8->uint8 ...
        elems(end+1) = e;                    %#ok  (정렬된 순서대로 append)
    end
    bus = Simulink.Bus; bus.Elements = elems;
    assignin('base', ['Bus_' M.name], bus);
    % 4) Param: factor/offset/min/max/unit 등록
end
```

핵심은 **`sortrows(..., 'StartBit')`** 한 줄 — 이게 이름순 증상의 근본 해결.

---

## 5. 시뮬레이션 검증 방향 (MATLAB 가용 시)

후작업 최소화를 위해 생성 직후 **자동 검증**을 넣을 것을 권장:
- Bus Element 순서의 StartBit 가 **단조증가**인지 assert.
- 각 메시지 비트 합 ≤ DLC×8 인지 체크(겹침/초과 탐지).
- CAN Unpack 출력과 Bus 순서 일치 확인.

> 본 환경엔 MATLAB 이 없어 미실행. 사용자가 로직 작성·시뮬레이션 후 결과(생성된 Bus 순서)를
> 공유해 주시면, DB 와 대조해 매칭 검증하겠습니다.

---

## 6. 결론 (방향성)

- **채택: 방향 B — Start Bit 명시 정렬 + DBC Signal 이름 + 메시지 단위 Bus.**
- 이유: 이름순 버그 **근본 차단**, DB 편집에 강건, CAN Unpack 과 순서 일치 → **재정렬·수기보정 후작업 0 지향**.
- 로직은 사용자가 작성 → 생성 결과(Bus 순서)를 공유하면 DB 와 매칭 검증 수행.
