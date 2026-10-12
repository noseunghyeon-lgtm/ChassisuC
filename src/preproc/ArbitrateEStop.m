function estop_active = ArbitrateEStop(hw_estop, estop_vc)
% ArbitrateEStop - E-Stop 다중소스(HW + VC) OR 중재
%
%   [v0.7 변경] Control Computer 삭제 → VC 통합. E-Stop 2경로:
%   하드와이어(HW) + VC(E_STOP_AB). 하나라도 ESTOP 이면 작동(안전측 OR).
%   (DBC RS_E_STOP2.E_STOP_AB ValueTable: 7=ESTOP, 1=None, 0=Invalid)
%
% 입력:
%   hw_estop  - 하드와이어 E-Stop 신호 (boolean). true=작동.
%   estop_vc  - E_STOP_AB 값 (uint8). 7=ESTOP.
%
% 출력:
%   estop_active - E-Stop 작동 (boolean). 상태머신 최우선(순위0) 입력.
%
% 비고: Invalid(0)/None(1)은 미작동으로 취급. 7(ESTOP)만 작동.
%       (구 CC 경로 E_STOP_AA 는 v0.7 에서 삭제됨)

    EV_ESTOP = uint8(7);
    vc_fire = (uint8(estop_vc) == EV_ESTOP);
    estop_active = logical(hw_estop) || vc_fire;
end
