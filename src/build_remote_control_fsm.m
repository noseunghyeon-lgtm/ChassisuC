function build_remote_control_fsm()
% BUILD_REMOTE_CONTROL_FSM  원격 차량 제어 Top StateMachine 자동 생성 스크립트
%
%   Stateflow API 로 원격 차량 제어 상태 머신을 .slx 로 생성한다.
%   상태 정의 정본: 「차량 전체 상태천이 §3」
%   구현 설계  : 「전체 관리 프로세스 / 1 — 상태 머신」
%
%   상태: S0(SLEEP) / INIT / S1(MANUAL) / S2(REMOTE_READY) /
%         S3(REMOTE_ACTIVE) / S4(AEBS) / S5(SAFE_STOP) / S6(FAULT_SAFE)
%
%   ─────────────────────────────────────────────────────────────────
%   ⚠️ 미확정(TBD) 항목은 임의 수치를 넣지 않고 명시 상수 + 주석으로 분리한다.
%      실제 값은 소관 문서/SRS 확정 후 이 스크립트의 파라미터 절만 수정하면 된다.
%   ─────────────────────────────────────────────────────────────────
%
%   사용:  >> build_remote_control_fsm
%   출력:  RemoteControlFSM.slx  (현재 폴더)

    modelName = 'RemoteControlFSM';

    %% 0. 기존 모델 정리
    if bdIsLoaded(modelName)
        close_system(modelName, 0);
    end

    %% 0.1 가드에서 사용하는 열거형 타입 정의 (전역 클래스)
    %      Stateflow 가드에서 IG_ON / REQ_TO_S2 같은 리터럴을 쓰려면
    %      해당 enum 클래스가 먼저 정의되어 있어야 한다 (데이터 딕셔너리 §6).
    defineEnumTypes();

    %% 1. 새 Stateflow 차트가 포함된 모델 생성
    sfnew(modelName);
    rt = sfroot;
    m  = rt.find('-isa', 'Simulink.BlockDiagram', '-and', 'Name', modelName);
    ch = m.find('-isa', 'Stateflow.Chart');

    ch.Name = 'RemoteControlTopFSM';
    % 이산 시스템: 10ms 틱 (문서 §2 — 제동 제어 루프와 동일)
    ch.ChartUpdate = 'DISCRETE';
    ch.SampleTime  = '0.010';           % TICK_MS = 10 ms (확정)

    %% 2. 열거형/파라미터 (데이터 딕셔너리 §1, §5)
    defineData(ch);

    %% 3. 상태 생성
    S = createStates(ch);

    %% 4. INIT 서브상태 (Power_ON_GA -> GS -> EPS)  ※ §12-1 기어계통 준비
    createInitSubstates(ch, S.INIT);

    %% 5. 전이 (전이표 T01~T15 + 금지천이 감시 §7)
    createTransitions(ch, S);

    %% 6. 레이아웃 정돈 후 저장
    Simulink.BlockDiagram.arrangeSystem(modelName);
    save_system(modelName);
    fprintf('[OK] %s.slx 생성 완료\n', modelName);
end

% =====================================================================
function defineEnumTypes()
% 가드에서 참조하는 enum 클래스 정의 (데이터 딕셔너리 §6).
% Simulink.defineIntEnumType 은 base workspace 에 클래스를 등록한다.

    % IgKey: 키 위치
    Simulink.defineIntEnumType('IgKey', ...
        {'IG_OFF','IG_ON','IG_START'}, [0 1 2], ...
        'Description','키 위치 (§12)');

    % ModeReq: 모드 전환 요청
    Simulink.defineIntEnumType('ModeReq', ...
        {'REQ_NONE','REQ_TO_S1','REQ_TO_S2','REQ_TO_S3'}, [0 1 2 3], ...
        'Description','모드 전환 요청 (「원격/수동 전환」 소관)');
end

