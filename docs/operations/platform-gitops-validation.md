# Platform GitOps — Local Validation Runbook

## Purpose and scope

This runbook describes how to validate changes in the `platform-gitops` repository **locally** before opening a merge request or relying on Flux to reconcile. It covers:

- Rendering Kubernetes and Flux objects with **Kustomize**
- Optional **API server validation** with `kubectl` dry-run (read-only; does not mutate the cluster)
- Troubleshooting common failures (YAML, Kustomize accumulation, connectivity, policy admission)

It applies to cluster entrypoints under `clusters/` (for example `clusters/talos-prod` and `clusters/cryptophys-genesis`) and to the `platform/` tree those entrypoints reference.

Out of scope: applying manifests with `kubectl apply` without GitOps approval, changing live Talos nodes, and editing `ssot-core` policy content (read-only per platform law).

## Severity classification

| Class | When this runbook applies | Response time |
|-------|---------------------------|---------------|
| P4 — hygiene | Routine PR checks, refactors, documentation-only branches | Best effort before merge |
| P3 — defect suspected | CI or Flux reports reconcile errors after a merge | Same business day |
| P2 — blocked promotion | Main cannot be validated; release train stopped | Immediate during working session |

Local validation itself does not constitute a production incident. Escalate to P2 when validation failures block an approved change set from merging or deploying.

## Preconditions

- **Repository clone:** You are at the root of `platform-gitops` (the directory that contains `clusters/` and `platform/`).
- **Tools:**
  - `kustomize` v5.x on `PATH` (standalone binary; matches CI expectations better than the embedded `kubectl kustomize` version in some distributions).
  - `kubectl` compatible with the target API server (only if you run server dry-run steps).
  - `rg` (ripgrep) for searching manifests (`rg --glob='*.yaml' <pattern>`).
- **Kubeconfig (optional):** Valid context for the cluster you intend to validate against, with read-only use of `kubectl apply --dry-run=server` only. Do not use this runbook to justify live `apply`, `delete`, or `talosctl` mutations.
- **Anti-manual mandate:** Production changes flow through Git commits and Flux. Dry-run is validation, not deployment.

## Security requirements

- Do not paste kubeconfig, tokens, or certificate private keys into tickets or chat.
- If validation output might include Secret data, redact before sharing. Prefer validating overlays that reference `ExternalSecret` and similar non-sensitive scaffolding.

## Step-by-step execution

### 1. Select the cluster entrypoint

Primary production-style entrypoint used in workspace documentation:

```bash
export CLUSTER_ROOT=clusters/talos-prod
```

For the alternate bundled layout:

```bash
export CLUSTER_ROOT=clusters/cryptophys-genesis
```

### 2. Render the Flux cluster bundle (Kustomize)

This produces all `GitRepository`, `Kustomization` (Flux), and other resources defined at the cluster root.

```bash
kustomize build "${CLUSTER_ROOT}" > /tmp/platform-flux-bundle.yaml
```

**Checkpoint:** The command exits `0` and the output file is non-empty.

Inspect a single Flux `Kustomization` name if needed:

```bash
kustomize build "${CLUSTER_ROOT}" | rg -n "name: 00-crds" -n
```

### 3. Render every `spec.path` referenced by Flux `Kustomization` objects

Flux `Kustomization` resources under `${CLUSTER_ROOT}/kustomization/` declare `spec.path` relative to the repository root (as seen by the Flux `GitRepository` checkout). Build each distinct path.

**Talos production (`clusters/talos-prod`):** paths stay under `platform/` and a single pass with the default load restrictor is sufficient:

```bash
while IFS= read -r relpath; do
  echo "Building ${relpath}"
  kustomize build "${relpath}" > "/tmp/render-${relpath//\//_}.yaml"
done < <(rg '^\s+path: \./' "${CLUSTER_ROOT}/kustomization" --glob '*.yaml' \
  | sed 's/.*path: //' | sed 's#^\./##' | sort -u)
```

**Genesis / overlays that reference parent directories:** Some bases include files from a parent directory (for example `platform/infrastructure/backup-crs` including `../backup/velero-schedules.yaml`). The default Kustomize loader rejects those paths. Re-run failed paths with an explicit load restrictor:

```bash
kustomize build --load-restrictor LoadRestrictionsNone platform/infrastructure/backup-crs
kustomize build --load-restrictor LoadRestrictionsNone platform/infrastructure/database-crs
```

**Checkpoint:** Every path used by the selected cluster’s Flux `Kustomization` files renders with exit code `0`.

### 4. Paths backed by a different Git repository

Some Flux `Kustomization` objects use `sourceRef` pointing at **`ssot-core-repo`** (for example `path: ./policies/kyverno/full`). That content is **not** in `platform-gitops` alone. Options:

