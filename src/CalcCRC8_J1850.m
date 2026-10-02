function crc = CalcCRC8_J1850(data_bytes)
% CalcCRC8_J1850 - CRC-8 SAE J1850 체크섬 계산 (E2E 보호용)
%
%   Chassis uC CAN 메시지 E2E 보호 CRC (Issue #6, C23).
%   규격: CRC-8 SAE J1850
%     - 다항식(poly)  : 0x1D
%     - 초기값(init)  : 0xFF
%     - 최종 XOR(xorout): 0xFF
%     - reflect in/out : false (비반전)
%
%   계산 범위: **CRC 바이트(자기 자신)를 제외한 앞의 모든 바이트**.
%     관례상 CRC 는 메시지의 마지막 바이트에 위치하므로,
%     data_bytes 에는 CRC 바이트를 제외한 payload 전체를 순서대로 넘긴다.
%
% 입력:
%   data_bytes - CRC 를 뺀 데이터 바이트 배열 (1 x N), 각 원소 0~255
%                예: 8바이트 메시지에서 마지막이 CRC면 앞 7바이트 [b0..b6]
%
% 출력:
%   crc        - 계산된 CRC-8 값 (uint8, 0~255)
%
% 사용 예:
%   msg = [0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE];  % CRC 제외 payload
%   crc = CalcCRC8_J1850(msg);
%   full_msg = [msg, crc];                              % 마지막에 CRC 부착
%
% 검증(수신 측):
%   rx_crc  = full_msg(end);
%   calc    = CalcCRC8_J1850(full_msg(1:end-1));
%   crc_ok  = (calc == rx_crc);
%
% 비고: Simulink/Stateflow 에서 MATLAB Function 블록으로 그대로 사용 가능.
%       코드 생성(Embedded Coder) 호환을 위해 스칼라 루프 + 비트연산으로 구현.

    POLY   = uint8(29);    % 0x1D
    INIT   = uint8(255);   % 0xFF
    XOROUT = uint8(255);   % 0xFF

    crc = INIT;
    n = numel(data_bytes);

    for i = 1:n
        crc = bitxor(crc, uint8(data_bytes(i)));
        for b = 1:8
            if bitand(crc, uint8(128)) ~= 0        % MSB(0x80) 가 1 이면
                crc = bitxor(bitshift(crc, 1), POLY);  % 좌시프트 후 다항식 XOR
            else
                crc = bitshift(crc, 1);                % 좌시프트만
            end
            crc = bitand(crc, uint8(255));          % 8bit 유지
        end
    end

    crc = bitxor(crc, XOROUT);   % 최종 XOR
end
