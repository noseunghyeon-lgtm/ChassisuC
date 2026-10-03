function crc_ok = CheckCRC(frame_bytes)
% CheckCRC - 수신 CAN 프레임의 CRC-8 SAE J1850 무결성 점검
%
%   프레임의 마지막 바이트를 수신 CRC 로 보고, 나머지 앞 바이트로 CRC 를
%   재계산해 일치 여부를 반환한다. (CRC-8 SAE J1850, src/CalcCRC8_J1850.m)
%
% 입력:
%   frame_bytes - 전체 프레임 바이트 배열 (1 x N), 마지막 바이트 = 수신 CRC
%                 예: 8바이트 메시지면 [b0..b6, crc]
%
% 출력:
%   crc_ok      - CRC 일치 (boolean)
%
% 사용 예:
%   crc_ok = CheckCRC([0x12,0x34,0x56,0x78,0x9A,0xBC,0xDE, received_crc]);
%
% 비고: 계산 범위는 "CRC 바이트(자기)를 뺀 앞의 모든 바이트" (확정, Issue #6).
%       CRC 는 메시지 마지막 바이트에 위치하는 관례를 따른다.

    n = numel(frame_bytes);
    if n < 2
        crc_ok = false;      % payload + CRC 최소 2바이트 필요
        return;
    end

    data_bytes   = frame_bytes(1:n-1);   % CRC 뺀 앞 전체
    received_crc = uint8(frame_bytes(n));
    computed     = CalcCRC8_J1850(data_bytes);

    crc_ok = (computed == received_crc);
end
