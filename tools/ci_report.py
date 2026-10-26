#!/usr/bin/env python3
"""The CI run's test report, in Markdown for a job summary, from the reports tools/check.sh writes (CHECK_REPORT).

  ci_report.py <name>.tsv                       one job: its failed and flaky tests, then its steps with their results
                                                and times
  ci_report.py --jobs jobs.json <name>.tsv...   the run: every job (jobs.json, the API's list of the run's jobs)
                                                with its result and time, the failed and flaky tests, the failed,
                                                flaky and advisory steps, then the slowest steps

A report's lines are "<result>\\t<seconds>\\t<step>", result one of pass, fail, flaky, advisory or problem. The job's
output beside it (<name>.log) names the tests inside the steps: Dart's failed tests and its retries (retry: 3 in
dart_test.yaml), nextest's FAIL and FLAKY and the shell tests' FAIL: lines; a shell test that passed on a retry
(CHECK_RETRIES) is a flaky step.
"""
import json
import os
import re
import sys
from datetime import datetime

MARK = {"pass": "✅", "fail": "❌", "flaky": "⚠️ flaky", "advisory": "ℹ️ advisory", "problem": "❌ problem"}
CONCLUSION = {"success": "✅", "failure": "❌", "cancelled": "🚫 cancelled", "skipped": "⏭️ skipped",
              "timed_out": "⏱️ timed out"}
# Up to this many tests of one kind per job: a step that fails everything says so in its log
MOST = 30

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
STEP = re.compile(r"^==> (\[.*)$")
# flutter test's GitHub reporter, and the expanded reporter dart test uses elsewhere
DART_FAILED = (re.compile(r"❌ (?:\S+: )?(.+?) \(failed\)$"), re.compile(r"^\d+:\d+ [+~\-\d ]*: (.+?) \[E\]$"))
DART_RETRY = re.compile(r"^\s*Retry: (.+)$")
NEXTEST_FAIL = re.compile(r"^\s*(?:TRY \d+ )?(?:FAIL|SIGSEGV|SIGABRT|TIMEOUT) \[[^\]]*\] (?:\([^)]*\) )?(.+)$")
NEXTEST_FLAKY = re.compile(r"^\s*FLAKY \d+/\d+ \[[^\]]*\] (?:\([^)]*\) )?(.+)$")
SHELL_FAIL = re.compile(r"^FAIL: (.+)$")


def duration(seconds):
    seconds = int(seconds)
    return f"{seconds}s" if seconds < 60 else f"{seconds // 60}m{seconds % 60:02d}s"


def cell(text, most=200):
    text = text.replace("|", "\\|").replace("\n", " ").replace("`", "'")
    return text if len(text) <= most else text[:most - 1] + "…"


def read_report(path):
    rows = []
    with open(path, encoding="utf-8") as report:
        for line in report:
            result, seconds, step = line.rstrip("\n").split("\t", 2)
            rows.append((result, int(seconds), step))
    return rows


def short(text):
    """Without the checkout's path, which every step's command repeats."""
    root = os.environ.get("GITHUB_WORKSPACE")
    text = text.replace(root.rstrip("/") + "/", "") if root else text
    return re.sub(r"/home/runner/work/[^/\s]+/[^/\s]+/", "", text)


def read_tests(path, rows):
    """The tests the job's log names, each as (step, test, how): those that failed, those that failed and then passed
    on a retry (flaky), and those that failed in an advisory step (not counted)."""
    if not os.path.exists(path):
        return [], [], []
    results = {step: result for result, _, step in rows}
    step = ""
    events = {}  # (step, test) -> {kind: how}
    note = lambda key, kind, how: events.setdefault(key, {}).setdefault(kind, how)
    with open(path, encoding="utf-8", errors="replace") as log:
        for line in log:
            line = ANSI.sub("", line.rstrip("\n"))
            if match := STEP.match(line):
                step = match.group(1)
                continue
            for pattern in DART_FAILED:
                if match := pattern.search(line):
                    note((step, match.group(1)), "failed", "dart")
            if match := DART_RETRY.match(line):
                note((step, match.group(1)), "retried", "dart")
            if match := NEXTEST_FLAKY.match(line):
                note((step, match.group(1).strip()), "flaky", "nextest")
            elif match := NEXTEST_FAIL.match(line):
                # With --retries every attempt is a TRY: a test that failed its tries and was not FLAKY failed
                note((step, match.group(1).strip()), "failed", "nextest")
            if match := SHELL_FAIL.match(line):
                note((step, match.group(1)), "failed", "shell")
    failed, flaky, advisory = [], [], []
    for key, kinds in events.items():
        result = results.get(key[0], "fail")
        how = kinds.get("failed") or kinds.get("flaky") or kinds.get("retried")
        if "failed" not in kinds:
            flaky.append((*key, f"{how}, passed on a retry"))
        elif result == "advisory":
            advisory.append((*key, f"{how}, advisory step"))
        elif result == "fail" and "flaky" not in kinds:
            failed.append((*key, how))
        else:
            flaky.append((*key, f"{how}, passed on a retry"))
    return failed, flaky, advisory


