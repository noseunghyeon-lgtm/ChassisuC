function build_chassis_controller()
% BUILD_CHASSIS_CONTROLLER  Chassis uC 메인 Stateflow 생성 스크립트
%
%   Stateflow API 로 Chassis uC(구동부 제어 컨트롤러)의 Top 상태머신을 .slx 로 생성한다.
%   - 명칭: 명칭 사전(docs/00_glossary.md) 정본 식별자 사용.
%   - 범위: **상태머신 코어만** (상태·전이·가드). 진입/이탈 액션 상세는 미포함.
%   - S3(REMOTE_ACTIVE): **빈 composite state** 로 생성 — 서브상태(Normal/Degraded)는
%     사용자가 직접 작업. 본 스크립트는 S3 의 I/O(입력/출력)만 데이터로 반영한다.
%   - 미확정(TBD): placeholder 상수 + 주석으로 분리 (값 임의 설정 금지).
%
%   상태: S0(SLEEP) · INIT · S1(MANUAL) · S2(REMOTE_ARMED) · S3(REMOTE_ACTIVE) ·
%         S4(AEBS_OVERRIDE) · S5(COMM_LOSS_BRAKE) · S6(FAULT_SAFE_STATE)
%
%   사용:  >> build_chassis_controller
%   출력:  ChassisController.slx  (현재 폴더)
%
%   ※ MATLAB + Simulink + Stateflow 필요. 본 저장소 환경에서는 실행 검증되지 않음.

    modelName = 'ChassisController';

    %% 0. 기존 모델 정리
    if bdIsLoaded(modelName)
        close_system(modelName, 0);
    end

    %% 0.1 enum 타입 정의 (가드에서 리터럴 사용)
    defineEnumTypes();

    %% 1. 새 Stateflow 차트 생성
    sfnew(modelName);
    rt = sfroot;
    m  = rt.find('-isa', 'Simulink.BlockDiagram', '-and', 'Name', modelName);
    ch = m.find('-isa', 'Stateflow.Chart');

    ch.Name = 'ChassisControllerFSM';
    ch.ChartUpdate = 'DISCRETE';
    ch.SampleTime  = '0.010';     % 10 ms 틱 (문서 §2)

    %% 2. 데이터(enum/상수/파라미터/입출력/로컬)
    defineData(ch);

    %% 3. 상태 생성 (S3 는 빈 composite)
    S = createStates(ch);

    %% 4. 코어 전이 (가드) — 우선순위 ExecutionOrder 반영
    createTransitions(ch, S);

    %% 5. 저장
    Simulink.BlockDiagram.arrangeSystem(modelName);
    save_system(modelName);
    fprintf('[OK] %s.slx 생성 완료 (코어 상태머신, S3 서브상태는 사용자 작업)\n', modelName);
end

% =====================================================================
function defineEnumTypes()
    % IgKey: 키 위치
    Simulink.defineIntEnumType('IgKey', ...
        {'IG_OFF','IG_ON','IG_START'}, [0 1 2], ...
        'Description','키 위치 (§12)');
    % ModeReq: 모드 전환 요청
    Simulink.defineIntEnumType('ModeReq', ...
        {'REQ_NONE','REQ_TO_S1','REQ_TO_S2','REQ_TO_S3'}, [0 1 2 3], ...
        'Description','모드 전환 요청');
end

