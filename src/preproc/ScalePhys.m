function phys = ScalePhys(raw, factor, offset)
% ScalePhys - CAN raw 값을 물리값으로 변환 (phys = raw*factor + offset)
%
%   DB 의 Factor/Offset 적용 (전처리 §1.1). 스케일 신호 135건.
%   예: Vehicle_Velocity (factor 0.5, offset 0) → kph
%       Steering_Angle   (factor 0.1, offset -800) → deg
%
% 입력:
%   raw    - 수신 raw 값 (정수)
%   factor - DB Factor (double)
%   offset - DB Offset (double)
%
% 출력:
%   phys   - 물리값 (double)

    phys = double(raw) * double(factor) + double(offset);
end
