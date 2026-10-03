function [value_out, valid] = ValidateHoldLast(raw, invalid_val, reset)
% ValidateHoldLast - Invalid 값 수신 시 마지막 유효값 유지(hold-last-valid)
%
%   많은 CAN 신호가 Invalid 특수값(예: 0, 101, 7:Fault)을 가진다.
%   Invalid 수신 시 해당 입력을 바꾸지 않고 마지막 유효값을 유지하며
%   valid=false 로 표시한다. (전처리 §1.2)
%
% 입력:
%   raw         - 수신 raw 값 (double/정수)
%   invalid_val - 이 값과 같으면 Invalid 로 간주 (예: 0, 101)
%   reset       - 상태 초기화 (boolean)
%
% 출력:
%   value_out   - 유효하면 raw, 아니면 마지막 유효값 (hold)
%   valid       - 이번 값이 유효한지 (boolean)
%
% 비고: persistent 로 마지막 유효값 유지. 다중 신호엔 인스턴스 분리 또는
%       배열 persistent 로 확장. 범위검사(min/max)가 더 필요하면 입력 추가.

    persistent last_valid has_valid
    if isempty(has_valid) || reset
        last_valid = raw;
        has_valid  = false;
    end

    if raw == invalid_val
        valid     = false;
        value_out = last_valid;      % hold
    else
        valid      = true;
        last_valid = raw;
        has_valid  = true;
        value_out  = raw;
    end
end