% =====================================================================
function defineData(ch)
% 상태 enum, 입력, 출력, 로컬, 파라미터 정의 (데이터 딕셔너리 참조)

    % ---- 상태 발행 코드 상수 (VEH_STS.SystemState) ----
    addConst(ch, 'C_S0',   '0');
    addConst(ch, 'C_S1',   '1');
    addConst(ch, 'C_S2',   '2');
    addConst(ch, 'C_S3',   '3');
    addConst(ch, 'C_S4',   '4');
    addConst(ch, 'C_S5',   '5');
    addConst(ch, 'C_S6',   '6');
    % ⚠️ TBD_INIT_ENCODING — CAN §2.2 (§10). 임시 placeholder 255(0xFF).
    addConst(ch, 'C_INIT', '255');

    % ---- 파라미터/타이머 (문서 §5) ----
    addParam(ch, 'HEARTBEAT_TIMEOUT_MS', '400');   % SRS-SYS-007 (확정)
    addParam(ch, 'AEBS_BRAKE_TTC_S',     '0.8');   % 정본 §3.3 (확정)
    addParam(ch, 'AEBS_WARN_TTC_S',      '2.0');   % 정본 §3.3, 상태천이 없음
    % ⚠️ 아래는 미확정. 안전 관련이므로 0/큰값 등 임의값 대신 -1(무효) placeholder.
    %    실제 값 확정 전에는 관련 가드가 절대 참이 되지 않도록 설계됨.
    addParam(ch, 'TBD_FAULT_DEBOUNCE_N', '-1');    % SRS-SYS-038 / 「진단」§4
    addParam(ch, 'TBD_STANDSTILL_SPEED', '-1');    % 「기어 변속 판단」
    addParam(ch, 'TBD_S0_ENTRY_DELAY',   '-1');    % 「전원/Wake-up」

    % ---- 입력 (모듈/센서 -> FSM) ----
    % {이름, 데이터타입}. '' 이면 Stateflow 기본(추론) 타입.
    inSpec = { ...
        'ig_key','Enum: IgKey'; ...
        'wake_source','boolean'; ...
        'heartbeat_ok','boolean'; ...
        'heartbeat_age_ms','uint16'; ...
        'ttc_s','single'; ...
        'fault_critical_confirmed','boolean'; ...
        'fault_suspect','boolean'; ...
        'fault_threatens_control','boolean'; ...
        'estop_active','boolean'; ...
        'interlock_ok','boolean'; ...
        'actuators_neutral','boolean'; ...
        'first_valid_cmd','boolean'; ...
        'mode_req','Enum: ModeReq'; ...
        'vehicle_speed','single'; ...
        'pedal_pos','single'; ...
        'cam_at_origin','boolean'; ...
        'gear_ready','boolean'; ...
        'selftest_done','boolean'; ...
        'dtc_cleared','boolean'};
    for i = 1:size(inSpec, 1)
        addIO(ch, inSpec{i,1}, 'Input', inSpec{i,2});
    end

    % ---- 출력 (FSM -> CAN/모듈) ----
    outSpec = { ...
        'veh_state_code','uint8'; ...
        'dual_s4s5_flag','boolean'; ...
        'brake_req_src_state','single'; ...
        'remote_cmd_lock','boolean'; ...
        'fault_reason_code','uint16'; ...
        'sw_defect_dtc','boolean'};
    for i = 1:size(outSpec, 1)
        addIO(ch, outSpec{i,1}, 'Output', outSpec{i,2});
    end

    % ---- 로컬 ----
    localSpec = { ...
        'prev_state_before_s4','uint8'; ...
        'heartbeat_timer_ms','uint16'; ...
        'fault_debounce_cnt','uint16'; ...
        'tick_overrun','boolean'; ...
        'state_integrity_ok','boolean'};
    for i = 1:size(localSpec, 1)
        addIO(ch, localSpec{i,1}, 'Local', localSpec{i,2});
    end
end

