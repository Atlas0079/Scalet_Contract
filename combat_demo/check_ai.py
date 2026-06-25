from __future__ import annotations

from simulation.scenarios import run_ai_scenarios


def main() -> int:
    results = run_ai_scenarios()
    failed = [result for result in results if not result.passed]
    for result in results:
        status = "PASS" if result.passed else "FAIL"
        print(f"{status} {result.name}: {result.detail}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
