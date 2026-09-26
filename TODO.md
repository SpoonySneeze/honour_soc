# TODO — Honour SoC Agent Work Plan

_Last updated: 2026-09-26 17:04_

---

## STATUS LEGEND
- ✅ DONE
- 🔄 IN PROGRESS
- ❌ NOT STARTED
- ⚠️ DONE WITH ISSUE

---

## PHASE 1 — Firmware Per-IP Test Execution

Run each per-IP firmware test, observe terminal output, and confirm all subtests
pass. If any subtest fails, debug and fix before moving to the next.

| # | Command | Status | Notes |
|---|---------|--------|-------|
| 1 | `make test_timer` | ✅ DONE | 4/4 PASS |
| 2 | `make test_gpio` | ✅ DONE | 4/4 PASS |
| 3 | `make test_heartbeat` | ✅ DONE | 5/5 PASS (fixed SUBTEST 3 assertion) |
| 4 | `make test_uart` | ❌ NOT RUN | — |
| 5 | `make test_reset_sequencer` | ❌ NOT RUN | — |
| 6 | `make test_recovery_policy` | ❌ NOT RUN | — |
| 7 | `make test_vga` | ❌ NOT RUN | — |
| 8 | `make test_all_ips` | ❌ NOT RUN | Run this LAST — unified all-IP suite |

### What to do if a test fails:
1. Read the `[FAIL]` subtest name in terminal output carefully.
2. Check `firmware/test/test_<ip>.c` — look at what register is being tested.
3. Check the corresponding RTL file in `rtl/custom_ips/` for the register's
   actual offset and behaviour.
4. Fix either the test assertion OR the RTL if there is a real hardware bug.
5. Re-run `make test_<ip>` to confirm fix.
6. If RTL was changed, re-run `make sim_all` to verify no regressions.

---

## PHASE 2 — Full Regression After All Firmware Tests Pass

Once all 8 firmware tests pass, run the complete simulation suite to confirm
no RTL changes broke anything:

```bash
make sim_all
```

Expected output:
```
sim_hbm:  9 passed, 0 failed
sim_rst: 12 passed, 0 failed
sim_pol: 16 passed, 0 failed
sim_axi: 18 passed, 0 failed
sim_soc: 17 passed, 0 failed
sim_core: 17 passed, 0 failed
ALL SIMULATION TEST SUITES COMPLETED SUCCESSFULLY!
```

Status: ❌ NOT RUN (pending firmware tests above)

---

## PHASE 3 — Git Commit & Push Results

After all tests pass and regression is clean:

```bash
git add -A
git commit -m "test: verify all per-IP firmware tests pass — all 7 IPs validated on VeeR EL2 core"
git push
```

Status: ❌ NOT STARTED

---

## PHASE 4 — Optional Improvements (Nice to Have)

These are improvements that are not strictly required but would make the
project more complete and robust:

| # | Task | Priority |
|---|------|----------|
| 1 | Add VCS waveform dumps (`$dumpvars`) to each test firmware so Verdi can show signal traces during per-IP tests | Medium |
| 2 | Add timeout watchdog to each test — if a test hangs (e.g. waiting on a register), simulation should auto-exit after N cycles | Medium |
| 3 | Add a `make test_all_ips_verbose` target that shows full register hex dumps for every subtest | Low |
| 4 | Write `test_interconnect.c` — firmware test that accesses all 7 slaves back-to-back to verify AXI arbitration | Low |
| 5 | Set global git user name/email so commits show proper author identity | Low |

---

## CURRENT IMMEDIATE NEXT STEP

> **Run `make test_uart` and observe terminal output. Fix any failures.**
> Then proceed through the table in PHASE 1 in order, finishing with `make test_all_ips`.
> After all pass, run `make sim_all` for full regression, then commit and push.
