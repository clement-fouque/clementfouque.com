+++
title = "Test Elastic Agent integrations locally before production"
date = 2026-10-23
summary = "One local setup runs the Elastic stack, a standalone Elastic Agent, my custom Elasticsearch resources, and Kibana detection rules, so I can test integration changes before they reach production."
slug = "testing-elastic-integrations-locally"
draft = true
+++

I maintain Elastic Agent integrations that bring security data into Elasticsearch. Some are native integrations, such as Qualys, HackerOne, and Snyk. Others are custom, such as one that ingests JSON files from a private GitHub repository. In our environment, the integration is only the first part of the data path. Custom ingest pipelines, component templates, ILM policies, and transforms change the data before anyone searches it. When something broke in that layer, I had to troubleshoot it in production: change the configuration, wait for new data, check the result, and start again. Each cycle was slow, and each mistake reached real data.

To shorten that loop, I built a setup to test Elastic Agent integrations locally with the similar configuration I deploy to production. `elastic-package` starts Elasticsearch and Kibana. Then one command per integration uses OpenTofu to install the integration package and deploy my Elasticsearch resources and Kibana detection rules from JSON files, and Docker Compose to start a standalone Elastic Agent. I can reproduce a problem, test a fix, and compare the result with production before I roll anything out.

This post explains why I built the setup this way, using the native GitHub integration and its security advisories data. It starts with a data problem: the Dataset Quality page in Kibana showed that two fields were losing values, `vulnerability.description` and `github.security_advisory.references`, both mapped as `keyword`. It ends with a use case: a Slack message when GitHub publishes a new malware advisory, tested on the same local stack before production. The setup will become v2 of the [elastic-integrations-standalone repository](https://github.com/clement-fouque/elastic-integrations-standalone).

![Flow diagram: elastic-package starts Elasticsearch and Kibana, OpenTofu deploys JSON resources, Docker Compose starts the standalone Elastic Agent, the Agent sends GitHub advisories to a data stream, and Dataset Quality findings feed back into the JSON resources](local-integration-flow.png)

## What is Dataset Quality?

Dataset Quality is a Kibana page that lists your data streams and shows how many documents are degraded. A document is degraded when Elasticsearch ignored at least one of its fields during indexing. The original value stays in `_source`, but the field is not indexed, so you cannot search, filter, or aggregate on it.

A common cause is a long string in a `keyword` field. When a value is longer than the field's `ignore_above` limit, Elasticsearch skips it and records the field name in `_ignored`. Advisory descriptions and reference lists can be long, which makes them likely candidates.

For a security team, this matters. An analyst who searches advisory descriptions for a package name will not find documents where the description was ignored. Nothing fails loudly, and the gap only shows up on this page.

## Why the integration test was not enough

Testing an integration package on its own is easy. `elastic-package` can start a stack and run the package's system tests. That tells me the package works. It does not tell me what my environment does with the data.

In production, the data path has more parts than the package:

- the integration version we run
- custom ingest pipelines that rename, enrich, or drop fields
- component templates that override mappings
- lifecycle policies and transforms that read the data stream later

A bug can come from any of these, or from how they interact. In production, a wrong change affects every document that arrives after it.

I wanted the whole data path on my laptop, with the same configuration files I deploy to production.

## What one deployment runs

The setup has two commands. The first starts the stack:

```sh
elastic-package stack up --version 9.5.5 -d
```

The second deploys everything for one integration:

```sh
make deploy-local INTEGRATION=github_security_advisories
```

`make deploy-local` runs OpenTofu `init`, `plan`, and `apply`, then restarts the Agent with Docker Compose. OpenTofu installs the integration package and deploys the resources that sit around it. On the Elasticsearch side, these are component and index templates, ingest pipelines, ILM policies, and transforms. On the Kibana side, these are dashboards, detection rules, and connectors. Docker Compose starts a standalone Elastic Agent with the policy from `elastic-agent.yml`.

I keep the stack and the integration as separate commands on purpose. The stack takes the longest to start, so I leave it running. I redeploy the integration as often as I need, and I can test several integrations on the same stack.

The current baseline uses Elasticsearch, Kibana, and Elastic Agent 9.5.5, the GitHub integration package 2.32.0, OpenTofu 1.13.1, and `elastic-package` 0.126.4. I will update these numbers if they change before the v2 release.

With the stack running, I can go back to the ignored fields.

## Fixing the ignored fields

Here are the two fields Dataset Quality reported, as mapped in GitHub integration package 2.32.0:

| Field | Current mapping | Planned test |
| --- | --- | --- |
| `vulnerability.description` | `keyword` | Text-oriented mapping |
| `github.security_advisory.references` | `keyword` | Text-oriented mapping |

The plan is to add a mapping override in a JSON component template, run `make deploy-local`, let the Agent ingest advisories again, and check Dataset Quality. I still need to choose between `text` and `match_only_text`, and validate the result against real advisory documents. I will add before-and-after screenshots of Dataset Quality when that test is complete.

To confirm the result, I can ask Elasticsearch which mapping a field has in Kibana Dev Tools:

```
GET logs-github.security_advisories-default/_mapping/field/vulnerability.description
```

The response is JSON. That detail is the reason for the next design choice.

## Why I keep resource definitions in JSON

OpenTofu decides the deployment order and tracks state. The Elasticsearch resources themselves live in JSON files whenever possible, one folder per resource type under `integrations/<name>/`.

I chose JSON because Elasticsearch speaks JSON. When I read a component template from production with the API, I get JSON. When I write the same template in the repository, it is also JSON. I can compare the two files with `diff`, or copy a production resource into the repository to reproduce a problem.

If I had written these resources as Terraform blocks, every comparison would need a translation step from HCL to the API format and back. That step is easy to get wrong when you are in the middle of an incident.

Detection rules follow the same idea. Each rule is a JSON file in the format of the Kibana detection rules create API, and the Slack connector is a JSON file without its secret. Dashboards are the exception. They need more provider logic, so they stay as OpenTofu code.

JSON files also make it cheap to go one step further than mappings. Once the data is correct, I can test what we do with it.

## From advisory data to a Slack alert

GitHub publishes malware advisories for package versions that contain malicious code, such as a compromised npm package. I want a Slack message when a new one appears, so the team can check whether we use the package. The GitHub integration already collects these advisories in a dedicated stream. The missing part was a detection rule and a notification.

The first version of the rule was harder to get right than I expected. The Agent polls GitHub every 24 hours and ingests the full advisory list each time, so a simple query rule would alert on the same advisories every day. The rule also must not alert on years of old advisories on its first run. I iterated on the query, the lookback, and the Slack message many times. Each iteration was `make deploy-local`, a restart of the Agent, and a look at Slack. Doing this in production would have sent test messages to a real channel.

The final rule is a new terms rule. It alerts only the first time a `ghsa_id` appears in a 14-day history window, and only for advisories published in the last 7 days. Here is an excerpt of `detection_rules/github-malware-advisory-published.json`:

```json
{
  "type": "new_terms",
  "name": "GitHub Malware Advisory Published",
  "index": ["logs-github.security_advisories-default"],
  "language": "kuery",
  "query": "github.security_advisory.type:\"malware\" and github.security_advisory.published_at >= \"now-7d\"",
  "new_terms_fields": ["github.security_advisory.ghsa_id"],
  "history_window_start": "now-14d",
  "interval": "5m",
  "from": "now-6m",
  "to": "now",
  "timestamp_override": "event.ingested"
}
```

The rule's `actions` block points to the Slack connector, which is also a JSON file in `connectors/`:

```json
{
  "connector_type_id": ".slack",
  "name": "GitHub Security Advisories Slack"
}
```

The webhook URL is not in the file. It comes from a Git-ignored `.env` file and goes to Kibana through a write-only OpenTofu attribute, so it is not stored in the OpenTofu state.

Testing the alert locally also showed me a gap. If the Agent stops or the GitHub API returns errors, the malware rule stays quiet, and a quiet rule looks the same as a quiet day. I added two ES|QL rules for ingestion health that send to the same Slack connector. One alerts when documents contain errors from the GitHub API or the ingest pipeline. The other alerts when one of the three advisory streams ingests nothing for 26 hours.

The errors rule needed a small mapping change first. Fleet maps `error.code` and `error.message` only after the first error document arrives, so the ES|QL query failed with `Unknown column [error.code]`. A `logs-github.security_advisories@custom` component template now maps these fields in advance, and an existing data stream needs a rollover to use it. I found this locally, which is the kind of surprise I want to find before production.

## What the local stack does not cover

A local stack is a single node with a small amount of data. It will not show performance problems, shard sizing issues, or behavior that only appears with production volume. Cross-cluster search, security roles, and network rules are also outside its scope.

There is also a version risk. If the local stack, package, or Agent version differs from production, a test can pass locally and fail after deployment. I pin all three for that reason.

A local stack also does not have production's alert volume. The Slack test shows that the rule and the message work. It does not show how many alerts the team will receive in a busy week.

For mapping, ingest, and detection rule changes, these limits are acceptable. Those changes depend on the data shape and the configuration, and both are the same locally.

## What comes next

The diagram at the top of the post shows the full loop: start the stack, deploy the configuration, ingest data, check the result, and update the JSON files.

The malware advisory rule, the two ingestion health rules, and the Slack connector are now in the repository. The mapping fix for the two ignored fields is the remaining piece. When it is validated, I will release v2 of the [elastic-integrations-standalone repository](https://github.com/clement-fouque/elastic-integrations-standalone). If you maintain custom ingest pipelines on top of Elastic integrations, try the setup on one data stream and check what Dataset Quality shows you.
