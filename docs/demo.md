# Demo

A runbook for showing the supply chain end to end: verify an artifact came from
this pipeline, then watch the cluster admit the verified image and refuse an
untrusted one. The commands are the same whether you're following along or
recording.

## Prerequisites

- `cosign`, `kubectl`, `kind`, Docker running
- A signed image already published by CI (any push to `main` produces one)

Set the identity once (used by every verify command):

```bash
IMG=ghcr.io/brawndon-manu/nahui-app:latest
ISSUER=https://token.actions.githubusercontent.com
IDENTITY='^https://github.com/brawndon-manu/nahui/.+'
```

## Part 1 — verify the artifact (no cluster needed)

**The image is signed by this pipeline.** Verify against the CI identity:

```bash
cosign verify "$IMG" \
  --certificate-oidc-issuer "$ISSUER" \
  --certificate-identity-regexp "$IDENTITY"
```
The certificate subject is the workflow that built it, and the entry is in the
Rekor transparency log — so this proves origin, not just "signed by someone."

**It carries a SLSA provenance attestation** (how/where it was built):

```bash
cosign verify-attestation --type https://slsa.dev/provenance/v1 \
  --certificate-oidc-issuer "$ISSUER" \
  --certificate-identity-regexp "$IDENTITY" "$IMG"
```

**And an SBOM attestation** (what's inside it):

```bash
cosign verify-attestation --type https://spdx.dev/Document/v2.3 \
  --certificate-oidc-issuer "$ISSUER" \
  --certificate-identity-regexp "$IDENTITY" "$IMG"
```

## Part 2 — enforce it at the cluster

Stand up the demo environment (kind + Kyverno + namespace + policy):

```powershell
.\scripts\cluster-up.ps1
```
(Linux/macOS: `make cluster-up`.)

**Deploy the verified image — it runs:**

```bash
kubectl apply -f deploy/verified.yaml
kubectl get pods -n nahui -l app=nahui-app
# -> nahui-app-... 1/1 Running
```
Kyverno checked the signature and SBOM attestation against our identity and
annotated the pod `kyverno.io/verify-images: {"...":"pass"}`.

**Deploy an untrusted image — it's denied before it can schedule:**

```bash
kubectl apply -f deploy/unsigned.yaml
# -> admission webhook denied the request:
#    verify-image-signature: ... no signatures found
```
`deploy/unsigned.yaml` is a normal public `nginx`, digest-pinned. Nothing wrong
with it — it just never went through this pipeline, so it has no signature from
our identity. The cluster refuses it.

## Cleanup

```powershell
.\scripts\cluster-down.ps1
```
(Linux/macOS: `make cluster-down`.)

## What the demo shows

The same image content is signed, attested, and then checked again at the last
possible moment before it runs. An artifact that can't present a valid signature
and SBOM attestation from this pipeline doesn't get scheduled — which is the
whole point of the four pillars working together.
