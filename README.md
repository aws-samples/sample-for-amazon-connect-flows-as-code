# Manage Amazon Connect Customer flows as code at scale

> **This is sample code, for non-production usage.** You should work with your
> security and legal teams to meet your organizational security, regulatory and
> compliance requirements before deployment.
>
> It is published to accompany a blog post and is intended to educate, not to be
> deployed as-is. It creates real AWS resources and will incur charges. See
> [SECURITY.md](SECURITY.md) and the cleanup section below.

Companion code for the AWS Contact Center blog post *How Booking.com manages
Amazon Connect Customer flows as code at scale*.

Published at [aws-samples/sample-for-amazon-connect-flows-as-code](https://github.com/aws-samples/sample-for-amazon-connect-flows-as-code) under MIT-0.

A contact flow is designed in a console, and the console is attached to one
Amazon Connect instance. The flow's JSON is full of that instance's IDs — queue
IDs, flow module IDs, data table IDs — so the same JSON deployed to a second
instance points at resources that do not exist there. That is the problem this
repo demonstrates a fix for.

It creates **two Connect instances in one AWS account**, seeds flows into the
first, exports them as portable templates, and deploys those same templates into
the second with **no manual JSON editing and a single `terraform apply`**. There
is no CI/CD pipeline: everything runs from your laptop so the mechanism is
visible rather than buried in a pipeline definition.

---

## The idea in one paragraph

Two strategies, used for different things.

**Composition first.** Design the flow so the references that *can* be resolved
at contact time are read from an Amazon Connect **data table** rather than
embedded in the flow. Terraform writes each environment's own IDs into that
table as it provisions resources, and the flow looks them up per contact. The
flow JSON never mentions them.

**Substitution second.** For references that genuinely must be in the JSON — a
data table ID, a flow module ID — the exporter replaces the ID with a placeholder
whose suffix is the base64-encoded resource **name**:

```json
"QueueId": "${queue_cmV0YWlsLXN1cHBvcnRfZW4}"
```

`cmV0YWlsLXN1cHBvcnRfZW4` decodes to `retail-support_en`. Names are stable across
instances; IDs are not. On deployment, Terraform rebuilds that same key from the
resources it manages in the target instance and renders the template with
`templatefile()`.

The two sides never talk to each other. They agree because both apply the same
transform — which is why `tests/` asserts both against one shared fixture.

---

## Layout

```
sample-amazon-connect-flows-as-code/
├── 01-source/                  root module: instance 1, seeded flows, exporter
│   └── flows/                  hand-written templates
├── 02-target/                  root module: instance 2, promoted flows
│   ├── flows/                  <- you copy exported templates here
│   └── flow-modules/           <- and here
├── modules/
│   ├── connect-baseline/       instance, hours of operation, queues, data table
│   ├── placeholder-keys/       the name -> placeholder-key transform
│   ├── flow-deployer/          renders templates, creates flows and modules
│   ├── routing-config/         writes this instance's IDs into the data table
│   └── flow-exporter/          Lambda + EventBridge + S3
└── tests/                      the cross-language encoding contract
```

Both root modules call the **same** `connect-baseline` and `flow-deployer`. That
symmetry is the point: baseline gives the two instances identically-*named*
resources with different ARNs, and `flow-deployer` renders the same template
format in both places. The only differences are in `02-target/main.tf`:

| | `01-source` | `02-target` |
|---|---|---|
| Where templates come from | written by hand | produced by the exporter |
| `console_owns_content` | `true` — a designer's console edit survives `apply` | `false` — a new template updates the flow |
| Exporter | yes | no; nothing is authored here |

`console_owns_content` is the asymmetry the whole pattern rests on. Terraform's
`lifecycle` block cannot take a variable, so it selects between two otherwise
identical resource blocks rather than toggling `ignore_changes`.

---

## Prerequisites

- Terraform >= 1.6 (verified on 1.14.1)
- `python3` and `pip` on the machine running Terraform — `flow-exporter` builds
  its Lambda at apply time
- AWS credentials for one account, and the AWS CLI for the verification steps
- `jq`, used by the optional diff and inspection commands below (not needed to deploy or destroy)
- **Quota headroom for two Connect instances.** You do not need to create any —
  `01-source` and `02-target` each create one. What you need is room for two
  under the instance quota (`L-AA17A6B9`), which defaults to 2 per Region and
  counts instances that already exist. So on an account with two instances
  already, the first apply fails until the quota is raised:

  ```bash
  aws service-quotas get-service-quota --service-code connect --quota-code L-AA17A6B9
  aws connect list-instances --query 'length(InstanceSummaryList)'   # existing, counts against it
  ```

  The quota is adjustable and increases can be requested programmatically:

  ```bash
  aws service-quotas request-service-quota-increase \
    --service-code connect --quota-code L-AA17A6B9 --desired-value 5
  ```

- A Region that supports Amazon Connect **data tables**. Verified in
  `us-east-1`.

**No phone numbers are claimed.** That is deliberate — they cost money and
Connect number release is frequently irreversible. The consequence is honest:
this demo verifies flows by *content and reference correctness*, not by placing a
live call. Claiming a number and attaching it to `gui-retail-support_main` is an
optional extra if you want to hear it work.

Everything else is inside the free tier or costs cents: one small Lambda, one S3
bucket, one SQS DLQ, two idle Connect instances.

---

## Walkthrough

Set your Region explicitly. `AWS_REGION` takes precedence over
`AWS_DEFAULT_REGION`, and a mismatch between your shell and `var.aws_region`
produces confusing results:

```bash
export AWS_REGION=us-east-1 AWS_DEFAULT_REGION=us-east-1
```

### 1. Create the source instance

```bash
cd 01-source
terraform init
terraform apply -parallelism=2
```

`-parallelism=2` matters. The Amazon Connect API throttles aggressively and the
default of 10 causes `ThrottlingException` part-way through an apply.

This creates the instance, hours of operation, two queues (`retail-support_en`,
`retail-priority_en`), a `routing_config` data table with one row, the exporter,
and three complete flow resources:

| Resource | Purpose |
|---|---|
| `gui-retail-support_main` | main inbound flow |
| `gui-retail-support_fallback` | reached on error, **dynamically** |
| `gui-global_read_prompt_from_datatable` | flow module; reads caller-facing copy from the data table |

`terraform output next_steps` prints the console URL and the commands below.

### 2. Act as the designer

`gui-retail-support_main` is deployed deliberately **wrong**: it routes to
`retail-priority_en`. Everything else is wired for you, because building a flow
from scratch is not what this demo is about.

Open the flow in the console:

```
https://<instance-alias>.my.connect.aws/contact-flows
```

Open `gui-retail-support_main` → the **Set working queue** block → change the
queue to **`retail-support_en`** → **Save**, then **Publish**.

One dropdown. No typing, no IDs, and it cannot fail validation because both
queues exist. It is exactly the small change a designer makes every day, and it
gives the export something to capture that Terraform did not put there.

### 3. Watch the exporter fire

```bash
aws logs tail /aws/lambda/$(terraform output -raw exporter_function_name) --since 10m --follow
```

The trigger is CloudTrail → EventBridge. **No CloudTrail trail is created**, and
none is needed: *mutating* management events are published to EventBridge by
default, and `UpdateContactFlowContent` is mutating. (The trail prerequisite you
may have read about applies to read-only events.) Delivery is eventually
consistent — expect tens of seconds, occasionally a few minutes.

If nothing arrives, prove the Lambda independently of the event plumbing with a
full export; an empty payload means "export everything":

```bash
aws lambda invoke --function-name $(terraform output -raw exporter_function_name) \
  --payload '{}' --cli-binary-format raw-in-base64-out /dev/stdout
```

### 4. Read the artifact

This is the payoff.

```bash
BUCKET=$(terraform output -raw export_bucket)
aws s3 ls "s3://$BUCKET/source/" --recursive
aws s3 cp "s3://$BUCKET/source/contact_flows/retail-support_main.json.tpl" -
```

Confirm three things:

- **No ARNs and no source-instance IDs.** Every environment-specific reference
  is a `${...}` placeholder.
- **The queue is `retail-support_en`.** The export captured *your* console change,
  not the template it was seeded from. Decode a placeholder to check — note the
  `=` padding is stripped, so it has to be added back or `base64 -d` silently
  truncates:

  ```bash
  b64pad() { printf '%s' "$1" | awk '{n=length($0)%4; if(n) printf "%s%s\n", $0, substr("===",1,4-n); else print}' | base64 -d; echo; }
  b64pad cmV0YWlsLXN1cHBvcnRfZW4      # -> retail-support_en
  ```

- **`$.DataTables.RoutingLookup.FallbackFlowId` survived.** The dynamic
  reference round-tripped intact.

See what the console change produced, seed versus export:

```bash
diff <(terraform output -json rendered_flows | jq -r '."retail-support_main"' | jq -S .) \
     <(aws s3 cp "s3://$BUCKET/source/contact_flows/retail-support_main.json.tpl" - | jq -S .)
```

About 24 lines, and the important ones read:

```diff
-          "QueueId": "6ccf6102-f774-...-89e28aa9ae65"   # the WRONG queue, resolved
+          "QueueId": "${queue_cmV0YWlsLXN1cHBvcnRfZW4}"
-            "text": "retail-priority_en"
+            "text": "${display_queue_cmV0YWlsLXN1cHBvcnRfZW4}"
```

The seed carried a resolved ID for the *wrong* queue; the export carries a
placeholder for the right one. On the left is what Terraform put in the instance,
on the right what is safe to promote.

**Expect a few differences beyond your edit.** The exporter strips non-deployable
fields, sorts keys and re-indents. That normalisation is what makes the next
promotion's diff reviewable, and it is not a bug to fix.

Trigger a second export with no changes in between and the summary reads
`{"exported": 0, "skipped": 3}` — identical content is not rewritten, so S3
version history tracks real changes only.

### 5. Promote

Copying templates out of the bucket and into `02-target/` stands in for the step
a pipeline would do: commit them to Git and review the diff.

First force a **full** export. This matters: the exporter is event-driven, so it
exports what changed. Editing the main flow in step 2 exported the contact flows
but not the flow module, which would leave `flow-modules/` empty and the flow
templates carrying a `${flow_module_<b64>}` placeholder with nothing to resolve.
An empty payload means "export everything":

```bash
cd ../01-source
aws lambda invoke --function-name $(terraform output -raw exporter_function_name) \
  --payload '{}' --cli-binary-format raw-in-base64-out /dev/stdout
BUCKET=$(terraform output -raw export_bucket)
aws s3 ls "s3://$BUCKET/source/" --recursive    # expect 3 templates
```

Then copy and apply:

```bash
cd ../02-target
mkdir -p flows flow-modules
aws s3 cp "s3://$BUCKET/source/contact_flows/"        flows/        --recursive
aws s3 cp "s3://$BUCKET/source/contact_flow_modules/" flow-modules/ --recursive

terraform init
terraform apply -parallelism=2
```

`02-target` discovers whatever is in those directories with `fileset()`, so
adding a flow to the demo is a file copy, not a Terraform edit.

**One apply is enough.** The production implementation needs two, because a flow
that embeds another flow's ARN creates a Terraform dependency cycle. Here the
fallback flow is resolved from the data table at contact time instead —
`TransferToFlow` accepts a single JSONPath in `ContactFlowId` — so there is no
cycle, no `terraform_remote_state`, and no `PENDING_CROSS_FLOW_REF` anywhere.

### 6. Prove it

```bash
terraform output verify        # prints the commands below with IDs filled in
```

```bash
aws connect describe-contact-flow \
  --instance-id "$(terraform output -raw instance_id)" \
  --contact-flow-id "$(terraform output -json contact_flow_ids | jq -r '."retail-support_main"')" \
  --query 'ContactFlow.Content' --output text | jq .
```

Same logic as the source instance, and every resolved ID belongs to the **target**
instance. Side by side:

```bash
diff <(cd ../01-source && terraform output -json queue_ids) \
     <(terraform output -json queue_ids)
```

Same names, different IDs. That is the promotion working.

Finally, confirm the source instance still respects the designer:

```bash
cd ../01-source && terraform apply -parallelism=2
```

Your console edit is still there. `ignore_changes = [content]` is the one line
that makes that true; without it, re-applying silently reverts a designer's work.

---

## Cleanup

Destroy in reverse order:

```bash
cd 02-target && terraform destroy -parallelism=2
cd ../01-source && terraform destroy -parallelism=2
```

The export bucket is versioned but declared with `force_destroy = true`, so
Terraform empties it as part of the destroy. That is deliberate for a sample —
without it, destroy fails with `BucketNotEmpty` and you have to delete every
object *version* and delete marker by hand. Do not copy that setting into a
production module.

If a destroy does fail part-way — Amazon Connect throttles, so it can — re-run
it; Terraform is resumable. Note that a partial destroy may have already removed
the resources the outputs depend on, in which case `terraform output -raw
export_bucket` stops working. Find the bucket directly instead:

```bash
aws s3 ls | grep connect-flow-export
```

**Deleting an Amazon Connect instance is irreversible.** Both instances here are
created by this sample and hold nothing else, but check the alias before you
confirm — `terraform destroy` only touches what is in its own state, so
pre-existing instances in the account are not at risk.

---

## Tests

The encoding contract is the one thing in this repo that fails silently if it
breaks: the exporter and the deployer derive placeholder keys independently, and
a drift on either side means no placeholder resolves in whichever environment
applies first.

```bash
python3 tests/test_encoding.py                        # exporter side
cd modules/placeholder-keys && terraform test         # deployer side
```

Both read `tests/encoding-fixture.json`, so neither can be changed alone. The
Terraform half needs **no AWS credentials** — `placeholder-keys` declares no
providers, which is most of why the transform lives in its own module.

---

## Notes for anyone reading the code

Things that cost time to work out, recorded so they do not have to be worked out
again. Each is also commented at the point it matters.

- **A flow module needs `Settings` inside `Content`**, not just in the top-level
  `settings` argument. Undocumented; the API rejects the flow otherwise.
- **`settings` is write-only.** `DescribeContactFlowModule` and Cloud Control both
  return `"{}"` whatever you wrote, so it can never converge and is in
  `ignore_changes`. A module's real interface travels in `Content.Settings`, which
  does round-trip.
- **`value_lock_level` must be `NONE`** on a data table whose rows Terraform owns.
  Any other level requires a lock token on write, and
  `AWS::Connect::DataTableRecord` has no field to carry one. Locking protects
  concurrent console editors; when Terraform is the only writer, state serialises
  the writes instead.
- **`awscc` never exposes a bare ID.** Contact flows, flow modules and data tables
  expose an ARN plus a composite `id`. Flow JSON needs the bare UUID, so
  everything derives it with `regex("[^/]+$", ...)`.
- **Connect validates flow content at create time**, and neither provider exposes
  `Status` (`SAVED` vs `PUBLISHED`), so every flow created here is published and
  must pass validation. Three requirements that are easy to miss:
  `TransferToFlow` requires `Transitions.NextAction`; `TransferContactToQueue`
  requires a `QueueAtCapacity` error branch; `UpdateFlowLoggingBehavior` *rejects*
  a `NoMatchingError` branch.
- **The exporter logs `Unresolvable reference found` for every action
  Identifier.** Noise, not a problem — action identifiers are UUIDs and the
  substitutor checks every UUID it sees against its mapping.
- **`awscc` occasionally fails its plugin handshake** under memory pressure
  (`Failed to load plugin schemas`). Environmental; retry.

## How this differs from the production implementation

This sample is a deliberately simplified version of the system it describes. Two
of the changes are bug fixes worth folding back into that implementation; the
third is a
simplification specific to a teaching artifact.

**Fixes:**

- `ChangeDetector` double-applied the S3 prefix, so it read `source/source/...`,
  never found the existing object, and rewrote identical content on every save.
- The botocore trim in `lambda.tf` must keep `lexv2-models`. Dropping a service
  the substitutor uses is not a hard failure — it warns and continues with an
  incomplete mapping — so it surfaces as a placeholder that silently never
  resolves.

**Simplification — the DynamoDB resource registry is removed.** In the production
system a registry table is how Terraform and the exporter Lambda divide ownership
of discovered resources. Here every placeholder resolves from module outputs
instead, so the table would be created, written to, and never read: no file in
`lambda/exporter/**` performs a DynamoDB read. Removing it took out the
`registry/` package, four Terraform variables, an IAM policy, and `dynamodb` from
the bundled botocore services.

`ReferenceSubstitutor.get_discovered_resources()` is deliberately left in place
even though only the registry called it. It is one method in the 699-line file
that is the actual substitution mechanism, and diverging further from the
implementation it came from costs more than it saves.

**Also simplified:** the flow is promoted between two instances in one account
rather than across accounts and environments, there is no CI/CD pipeline, and
cross-flow references are resolved dynamically at contact time rather than by the
two-pass apply the production code uses. See the note on `TransferToFlow` above.

**The data table keys on a constant, not the dialed number.** The blog post's
Figure 2 shows the production-grade pattern: the `routing_config` table keyed on
`DialedNumber = $.SystemEndpoint.Address`, so one flow routes each caller by the
number they dialed. This sample claims no phone number (they cost money and are
hard to release), so there is nothing per-contact to key on — the flow looks up a
fixed `ConfigKey = "retail"` instead. That is the one deliberate difference
between the post's example and this code: the **Data table block and the
substitution mechanism are identical**, only the lookup key is constant. Keying on
a constant also means the happy path is reachable without placing a call, which is
how the sample is verified — by content, not by audio.

---

## Security

See [SECURITY.md](SECURITY.md). No public endpoints are created: there is no
CloudFront distribution and no public API Gateway, and the export bucket blocks
public access with server-side encryption enabled.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SUPPORT.md](SUPPORT.md).

## License

This sample is licensed under **MIT No Attribution** (MIT-0). See
[LICENSE](LICENSE).

Third-party software bundled into the exporter's Lambda package is attributed in
[THIRD-PARTY-LICENSES](THIRD-PARTY-LICENSES). See also [NOTICE](NOTICE).
