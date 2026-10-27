function [remote_reengage_ok, mn_reengaged, vc_reengaged] = ...
        DetectRemoteReengage(u8_MODE_MN, Chassis_Op_Mode, reset)
% DetectRemoteReengage - AEBS 해제용 2중화 Remote 재진입 엣지검출 (AND 합성)
%
%   S4(AEBS_OVERRIDE) 이탈(S4→S2)의 정상 조건 remote_reengage_ok 를 산출한다.
%   AEBS 작동 시 차속은 0까지 완전정지하며, 해제는 "VC 가 Remote 버튼을
%   Manual 로 바꿨다가 다시 Remote 로 전환하는 조작"을 거쳐야 한다.
%
%   2중화 두 경로를 **각각 독립적으로** Manual 경유 엣지 시퀀스로 요구하고,
%   두 경로가 **모두** 재진입(latch)했을 때만 유효(AND)로 판정한다.
%   (E-Stop 은 안전측 OR 이지만, 모드 재진입은 두 경로 동시 성립을 요구하는 AND)
%
%   (1) 차량쪽 HW 경로 = u8_MODE_MN (K31 MODE_MN / K34 MODE_RM 핀 전처리값)
%   (2) VC쪽 CAN 경로  = Chassis_Op_Mode (RS_Chassis_Command, VC 송신, 4비트)
%       DBC VAL_ Chassis_Op_Mode: 0=Invalid, 1=Manual, 2=RS(Remote)
%
% 입력:
%   u8_MODE_MN       - 차량 HW 수동/원격 모드값 (uint8). 1:Manual, 2:Remote.
%   Chassis_Op_Mode  - VC CAN 운용모드 (uint8). 0:Invalid, 1:Manual, 2:RS(Remote).
%   reset            - latch 초기화 (boolean). ★ S4 진입 시 true 로 주어
%                      새 AEBS 이벤트마다 2단 조작을 새로 요구한다.
%
% 출력:
%   remote_reengage_ok - 2중화 재진입 완료 (boolean) = mn_reengaged && vc_reengaged
%   mn_reengaged       - 차량 HW 경로 재진입 latch (boolean)
%   vc_reengaged       - VC CAN 경로 재진입 latch (boolean)
%
% 엣지 시퀀스(경로별 독립):
%   HW:  u8_MODE_MN==Manual 관측 시 mn_reset_armed=TRUE;
%        mn_reset_armed && u8_MODE_MN==Remote 시 mn_reengaged=TRUE (latch)
%   VC:  Chassis_Op_Mode==1(Manual) 관측 시 vc_reset_armed=TRUE;
%        vc_reset_armed && Chassis_Op_Mode==2(RS) 시 vc_reengaged=TRUE (latch)
%   합성: remote_reengage_ok = mn_reengaged && vc_reengaged
%
% 비고: persistent 로 armed/latch 유지. 코드생성(Embedded Coder) 호환 — 스칼라 연산.
%       mn_reengaged/vc_reengaged/mn_reset_armed/vc_reset_armed 는 reset(=S4 진입) 시
%       모두 FALSE 초기화. latch 는 reset 전까지 유지된다.

    % ---- 모드 상수 (uint8, 명시적 타입 — C 코드생성 D5) ----
    MODE_MANUAL = uint8(1);   % u8_MODE_MN / Chassis_Op_Mode 공통: 1 = Manual
    MODE_REMOTE = uint8(2);   % 2 = RS (Remote)

    persistent mn_reset_armed vc_reset_armed mn_latch vc_latch initialized
    if isempty(initialized) || reset
        mn_reset_armed = false;   % HW 경로 Manual 관측 여부
        vc_reset_armed = false;   % VC 경로 Manual 관측 여부
        mn_latch       = false;   % HW 경로 재진입 완료 latch
        vc_latch       = false;   % VC 경로 재진입 완료 latch
        initialized    = true;
    end

    hw_mode = uint8(u8_MODE_MN);
    vc_mode = uint8(Chassis_Op_Mode);

    % ---- (1) 차량 HW 경로 엣지검출 ----
    if hw_mode == MODE_MANUAL
        mn_reset_armed = true;                 % Manual 을 한 번 거침 → arm
    end
    if mn_reset_armed && (hw_mode == MODE_REMOTE)
        mn_latch = true;                       % Manual 경유 후 Remote 복귀 → latch
    end

    % ---- (2) VC CAN 경로 엣지검출 ----
    if vc_mode == MODE_MANUAL
        vc_reset_armed = true;                 % Manual 을 한 번 거침 → arm
    end
    if vc_reset_armed && (vc_mode == MODE_REMOTE)
        vc_latch = true;                       % Manual 경유 후 RS 복귀 → latch
    end

    % ---- 합성: AND (두 경로 모두 재진입해야 유효) ----
    mn_reengaged       = mn_latch;
    vc_reengaged       = vc_latch;
    remote_reengage_ok = mn_latch && vc_latch;
end
