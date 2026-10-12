function sf = PreprocessInputs(asw)
% PreprocessInputs - ASW raw 신호 → Stateflow 입력(파생 플래그) 단일 진입점
%
%   방식 1 경계: [ASW raw] → PreprocessInputs → [Stateflow 입력].
%   ★ 이 함수의 입력 struct 필드명 = ASW heading (ASW 와 1:1 일치).
%   ★ 출력 struct 필드명 = Stateflow 입력 포트명 (build_chassis_controller.m 과 일치).
%
%   Simulink: Bus(ASW) → MATLAB Function(PreprocessInputs) → Bus(Stateflow in).
%   코드생성(C) 호환 — 스칼라 연산.
%
% 입력 (asw.*  = ASW raw 신호, heading):
%   asw.IGN_ON                  (bool)   점화 ON
%   asw.VC_Net_Level            (u8 0~10)
%   asw.VC_Net_Link_Count       (u8)     인증 판단
%   asw.VC_Communication_Fault  (bool)   VC 통신고장
%   asw.u8_AEBS                 (u8)     7=AEBS
%   asw.u8_Req_Remote_Mode      (u8)     0:Inv 1:Manual 2:RS
%   asw.f_VehicleSpeed          (single) kph
%   asw.u8_APP                  (u8)     가속페달
%   asw.u8_Gear_Status          (u8)     0:P 1:L 2:2 3:3 4:NC 5:D 6:N 7:R
%   asw.BRK_Status_Position     (single) 제동 캠 위치
%   asw.estop_hw                (bool)   HW E-Stop
%   asw.estop_can               (bool)   CAN E-Stop (RS_E_STOP2)
%   asw.u8_HW_Fault             (u8)     4 Fault bitfield (b0:Accel b1:Brake b2:GearActu b3:GearSel)
%   asw.u8_MODE_MN              (bool)   차량실내 Manual 스위치
%   asw.steer_intervention      (bool)   조향 개입
%   asw.Tx_IGN                  (bool)   selftest 판단
%
% 출력 (sf.*  = Stateflow 입력 포트):
%   sf.ign_on, sf.vc_net_level, sf.aebs_flag, sf.mode_req, sf.vehicle_speed,
%   sf.pedal_pos, sf.heartbeat_ok, sf.estop_active, sf.fault_critical_confirmed,
%   sf.actuators_neutral, sf.cam_at_origin, sf.arm_rs_mutual_auth, sf.arm_speed_zero,
%   sf.arm_gear_park_or_neutral, sf.gear_ready, sf.selftest_done, sf.takeover_req,
%   sf.manual_switch_req
%
% 비고: TBD 임계값은 상수로 분리(STANDSTILL_SPEED 등). 확정 시 교체.

    % ---- 파라미터(TBD 포함) ----
    STANDSTILL_SPEED = single(-1);  % 차속0 임계 (C05, placeholder)
    GEAR_P = uint8(0);  GEAR_N = uint8(6);
    AEBS_FIRE = uint8(7);

    % ---- 직통(형변환/스케일만) ----
    sf.ign_on        = logical(asw.IGN_ON);
    sf.vc_net_level  = uint8(asw.VC_Net_Level);
    sf.vehicle_speed = single(asw.f_VehicleSpeed);
    sf.pedal_pos     = single(asw.u8_APP);

    % ---- AEBS: u8==7 → bool ----
    sf.aebs_flag = (uint8(asw.u8_AEBS) == AEBS_FIRE);

    % ---- 모드 요청: 단일 소스 매핑 ----
    sf.mode_req = ArbitrateModeReq(asw.u8_Req_Remote_Mode);

    % ---- Heartbeat: 통신고장 반전 ----
    sf.heartbeat_ok = ~logical(asw.VC_Communication_Fault);

    % ---- E-Stop: HW OR CAN (동일 레벨) ----
    sf.estop_active = ArbitrateEStop(asw.estop_hw, ternary(asw.estop_can, uint8(7), uint8(1)));

    % ---- 치명고장: u8_HW_Fault 비트 중 하나라도 ----
    sf.fault_critical_confirmed = (uint8(asw.u8_HW_Fault) ~= uint8(0));

    % ---- 중립: 현재 기어 == N ----
    sf.actuators_neutral = (uint8(asw.u8_Gear_Status) == GEAR_N);

    % ---- 캠 원점: BRK 위치 ----
    sf.cam_at_origin = (single(asw.BRK_Status_Position) <= single(0));  % 원점 판정(임계 TBD)

    % ---- 인터록 3조건 ----
    sf.arm_rs_mutual_auth       = (uint8(asw.VC_Net_Link_Count) > uint8(0));  % 연결 수립
    sf.arm_speed_zero           = (single(asw.f_VehicleSpeed) <= STANDSTILL_SPEED); % TBD(-1→항상 거짓)
    g = uint8(asw.u8_Gear_Status);
    sf.arm_gear_park_or_neutral = (g == GEAR_P) || (g == GEAR_N);

    % ---- 기어 준비 / selftest ----
    sf.gear_ready     = (uint8(asw.u8_Gear_Status) ~= uint8(4));  % NC(4) 아니면 준비(판단 가능, 상세 TBD)
    sf.selftest_done  = logical(asw.Tx_IGN);

    % ---- 테이크오버: 조향개입 OR E-Stop OR MN스위치 ----
    sf.takeover_req = logical(asw.steer_intervention) || sf.estop_active || logical(asw.u8_MODE_MN);

    % ---- 수동전환: 차량실내 Manual 스위치 ----
    sf.manual_switch_req = logical(asw.u8_MODE_MN);
end

function y = ternary(cond, a, b)
    if cond, y = a; else, y = b; end
end
