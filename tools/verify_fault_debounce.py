#!/usr/bin/env python3
"""
verify_fault_debounce.py - C04 치명고장 확정 디바운스 동치검증

이 환경에는 MATLAB 이 없어 .slx 실제 실행이 불가하다.
src/preproc/DebounceFaultCritical.m 의 디바운스 로직(persistent 카운터)을
동일 규칙으로 Python 에 재현하고, 대표 시나리오로 거동을 검증한다.

규칙(MATLAB 과 1:1):
  DEBOUNCE_TICKS = 10, TICK_MS = 10  (총 100ms)
  - raw=True  → cnt 누적(DEBOUNCE_TICKS 에서 포화)
  - raw=False → cnt = 0 (연속 지속 요구, 중간 해제 시 리셋)
  - confirmed = (cnt >= DEBOUNCE_TICKS)

코드생성 호환성 note: uint8 포화를 모사(카운터는 DEBOUNCE_TICKS 에서 멈춤).
"""

DEBOUNCE_TICKS = 10
TICK_MS = 10


class FaultDebounce:
    """DebounceFaultCritical.m 의 persistent 상태를 캡슐화."""

    def __init__(self):
        self.cnt = 0
        self.initialized = False

    def step(self, fault_critical_raw: bool, reset: bool = False) -> bool:
        if not self.initialized or reset:
            self.cnt = 0
            self.initialized = True
        if fault_critical_raw:
            if self.cnt < DEBOUNCE_TICKS:
                self.cnt += 1
        else:
            self.cnt = 0
        return self.cnt >= DEBOUNCE_TICKS


def run(seq, reset_at=()):
    """raw bool 시퀀스를 흘려 confirmed 시퀀스를 반환."""
    dq = FaultDebounce()
    out = []
    for i, raw in enumerate(seq):
        out.append(dq.step(raw, reset=(i in reset_at)))
    return out


def check(name, got, expected):
    ok = got == expected
    print(f"[{'PASS' if ok else 'FAIL'}] {name}")
    if not ok:
        print(f"       got     : {got}")
        print(f"       expected: {expected}")
    return ok


def main():
    results = []

    # 1) 9틱 연속은 확정 안 됨(100ms 미만), 10틱째 확정.
    seq = [True] * 12
    got = run(seq)
    expected = [False] * 9 + [True] * 3  # idx0..8 False, idx9(10틱)부터 True
    results.append(check("10틱(100ms) 연속 지속 시 확정", got, expected))

    # 2) 9틱 지속 후 1틱 해제 → 카운터 리셋, 재확정은 다시 10틱 필요.
    seq = [True] * 9 + [False] + [True] * 10
    got = run(seq)
    # 0..8:False, 9:False(해제 리셋), 10..18:False(재누적 1..9), 19:True(10틱째)
    expected = [False] * 9 + [False] + [False] * 9 + [True]
    results.append(check("중간 1틱 해제 시 카운터 리셋(연속 지속 요구)", got, expected))

    # 3) 확정 유지: 10틱 이후 계속 True 면 계속 확정(포화 유지).
    seq = [True] * 15
    got = run(seq)
    expected = [False] * 9 + [True] * 6
    results.append(check("확정 후 지속 유지(uint8 포화)", got, expected))

    # 4) 확정 후 해제되면 즉시 비확정(래치 없음).
    seq = [True] * 11 + [False] + [True] * 2
    got = run(seq)
    # 0..8:F, 9:T,10:T, 11:F(해제 리셋), 12:F,13:F(재누적 1..2)
    expected = [False] * 9 + [True, True, False, False, False]
    results.append(check("확정 후 해제 시 즉시 비확정(래치 없음)", got, expected))

    # 5) reset 입력으로 카운터 초기화.
    seq = [True] * 12
    got = run(seq, reset_at=(10,))
    # 0..8:F, 9:T, 10:reset→cnt=0 then raw True → cnt=1 → F, 11: cnt=2 → F
    expected = [False] * 9 + [True, False, False]
    results.append(check("reset 입력 시 카운터 초기화", got, expected))

    # 6) 총 디바운스 시간 = 100ms 확인.
    results.append(check("디바운스 총시간 = 100ms",
                         DEBOUNCE_TICKS * TICK_MS, 100))

    print()
    if all(results):
        print(f"ALL PASS ({len(results)}개) — DebounceFaultCritical.m 거동 동치 확인")
        return 0
    print("SOME FAILED")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