def tests_section(title, tests, job=None):
    if not tests:
        return []
    out = ["", f"### {title} ({len(tests)})", "", "| Job | Test | Kind | In step |" if job is None else
           "| Test | Kind | In step |", "|---|---|---|---|" if job is None else "|---|---|---|"]
    shown = {}
    for name, step, test, how in tests:
        shown[name] = shown.get(name, 0) + 1
        if shown[name] > MOST:
            continue
        row = f"| {cell(test)} | {how} | `{cell(short(step), 120)}` |"
        out.append(row if job is not None else f"| {name} {row}")
    hidden = sum(max(0, count - MOST) for count in shown.values())
    if hidden:
        out += ["", f"…and {hidden} more: the job's log (its report-<job> artifact) has them all."]
    return out


def job_seconds(job):
    if not job.get("started_at") or not job.get("completed_at"):
        return 0
    return (datetime.fromisoformat(job["completed_at"]) - datetime.fromisoformat(job["started_at"])).total_seconds()


def one_job(name, rows, failed, flaky, advisory):
    if not rows:
        return ["No step ran: the job's source is not in the repository yet, or the gate stopped first."]
    out = [f"## {name}: {sum(r == 'pass' for r, _, _ in rows)} of {len(rows)} steps passed"]
    out += tests_section("Failed tests", [(name, *test) for test in failed], job=name)
    out += tests_section("Flaky tests (failed, then passed on a retry)", [(name, *test) for test in flaky], job=name)
    out += tests_section("Advisory tests (failed, not counted)", [(name, *test) for test in advisory], job=name)
    out += ["", "### Steps", "", "| Result | Time | Step |", "|---|---:|---|"]
    out += [f"| {MARK.get(result, result)} | {duration(seconds)} | `{cell(short(step))}` |"
            for result, seconds, step in rows]
    return out


def whole_run(jobs, reports, tests):
    out = ["## Gate report", "", "| Job | Result | Time | Steps | Failed steps | Failed tests | Flaky tests |",
           "|---|---|---:|---:|---:|---:|---:|"]
    # The API names a block's job "<block> / <job>"; its report is named after the job alone
    for job in sorted(jobs, key=lambda job: job["name"]):
        if job["name"] == "gate":
            continue
        short_name = job["name"].split(" / ")[-1]
        rows = reports.get(short_name)
        failed, flaky, _ = tests.get(short_name, ([], [], []))
        # A job without a report ran no step: its counts are a dash, not a zero
        counts = ["–"] * 4 if rows is None else [
            len(rows), sum(r in ("fail", "problem") for r, _, _ in rows), len(failed), len(flaky)]
        result = CONCLUSION.get(job.get("conclusion") or "", job.get("conclusion") or job.get("status", ""))
        out.append(f"| {cell(job['name'])} | {result} | {duration(job_seconds(job))} | "
                   + " | ".join(str(count) for count in counts) + " |")
    out += tests_section("Failed tests",
                         [(name, *test) for name, (failed, _, _) in sorted(tests.items()) for test in failed])
    out += tests_section("Flaky tests (failed, then passed on a retry)",
                         [(name, *test) for name, (_, flaky, _) in sorted(tests.items()) for test in flaky])
    out += tests_section("Advisory tests (failed in an advisory step, not counted)",
                         [(name, *test) for name, (_, _, advisory) in sorted(tests.items()) for test in advisory])
    every = [(name, *row) for name, rows in sorted(reports.items()) for row in rows]
    for title, kinds in (("Failed steps", ("fail", "problem")), ("Flaky steps (failed, then passed)", ("flaky",)),
                         ("Advisory steps (failed, not counted)", ("advisory",))):
        picked = [row for row in every if row[1] in kinds]
        if picked:
            out += ["", f"### {title}", ""]
            out += [f"- **{name}** ({duration(seconds)}): `{cell(short(step))}`" for name, _, seconds, step in picked]
    slowest = sorted((row for row in every if row[1] != "problem"), key=lambda row: -row[2])[:10]
    if slowest:
        out += ["", "### Slowest steps", "", "| Time | Job | Step |", "|---:|---|---|"]
        out += [f"| {duration(seconds)} | {name} | `{cell(short(step))}` |" for name, _, seconds, step in slowest]
    return out


def main(argv):
    jobs = None
    if argv[:1] == ["--jobs"]:
        with open(argv[1], encoding="utf-8") as listing:
            jobs = json.load(listing)
        jobs = jobs.get("jobs", jobs) if isinstance(jobs, dict) else jobs
        argv = argv[2:]
    reports, tests = {}, {}
    for path in argv:
        name = os.path.basename(path).removesuffix(".tsv")
        reports[name] = read_report(path)
        tests[name] = read_tests(path.removesuffix(".tsv") + ".log", reports[name])
    if jobs is None:
        if len(reports) != 1:
            sys.exit("usage: ci_report.py <name>.tsv | ci_report.py --jobs jobs.json <name>.tsv...")
        name = next(iter(reports))
        lines = one_job(name, reports[name], *tests[name])
    else:
        lines = whole_run(jobs, reports, tests)
    print("\n".join(lines))


if __name__ == "__main__":
    main(sys.argv[1:])
