function fault_critical_confirmed = DebounceFaultCritical(fault_critical_raw, reset)
% DebounceFaultCritical - 치명고장 "검출" → "확정" 디바운스 (C04 확정)
%
%   치명고장 검출 플래그(fault_critical_raw)가 DEBOUNCE_TICKS(10틱) 동안
%   연속 지속되어야 fault_critical_confirmed = true 로 확정한다.
%   10틱 × TICK_MS(10ms) = 100ms. (M02: 검출 ≠ 확정, §6-3 디바운스)
%
%   fault_critical_raw 는 u8_HW_Fault 4비트(Accel/Brake/GearActu/GearSel)
%   중 하나라도 고장이면 OR 로 산출된 치명고장 검출 플래그다. (호출측에서 OR)
%   중간에 한 틱이라도 해제되면 카운터는 0 으로 리셋(연속 지속 요구).
%
% 입력:
%   fault_critical_raw - 이번 틱 치명고장 검출 (boolean). u8_HW_Fault OR 결과.
%   reset              - 상태 초기화 (boolean). 상태 진입/재기동 시 true 1틱.
%
% 출력:
%   fault_critical_confirmed - 치명고장 확정 (boolean). 상태머신 S6 전이 입력.
%
% 파라미터(상수):
%   DEBOUNCE_TICKS = 10   (C04 확정)
%   TICK_MS        = 10   (호출 주기 [ms], 문서 §2)
%                         → 디바운스 총시간 = 10 × 10 = 100ms
%
% 사용 예 (Simulink MATLAB Function 블록):
%   raw = accel_fault || brake_fault || gearactu_fault || gearsel_fault;
%   fcc = DebounceFaultCritical(raw, false);
%
% 비고: persistent 로 카운터 유지. 코드생성(Embedded Coder) 호환.
%       확정은 래치하지 않는다(현 틱 기준 연속 지속 판정). 확정 후 래치가
%       필요하면 호출측 상태(S6 진입)에서 유지한다.

    DEBOUNCE_TICKS = uint8(10);   % C04 확정
    %#ok<*NASGU> TICK_MS 는 디바운스 총시간(100ms) 문서화를 위한 상수
    TICK_MS        = uint8(10);   % 틱 주기 [ms] → DEBOUNCE_TICKS*TICK_MS = 100ms

    persistent cnt initialized
    if isempty(initialized) || reset
        cnt         = uint8(0);
        initialized = true;
    end

    if logical(fault_critical_raw)
        % 연속 지속 → 카운터 누적(포화)
        if cnt < DEBOUNCE_TICKS
            cnt = cnt + uint8(1);
        end
    else
        % 해제 → 카운터 리셋(연속 지속 요구)
        cnt = uint8(0);
    end

    fault_critical_confirmed = (cnt >= DEBOUNCE_TICKS);
end
