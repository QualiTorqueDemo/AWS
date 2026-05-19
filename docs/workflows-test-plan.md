# AWS Workflows — Step-by-Step Test Plan

Step-by-step tests for the four new workflows: EC2 Resize, EKS Upgrade,
Route53 Record, Resource Tags Update.

Each test is broken into **Setup → Run → Verify → Cleanup**. Follow them
in order — earlier tests leave resources running that later tests reuse.

---

## 0. Global setup (do this once)

1. Sign in to the Torque space where the AWS catalog is published.
2. Confirm an agent named `demo-prod` (or your equivalent) is online: top-right user menu → **Agents** → look for a green dot.
3. Confirm the agent's IAM role has these actions (ask your AWS admin if unsure):
   - EC2: `ec2:DescribeInstances`, `ec2:StartInstances`, `ec2:StopInstances`, `ec2:ModifyInstanceAttribute`
   - EKS: `eks:DescribeCluster`, `eks:UpdateClusterVersion`, `eks:ListNodegroups`, `eks:DescribeNodegroup`, `eks:UpdateNodegroupVersion`
   - Route53: `route53:ChangeResourceRecordSets`, `route53:GetChange`
   - Tagging: `tag:TagResources`, `tag:UntagResources`, `tag:GetResources`
4. In the Catalog, verify the four workflows are visible and published:
   - **AWS EC2 Resize (Shell)**
   - **AWS EKS Upgrade (Shell)**
   - **AWS Route53 Record (Shell)**
   - **AWS Resource Tags Update (Shell)**
5. Open a second browser tab to the AWS console (same account/region) so you can verify each workflow's effect side-by-side.

---

## Test 1 — AWS EC2 Resize

Three sub-tests: 1.1 happy path, 1.2 idempotent, 1.3 stopped-stays-stopped.

### Setup (run once for all three sub-tests)

1. In Torque, open the Catalog and find **AWS EC2 Instance**.
2. Click **Launch**. Fill in:
   - `name`: `torque-test-resize`
   - `subnet_id`: an existing public subnet ID in your test VPC
   - `operating_system`: `Amazon Linux 2023`
   - `instance_type`: `t3.micro`
   - `agent`: `demo-prod`
   - Leave everything else default.
3. Click **Launch**. Wait until the environment status shows **Active** (~2-3 min).
4. Open the env → **Resources** tab → click the `terraform-aws-ec2-instance` resource. Confirm:
   - `id` output is populated (the EC2 instance ID, e.g. `i-0abc...`)
   - In the AWS console, the instance shows state **running** and type **t3.micro**.

### Test 1.1 — Resize while running (happy path)

**Run:**

1. In the env, on the EC2 resource card, click the **kebab menu (⋮)** → **Run workflow** → pick **AWS EC2 Resize**.
2. In the workflow form:
   - `agent`: `demo-prod`
   - `instance_type`: `t3.small`
3. Click **Launch workflow**.

**Verify:**

4. Watch the workflow's **Activity Feed** — you should see, in this order:
   - `Target: instance_id=i-... region=... new_type=t3.small`
   - `state_before=running instance_type_before=t3.micro`
   - `Stopping instance before resize...`
   - `Modifying instance type to t3.small...`
   - `Starting instance back up...`
   - `instance_type_after=t3.small state_after=running`
5. After ~3-5 min the workflow completes. Click **Outputs** and confirm:
   - `instance_type_before` = `t3.micro`
   - `instance_type_after` = `t3.small`
   - `state_after` = `running`
6. In AWS console → EC2 → the instance: type now **t3.small**, state **running**.

**Pass criteria:** all 6 verification steps match.

### Test 1.2 — Re-run with the same type (idempotent)

**Run:**

1. Same kebab menu → **Run workflow** → **AWS EC2 Resize**.
2. Inputs:
   - `agent`: `demo-prod`
   - `instance_type`: `t3.small`   *(same as current!)*
3. Launch.

**Verify:**

4. Activity Feed should be short and contain: `Instance is already of type t3.small - nothing to do.`
5. Workflow completes in <30 s.
6. Outputs: `instance_type_before == instance_type_after == t3.small`, `state_after == running`.
7. AWS console: nothing changed — no stop/start cycle in the instance event history.

**Pass criteria:** no stop/start happened; outputs reflect a no-op.

### Test 1.3 — Resize while stopped (preserves stopped state)

**Run:**

1. In AWS console, **stop** the instance manually. Wait until state shows **stopped**.
2. Back in Torque, kebab → **Run workflow** → **AWS EC2 Resize**.
3. Inputs:
   - `agent`: `demo-prod`
   - `instance_type`: `t3.medium`