% =====================================================================
function defineData(ch)
% 명칭 사전(00_glossary.md) · 데이터 딕셔너리(02) 정본 반영

    % ---- 상태 발행 코드 상수 (Chassis_State_Machine_Status_VC) ----
    % ★ C21: DB Value Table 매칭 — 0:Invalid, 1:S0 .. 7:S6
    addConst(ch, 'C_INVALID', '0');  % DB 0:Invalid (INIT 구간 발행값)
    addConst(ch, 'C_S0',   '1');     % DB 1:S0
    addConst(ch, 'C_S1',   '2');     % DB 2:S1
    addConst(ch, 'C_S2',   '3');     % DB 3:S2
    addConst(ch, 'C_S3',   '4');     % DB 4:S3
    addConst(ch, 'C_S4',   '5');     % DB 5:S4
    addConst(ch, 'C_S5',   '6');     % DB 6:S5
    addConst(ch, 'C_S6',   '7');     % DB 7:S6
    addConst(ch, 'C_INIT', '0');     % INIT 은 상태머신 미유효 → Invalid(0) 발행 (C02 해소)

    % ---- 파라미터 (확정값) ----
    addParam(ch, 'HEARTBEAT_TIMEOUT_MS',   '400');  % SRS-SYS-007
    addParam(ch, 'AEBS_BRAKE_TTC_S',       '0.8');  % 정본 §3.3
    addParam(ch, 'AEBS_WARN_TTC_S',        '2.0');  % 상태천이 없음(경고)
    addParam(ch, 'NET_LEVEL_STOP_MAX',     '1');    % net 0~1 → S5
    addParam(ch, 'NET_LEVEL_DEGRADED_MAX', '4');    % net 2~4 → S3_Degraded
    addParam(ch, 'NET_LEVEL_NORMAL_MIN',   '5');    % net 5~10 → S3_Normal
    addParam(ch, 'DEGRADED_SPEED_LIMIT',   '10');   % km/h (확정)
    % ⚠️ 미확정 — 안전 가드가 확정 전 참이 되지 않도록 -1(무효) placeholder
    addParam(ch, 'TBD_STANDSTILL_SPEED',   '-1');   % 차속0 임계 (C05)
    addParam(ch, 'TBD_LED_BLINK_HZ',       '-1');   % LED 점멸주기 (C17)
    addParam(ch, 'MC_STALE_FAIL_COUNT',    '10');   % MC 10회 연속 실패 → stale (C23/#6)
    addParam(ch, 'MODE_PRIORITY_CC',       '1');    % CC 우선 (C20/#5)

    % ---- 입력 (데이터 딕셔너리 §2) ----
    inSpec = { ...
        'ig_key','Enum: IgKey'; ...
        'wake_source','boolean'; ...
        'heartbeat_ok','boolean'; ...
        'heartbeat_age_ms','uint16'; ...
        'video_hb_ok','boolean'; ...
        'vc_net_level','uint8'; ...            % 0~10 통신 네트워크 레벨 (VC, degradation 기준)
        'cc_net_level','uint8'; ...            % 0~10 (CC, 보조 모니터 — C19 중재)
        'aebs_flag','boolean'; ...             % ★ C22: AEBS 판정 결과 플래그(CC/VC OR). TTC 대체
        'ttc_s','single'; ...                  % (참고용 유지, 가드는 aebs_flag 사용)
        'fault_critical_confirmed','boolean'; ...
        'fault_suspect','boolean'; ...
        'fault_threatens_control','boolean'; ...
        'estop_active','boolean'; ...
        'actuators_neutral','boolean'; ...
        'first_valid_cmd','boolean'; ...
        'mode_req','Enum: ModeReq'; ...
        'vehicle_speed','single'; ...
        'pedal_pos','single'; ...
        'cam_at_origin','boolean'; ...
        % S1→S2 진입 6조건 (interlock, 모두 AND)
        'arm_rs_mutual_auth','boolean'; ...
        'arm_rmc_2stage','boolean'; ...        % ⚠️ Q-56 핀 부재 이슈
        'arm_speed_zero','boolean'; ...
        'arm_brake_pedal','boolean'; ...
        'arm_brake_remote_set','boolean'; ...
        'arm_gear_park','boolean'; ...
        'gear_ready','boolean'; ...
        'selftest_done','boolean'; ...
        'dtc_cleared','boolean'};
    for i = 1:size(inSpec,1)
        addIO(ch, inSpec{i,1}, 'Input', inSpec{i,2});
    end

    % ---- 출력 (데이터 딕셔너리 §3) ----
    outSpec = { ...
        'veh_state_code','uint8'; ...
        'dual_s4s5_flag','boolean'; ...
        'brake_req_src_state','single'; ...
        'remote_cmd_lock','boolean'; ...
        'fault_reason_code','uint16'; ...
        'sw_defect_dtc','boolean'; ...
        'video_hb_warn','boolean'; ...         % 영상 HB 경고(천이 없음)
        'speed_limit_active','boolean'; ...     % S3_Degraded
        'speed_limit_value','single'; ...
        'degraded_led_blink','boolean'; ...     % S3_Degraded LED
        'system_check_request','boolean'};      % CC/VC 모드 불일치 운영자 점검요청 (C20/#5)
    for i = 1:size(outSpec,1)
        addIO(ch, outSpec{i,1}, 'Output', outSpec{i,2});
    end

    % ---- 로컬 ----
    localSpec = { ...
        'prev_state_before_s4','uint8'; ...
        'heartbeat_timer_ms','uint16'; ...
        'tick_overrun','boolean'; ...
        'state_integrity_ok','boolean'};
    for i = 1:size(localSpec,1)
        addIO(ch, localSpec{i,1}, 'Local', localSpec{i,2});
    end
end

% =====================================================================
function S = createStates(ch)
% Top-level 상태 8개. S3 는 빈 composite(서브상태는 사용자 작업).

    S.S0   = newState(ch, 'S0_SLEEP',            [ 40  40 170 70]);
    S.INIT = newState(ch, 'INIT',                [ 40 150 170 70]);
    S.S1   = newState(ch, 'S1_MANUAL',           [ 40 400 170 80]);
    S.S2   = newState(ch, 'S2_REMOTE_ARMED',     [280 400 180 80]);
    S.S3   = newState(ch, 'S3_REMOTE_ACTIVE',    [280 540 260 180]);  % composite(큰 크기)
    S.S4   = newState(ch, 'S4_AEBS_OVERRIDE',    [600 400 180 80]);
    S.S5   = newState(ch, 'S5_COMM_LOSS_BRAKE',  [600 540 180 80]);
    S.S6   = newState(ch, 'S6_FAULT_SAFE_STATE', [600 150 180 90]);

    % 상태별 entry — 발행 코드만(코어). 액션 상세는 미포함.
    S.S0.LabelString   = sprintf('S0_SLEEP\nentry: veh_state_code = C_S0; remote_cmd_lock = true;');
    S.INIT.LabelString = sprintf(['INIT\nentry:\n veh_state_code = C_INIT;  %% TBD 인코딩(C02)\n' ...
                                  ' remote_cmd_lock = true;  %% INIT 원격 거부(§6-1)']);
    S.S1.LabelString   = sprintf('S1_MANUAL\nentry: veh_state_code = C_S1; remote_cmd_lock = false;');
    S.S2.LabelString   = sprintf('S2_REMOTE_ARMED\nentry: veh_state_code = C_S2;');
    % S3: 빈 composite — 서브상태(Normal/Degraded)는 사용자가 추가.
    S.S3.LabelString   = sprintf(['S3_REMOTE_ACTIVE\nentry: veh_state_code = C_S3;\n' ...
                                  ' %% [사용자 작업] 서브상태 S3_Normal / S3_Degraded 추가\n' ...
                                  ' %% net 2~4: speed_limit_active=true, speed_limit_value=DEGRADED_SPEED_LIMIT, degraded_led_blink\n' ...
                                  ' %% net 0~1: S5 로 이탈 (아래 전이 참조)']);
    S.S4.LabelString   = sprintf('S4_AEBS_OVERRIDE\nentry: veh_state_code = C_S4;');
    S.S5.LabelString   = sprintf(['S5_COMM_LOSS_BRAKE\nentry:\n veh_state_code = C_S5;\n' ...
                                  ' brake_req_src_state = 1.0;  %% 최대 제동(Stop 시퀀스)']);
    S.S6.LabelString   = sprintf(['S6_FAULT_SAFE_STATE\nentry:\n veh_state_code = C_S6; remote_cmd_lock = true;\n' ...
                                  ' %% C03(#2): 유인(S1) 진입 시 최대제동 금지 + 원격기능만 잠금 + 원격모드 진입불가\n' ...
                                  ' %% 무인(S2~S5) 진입 시: 최대제동 후 유지\n' ...
                                  ' %% C06(#3): 조향 홀드 - EPS 제어 안 함(내력 미발생). S6 이탈은 S0 뿐(원격 이탈 불가)']);
end

% =====================================================================
function createTransitions(ch, S)
% 코어 전이 T01~T15 + 우선순위(ExecutionOrder) + 금지천이는 미생성으로 차단.
% 우선순위(§3): E-Stop > 치명고장(S6) > HB상실(S5) > AEBS(S4) > 모드전환.

    % 기본 진입: 시작 -> S0
    d0 = Stateflow.Transition(ch);
    d0.Destination = S.S0;
    d0.DestinationOClock = 9;

    % T01 S0 -> INIT
    tr(ch, S.S0,   S.INIT, '[wake_source || ig_key == IG_ON]');
    % T02 INIT -> S1 (실패처리 TBD, C08)
    tr(ch, S.INIT, S.S1,  '[selftest_done && gear_ready]');
    % T03 INIT -> S6
    tr(ch, S.INIT, S.S6,  '[fault_critical_confirmed]');

    % ── S1 이탈 (우선순위) ──
    tr(ch, S.S1, S.S6, '[fault_critical_confirmed || fault_threatens_control]', 1);  % T14 유인 S6(정책 TBD)
    tr(ch, S.S1, S.S4, '[aebs_flag]{prev_state_before_s4 = C_S1;}', 2); % T11 (C22: AEBS 플래그)
    tr(ch, S.S1, S.S2, '[arm_rs_mutual_auth && arm_rmc_2stage && arm_speed_zero && arm_brake_pedal && arm_brake_remote_set && arm_gear_park && mode_req == REQ_TO_S2]', 3); % T05 6조건 AND
    tr(ch, S.S1, S.S0, '[ig_key == IG_OFF]', 4);  % T04

    % ── S2 이탈 (우선순위) ──
    tr(ch, S.S2, S.S6, '[fault_critical_confirmed]', 1);                                  % T13
    tr(ch, S.S2, S.S5, '[heartbeat_age_ms > HEARTBEAT_TIMEOUT_MS]', 2);                   % T09
    tr(ch, S.S2, S.S4, '[aebs_flag]{prev_state_before_s4 = C_S2;}', 3);    % T11 (C22)
    tr(ch, S.S2, S.S3, '[actuators_neutral && first_valid_cmd]', 4);                      % T07
    tr(ch, S.S2, S.S1, '[mode_req == REQ_TO_S1 && cam_at_origin]', 5);                    % T06

    % ── S3 이탈 (우선순위) ── S3 내부(Normal/Degraded)는 사용자 작업.
    tr(ch, S.S3, S.S6, '[fault_critical_confirmed]', 1);                                  % T13
    % T09+net: net 0~1(Stop) 또는 HB 초과 → S5
    tr(ch, S.S3, S.S5, '[vc_net_level <= NET_LEVEL_STOP_MAX || heartbeat_age_ms > HEARTBEAT_TIMEOUT_MS]', 2);
    tr(ch, S.S3, S.S4, '[aebs_flag]{prev_state_before_s4 = C_S3;}', 3);    % T11 (C22)
    tr(ch, S.S3, S.S2, '[mode_req == REQ_TO_S2 && vehicle_speed <= TBD_STANDSTILL_SPEED]', 4); % T08

    % ── S4 이탈 (우선순위) ──
    tr(ch, S.S4, S.S6, '[fault_critical_confirmed]', 1);                                  % T13
    tr(ch, S.S4, S.S1, '[~aebs_flag && prev_state_before_s4 == C_S1]', 2); % T12 (C22: 해제=플래그 해제)
    tr(ch, S.S4, S.S2, '[~aebs_flag && (prev_state_before_s4 == C_S2 || prev_state_before_s4 == C_S3)]', 3); % T12 (직전 S3→S2)

    % ── S5 이탈 (우선순위) ──
    tr(ch, S.S5, S.S6, '[fault_critical_confirmed]', 1);                                  % T13
    tr(ch, S.S5, S.S2, '[heartbeat_ok && vc_net_level >= NET_LEVEL_NORMAL_MIN && vehicle_speed <= TBD_STANDSTILL_SPEED]', 2); % T10 (S2 경유 필수)

    % ── S6 이탈 ──
    tr(ch, S.S6, S.S0, '[ig_key == IG_OFF && dtc_cleared]');  % T15 비가역 이탈

    % ---- 금지천이(§7)는 생성하지 않음: S3->S1 직접, S5->S3 직접, S6 원격이탈 없음.
end

% ======================= 헬퍼 ========================================
function st = newState(ch, name, pos)
    st = Stateflow.State(ch); st.Name = name; st.Position = pos;
end

function t = tr(ch, src, dst, label, execOrder)
    t = Stateflow.Transition(ch);
    t.Source = src; t.Destination = dst;
    if nargin > 3 && ~isempty(label), t.LabelString = label; end
    if nargin > 4 && ~isempty(execOrder), t.ExecutionOrder = execOrder; end
end

function addIO(ch, name, scope, dataType)
    d = Stateflow.Data(ch); d.Name = name; d.Scope = scope;
    if nargin > 3 && ~isempty(dataType), d.DataType = dataType; end
end

function addConst(ch, name, val)
    d = Stateflow.Data(ch); d.Name = name; d.Scope = 'Constant';
    d.Props.InitialValue = val;
end

function addParam(ch, name, val)
    % 설계 상수는 Constant 스코프로 생성한다.
    % (Stateflow 의 Parameter 스코프 데이터는 차트 내 InitialValue 를 지원하지 않고,
    %  값이 MATLAB/모델 workspace 에서 와야 하므로 여기서는 Constant 를 사용)
    d = Stateflow.Data(ch); d.Name = name; d.Scope = 'Constant';
    d.Props.InitialValue = val;
end
