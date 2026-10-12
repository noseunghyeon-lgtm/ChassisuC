# build_chassis_controller.m — Stateflow 로직 생성 가이드

> Chassis uC Top 상태머신(S0~S6+INIT)을 Stateflow API로 생성하는 스크립트.
> 지금까지 확정된 전 설계(인터록 4조건·테이크오버 B안·E-Stop·C 코드생성 타입)가 반영됨.

## 실행
```matlab
cd src
build_chassis_controller      % → ChassisController.slx 생성
```
요구: MATLAB + Simulink + Stateflow. **코드생성 시** Embedded Coder.

## 생성되는 것
- 모델 `ChassisController.slx`, 차트 `ChassisControllerFSM` (이산, 10ms 틱)
- 상태 8개: S0_SLEEP · INIT · S1_MANUAL · S2_REMOTE_ARMED · S3_REMOTE_ACTIVE(빈 composite) ·
  S4_AEBS_OVERRIDE · S5_COMM_LOSS_BRAKE · S6_FAULT_SAFE_STATE
- 전이 28개 (상태별 이탈: S0=1, INIT=2, S1=5, S2=6, S3=6, S4=4, S5=3, S6=1)
- 데이터 71개 (입력/출력/로컬/상수/파라미터/enum)

## 반영된 확정 설계
| 항목 | 반영 |
| --- | --- |
| 상태 발행코드 | S0=1..S6=7, Invalid=0 (DB ValueTable, C21) |
| 우선순위 | E-Stop(0) > S6(1) > S5(2) > S4(3) > 테이크오버/모드(4~5), ExecutionOrder |
| S1→S2 인터록 | **정본 4조건**(RS인증·2단조작·차속0·기어P/N) (A1) |
| AEBS | aebs_flag 방식(TTC 아님) (C22) |
| E-Stop | S1~S5 최우선 전이, 임시 S6 (A3/C01) |
| INIT 타임아웃 | init_timeout → S6 (G2) |
| 테이크오버 | S3→S1 직접(B안), takeover_req (T16, Q-118) |
| 안전정지 | S3→S2 전환(manual_switch_req), 새 상태 아님 (Q-121) |
| 코드생성 타입 | 상수/파라미터 명시 타입(uint8/uint16/single) (D5) |
| during | dual_s4s5_flag, fault_suspect→lock, 자기진단 골격 (G4/G7/G8) |

## 사용자 작업 영역
- **S3 서브상태**(Normal/Degraded): 빈 composite로 생성됨. net 2~4 degradation 로직 추가.
  필요 신호(vc_net_level, speed_limit_*, degraded_led_blink) 모두 데이터로 준비됨.

## 실행 전 체크 (환경 의존)
1. enum 등록: `Simulink.defineIntEnumType` (IgKey, ModeReq) 성공
2. `DataType='Enum: IgKey'` 표기 인식 (MATLAB 릴리스별 확인)
3. composite state 기본 진입 화살표
4. `arrangeSystem` 레이아웃
> 본 저장소 환경엔 MATLAB 없어 **정적 검토만 수행**(가드 참조 식별자 71개 전부 정의 확인).

## TBD (placeholder, 값만 교체하면 됨)
- TBD_STANDSTILL_SPEED(-1, C05), TBD_LED_BLINK_HZ(-1, C17), init_timeout 수치(SRS-039)
- E-Stop 결과상태(C01), 테이크오버 모터토크 임계(Q-118)
- single → fixed-point: 타깃 ECU FPU 없으면 전환 필요

## 관련 문서
- 전이표 docs/01, 데이터 docs/02, 상태카드 docs/08, 점검 docs/14, 체크리스트 docs/18
