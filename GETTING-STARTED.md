# Getting Started — Zero to Running Cluster

Exact order of operations. Each step says what it does, why it exists,
and the exact command to run. Jargon gets defined the first time it
shows up.

**Do not skip ahead** — step 3 will fail if step 1 hasn't finished, step
7 will fail if step 6 hasn't happened, and so on. Everything here is
sequential on purpose.

---

## 0. Before you start

You need three tools installed and working: AWS CLI, Terraform (1.10+),
and `kubectl`. Confirm each one responds:

```
aws --version
terraform --version
kubectl version --client
```

If any of these error out, install that tool before continuing —
nothing below will work without it.

---

## 1. Bootstrap — create the Terraform state bucket

**What this does:** creates the S3 bucket that every other step's
Terraform state will live in.
**Why it's separate:** you can't tell Terraform to store state in a
bucket that doesn't exist yet — this step has to run with local state,
once, before anything else.

```
cd bootstrap
terraform init
terraform apply
```

Type `yes` when prompted. Note the bucket name it creates — you need it
in step 3.

---

## 2. Fill in your real values

Copy the example tfvars file:

```
cd ../environments/dev
copy terraform.tfvars.example terraform.tfvars
```

*(`copy` is the PowerShell/CMD equivalent of `cp` — if you're in Git
Bash or WSL, use `cp` instead.)*

Open `terraform.tfvars` and set your real `aws_region` and
`project_name`. Leave `records = {}` exactly as it is — there's nothing
to point DNS at yet.

Then open `main.tf` in the same folder and replace the two
`REPLACE-ME-...` values in the `backend "s3"` block with the bucket
name from step 1 and your region.

---

## 3. Apply — this builds the VPC, EKS cluster, and node group

**What this does:** creates the whole foundation in one apply — VPC,
public/private subnets across 2 AZs, the NAT instance, the EKS control
plane, and the worker nodes that will run your pods.

**Why one apply, not several:** Terraform reads the dependency chain
itself (EKS needs the VPC's subnet IDs, which don't exist until the VPC
is created) and orders the actual resource creation correctly, even
though the code is written top-to-bottom as if it happens in sequence.

```
terraform init
terraform apply
```

This one takes a while — EKS control planes typically take 10-15
minutes to become active. That's normal, not stuck.

---

## 4. Point kubectl at your new cluster

**What this does:** `kubectl` needs to know which cluster to talk to
and how to authenticate. This step writes that config.

```
aws eks update-kubeconfig --name eks-lab --region YOUR_REGION
```

(Replace `eks-lab` if you changed `project_name` in step 2, and
`YOUR_REGION` with your actual region.)

**Verify it worked:**

```
kubectl get nodes
```

You should see 2 nodes (or however many you set `node_desired_size` to)
in `Ready` status. If they show `NotReady` for more than a few minutes,
something's wrong with the node IAM role or networking — check the AWS
console's EKS page for node group health first.

---

## 4.5 Bastion host — SSH access without opening it to the world

**What this does:** a small EC2 instance with a security group that
allows port 22 from exactly one IP address — yours — instead of the
usual `0.0.0.0/0` you'll see in most tutorials. `0.0.0.0/0` means "any
IP on the internet"; a `/32` CIDR means "this one specific address."

**Generate an SSH key pair** (PowerShell, using the OpenSSH client
bundled with Windows 10+):
```
ssh-keygen -t ed25519 -f $HOME\.ssh\bastion-key
```
This creates two files: `bastion-key` (private — never share this) and
`bastion-key.pub` (public — this is what goes into AWS).

**Find your current public IP:**
```
Invoke-RestMethod -Uri "https://checkip.amazonaws.com"
```
Take that value and add `/32` to the end, e.g. `203.0.113.5/32`. Put it
in `terraform.tfvars` as `allowed_ssh_cidr`, and set
`ssh_public_key_path` to the full path of `bastion-key.pub`.

```
terraform apply
```

**Connect with PuTTY:**
1. Open PuTTYgen → Load → select `bastion-key` (the private key, no
   extension) → Save private key → save as `bastion-key.ppk`.
2. Open PuTTY → Host: the `bastion_public_ip` output value → Connection
   → SSH → Auth → Credentials → browse to `bastion-key.ppk` → Open.
3. Log in as `ec2-user` (the default user on the Amazon Linux 2023 AMI).

**Or connect with plain SSH** (Git Bash / WSL / PowerShell's OpenSSH):
```
ssh -i $HOME\.ssh\bastion-key ec2-user@<bastion_public_ip>
```

**If your IP changes** (different network, VPN, etc.) and SSH stops
working, you still have SSM as a fallback — no key or security group
change needed:
```
aws ssm start-session --target <bastion_instance_id>
```

---



**What this does:** this is the piece that watches for Kubernetes
`Ingress` objects and actually creates the ALB/NLB in AWS behind them.
Without it, deploying an app with an Ingress does nothing — Kubernetes
records the intent, but nothing creates the load balancer.

**Why this isn't in the Terraform above:** it's a cluster *add-on*, not
infrastructure — it's more commonly installed via Helm than raw
Terraform, and doing it via Helm here keeps the two concerns separate.
This is a manual step for now; ask me to turn it into Terraform later
if you want it fully automated.

```
aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://iam-policy.json
```

(Download the official policy JSON from the AWS Load Balancer
Controller's GitHub releases page first — the exact URL changes with
each version, so check the latest release rather than a hardcoded link
here.)

Then follow the "Install cert-manager" and "Install with Helm" sections
in the AWS Load Balancer Controller docs for creating the IRSA role and
running `helm install`. This part has enough moving pieces (IRSA trust
policy, Helm repo add, exact chart values) that it deserves its own
walkthrough — say so and I'll build one.

---

## 6. Deploy something with an Ingress

Once the controller is running, deploying any app with a Kubernetes
`Ingress` resource will make it create a real ALB automatically. That
ALB's name is what goes into `records` in step 7.

```
kubectl get ingress -n default
```

---

## 7. Wire up the DNS record

**What this does:** now that a load balancer actually exists, go back to
`terraform.tfvars` and add an entry to `records`:

```
records = {
  myapp = "k8s-default-myapp-xxxxxxx"
}
```

(Get the exact load balancer name with the `aws elbv2
describe-load-balancers` command from the Phase 1 README if you don't
remember the exact syntax.)

```
terraform apply
```

---

## 8. Verify

```
kubectl run dns-test --rm -it --image=busybox --restart=Never -- nslookup myapp.eks.internal
```

If that resolves to the ALB's IP, the whole chain — VPC → EKS → app →
load balancer → Route 53 — is wired together end to end.

---

## What's next

- **IRSA roles** for Jenkins/Argo CD specifically (scoped permissions
  per pod, not per node) — the `oidc_provider_arn` output from this
  apply is what that depends on.
- **AWS Load Balancer Controller as Terraform**, not a manual Helm step.
- **Jenkins pipeline** to run `terraform plan`/`apply` instead of you
  running it from your laptop.

Say which one and I'll build it the same way as everything else here —
real files, exact steps.
