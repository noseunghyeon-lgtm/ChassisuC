function mode_req = ArbitrateModeReq(opmode)
% ArbitrateModeReq - 모드요청 매핑 (단일 소스)
%
%   [v0.7 변경] Control Computer 삭제 → VC 통합. 모드 경로가 1개(RS_Chassis_Command.
%   Chassis_Op_Mode)로 통합되어 **CC/VC 중재가 불필요**해짐.
%   (구 C20 "CC 우선 + 불일치 점검요청" 로직은 CC 삭제로 폐기 — system_check_request 불필요)
%
% 입력:
%   opmode   - Chassis_Op_Mode (uint8). 0:Invalid, 1:Manual, 2:RS (DBC RS_Chassis_Command)
%
% 출력:
%   mode_req - 모드 전환 요청 (uint8, ModeReq enum): 0:REQ_NONE, 1:REQ_TO_S1, 2:REQ_TO_S2
%
% 매핑: 1(Manual)->REQ_TO_S1, 2(RS)->REQ_TO_S2, 0(Invalid)->REQ_NONE

    MANUAL=uint8(1); RS=uint8(2);
    REQ_NONE=uint8(0); REQ_TO_S1=uint8(1); REQ_TO_S2=uint8(2);

    switch uint8(opmode)
        case MANUAL
            mode_req = REQ_TO_S1;
        case RS
            mode_req = REQ_TO_S2;
        otherwise
            mode_req = REQ_NONE;
    end
end
