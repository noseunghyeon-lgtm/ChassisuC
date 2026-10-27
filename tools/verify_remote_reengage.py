#!/usr/bin/env python3
"""Equivalence check for DetectRemoteReengage.m (AEBS 해제 2중화 Remote 재진입).

이 레포는 CRC 로직을 Python 동치검증으로 확인한 전례가 있다. MATLAB 이 없는
환경에서 엣지검출 + AND 합성 + latch + S4 진입 리셋의 올바름을 확인한다.

MATLAB 원본(src/preproc/DetectRemoteReengage.m)의 스칼라 로직을 1:1 로 옮긴
tick 함수로, 입력 시퀀스를 흘려보내며 기대 출력과 대조한다.

실행: python3 tools/verify_remote_reengage.py   (exit 0 = 전부 통과)
"""

MODE_INVALID = 0
MODE_MANUAL = 1   # u8_MODE_MN / Chassis_Op_Mode 공통: 1 = Manual
MODE_REMOTE = 2   # 2 = RS (Remote)


class RemoteReengage:
    """DetectRemoteReengage.m 의 persistent 상태를 캡슐화한 동치 구현."""

    def __init__(self):
        # persistent 초기화 상태 (reset 과 동일 효과)
        self.mn_reset_armed = False
        self.vc_reset_armed = False
        self.mn_latch = False
        self.vc_latch = False

    def tick(self, u8_mode_mn, chassis_op_mode, reset):
        # reset(=S4 진입) 시 armed/latch 모두 FALSE 초기화
        if reset:
            self.mn_reset_armed = False
            self.vc_reset_armed = False
            self.mn_latch = False
            self.vc_latch = False

        hw = u8_mode_mn
        vc = chassis_op_mode

        # (1) 차량 HW 경로 엣지검출
        if hw == MODE_MANUAL:
            self.mn_reset_armed = True
        if self.mn_reset_armed and hw == MODE_REMOTE:
            self.mn_latch = True

        # (2) VC CAN 경로 엣지검출
        if vc == MODE_MANUAL:
            self.vc_reset_armed = True
        if self.vc_reset_armed and vc == MODE_REMOTE:
            self.vc_latch = True

        remote_reengage_ok = self.mn_latch and self.vc_latch
        return remote_reengage_ok, self.mn_latch, self.vc_latch


# ---- 테스트 러너 ---------------------------------------------------------

_failures = []


def run(name, steps, expect_final):
    """steps: [(mode_mn, op_mode, reset), ...]; expect_final: remote_reengage_ok 기대값.
       추가로 step 별 기대값을 (ok, mn, vc) 튜플로 넣을 수도 있다."""
    det = RemoteReengage()
    last = None
    for i, step in enumerate(steps):
        mn, vc, reset = step[0], step[1], step[2]
        ok, mnl, vcl = det.tick(mn, vc, reset)
        last = (ok, mnl, vcl)
        if len(step) > 3 and step[3] is not None:
            exp = step[3]
            if (ok, mnl, vcl) != exp:
                _failures.append(
                    f"[{name}] step{i} got {(ok, mnl, vcl)} expected {exp}")
    if last[0] != expect_final:
        _failures.append(
            f"[{name}] final remote_reengage_ok={last[0]} expected {expect_final}")
    status = "OK " if not any(name in f for f in _failures) else "FAIL"
    print(f"  [{status}] {name}: final={last}")


def main():
    print("DetectRemoteReengage equivalence check")
    print("-" * 60)

    R, M, I = MODE_REMOTE, MODE_MANUAL, MODE_INVALID

    # 1) 아무 조작 없이 Remote 유지만: 재진입 아님 (Manual 경유 안 함) → False
    run("no_manual_both_remote",
        [(R, R, True)] + [(R, R, False)] * 5,
        expect_final=False)

    # 2) 두 경로 모두 Manual 경유 후 Remote 복귀 → True (정상 시퀀스)
    run("both_paths_full_sequence",
        [(R, R, True),      # S4 진입 리셋
         (M, M, False),     # 두 경로 Manual 관측 → armed
         (R, R, False)],    # 두 경로 Remote 복귀 → 둘 다 latch → AND True
        expect_final=True)

    # 3) HW 만 시퀀스 완료, VC 는 Remote 유지(Manual 경유 안 함) → AND False
    run("only_hw_sequence",
        [(R, R, True),
         (M, R, False),     # HW armed, VC 는 계속 Remote
         (R, R, False)],    # HW latch, VC latch 없음
        expect_final=False)

    # 4) VC 만 시퀀스 완료, HW 는 Remote 유지 → AND False
    run("only_vc_sequence",
        [(R, R, True),
         (R, M, False),
         (R, R, False)],
        expect_final=False)

    # 5) 두 경로 독립 타이밍: HW 먼저 완료, 나중에 VC 완료 → 완료 시점에 True
    run("independent_timing",
        [(R, R, True),
         (M, R, False, (False, False, False)),  # HW armed only
         (R, R, False, (False, True, False)),   # HW latch, VC 아직
         (R, M, False, (False, True, False)),   # VC armed
         (R, R, False, (True, True, True))],    # VC latch → AND True
        expect_final=True)

    # 6) latch 유지: 완료 후 Manual 로 다시 가도 latch 는 유지(reset 전까지)
    run("latch_persists_until_reset",
        [(R, R, True),
         (M, M, False),
         (R, R, False, (True, True, True)),     # 완료
         (M, M, False, (True, True, True)),     # Manual 재방문해도 latch 유지
         (R, R, False, (True, True, True))],
        expect_final=True)

    # 7) 새 AEBS 이벤트(reset) 후에는 2단 조작을 새로 요구 → 리셋 직후 False
    run("reset_requires_new_sequence",
        [(R, R, True),
         (M, M, False),
         (R, R, False, (True, True, True)),     # 1차 완료
         (R, R, True, (False, False, False)),   # 새 S4 진입(reset) → 전부 FALSE
         (R, R, False, (False, False, False))], # Manual 경유 안 하면 재진입 아님
        expect_final=False)

    # 8) 리셋 후 다시 full 시퀀스 거치면 True
    run("reset_then_resequence",
        [(R, R, True),
         (M, M, False), (R, R, False),          # 1차 완료
         (R, R, True),                          # 새 S4
         (M, M, False), (R, R, False)],         # 2차 완료
        expect_final=True)

    # 9) Invalid(0) 는 Manual 도 Remote 도 아님 → armed/latch 변화 없음
    run("invalid_mode_noop",
        [(R, R, True),
         (I, I, False, (False, False, False)),  # Invalid: 아무 것도 안 함
         (M, M, False, (False, False, False)),  # armed only
         (I, I, False, (False, False, False)),  # Invalid: latch 안 됨(Remote 아님)
         (R, R, False, (True, True, True))],    # Remote 복귀 → latch
        expect_final=True)

    # 10) 엣지 순서 역: Remote→(armed 없이) 바로 Remote 는 latch 안 됨
    run("remote_before_manual_no_latch",
        [(R, R, True),
         (R, R, False, (False, False, False)),  # armed 전 Remote → latch 안 됨
         (M, M, False, (False, False, False)),  # 이제 armed
         (R, R, False, (True, True, True))],
        expect_final=True)

    print("-" * 60)
    if _failures:
        print(f"FAILED ({len(_failures)} assertion(s)):")
        for f in _failures:
            print("   -", f)
        raise SystemExit(1)
    print("ALL PASS")


if __name__ == "__main__":
    main()
