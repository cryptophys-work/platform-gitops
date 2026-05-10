import importlib.util
import sys
import json
from pathlib import Path
import pytest
from unittest.mock import MagicMock, patch

# Import the script using importlib because of the hyphen in the filename
script_path = Path(__file__).parent / "check-platform-smoke-gates.py"
module_name = "check_platform_smoke_gates"
spec = importlib.util.spec_from_file_location(module_name, script_path)
gates_script = importlib.util.module_from_spec(spec)
sys.modules[module_name] = gates_script
spec.loader.exec_module(gates_script)

def test_get_depends_on():
    # Valid dependsOn
    doc = {
        "spec": {
            "dependsOn": [
                {"name": "stage1"},
                {"name": "stage2 "}
            ]
        }
    }
    assert gates_script.get_depends_on(doc) == {"stage1", "stage2"}

    # Empty dependsOn
    doc = {"spec": {"dependsOn": []}}
    assert gates_script.get_depends_on(doc) == set()

    # Missing spec
    assert gates_script.get_depends_on({}) == set()

    # Missing dependsOn
    assert gates_script.get_depends_on({"spec": {}}) == set()

    # Malformed dependsOn items
    doc = {"spec": {"dependsOn": [{"no-name": "foo"}, "not-a-dict"]}}
    assert gates_script.get_depends_on(doc) == set()

def test_condition_status():
    # Condition present and True
    obj = {
        "status": {
            "conditions": [
                {"type": "Ready", "status": "True"},
                {"type": "Other", "status": "False"}
            ]
        }
    }
    assert gates_script.condition_status(obj, "Ready") == "True"

    # Condition present and False
    assert gates_script.condition_status(obj, "Other") == "False"

    # Condition absent
    assert gates_script.condition_status(obj, "Missing") is None

    # No status or conditions
    assert gates_script.condition_status({}, "Ready") is None
    assert gates_script.condition_status({"status": {}}, "Ready") is None

def test_selected_gates():
    # Empty names returns all gates
    assert gates_script.selected_gates([]) == gates_script.GATES

    # Valid gate name
    gate_name = gates_script.GATES[0].name
    selected = gates_script.selected_gates([gate_name])
    assert len(selected) == 1
    assert selected[0].name == gate_name

    # Unknown gate name
    with pytest.raises(gates_script.SmokeGateError, match="unknown gate"):
        gates_script.selected_gates(["non-existent-gate"])

def test_validate_local_gate_success():
    gate = gates_script.GateSpec(
        name="test-gate",
        stages=("stage1", "stage2"),
    )
    specs = {
        "stage1": {"metadata": {"name": "stage1"}},
        "stage2": {
            "metadata": {"name": "stage2"},
            "spec": {"dependsOn": [{"name": "stage1"}]}
        }
    }
    lines = gates_script.validate_local_gate(gate, specs)
    assert len(lines) == 1
    assert "[pass]" in lines[0]
    assert "stage1 -> stage2" in lines[0]

def test_validate_local_gate_missing_kustomization():
    gate = gates_script.GateSpec(name="test-gate", stages=("stage1",))
    specs = {}
    with pytest.raises(gates_script.SmokeGateError, match="missing kustomizations: stage1"):
        gates_script.validate_local_gate(gate, specs)

def test_validate_local_gate_broken_chain():
    gate = gates_script.GateSpec(name="test-gate", stages=("stage1", "stage2"))
    specs = {
        "stage1": {"metadata": {"name": "stage1"}},
        "stage2": {"metadata": {"name": "stage2"}} # Missing dependsOn
    }
    with pytest.raises(gates_script.SmokeGateError, match="expected stage2 to depend on stage1"):
        gates_script.validate_local_gate(gate, specs)

@patch("check_platform_smoke_gates.run_kubectl")
def test_check_flux_stage_ready(mock_run):
    # Success
    mock_run.return_value = {
        "status": {"conditions": [{"type": "Ready", "status": "True"}]}
    }
    assert "[pass]" in gates_script.check_flux_stage_ready("stage1")

    # Failure
    mock_run.return_value = {
        "status": {"conditions": [{"type": "Ready", "status": "False"}]}
    }
    with pytest.raises(gates_script.SmokeGateError, match="Ready=False"):
        gates_script.check_flux_stage_ready("stage1")

@patch("check_platform_smoke_gates.run_kubectl")
def test_check_workload_deployment(mock_run):
    workload = gates_script.WorkloadCheck(
        namespace="ns", name="deploy", kinds=("deployment",), min_ready=2
    )

    # Success
    mock_run.return_value = {
        "spec": {"replicas": 3},
        "status": {"readyReplicas": 2}
    }
    assert "[pass]" in gates_script.check_workload(workload)
    assert "ready=2/3" in gates_script.check_workload(workload)

    # Failure
    mock_run.return_value = {
        "spec": {"replicas": 3},
        "status": {"readyReplicas": 1}
    }
    with pytest.raises(gates_script.SmokeGateError, match="ready=1 min=2"):
        gates_script.check_workload(workload)

@patch("check_platform_smoke_gates.run_kubectl")
def test_check_workload_daemonset(mock_run):
    # require_all_ready = True
    workload = gates_script.WorkloadCheck(
        namespace="ns", name="ds", kinds=("daemonset",), require_all_ready=True
    )

    # Success
    mock_run.return_value = {
        "status": {"desiredNumberScheduled": 3, "numberReady": 3}
    }
    assert "[pass]" in gates_script.check_workload(workload)

    # Failure
    mock_run.return_value = {
        "status": {"desiredNumberScheduled": 3, "numberReady": 2}
    }
    with pytest.raises(gates_script.SmokeGateError, match="ready=2 desired=3"):
        gates_script.check_workload(workload)

    # min_ready check
    workload_min = gates_script.WorkloadCheck(
        namespace="ns", name="ds", kinds=("daemonset",), min_ready=2
    )
    mock_run.return_value = {
        "status": {"desiredNumberScheduled": 3, "numberReady": 2}
    }
    assert "[pass]" in gates_script.check_workload(workload_min)

@patch("check_platform_smoke_gates.run_kubectl")
def test_check_condition(mock_run):
    condition = gates_script.ConditionCheck(
        resource="cr", name="my-cr", condition="Ready", namespace="ns"
    )

    # Success
    mock_run.return_value = {
        "status": {"conditions": [{"type": "Ready", "status": "True"}]}
    }
    assert "[pass]" in gates_script.check_condition(condition)

    # Failure
    mock_run.return_value = {
        "status": {"conditions": [{"type": "Ready", "status": "False"}]}
    }
    with pytest.raises(gates_script.SmokeGateError, match="Ready=False"):
        gates_script.check_condition(condition)

@patch("check_platform_smoke_gates.run_kubectl")
def test_check_budget(mock_run):
    budget = gates_script.BudgetCheck(resource="ur", threshold=1)

    # Success (1 pending <= 1 threshold)
    mock_run.return_value = {
        "items": [
            {"status": {"state": "Completed"}},
            {"status": {"state": "Pending"}}
        ]
    }
    assert "[pass]" in gates_script.check_budget(budget)

    # Failure (2 pending > 1 threshold)
    mock_run.return_value = {
        "items": [
            {"status": {"state": "Pending"}},
            {"status": {"state": "Running"}}
        ]
    }
    with pytest.raises(gates_script.SmokeGateError, match="pending=2 threshold=1"):
        gates_script.check_budget(budget)