% =====================================================================
function S = createStates(ch)
% Top-level 상태 8개 생성 및 배치

    S.S0   = newState(ch, 'S0_SLEEP',        [ 40  40 160 70]);
    S.INIT = newState(ch, 'INIT',            [ 40 150 200 200]);
    S.S1   = newState(ch, 'S1_MANUAL',       [ 40 400 160 80]);
    S.S2   = newState(ch, 'S2_REMOTE_READY', [280 400 170 80]);
    S.S3   = newState(ch, 'S3_REMOTE_ACTIVE',[280 520 170 80]);
    S.S4   = newState(ch, 'S4_AEBS',         [540 400 160 80]);
    S.S5   = newState(ch, 'S5_SAFE_STOP',    [540 520 160 80]);
    S.S6   = newState(ch, 'S6_FAULT_SAFE',   [540 150 160 90]);

    % ---- 상태별 entry/during 액션 (발행 코드, 원격 잠금 등) ----
    S.S0.LabelString = sprintf(['S0_SLEEP\n' ...
        'entry: veh_state_code = C_S0; remote_cmd_lock = true;']);

    % INIT: 원격 요청 거부(§6-1), 발행코드는 TBD placeholder
    S.INIT.LabelString = sprintf(['INIT\n' ...
        'entry:\n veh_state_code = C_INIT;  %% TBD_INIT_ENCODING (CAN 2.2)\n' ...
        ' remote_cmd_lock = true;  %% 6-1: INIT 구간 원격 천이 요청 거부']);

    S.S1.LabelString = sprintf(['S1_MANUAL\n' ...
        'entry: veh_state_code = C_S1; remote_cmd_lock = false;']);

    S.S2.LabelString = sprintf(['S2_REMOTE_READY\n' ...
        'entry: veh_state_code = C_S2;']);

    S.S3.LabelString = sprintf(['S3_REMOTE_ACTIVE\n' ...
        'entry: veh_state_code = C_S3;']);

    % S4: 진입 직전 상태 보관(6-4). 발행은 우선순위 처리로 결정.
    S.S4.LabelString = sprintf(['S4_AEBS\n' ...
        'entry: veh_state_code = C_S4;']);

    % S5: 즉시 최대 제동(T09). brake_req 최댓값 중재는 외부 로직.
    S.S5.LabelString = sprintf(['S5_SAFE_STOP\n' ...
        'entry:\n veh_state_code = C_S5;\n' ...
        ' brake_req_src_state = 1.0;  %% 즉시 최대 제동(변화율 제한 미적용)']);

    % S6: 비가역. 유인/무인 대응 차등은 TBD(6-2) — 진입 액션은 코드/잠금만.
    S.S6.LabelString = sprintf(['S6_FAULT_SAFE\n' ...
        'entry:\n veh_state_code = C_S6;  remote_cmd_lock = true;\n' ...
        ' %% TBD_S6_MANNED_POLICY: 유인(S1) 진입 시 최대제동 금지 — 「안전」+기아 합의(6-2)']);
end

% =====================================================================
function createInitSubstates(ch, initState)
% INIT 내부: 기어계통 준비 시퀀스 (§12-1). GA=Gear Actuator, GS=Gear Shift, EPS.

    ga  = newState(ch, 'Power_ON_GA',  [initState.Position(1)+20, initState.Position(2)+40,  150, 40]);
    gs  = newState(ch, 'Power_ON_GS',  [initState.Position(1)+20, initState.Position(2)+100, 150, 40]);
    eps = newState(ch, 'Power_ON_EPS', [initState.Position(1)+20, initState.Position(2)+160, 150, 40]);

    ga.LabelString  = 'Power_ON_GA';    % 기어 액추에이터 급전/단수 확인(§12-1 2~5)
    gs.LabelString  = 'Power_ON_GS';    % 변속기어실렉터 Handshake
    eps.LabelString = 'Power_ON_EPS';   % 조향 유닛 Wakeup(§12-1 8~9, 9단계 TBD)

    % 기본 진입 화살표 -> GA
    dGA = Stateflow.Transition(ch);
    dGA.Destination = ga;
    dGA.SourceOClock = 0; dGA.DestinationOClock = 0;

    % GA -> GS -> EPS 순차 (가드는 준비완료 신호)
    t1 = Stateflow.Transition(ch); t1.Source = ga;  t1.Destination = gs;
    t1.LabelString = '[gear_ready]';   % ⚠️ 세분 신호는 §12-1 단계별로 확장 가능
    t2 = Stateflow.Transition(ch); t2.Source = gs;  t2.Destination = eps;
    t2.LabelString = '';               % handshake 완료 조건 — 정본/§12-1 대조
