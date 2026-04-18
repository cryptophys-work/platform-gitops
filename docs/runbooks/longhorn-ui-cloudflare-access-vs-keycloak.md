# Longhorn UI: Cloudflare Access vs Keycloak (Ingress SSO)

## Purpose and scope

Explain why operators sometimes see a **Cloudflare Access / Zero Trust** login instead of **Keycloak** when opening `longhorn.cryptophys.work`, and how to restore the intended **Keycloak-backed** flow enforced by the cluster ingress.

This runbook applies to **Longhorn UI** and any other hostname that uses the same pattern: **nginx `auth_request` → `headlamp-oauth2-proxy` → Keycloak**.

## Severity classification

**Medium** — authentication confusion; operators may be blocked from Longhorn UI until edge policy is corrected. No direct data loss from the symptom alone.

## Preconditions

- Cloudflare account with permission to edit **Zero Trust (Access)** applications and/or zone **WAF / Rules**.
- `kubectl` access to read `Ingress` in `longhorn-system` and `HelmRelease` / pods in `platform-ui` (read-only is enough for validation).
- Awareness that **GitOps** defines ingress auth; **Cloudflare dashboard** defines edge Access.

## Background (why two “logins” exist)

1. **Edge (optional): Cloudflare Zero Trust / Access**  
   If an Access application matches `longhorn.cryptophys.work` (or a wildcard like `*.cryptophys.work`), Cloudflare may intercept the browser **before** traffic reaches the cluster.

2. **Cluster (intended): Keycloak via oauth2-proxy**  
   The Longhorn UI `Ingress` uses nginx external auth against the Headlamp oauth2-proxy service, then Keycloak OIDC:

   - Manifest: `platform/infrastructure/networking/ingress-longhorn-ui.yaml`
   - `auth-url` → `headlamp-oauth2-proxy.platform-ui.svc.cluster.local:4180/oauth2/auth`
   - `auth-signin` → `https://headlamp.cryptophys.work/oauth2/start?rd=...` (return URL is the Longhorn host)

3. **Tunnel**  
   `cloudflared` forwards `*.cryptophys.work` to the in-cluster nginx ingress; it does **not** configure Access. Access is separate dashboard configuration.

**If Access is enabled for the same hostname, users will see Cloudflare first — not a regression in the Longhorn chart.**

## Step-by-step execution (restore Keycloak-first flow)

1. In **Cloudflare Zero Trust**, open **Access → Applications** (or the equivalent path in your tenant UI).
2. Search for policies tied to:
   - `longhorn.cryptophys.work`, or
   - `*.cryptophys.work`, or
   - a catch-all that unintentionally includes Longhorn.
3. For the intended SSO model (Keycloak at ingress), choose **one**:
   - **Remove** the Access application for `longhorn.cryptophys.work`, **or**
   - **Narrow** the hostname list so Longhorn is excluded, **or**
   - Add a **Bypass** rule (e.g. trusted IP list / service token) only if the organization explicitly wants two layers — document who owns each layer.
4. Publish changes and wait for propagation (typically seconds to a few minutes).
5. Clear browser state for the hostname (or use a private window) and retry `https://longhorn.cryptophys.work`.

## Validation checkpoints

- Browser address bar during login shows **Keycloak** (`id.cryptophys.work` realm) after redirect from `headlamp.cryptophys.work/oauth2/start`, not `cloudflareaccess.com` (or similar Access host).
- `kubectl -n longhorn-system get ingress longhorn-ui -o yaml` still shows `auth-url` / `auth-signin` annotations pointing at Headlamp oauth2-proxy (GitOps unchanged).
- After successful login, the UI loads **Longhorn** (not stuck on Headlamp); if stuck on Headlamp, see `apps-gitops` `headlamp-oauth2-proxy` cookie domain / `whitelist-domain` for `.cryptophys.work` (subdomain SSO).

## Rollback criteria

Rollback **Cloudflare** changes only if a deliberate Access policy must remain; in that case, document **dual authentication** (Access + Keycloak) and expected UX. Do not remove cluster ingress auth without security sign-off.

## Incident logging requirements

- Record: previous Access policy name, hostname scope, who changed it, time (UTC), and confirmation after validation.
- If Keycloak was unreachable during the incident, capture `identity-core` / IdP status separately (not covered here).

## Owner and last review date

- **Owner:** Platform / GitOps + whoever owns Cloudflare Zero Trust for `cryptophys.work`.
- **Last review:** 2026-04-18
