# EKS Internal DNS — Production-Standard Layout

This supersedes the flat `route53-phase1/` folder. Same underlying Route 53
resources — private hosted zone, ALIAS records — restructured the way a
real team would maintain it, plus the two foundations every production
Terraform codebase needs: a backend that can't corrupt itself, and a
module instead of hardcoded, copy-pasted resources.

```
bootstrap/            # run once — creates the S3 state bucket
modules/
  internal-dns/       # reusable: zone + N records, driven by a map
environments/
  dev/                # calls the module with dev's real values
  (prod/ — copy dev/ when you're ready for a second environment)
```

---

## Why this structure (the industry-standard reasoning)

**Locking.** Two `terraform apply` runs at once — you on your laptop and
a Jenkins job, say — can corrupt shared state if nothing's coordinating
them. `use_lockfile = true` gives you that coordination via the S3 backend
itself (Terraform 1.10+), no separate DynamoDB table required. If you're
on an older Terraform version, a DynamoDB table with a `LockID` string
key is the classic equivalent — one extra resource in `bootstrap/`.

**Versioned, encrypted state.** A bad apply that mangles your state file
is recoverable if the bucket is versioned. Encryption at rest is the
default now, not an opt-in.

**Modules over copy-paste.** `modules/internal-dns` takes a map —
`{ jenkins = "k8s-default-jenkins" }` — and loops over it. Adding a new
internal DNS name for any service on your cluster is a one-line change
to `terraform.tfvars`, not new HCL.

**Environments as folders, not workspaces.** Terraform workspaces share
one backend config, which makes it easy to accidentally apply dev
variables against prod state. Separate folders with separate backend
`key` values make that mistake structurally harder to make.

**Tags by default.** `default_tags` on the provider block means every
resource in a given environment is automatically tagged — nothing slips
through because someone forgot a `tags = {}` block.

---

## Running it

### 1. Bootstrap (once, ever)

```
cd bootstrap
terraform init
terraform apply
```

This has no remote backend on purpose — it creates the bucket everything
else stores state in. Keep the resulting `terraform.tfstate` file safe;
it only describes 3 resources, so it's low-risk to keep around locally.

### 2. Fill in dev's real values

Copy `environments/dev/terraform.tfvars.example` to
`environments/dev/terraform.tfvars` and fill in your actual region, VPC
ID, and load balancer names (see `route53-phase1/README.md` for the exact
lookup commands if you still have that folder — same process applies
here).

Then edit `environments/dev/main.tf` and replace the two
`REPLACE-ME-...` backend values with your bootstrap bucket name and
region.

### 3. Apply

```
cd environments/dev
terraform init
terraform apply
```

### 4. Verify

Same as Phase 1 — private zones only resolve inside the VPC:
```
kubectl run dns-test --rm -it --image=busybox --restart=Never -- nslookup jenkins.eks.internal
```

---

## What's deliberately not in this folder yet

- **CI/CD for the Terraform itself** — Jenkins running `plan` on PR,
  `apply` only after merge/approval. Worth doing once this structure is
  stable; wiring it in before that just means debugging pipeline issues
  and structural issues at the same time.
- **Monitoring/alerting** — CloudWatch alarms on health checks, wired
  into your existing Prometheus/Grafana. Depends on Phase 2 (health
  checks) existing first.
- **A second environment (prod)** — copy `environments/dev/`, change the
  backend `key` and the tfvars, done. Not worth building until dev is
  proven out.

Say which of those you want next and I'll build it the same way — as
real files, not just a description.