4. Launch.

**Verify:**

5. Activity Feed should **NOT** contain `Stopping...` or `Starting instance back up...`.
6. Should contain: `Modifying instance type to t3.medium...`
7. Outputs: `instance_type_before=t3.small`, `instance_type_after=t3.medium`, `state_after=stopped`.
8. AWS console: type **t3.medium**, state **stopped** (workflow respected the pre-existing stopped state).

**Pass criteria:** workflow modified the type but did not auto-start the instance.

### Cleanup for Test 1

1. **Don't end the env yet** — Test 2 reuses this instance.
2. In AWS console, start the instance back up so Test 2 can run against a running resource.

---

## Test 2 — AWS Resource Tags Update

Four sub-tests: 2.1 add, 2.2 merge/overwrite, 2.3 remove, 2.4 cross-type (optional).

### Setup

Reuse the EC2 env from Test 1 (running, currently `t3.medium`).

### Test 2.1 — Add two new tags

**Run:**

1. On the EC2 resource card, kebab → **Run workflow** → **AWS Resource Tags Update**.
2. Inputs:
   - `agent`: `demo-prod`
   - `action`: `add_tags`
   - `tags`: `Owner=alice,Env=test`
3. Launch.

**Verify:**

4. Activity Feed contains:
   - `Target: arn=arn:aws:ec2:... region=... action=add_tags`
   - `Adding tags (Env,Owner): {"Owner":"alice","Env":"test"}`
   - A formatted verification table at the end showing both keys present.
5. Outputs: `tags_keys = Env,Owner`, `action_taken = add_tags`.
6. In AWS console → EC2 → the instance → Tags tab: `Owner=alice` and `Env=test` both visible alongside the Torque-auto tags.

### Test 2.2 — Overwrite one, add another (merge semantics)

**Run:**

1. Same workflow, inputs:
   - `action`: `add_tags`
   - `tags`: `Owner=bob,Team=platform`
2. Launch.

**Verify:**

3. AWS console → EC2 → Tags:
   - `Owner` flipped from `alice` to **`bob`** (overwrite)
   - `Team=platform` is added (new)
   - `Env=test` from Test 2.1 is **still there** (preserved — merge, not replace)

### Test 2.3 — Remove a tag key

**Run:**

1. Same workflow, inputs:
   - `action`: `remove_tags`
   - `tags`: `Team`
2. Launch.

**Verify:**

3. Activity Feed: `Removing tag keys: Team`.
4. Outputs: `tags_keys = Team`, `action_taken = remove_tags`.
5. AWS console → Tags: `Team` is **gone**; `Owner=bob` and `Env=test` still present.

### Test 2.4 — Different resource type (optional, but recommended)

**Run:**

1. Launch a quick **AWS S3 Bucket** env from the catalog (defaults are fine — gives you an S3 bucket resource).
2. Wait for env Active.
3. On the bucket resource card, kebab → **Run workflow** → **AWS Resource Tags Update**.
4. Inputs:
   - `action`: `add_tags`
   - `tags`: `CostCenter=123`
5. Launch.

**Verify:**

6. Outputs: `resource_arn` starts with `arn:aws:s3:::...`
7. AWS console → S3 → bucket → Properties → Tags: `CostCenter=123` visible.

This confirms the ARN extractor works for non-EC2 resources.

### Cleanup for Test 2

