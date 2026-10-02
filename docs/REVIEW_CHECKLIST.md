# PR 리뷰 체크리스트 — Chassis uC Stateflow 설계

> [PR #1](https://github.com/noseunghyeon-lgtm/ChassisuC/pull/1) 리뷰용 가이드.
> 이 설계는 **개념설계 단계**이며 구현(.slx)은 로컬 MATLAB에서 생성한다. 미확정(TBD)은 명시 분리됨.

## 리뷰 순서 (권장)
1. `docs/00_glossary.md` — 명칭 사전(정본). 모든 이름의 기준.
2. `docs/10_state_summary.md` — 상태 종합(정의·역할·천이). 전체 그림.
3. `docs/09_mermaid_diagrams.md` — 다이어그램(GitHub에서 렌더링).
4. `docs/01_state_transition_table.md` + `docs/08_state_cards.md` — 전이 상세(교차검증).
5. `docs/11_can_signal_mapping.md` + `docs/12_can_preprocessing.md` — CAN DB 반영.
6. `docs/05_consistency_check.md` — 미해결(C01~C23) 추적.
7. `src/build_chassis_controller.m` — Stateflow 생성 스크립트.

## 리뷰 체크 항목

### 상태 정의·전이
- [ ] S0~S6 + INIT 정의가 정본(「차량 전체 상태천이 §3」)과 일치하는가
- [ ] 우선순위(E-Stop>S6>S5>S4>모드)가 각 상태 이탈에 올바로 투영됐는가
- [ ] 금지천이(S3→S1, S5→S3, S6 원격이탈)가 차단되는가
- [ ] S4 복귀 규칙(직전 S3→S2)이 반영됐는가
- [ ] S3 서브상태(Normal/Degraded) 경계(net 5~10/2~4/0~1)가 맞는가

### CAN DB 반영
- [ ] 상태 발행코드 S0=1..S6=7, Invalid=0 (C21)
- [ ] AEBS가 플래그 방식(aebs_flag)으로 전환됐는가 (C22)
- [ ] E-Stop 3경로(HW+CC+VC) OR 중재가 타당한가
- [ ] Heartbeat = AliveCounter 정체감시 방식이 맞는가
- [ ] 전처리 분리(Stateflow는 순수 로직) 구조에 동의하는가

### 미확정(확정 필요 — 아래 Issue 참조)
- [ ] C03 유인 S6 대응 정책 (기아 합의)
- [ ] C06 Q-76 조향 거동
- [ ] C19 CC/VC net level 중재 방식
- [ ] C20 CC/VC 모드요청 중재 / 마스터 지정
- [ ] C23 CRC 다항식·MC 임계

## 코멘트 작성 가이드
- 설계 변경 요청은 **어느 문서 §절**인지 명시 (예: "08 S3 카드 이탈조건").
- 미확정 항목은 Issue(C-xx)에 코멘트, 설계 오류는 PR 인라인 코멘트.
- 반영은 **같은 PR 브랜치**(`design/chassis-controller-stateflow`)에 업데이트.

## 검증 한계
- ⚠️ MATLAB 미설치 환경 → `.m` 스크립트는 **정적 검토만**. 로컬 MATLAB 실행 검증 필요.
- 설계 문서는 CAN DB(`DB_ChassisuC.xlsx`)와 교차검증 완료.
