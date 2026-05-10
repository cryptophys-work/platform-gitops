#!/usr/bin/env python3
"""Validate critical Flux dependency chains and optional live smoke gates."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml


ROOT = Path(__file__).resolve().parent.parent
KUSTOMIZATION_ROOT = ROOT / "clusters" / "cryptophys-genesis" / "kustomization"
READY_CONDITION = "Ready"


@dataclass(frozen=True)
class WorkloadCheck:
    namespace: str
    name: str
    kinds: tuple[str, ...]
    min_ready: int = 1
    require_all_ready: bool = False


@dataclass(frozen=True)
class ConditionCheck:
    resource: str
    name: str
    condition: str
    namespace: str | None = None


@dataclass(frozen=True)
class BudgetCheck:
    resource: str
    threshold: int
    completed_states: tuple[str, ...] = ("Completed", "Succeeded")


@dataclass(frozen=True)
class GateSpec:
    name: str
    stages: tuple[str, ...]
    expected_edges: tuple[tuple[str, str], ...] = field(default_factory=tuple)
    workloads: tuple[WorkloadCheck, ...] = field(default_factory=tuple)
    conditions: tuple[ConditionCheck, ...] = field(default_factory=tuple)
    budgets: tuple[BudgetCheck, ...] = field(default_factory=tuple)


GATES: tuple[GateSpec, ...] = (
    GateSpec(
        name="storage-vault-secrets-spire",
        stages=("12-storage", "30-vault", "31-secrets", "35-spire"),
        workloads=(
            WorkloadCheck("vault-system", "vault", ("statefulset",)),
            WorkloadCheck("external-secrets", "external-secrets", ("deployment",)),
            WorkloadCheck("external-secrets", "external-secrets-webhook", ("deployment",)),
            WorkloadCheck("spire-system", "spire-server", ("statefulset",)),
            WorkloadCheck("spire-system", "spire-agent", ("daemonset",), require_all_ready=True),
            WorkloadCheck("spire-system", "spiffe-csi-driver", ("daemonset",), require_all_ready=True),
        ),
        conditions=(
            ConditionCheck("clustersecretstore.external-secrets.io", "vault-backend", READY_CONDITION),
        ),
    ),
    GateSpec(
        name="policy-control-plane",
        stages=("15-policy", "16-policy-ssot", "18-resource-governance"),
        expected_edges=(
            ("15-policy", "16-policy-ssot"),
            ("15-policy", "18-resource-governance"),
        ),
        workloads=(
            WorkloadCheck("kyverno-system", "kyverno-admission-controller", ("deployment",)),
            WorkloadCheck("kyverno-system", "kyverno-background-controller", ("deployment",)),
            WorkloadCheck("kyverno-system", "kyverno-cleanup-controller", ("deployment",)),
        ),
        budgets=(
            BudgetCheck("updaterequests.kyverno.io", threshold=25),
        ),
    ),
    GateSpec(
        name="secrets-argocd",
        stages=("31-secrets", "42-argocd"),
        workloads=(
            WorkloadCheck("apps-system", "argocd-server", ("deployment",)),
            WorkloadCheck("apps-system", "argocd-repo-server", ("deployment",)),
            WorkloadCheck("apps-system", "argocd-application-controller", ("statefulset", "deployment")),
        ),
        conditions=(
            ConditionCheck("externalsecret.external-secrets.io", "argocd-server-secret", READY_CONDITION, "apps-system"),
            ConditionCheck("externalsecret.external-secrets.io", "apps-gitops-repo-internal", READY_CONDITION, "apps-system"),
        ),
    ),
)


class SmokeGateError(RuntimeError):
    """Expected operational validation failure."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate critical Flux dependency chains and optional live smoke gates."
    )
    parser.add_argument(
        "--live",
        action="store_true",
        help="Query the cluster with kubectl in addition to local dependency validation.",
    )
    parser.add_argument(
        "--gate",
        action="append",
        default=[],
        help="Limit checks to one or more gate names.",
    )
    return parser.parse_args()


def load_yaml_docs(path: Path) -> list[dict[str, Any]]:
    docs: list[dict[str, Any]] = []
    for doc in yaml.safe_load_all(path.read_text(encoding="utf-8")):
        if isinstance(doc, dict):
            docs.append(doc)
    return docs


def load_kustomization_specs() -> dict[str, dict[str, Any]]:
    specs: dict[str, dict[str, Any]] = {}
    for file_path in sorted(KUSTOMIZATION_ROOT.glob("*.yaml")):
        for doc in load_yaml_docs(file_path):
            if doc.get("kind") != "Kustomization":
                continue
            metadata = doc.get("metadata", {}) or {}
            name = str(metadata.get("name", "")).strip()
            if not name:
                continue
            specs[name] = doc
    return specs


def get_depends_on(doc: dict[str, Any]) -> set[str]:
    depends = doc.get("spec", {}).get("dependsOn", []) or []
    result: set[str] = set()
    for item in depends:
        if isinstance(item, dict):
            name = str(item.get("name", "")).strip()
            if name:
                result.add(name)
    return result


def validate_local_gate(gate: GateSpec, specs: dict[str, dict[str, Any]]) -> list[str]:
    lines: list[str] = []
    missing = [stage for stage in gate.stages if stage not in specs]
    if missing:
        raise SmokeGateError(f"gate {gate.name}: missing kustomizations: {', '.join(missing)}")

    edges = gate.expected_edges or tuple(zip(gate.stages, gate.stages[1:]))
    for upstream, downstream in edges:
        depends_on = get_depends_on(specs[downstream])
        if upstream not in depends_on:
            raise SmokeGateError(
                f"gate {gate.name}: expected {downstream} to depend on {upstream}, got {sorted(depends_on)}"
            )
        lines.append(f"[pass] {gate.name} chain {upstream} -> {downstream}")
    return lines