1. Run Test 2.3 again with `tags = Owner,Env` to leave the EC2 instance clean.
2. End the S3 env from Test 2.4 (it'll cost <$0.01 per day, but tidy up).
3. **Do not** end the EC2 env yet if you want to keep it for the smoke test at the end — otherwise end it now.

---

## Test 3 — AWS Route53 Record

Four sub-tests: 3.1 UPSERT create, 3.2 UPSERT replace, 3.3 multi-value, 3.4 DELETE.

### Setup

The catalog has no Route53 Zone blueprint yet, so create the zone manually.

1. In AWS console → Route 53 → Hosted zones → **Create hosted zone**.
   - Domain name: `torque-test.local`
   - Type: **Private hosted zone**
   - Associate with the VPC used by your test agent (any test VPC works)
   - Click **Create hosted zone**.
2. Copy the **Hosted zone ID** (looks like `Z01234567ABCDEFG`).
3. Now you need a Torque env that has this zone as an `aws_route53_zone` resource. Easiest way:
   - Use the Torque **terraform import** feature, OR
   - Author a tiny throwaway blueprint that wraps `aws_route53_zone` and launches it pointing at the existing zone.
   - If neither is convenient, ask me and I'll add a small `AWS-Route53-Zone` blueprint to the catalog.
4. Once the zone resource is in an env, open it → **Resources** tab → find the `aws_route53_zone` resource card.

### Test 3.1 — UPSERT a new A record

**Run:**

1. On the zone resource card, kebab → **Run workflow** → **AWS Route53 Record**.
2. Inputs:
   - `agent`: `demo-prod`
   - `action`: `UPSERT`
   - `record_name`: `api`
   - `record_type`: `A`
   - `record_value`: `10.0.0.1`
   - `ttl`: `300`
3. Launch.

**Verify:**

4. Activity Feed prints the ChangeBatch JSON (with `Action: UPSERT`).
5. Outputs:
   - `zone_id` = your hosted zone ID
   - `change_id` starts with `/change/`
   - `change_status` = `PENDING` (becomes `INSYNC` after ~30-60 s)
   - `record_fqdn` = `api.torque-test.local.` (trailing dot auto-added)
6. AWS console → Route 53 → the zone: record `api.torque-test.local` of type A, value `10.0.0.1`, TTL 300.

### Test 3.2 — UPSERT replaces existing record

**Run:**

1. Same workflow, inputs:
   - `action`: `UPSERT`
   - `record_name`: `api`, `record_type`: `A`
   - `record_value`: `10.0.0.2`
   - `ttl`: `300`
2. Launch.

**Verify:**

3. AWS console: same record now has value **10.0.0.2**, not two records.

### Test 3.3 — UPSERT with multi-value

**Run:**

1. Inputs:
   - `action`: `UPSERT`
   - `record_name`: `api`, `record_type`: `A`
   - `record_value`: `10.0.0.2,10.0.0.3,10.0.0.4`
   - `ttl`: `300`
2. Launch.

**Verify:**

3. Activity Feed: ChangeBatch JSON shows three entries in `ResourceRecords`.
4. AWS console: same A record now has 3 values.

### Test 3.4 — DELETE the record

> Route53 DELETE requires the value and TTL to match the existing record exactly.

**Run:**

1. Inputs:
   - `action`: `DELETE`
   - `record_name`: `api`, `record_type`: `A`
   - `record_value`: `10.0.0.2,10.0.0.3,10.0.0.4`   *(must match current values)*
   - `ttl`: `300`
2. Launch.

**Verify:**

3. Outputs: `change_status` = `PENDING` / `INSYNC`, `action_taken` = `DELETE`.
4. AWS console: the `api.torque-test.local` record is gone.

### Cleanup for Test 3

1. End the env that holds the zone resource (if a throwaway).
2. AWS console → Route 53 → delete the `torque-test.local` hosted zone.

---

## Test 4 — AWS EKS Upgrade

> Heads up: full upgrade takes 30-60 minutes and counts against your
> AWS upgrade quota. Schedule a maintenance window.

Three sub-tests: 4.1 full upgrade, 4.2 idempotent, 4.3 control-plane only.

### Setup (only run once — reuse the cluster for all three sub-tests)

1. In Torque, Catalog → **AWS EKS** → Launch.
2. Inputs:
   - `cluster_name`: `torque-test-upgrade`
   - `cluster_version`: `1.31`   *(intentionally one minor behind so we have room to upgrade twice)*
   - `vpc_id`: an existing VPC with private subnets
   - `subnet_ids`: 2+ private subnet IDs across different AZs
   - `agent`: `demo-prod`
   - Leave node group defaults (gives you 2× t3.medium on 1.31)
3. Click **Launch**. Wait until status **Active** (~15-20 min for EKS).
4. Confirm AWS console → EKS → `torque-test-upgrade`:
   - Cluster status: **Active**, version **1.31**
   - Node group: **Active**, version **1.31**, 2 nodes Ready

### Test 4.1 — Full upgrade (control plane + node groups)

**Run:**

1. On the EKS cluster resource card, kebab → **Run workflow** → **AWS EKS Upgrade**.
2. Inputs:
   - `agent`: `demo-prod`
   - `target_version`: `1.32`
   - `upgrade_nodegroups`: `true`
3. Launch.

**Verify (this is a long test — check every ~10 min):**

4. Activity Feed should progress through:
   - `Target: cluster_name=... target_version=1.32`
   - `Updating cluster version 1.31 -> 1.32...`
   - `Waiting for cluster to become ACTIVE on 1.32 (may take 20-40 minutes)...`
   - (15-20 min later) `version_after=1.32`
   - `Upgrading node group <name> from 1.31 to 1.32...`
   - (another 15-30 min) workflow completes
5. Outputs:
   - `version_before` = `1.31`
   - `version_after` = `1.32`
   - `nodegroups_upgraded` = the node group name (with trailing space)
6. AWS console → EKS → cluster **and** node group both show version **1.32**, status **Active**.
7. `kubectl version --short` (if you have kubectl configured) shows server version 1.32.x.

### Test 4.2 — Re-run on the same target (idempotent)

**Run:**

1. Same workflow.
2. Inputs:
   - `target_version`: `1.32`   *(same as current!)*
   - `upgrade_nodegroups`: `true`
3. Launch.

**Verify:**

4. Workflow completes in <30 s.
5. Activity Feed:
   - `Cluster is already on 1.32 - skipping control plane upgrade.`
   - `Node group <name> already on 1.32 - skipping.`
6. Outputs: `version_before == version_after`, `nodegroups_upgraded = none`.

### Test 4.3 — Control-plane only, leave node groups behind

**Run:**

1. Same workflow.
2. Inputs:
   - `target_version`: `1.33`
   - `upgrade_nodegroups`: `false`
3. Launch.

**Verify (~15-20 min):**

4. Activity Feed:
   - `Updating cluster version 1.32 -> 1.33...`
   - `upgrade_nodegroups=false - leaving node groups on their current versions.`
5. Outputs: `version_after = 1.33`, `nodegroups_upgraded = none`.
6. AWS console:
   - Cluster: version **1.33**, Active
   - Node group: version **1.32** (unchanged) — AWS may show a yellow "version skew" warning, that's expected.

### Cleanup for Test 4

1. End the EKS env from Torque. Teardown takes ~10 min.

---

## Smoke test (~15 min, lowest cost — run after every change)

A quick, cheap, end-to-end check across EC2 + Tags. No Route53 zone or EKS needed.

1. Launch `AWS EC2 Instance` with `instance_type=t3.micro`, a valid `subnet_id`.
2. Wait for Active.
3. Run **AWS EC2 Resize** → `t3.small`. Confirm Outputs match (`instance_type_after=t3.small`).
4. Run **AWS Resource Tags Update** → `add_tags`, `Owner=smoke,Test=yes`. Confirm in AWS console.
5. Run **AWS Resource Tags Update** → `remove_tags`, `Test`. Confirm `Test` is gone.
6. End env.

If all 6 steps succeed, the resource-action workflow path is healthy.

---

## Sign-off checklist

- [ ] Test 1.1 — EC2 resize while running ✔
- [ ] Test 1.2 — EC2 resize idempotent ✔
- [ ] Test 1.3 — EC2 resize stopped stays stopped ✔
- [ ] Test 2.1 — Tags add ✔
- [ ] Test 2.2 — Tags merge/overwrite ✔
- [ ] Test 2.3 — Tags remove ✔
- [ ] Test 2.4 — Tags on S3 (optional) ✔
- [ ] Test 3.1 — Route53 UPSERT create ✔
- [ ] Test 3.2 — Route53 UPSERT replace ✔
- [ ] Test 3.3 — Route53 UPSERT multi-value ✔
- [ ] Test 3.4 — Route53 DELETE ✔
- [ ] Test 4.1 — EKS full upgrade ✔
- [ ] Test 4.2 — EKS upgrade idempotent ✔
- [ ] Test 4.3 — EKS control-plane only ✔
- [ ] Smoke test ✔

## Common failure signatures

| Symptom in Activity Feed | Likely cause | Fix |
|---|---|---|
| `Failed to extract instance_id/region from contract.json` | Wrong grain selected, or grain lacks the expected attributes | Re-run from a freshly deployed env; verify the resource is a real `aws_instance` |
| `jq: command not found` | Agent host missing jq | Install jq on the agent VM |
| `AccessDenied` from AWS CLI | Agent IAM role missing one of the actions in Section 0 | Add the missing action to the role |
| Route53 `InvalidChangeBatch` | DELETE provided values/TTL that don't match current record | Use `aws route53 list-resource-record-sets` to get the exact current values/TTL |
| EKS `InvalidParameterException: unsupported Kubernetes minor version update` | Tried to skip more than one minor version | Upgrade one minor at a time (1.31→1.32→1.33→1.34) |
| Workflow doesn't appear on a resource card | `workflow.scope` / `resource-types` mismatch, or workflow not published | Confirm the resource's TF type matches `resource-types`; publish the workflow in the Catalog |