- Validate in the environment that clones both repositories to the layout Flux uses, or
- Rely on the pipeline that already checks out SSOT alongside platform manifests.

Do not assume `kustomize build policies/kyverno/full` succeeds from a `platform-gitops`-only clone.

### 5. Optional — API server validation (read-only)

**Client dry-run** (schema validation without the API server; weaker than server):

```bash
kustomize build "${CLUSTER_ROOT}" | kubectl apply --dry-run=client -f -
```

**Server dry-run** (sends objects to the API server; still **no** persisted change when successful):

```bash
kustomize build "${CLUSTER_ROOT}" | kubectl apply --dry-run=server -f -
```

**Checkpoint:** `kubectl` completes with `created (dry run)` / `configured (dry run)` or reports validation errors you must fix in Git.

Server dry-run can fail for **expected** reasons when objects depend on CRDs or webhooks not present in the target cluster context. Treat those failures as signal: either switch to a context that matches production CRDs, or scope dry-run to a single rendered file after CRDs are installed.

## Validation checkpoints

Record in the PR or change record:

| Checkpoint | Command / action | Pass criteria |
|------------|------------------|---------------|
| C1 | `kustomize build "${CLUSTER_ROOT}"` | Exit `0`, YAML renders |
| C2 | Loop over `spec.path` builds (section 3) | All paths exit `0` |
| C3 | Optional `kubectl apply --dry-run=server -f -` | No unexpected validation errors for the chosen context |
| C4 | `rg --glob='*.yaml' '<pattern>'` for the area you changed | Matches reviewed intent, no stray references |

## Rollback criteria

Local validation has no cluster state to roll back.

- If you already merged a broken change, **rollback in Git** (revert commit) and let Flux reconcile the previous revision.
- If you only ran local renders, discard local `/tmp` outputs and fix the branch; no rollback beyond Git branch hygiene.

## Incident logging requirements

When validation failures block a merge or deployment:

1. Log the **exact commands**, **cluster context name** (if used), and **first failing file or resource**.
2. Attach the **minimal** redacted snippet showing the error (avoid dumping full Secret manifests).
3. Link the Git branch or commit SHA under test.

## Troubleshooting

### Kustomize: "security; file '...' is not in or below '<dir>'"

**Cause:** A `Kustomization` lists resources outside its directory; Kustomize’s default loader blocks that.

**Fix:** Rebuild with `--load-restrictor LoadRestrictionsNone` for that path only, after confirming the referenced files are intentional (not path traversal). Align with how your CI invokes Kustomize.

### Kustomize: "accumulating resources" / "no matches for Id"

**Cause:** Broken `resources:` entry, renamed file, or wrong `bases` / `components` reference.

**Fix:**

```bash
rg --glob='*.yaml' 'kind: Kustomization' platform/infrastructure -l
rg --glob='*.yaml' 'missing-resource-name' .
```

Open the listed `kustomization.yaml` and fix the `resources` list.

### Kustomize: duplicate `metadata.name` or `namespace`

**Cause:** Two manifests define the same object ID.

**Fix:** Render and search:

```bash
kustomize build "<path>" | rg '^  name:' | sort | uniq -d
```

Resolve duplicates in patches or remove overlapping bases.

### `kubectl apply --dry-run=server`: unknown kind / no matches for kind

**Cause:** CRD not installed in the target cluster, or wrong API version.

**Fix:** Confirm `kubectl config current-context`, compare `apiVersion` with `kubectl api-resources`, validate CRD stages first (for example `platform/infrastructure/crds`).

### `kubectl apply --dry-run=server`: webhook denied request

**Cause:** Admission controller (for example Kyverno, OPA) rejected the object shape.

**Fix:** This is valuable signal. Capture the policy name from the error, locate the policy in-repo (or in SSOT if applicable), and adjust manifests **via GitOps** after policy owners approve.

### Flux `Kustomization` path does not exist locally

**Cause:** Path points to another repository (SSOT) or an optional submodule not checked out.

**Fix:** Use the combined checkout layout or validate that stage in CI only.

### Version skew between local `kustomize` and CI

**Cause:** Different Kustomize versions treat `patchesStrategicMerge` / `components` differently.

**Fix:** Pin the same `kustomize` minor release CI uses; print `kustomize version` in the PR evidence.

## Owner and last review

| Field | Value |
|-------|-------|
| Owner | Platform GitOps maintainers (see repository `CODEOWNERS` or team roster) |
| Last reviewed | 2026-04-14 |

## Related documentation

- Runbook structure and mandatory sections: [runbook-standard.md](./runbook-standard.md)
- Active operational runbooks index: [../runbooks/README.md](../runbooks/README.md)