end

% =====================================================================
function createTransitions(ch, S)
% 전이표 T01~T15 + 금지천이 감시(§7)
%
% ★ 문서 §3 평가 우선순위: 치명고장(1) > Heartbeat/S5(2) > AEBS/S4(3) > 모드전환(4).
%   Stateflow 는 한 소스에서 나가는 전이를 ExecutionOrder 순으로 평가하므로,
%   아래에서 각 전이의 t.ExecutionOrder 를 우선순위에 맞춰 명시한다.
%   (동일 소스에서 S6 전이가 항상 S5/S4/모드전환보다 먼저 평가되어야 함)

    % 기본 진입: 시스템 시작 -> S0
    d0 = Stateflow.Transition(ch);
    d0.Destination = S.S0;
    d0.DestinationOClock = 9;

    % T01  S0 -> INIT : Wakeup
    tr(ch, S.S0,   S.INIT, '[wake_source || ig_key == IG_ON]');

    % T02  INIT -> S1 : 자기진단 완료 && 기어계통 준비
    %      ⚠️ TBD_INIT_S1_FAIL: 실패 처리 원문 없음(§12-3). 여기선 성공 가드만.
    tr(ch, S.INIT, S.S1,  '[selftest_done && gear_ready]');

    % T03  INIT -> S6 : 자기진단 중 치명 고장 확정
    tr(ch, S.INIT, S.S6,  '[fault_critical_confirmed]');

    % ── S2 에서 나가는 전이: 우선순위 S6(1) > S5(2) > S4(3) > 모드전환(4) ──
    % T13a S2 -> S6 (치명고장 확정) ─ 최우선
    tr(ch, S.S2, S.S6, '[fault_critical_confirmed]', 1);
    % T09a S2 -> S5 (Heartbeat > 400ms)
    tr(ch, S.S2, S.S5, '[heartbeat_age_ms > HEARTBEAT_TIMEOUT_MS]', 2);
    % T11a S2 -> S4 (AEBS)
    tr(ch, S.S2, S.S4, '[ttc_s < AEBS_BRAKE_TTC_S]{prev_state_before_s4 = C_S2;}', 3);
    % T07  S2 -> S3 (원격 추종 개시): 조작기 중립 && 첫 유효명령 (정본§3.3)
    tr(ch, S.S2, S.S3, '[actuators_neutral && first_valid_cmd]', 4);
    % T06  S2 -> S1 (원격 해제): 캠 원점 복귀 확인(무여자 금지 보호)
    tr(ch, S.S2, S.S1, '[mode_req == REQ_TO_S1 && cam_at_origin]', 5);

    % ── S3 에서 나가는 전이: 우선순위 S6(1) > S5(2) > S4(3) > 모드전환(4) ──
    % T13b S3 -> S6 (치명고장 확정) ─ 최우선
    tr(ch, S.S3, S.S6, '[fault_critical_confirmed]', 1);
    % T09b S3 -> S5 (Heartbeat > 400ms)
    tr(ch, S.S3, S.S5, '[heartbeat_age_ms > HEARTBEAT_TIMEOUT_MS]', 2);
    % T11b S3 -> S4 (AEBS)
    tr(ch, S.S3, S.S4, '[ttc_s < AEBS_BRAKE_TTC_S]{prev_state_before_s4 = C_S3;}', 3);
    % T08  S3 -> S2 (세션 종료): 차속 0 미달 시 S3 유지
    tr(ch, S.S3, S.S2, '[mode_req == REQ_TO_S2 && vehicle_speed <= TBD_STANDSTILL_SPEED]', 4);

    % ── S1 에서 나가는 전이 ──
    % T14  S1 -> S6 (치명고장/제어위협) ─ 유인 대응정책 TBD(§6-2)
    tr(ch, S.S1, S.S6, '[fault_critical_confirmed || fault_threatens_control]', 1);
    % T11c S1 -> S4 (AEBS)
    tr(ch, S.S1, S.S4, '[ttc_s < AEBS_BRAKE_TTC_S]{prev_state_before_s4 = C_S1;}', 2);
    % T05  S1 -> S2 (원격 진입): 인터록 4조건 && 모드전환
    tr(ch, S.S1, S.S2, '[interlock_ok && mode_req == REQ_TO_S2]', 3);
    % T04  S1 -> S0 (IG-OFF): S0 진입은 S1에서만(§6-5)
    tr(ch, S.S1, S.S0, '[ig_key == IG_OFF]', 4);

    % ── S5 에서 나가는 전이 ──
    % S5 -> S6 (치명고장) 우선
    tr(ch, S.S5, S.S6, '[fault_critical_confirmed]', 1);
    % T10  S5 -> S2 : Heartbeat 복구 && 차속 0. S5->S3 직접 금지(§7)
    tr(ch, S.S5, S.S2, '[heartbeat_ok && vehicle_speed <= TBD_STANDSTILL_SPEED]', 2);

    % ── S4 에서 나가는 전이 ──
    % S4 -> S6 (치명고장) 우선
    tr(ch, S.S4, S.S6, '[fault_critical_confirmed]', 1);
    % T12  S4 -> 복귀 : 해제 시. 직전 S3 이면 S2 로 복귀(§6-4)
    tr(ch, S.S4, S.S1, '[ttc_s >= AEBS_BRAKE_TTC_S && prev_state_before_s4 == C_S1]', 2);
    tr(ch, S.S4, S.S2, '[ttc_s >= AEBS_BRAKE_TTC_S && (prev_state_before_s4 == C_S2 || prev_state_before_s4 == C_S3)]', 3);

    % ── S6 에서 나가는 전이 ──
    % T15  S6 -> S0 : IG-OFF 재기동 + DTC 클리어(비가역 이탈). 원격 이탈 금지(§7)
    tr(ch, S.S6, S.S0, '[ig_key == IG_OFF && dtc_cleared]');

    % ---- 금지 천이(§7)는 위에서 아예 생성하지 않음으로 원천 차단:
    %      S3->S1 직접 없음 / S5->S3 직접 없음 / S6 원격이탈 없음.
    %      런타임 시도 감시(정의외 상태값 -> 즉시 S6)는 차트 레벨 감사 로직 또는
    %      상위 감시 블록에서 sw_defect_dtc 로 처리 (구현 주석 참조).
