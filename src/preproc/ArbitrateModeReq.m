function [mode_req, system_check_request] = ArbitrateModeReq(opmode_cc, opmode_vc)
% ArbitrateModeReq - CC/VC 모드요청 중재 (CC 우선, 불일치 시 점검요청)
%
%   확정(Issue #5, C20):
%     - CC 가 VC 보다 높은 priority.
%     - 서로 다른 모드 요청 시 → CC 채택 + 운영자 System 점검 요청.
%
% 입력:
%   opmode_cc - Chassis_Op_Mode_CC (uint8). 0:Invalid, 1:Manual, 2:RS
%   opmode_vc - Chassis_Op_Mode_VC (uint8). 0:Invalid, 1:Manual, 2:RS
%
% 출력:
%   mode_req             - 모드 전환 요청 (uint8, ModeReq enum 값)
%                          0:REQ_NONE, 1:REQ_TO_S1(Manual), 2:REQ_TO_S2(RS)
%   system_check_request - CC/VC 불일치 운영자 점검요청 (boolean, 상태천이 없음)
%
% 매핑: Op_Mode 1(Manual)->REQ_TO_S1, 2(RS)->REQ_TO_S2, 0(Invalid)->REQ_NONE

    INVALID=uint8(0); MANUAL=uint8(1); RS=uint8(2);
    REQ_NONE=uint8(0); REQ_TO_S1=uint8(1); REQ_TO_S2=uint8(2);

    cc = uint8(opmode_cc);
    vc = uint8(opmode_vc);

    system_check_request = false;

    if cc == vc
        src = cc;                      % 일치 → 그대로
    elseif cc ~= INVALID
        src = cc;                      % 불일치 → CC 우선
        system_check_request = true;   % + 운영자 점검요청
    else
        src = vc;                      % CC Invalid 시에만 VC
    end

    switch src
        case MANUAL
            mode_req = REQ_TO_S1;
        case RS
            mode_req = REQ_TO_S2;
        otherwise
            mode_req = REQ_NONE;
    end
end