def run_kubectl(args: list[str]) -> dict[str, Any]:
    proc = subprocess.run(
        ["kubectl", *args, "-o", "json"],
        check=False,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        stderr = proc.stderr.strip() or proc.stdout.strip()
        raise SmokeGateError(f"kubectl {' '.join(args)} failed: {stderr}")
    return json.loads(proc.stdout)


def condition_status(obj: dict[str, Any], target: str) -> str | None:
    for condition in obj.get("status", {}).get("conditions", []) or []:
        if str(condition.get("type")) == target:
            return str(condition.get("status"))
    return None


def check_flux_stage_ready(stage: str) -> str:
    obj = run_kubectl(["-n", "flux-system", "get", "kustomization", stage])
    status = condition_status(obj, READY_CONDITION)
    if status != "True":
        raise SmokeGateError(f"flux stage {stage} Ready={status or 'missing'}")
    return f"[pass] flux stage {stage} Ready=True"


def read_workload(kind: str, namespace: str, name: str) -> dict[str, Any]:
    return run_kubectl(["-n", namespace, "get", kind, name])


def check_workload(workload: WorkloadCheck) -> str:
    last_error: SmokeGateError | None = None
    for kind in workload.kinds:
        try:
            obj = read_workload(kind, workload.namespace, workload.name)
        except SmokeGateError as err:
            last_error = err
            continue

        status = obj.get("status", {}) or {}
        if kind == "daemonset":
            desired = int(status.get("desiredNumberScheduled") or 0)
            ready = int(status.get("numberReady") or 0)
            if workload.require_all_ready:
                if desired < 1 or ready < desired:
                    raise SmokeGateError(
                        f"{kind}/{workload.name} in {workload.namespace} ready={ready} desired={desired}"
                    )
            elif ready < workload.min_ready:
                raise SmokeGateError(
                    f"{kind}/{workload.name} in {workload.namespace} ready={ready} min={workload.min_ready}"
                )
            return f"[pass] {kind}/{workload.name} ready={ready}/{desired}"

        desired = int(obj.get("spec", {}).get("replicas") or 1)
        ready = int(status.get("readyReplicas") or 0)
        if ready < workload.min_ready:
            raise SmokeGateError(
                f"{kind}/{workload.name} in {workload.namespace} ready={ready} min={workload.min_ready}"
            )
        return f"[pass] {kind}/{workload.name} ready={ready}/{desired}"

    raise last_error or SmokeGateError(
        f"workload {workload.namespace}/{workload.name} not found as {', '.join(workload.kinds)}"
    )


def check_condition(condition: ConditionCheck) -> str:
    args: list[str] = []
    if condition.namespace:
        args.extend(["-n", condition.namespace])
    args.extend(["get", condition.resource, condition.name])
    obj = run_kubectl(args)
    status = condition_status(obj, condition.condition)
    if status != "True":
        ns = f"{condition.namespace}/" if condition.namespace else ""
        raise SmokeGateError(
            f"{condition.resource} {ns}{condition.name} {condition.condition}={status or 'missing'}"
        )
    ns = f"{condition.namespace}/" if condition.namespace else ""
    return f"[pass] {condition.resource} {ns}{condition.name} {condition.condition}=True"


def check_budget(budget: BudgetCheck) -> str:
    obj = run_kubectl(["get", budget.resource, "-A"])
    pending = 0
    for item in obj.get("items", []) or []:
        state = str(item.get("status", {}).get("state", "")).strip()
        if state not in budget.completed_states:
            pending += 1
    if pending > budget.threshold:
        raise SmokeGateError(
            f"{budget.resource} pending={pending} threshold={budget.threshold}"
        )
    return f"[pass] {budget.resource} pending={pending} threshold={budget.threshold}"


def validate_live_gate(gate: GateSpec) -> list[str]:
    lines: list[str] = []
    for stage in gate.stages:
        lines.append(check_flux_stage_ready(stage))
    for workload in gate.workloads:
        lines.append(check_workload(workload))
    for condition in gate.conditions:
        lines.append(check_condition(condition))
    for budget in gate.budgets:
        lines.append(check_budget(budget))
    return lines


def selected_gates(names: list[str]) -> tuple[GateSpec, ...]:
    if not names:
        return GATES
    selected = tuple(gate for gate in GATES if gate.name in set(names))
    missing = sorted(set(names) - {gate.name for gate in selected})
    if missing:
        raise SmokeGateError(f"unknown gate(s): {', '.join(missing)}")
    return selected


def main() -> int:
    args = parse_args()
    gates = selected_gates(args.gate)
    specs = load_kustomization_specs()

    if args.live and shutil.which("kubectl") is None:
        print("error: kubectl is required for --live", file=sys.stderr)
        return 2

    failures = 0
    for gate in gates:
        print(f"[gate] {gate.name}")
        try:
            for line in validate_local_gate(gate, specs):
                print(line)
            if args.live:
                for line in validate_live_gate(gate):
                    print(line)
        except SmokeGateError as err:
            failures += 1
            print(f"[fail] {err}", file=sys.stderr)

    if failures:
        print(f"error: {failures} smoke gate(s) failed", file=sys.stderr)
        return 1

    mode = "local+live" if args.live else "local"
    print(f"success: {len(gates)} platform smoke gate(s) passed in {mode} mode")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
