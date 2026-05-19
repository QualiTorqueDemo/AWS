# AWS Workflows — Test Plan

Test plan for the four new workflows added in commit `5cb0da1`:
EC2 Resize, EKS Upgrade, Route53 Record, Resource Tags Update.

## Suggested order

Run in this order — fastest/lowest-risk first, riskiest last:

1. **EC2 Resize** (~5 min per test, low risk)
2. **Resource Tags Update** (~1 min per test, low risk, reuses EC2 from #1)
3. **Route53 Record** (~2 min per test, low risk, but requires a zone)
4. **EKS Upgrade** (~30-60 min per test, high cost & disruption, do last)

## Global prerequisites

- A Torque agent named e.g. `demo-prod` with AWS credentials and an IAM role that has:
  - `ec2:DescribeInstances`, `ec2:StartInstances`, `ec2:StopInstances`, `ec2:ModifyInstanceAttribute`
  - `eks:DescribeCluster`, `eks:UpdateClusterVersion`, `eks:ListNodegroups`, `eks:DescribeNodegroup`, `eks:UpdateNodegroupVersion`
  - `route53:ChangeResourceRecordSets`, `route53:GetChange`
  - `tag:TagResources`, `tag:UntagResources`, `tag:GetResources`
- AWS CLI v2 and `jq` available on the agent (already required by existing workflows).
- The four workflow YAMLs published in the Torque space catalog.

## Verification helpers

After each run, in the Torque UI confirm:
- The workflow's **Activity Feed** shows the `echo` lines you see in the script
- The workflow **Outputs** populate with non-empty values
- The expected AWS-side state, verified by re-opening the resource in the AWS console or via CLI

---

## 1. AWS-EC2-Resize

### Prerequisites
Deploy an environment from `AWS-EC2-instance` blueprint with:
- `name`: `torque-test-resize`
- `instance_type`: `t3.micro`
- `operating_system`: `Amazon Linux 2023`
- a valid `subnet_id`

Wait for the env to be Active and note the `id` output (the instance ID).

### Test cases

**Case 1.1 — Happy path: scale up while running**
- Action: from the env's resource view, run `AWS EC2 Resize` on the instance
- Inputs: `instance_type = t3.small`
- Expected:
  - Activity feed: `state_before=running ... Stopping ... Modifying ... Starting ... state_after=running`
  - Outputs: `instance_type_before=t3.micro`, `instance_type_after=t3.small`, `state_after=running`
  - In AWS console: instance type is `t3.small`, state running
- Duration: ~3-5 min

**Case 1.2 — Idempotent: same type, no-op**
- Action: re-run the workflow on the same instance
- Inputs: `instance_type = t3.small`
- Expected:
  - Activity feed: `Instance is already of type t3.small - nothing to do.`
  - Outputs: `instance_type_before == instance_type_after == t3.small`, `state_after=running`
  - In AWS console: nothing changed (no stop/start cycle)
- Duration: <30 s

**Case 1.3 — Stopped stays stopped**
- Prep: in AWS console, stop the instance manually; wait for state=stopped
- Action: run the workflow with `instance_type = t3.medium`
- Expected:
  - Activity feed: no "Stopping" message (already stopped), no "Starting" message
  - Outputs: `instance_type_after=t3.medium`, `state_after=stopped`
  - In AWS console: type updated, still stopped (workflow respects the prior state)
- Duration: ~2 min

### Cleanup
End the env from Torque.

---

## 2. AWS-Resource-Tags-Update

### Prerequisites
Reuse the EC2 env from Section 1 (after restoring to `t3.small`, running). The workflow also supports RDS, S3, EKS, Lambda, ECR, Secrets Manager, CloudWatch Logs, App Runner, and Security Group resources — add an extra case at the bottom to cross-check one of those.

### Test cases

**Case 2.1 — add_tags: merge two new tags**
- Action: from the env's resource view, run `AWS Resource Tags Update` on the instance
- Inputs:
  - `action = add_tags`
  - `tags = {"Owner":"alice","Env":"test"}`
- Expected:
  - Activity feed includes "Adding tags: Env,Owner" and the verification table
  - Outputs: `tags_keys = "Env,Owner"`, `action_taken = add_tags`
  - In AWS console > EC2 > Tags: both new keys present alongside Torque-auto tags

**Case 2.2 — add_tags: overwrite existing, add new**
- Action: re-run with overlapping + new keys
- Inputs:
  - `action = add_tags`
  - `tags = {"Owner":"bob","Team":"platform"}`
- Expected:
  - `Owner` value flips from `alice` to `bob`
  - `Team` is added
  - `Env=test` from case 2.1 is preserved
  - Other Torque-auto tags untouched

**Case 2.3 — remove_tags: strip a key**
- Action: run with action=remove_tags
- Inputs:
  - `action = remove_tags`
  - `tags = ["Team"]`
- Expected:
  - Activity feed: "Removing tag keys: Team"
  - Outputs: `tags_keys = "Team"`
  - In AWS console: `Team` is gone; `Owner` and `Env` remain

**Case 2.4 — Different resource type (optional, recommended)**
- Prep: deploy `AWS-S3-Bucket` or `AWS-Secrets-Manager` in any env
- Action: run `AWS Resource Tags Update` on that resource with `{"CostCenter":"123"}`
- Expected: succeeds, `resource_arn` output shows the S3/Secrets ARN, tags visible in AWS console
- Why this matters: confirms the ARN extractor works across resource types

**Case 2.5 — Negative: resource without ARN attribute**
- Action: if you have an older grain that does not expose `.attributes.arn`, run against it
- Expected:
  - Workflow fails fast with: `Failed to extract resource ARN from contract.json ... The selected resource type may not expose .attributes.arn`
  - This validates the error path

### Cleanup
Run case 2.3 again with the remaining keys to leave the instance clean.

---

## 3. AWS-Route53-Record

### Prerequisites
The catalog does not currently ship a Route53 Zone blueprint. Two options:

- **Option A (recommended)**: in AWS console, create a private hosted zone like `torque-test.local` in any VPC, then in Torque pre-import it as an `aws_route53_zone` resource on an environment (use a `terraform import` grain or a Shell grain).
- **Option B**: temporarily author a thin `AWS-Route53-Zone` blueprint that wraps a single `aws_route53_zone` resource and deploy it to get a zone resource in an env.

Note the zone_id and create at least one record manually for the DELETE test.

### Test cases

**Case 3.1 — UPSERT a new A record**
- Action: run on the zone resource
- Inputs:
  - `action = UPSERT`
  - `record_name = api`  (or `api.torque-test.local` — workflow auto-appends trailing dot)
  - `record_type = A`
  - `record_value = 10.0.0.1`
  - `ttl = 300`
- Expected:
  - Activity feed prints the ChangeBatch JSON
  - Outputs: `change_id=/change/...`, `change_status=PENDING` or `INSYNC`, `record_fqdn=api.torque-test.local.`
  - In AWS console: record exists with value 10.0.0.1

**Case 3.2 — UPSERT replaces existing**
- Action: re-run with a different value
- Inputs:
  - `action = UPSERT`, same name/type
  - `record_value = 10.0.0.2`
- Expected:
  - Record value flips from 10.0.0.1 to 10.0.0.2 (no error, no duplicate record)

**Case 3.3 — UPSERT with multi-value**
- Action:
  - `action = UPSERT`, same name/type
  - `record_value = 10.0.0.2,10.0.0.3,10.0.0.4`
- Expected:
  - In AWS console: record now has 3 values
  - ChangeBatch JSON in the feed shows three ResourceRecords entries

**Case 3.4 — DELETE**
- Action: run with `action = DELETE`, same name/type, **the value and TTL must match the current record exactly** (this is a Route53 hard requirement)
  - `record_value = 10.0.0.2,10.0.0.3,10.0.0.4`
  - `ttl = 300`
- Expected:
  - `change_status = PENDING/INSYNC`
  - Record disappears from the zone

**Case 3.5 — Negative: DELETE with wrong TTL**
- Action: try DELETE with a TTL that does not match what's in the zone
- Expected:
  - AWS returns `InvalidChangeBatch`; workflow fails; activity feed shows the API error
  - This validates the surface of error messaging — make sure the AWS error is visible in the feed

### Cleanup
DELETE any test records and remove the hosted zone if it was created for the test.

---

## 4. AWS-EKS-Upgrade

> Warning: a full control-plane + nodegroup upgrade takes 30-60 minutes
> and counts against your EKS upgrade quota. Schedule a maintenance window.

### Prerequisites
Deploy an environment from `AWS-EKS` blueprint with:
- `cluster_name`: `torque-test-upgrade`
- `cluster_version`: `1.31` (intentionally one minor behind so we have room to upgrade)
- one managed node group at the same version
- 2x t3.medium nodes
- a valid VPC + private subnets

Wait for the env to be Active. Confirm via AWS console that cluster and node group are both `ACTIVE` at `1.31`.

### Test cases

**Case 4.1 — Happy path: full upgrade**
- Action: run `AWS EKS Upgrade` on the cluster resource
- Inputs:
  - `target_version = 1.32`
  - `upgrade_nodegroups = true`
- Expected:
  - Activity feed:
    - `Updating cluster version 1.31 -> 1.32...`
    - `Waiting for cluster to become ACTIVE on 1.32 ...`
    - `Upgrading node group <name> from 1.31 to 1.32...`
    - Final summary with version_before/after
  - Outputs: `version_before=1.31`, `version_after=1.32`, `nodegroups_upgraded=<name>`
  - In AWS console: cluster and node group both `1.32` and `ACTIVE`
- Duration: 30-60 min total (15-20 min control plane + 15-30 min per node group rolling update)

**Case 4.2 — Idempotent: already on target**
- Action: re-run the same workflow
- Inputs: `target_version = 1.32`, `upgrade_nodegroups = true`
- Expected:
  - Activity feed: `Cluster is already on 1.32 - skipping control plane upgrade.`
  - For each NG: `Node group <name> already on 1.32 - skipping.`
  - Outputs: `version_before == version_after`, `nodegroups_upgraded=` (empty list — none re-upgraded)
- Duration: <30 s

**Case 4.3 — Control-plane only**
- Action: run with `upgrade_nodegroups = false`
- Inputs: `target_version = 1.33`, `upgrade_nodegroups = false`
- Expected:
  - Control plane upgrades to 1.33; node groups stay on 1.32
  - Activity feed: `upgrade_nodegroups=false - leaving node groups on their current versions.`
  - Outputs: `version_after=1.33`, `nodegroups_upgraded=none`
- Duration: 15-20 min

**Case 4.4 — Negative: skip-version attempt**
- Action: run with a target that is 2+ minors above current
- Inputs: `target_version = 1.34` while cluster is at 1.31
- Expected:
  - AWS rejects with `InvalidParameterException: unsupported Kubernetes minor version update`
  - Workflow exits non-zero; error visible in the activity feed
  - This documents the one-minor-step rule for future users

### Cleanup
End the env from Torque (terminates the cluster + node groups).

---

## Smoke test (after all 4 pass)

Combined sequence on a fresh env, ~15 min, no cost beyond one t3.micro:

1. Deploy `AWS-EC2-instance` (`t3.micro`).
2. Run **EC2 Resize** -> `t3.small`. Check it's running.
3. Run **Resource Tags Update** -> add `{"Owner":"smoke","Test":"yes"}`.
4. Run **Resource Tags Update** -> remove `["Test"]`.
5. End the env.

If steps 2-4 all succeed and tags persist in AWS as expected, the workflow path
is healthy.

---

## Sign-off checklist

- [ ] Case 1.1, 1.2, 1.3 pass
- [ ] Case 2.1, 2.2, 2.3, 2.4 pass
- [ ] Case 3.1, 3.2, 3.3, 3.4 pass
- [ ] Case 4.1, 4.2, 4.3 pass
- [ ] Negative cases 2.5, 3.5, 4.4 produce clear errors in the activity feed
- [ ] Smoke test passes end-to-end

## Notes / gotchas

- **Activity feed retention**: the feed is the primary debug surface — verify every `echo` lands; if a feed is empty, the script likely failed before any `echo` (e.g. jq missing on the agent).
- **Route53 zone resource**: until a Route53 Zone blueprint is in the catalog, the test plan depends on a manually-prepared zone or a one-off blueprint.
- **EKS upgrade quota**: AWS limits how often you can upgrade a cluster. If you re-run Case 4.1 too quickly after a teardown, AWS may rate-limit.
- **IAM role on agent**: if a workflow fails with `AccessDenied`, the agent's role is missing one of the actions listed in *Global prerequisites*.
