import pytest
from audit_automation_secrets import Finding, dedupe, summarize

def test_summarize_empty():
    assert summarize([]) == {
        "total_findings": 0,
        "by_category": {},
        "by_severity": {},
    }

def test_summarize_single():
    findings = [
        Finding(
            category="cat1",
            severity="high",
            repo="repo1",
            path="path1",
            line=1,
            message="msg1"
        )
    ]
    expected = {
        "total_findings": 1,
        "by_category": {"cat1": 1},
        "by_severity": {"high": 1},
    }
    assert summarize(findings) == expected

def test_summarize_multiple():
    findings = [
        Finding("cat1", "high", "r1", "p1", 1, "m1"),
        Finding("cat1", "low", "r1", "p2", 2, "m2"),
        Finding("cat2", "high", "r2", "p3", 3, "m3"),
    ]
    expected = {
        "total_findings": 3,
        "by_category": {"cat1": 2, "cat2": 1},
        "by_severity": {"high": 2, "low": 1},
    }
    assert summarize(findings) == expected

def test_dedupe_no_duplicates():
    findings = [
        Finding("cat1", "high", "r1", "p1", 1, "m1"),
        Finding("cat2", "high", "r1", "p1", 1, "m1"), # Different category
    ]
    assert dedupe(findings) == findings

def test_dedupe_with_duplicates():
    f1 = Finding("cat1", "high", "r1", "p1", 1, "m1")
    f2 = Finding("cat1", "high", "r1", "p1", 1, "m1") # Identical
    findings = [f1, f2]
    assert dedupe(findings) == [f1]

def test_dedupe_ignores_severity():
    f1 = Finding("cat1", "high", "r1", "p1", 1, "m1")
    f2 = Finding("cat1", "low", "r1", "p1", 1, "m1") # Only severity differs
    findings = [f1, f2]
    # dedupe uses (category, repo, path, line, message) as key
    # so f2 is considered a duplicate of f1
    assert dedupe(findings) == [f1]
