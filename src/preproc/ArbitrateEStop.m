function estop_active = ArbitrateEStop(hw_estop, estop_cc, estop_vc)
% ArbitrateEStop - E-Stop 다중소스(HW + CC + VC) OR 중재
%
%   E-Stop 은 3경로로 수신: 하드와이어(HW) + CC(E_STOP_AA) + VC(E_STOP_AB).
%   하나라도 ESTOP 이면 작동(안전측 OR). (DB ValueTable: 7=ESTOP, 1=None, 0=Invalid)
%
% 입력:
%   hw_estop  - 하드와이어 E-Stop 신호 (boolean). true=작동.
%   estop_cc  - E_STOP_AA 값 (uint8). 7=ESTOP.
%   estop_vc  - E_STOP_AB 값 (uint8). 7=ESTOP.
%
% 출력:
%   estop_active - E-Stop 작동 (boolean). 상태머신 최우선(순위0) 입력.
%
% 비고: Invalid(0)/None(1)은 미작동으로 취급. 7(ESTOP)만 작동.
%       디바운스가 필요하면 호출측 또는 별도 블록에서 적용.

    EV_ESTOP = uint8(7);

    cc_fire = (uint8(estop_cc) == EV_ESTOP);
    vc_fire = (uint8(estop_vc) == EV_ESTOP);

    estop_active = logical(hw_estop) || cc_fire || vc_fire;
end