end

% ======================= 헬퍼 함수 ===================================
function st = newState(ch, name, pos)
    st = Stateflow.State(ch);
    st.Name = name;
    st.Position = pos;
end

function t = tr(ch, src, dst, label, execOrder)
    t = Stateflow.Transition(ch);
    t.Source = src;
    t.Destination = dst;
    if nargin > 3 && ~isempty(label)
        t.LabelString = label;
    end
    % ExecutionOrder: 같은 소스에서 나가는 전이의 평가 순서(문서 §3 우선순위 강제)
    if nargin > 4 && ~isempty(execOrder)
        t.ExecutionOrder = execOrder;
    end
end

function addIO(ch, name, scope, dataType)
    d = Stateflow.Data(ch);
    d.Name  = name;
    d.Scope = scope;         % 'Input' | 'Output' | 'Local'
    if nargin > 3 && ~isempty(dataType)
        d.DataType = dataType;   % e.g. 'boolean','uint8','single','Enum: IgKey'
    end
end

function addConst(ch, name, val)
    d = Stateflow.Data(ch);
    d.Name  = name;
    d.Scope = 'Constant';
    d.Props.InitialValue = val;
end

function addParam(ch, name, val)
    % 설계 상수는 Constant 스코프로 생성 (Parameter 스코프는 차트 내 InitialValue 미지원).
    d = Stateflow.Data(ch);
    d.Name  = name;
    d.Scope = 'Constant';
    d.Props.InitialValue = val;
end
