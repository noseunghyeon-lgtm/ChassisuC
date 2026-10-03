function [hb_ok, hb_age_ms, stale] = CheckHeartbeat(mc_raw, msg_valid, reset)
% CheckHeartbeat - Message Counter(Alive) 정체 감시로 Heartbeat 생존 판정
%
%   CAN 메시지의 Message Counter(MC, 0~15 순환)를 매 틱 관찰해,
%   값이 갱신되면 "살아있음", 일정 시간 정체되면 "두절"로 판정한다.
%   (DB: CC_AliveCounter / VC_AliveCounter / MC_* 4bit, 0~15)
%
% 입력:
%   mc_raw    - 이번 틱에 수신한 Message Counter 값 (uint8, 0~15)
%   msg_valid - 이번 틱에 해당 메시지 프레임을 수신했는지 (boolean)
%               (CRC/범위 검증을 통과한 유효 프레임일 때 true)
%   reset     - 상태 초기화 (boolean). 상태 진입/재기동 시 true 1틱.
%
% 출력:
%   hb_ok     - Heartbeat 정상 (boolean). age <= TIMEOUT 이면 true.
%   hb_age_ms - 마지막 MC 변화 이후 경과시간 [ms] (uint16)
%   stale     - 두절 확정 (boolean). age > TIMEOUT.
%
% 파라미터(상수):
%   TICK_MS     = 10    (호출 주기, 문서 §2)
%   TIMEOUT_MS  = 400   (SRS-SYS-007, 원격 명령 Heartbeat)
%
% 사용 예 (Simulink MATLAB Function 블록):
%   [ok, age, stale] = CheckHeartbeat(CC_AliveCounter, frame_valid, false);
%
% 비고: persistent 로 상태 유지. 코드생성(Embedded Coder) 호환.
%       영상 HB 처럼 TIMEOUT 이 다른 경우를 위해 별도 인스턴스로 쓰거나
%       파라미터화가 필요하면 TIMEOUT 을 입력으로 승격할 것.

    TICK_MS    = uint16(10);
    TIMEOUT_MS = uint16(400);

    persistent last_mc age_ms initialized
    if isempty(initialized) || reset
        last_mc     = uint8(mc_raw);
        age_ms      = uint16(0);
        initialized = true;
    end

    % 유효 프레임이고 MC 가 변했으면 "갱신" → age 리셋
    if msg_valid && (uint8(mc_raw) ~= last_mc)
        last_mc = uint8(mc_raw);
        age_ms  = uint16(0);
    else
        % 변화 없음(정체) 또는 미수신 → age 누적 (포화)
        if age_ms <= uint16(65535) - TICK_MS
            age_ms = age_ms + TICK_MS;
        else
            age_ms = uint16(65535);
        end
    end

    hb_age_ms = age_ms;
    hb_ok     = (age_ms <= TIMEOUT_MS);
    stale     = (age_ms >  TIMEOUT_MS);
end
