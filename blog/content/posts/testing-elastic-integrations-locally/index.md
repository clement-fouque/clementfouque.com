+++
title = "Test Elastic Agent integrations locally before production"
date = 2026-10-23
summary = "One local setup runs the Elastic stack, a standalone Elastic Agent, my custom Elasticsearch resources, and Kibana detection rules, so I can test integration changes before they reach production."
slug = "testing-elastic-integrations-locally"
draft = true
+++

I maintain Elastic Agent integrations that bring security data into Elasticsearch. Some are native, such as Qualys, HackerOne, and Snyk. Others are custom, such as one that ingests Elastic Security Advisories JSON files from a private GitHub repository. In our environment, the integration is only the first part of the data path, because custom resources change the data after it arrives. When something broke in that layer, troubleshooting was slow. Production access was limited, so I could not always test a change there, and building a local environment that matched production took more time than the fix itself.

So I built a new version of my standalone repository. One repository holds everything an integration needs: the Agent policy, the Elasticsearch resources (component or index templates, ingest pipelines, ...), and the Kibana detection rules, mostly as JSON files that use the same format as the Elastic APIs. Two commands start a local Elastic stack and deploy the integration on it. Because the files look like what production returns, I can test a change locally and compare it with production before I roll it out. This post explains that design, and uses one real example to show its value: a Slack notification when GitHub publishes a new malware advisory.

![Flow diagram: elastic-package starts Elasticsearch and Kibana, OpenTofu deploys JSON resources, Docker Compose starts the standalone Elastic Agent, the Agent sends GitHub advisories to a data stream, a detection rule sends new malware advisories to Slack, and test results feed back into the JSON resources](local-integration-flow.png)

## The problem

Testing an integration package on its own is easy. `elastic-package` can start a stack and run the package's system tests. That tells me the package works, but it does not tell me what my environment does with the data.

In production, the data path has more parts than the package:

- the integration version we run
- custom ingest pipelines that rename, enrich, or drop fields
- component templates that override mappings
- lifecycle policies and transforms that read the data stream later
- detection rules and connectors that act on the data

A bug can come from any of these parts, or from how they interact. I wanted all of them on my laptop, deployed from the same kind of files I use for production.

## How the repository is organized

### One folder per integration

Each integration has a folder under `integrations/` with its Agent policy and its resources, and an OpenTofu root under `infrastructure/` that deploys them. Here is the GitHub Security Advisories example:

```text
integrations/github_security_advisories/
├── compose.yml
├── elastic-agent.yml
├── terraform.tfvars
├── component_templates/
│   └── logs-github.security_advisories@custom.json
├── connectors/
│   └── github-security-advisories-slack.json
└── detection_rules/
    ├── github-advisory-ingestion-errors.json
    ├── github-advisory-ingestion-stopped.json
    └── github-malware-advisory-published.json
infrastructure/github_security_advisories/
├── main.tf
├── variables.tf
└── versions.tf
```

The folder names match the resource types. Other integrations can also have `index_templates/`, `pipelines/`, `ilm/`, and `transforms/`. A shared OpenTofu module reads every JSON file in these folders and deploys it, so adding a resource means adding a file.

### Two commands

The first command starts the stack. It uses `elastic-package` to stop any running stack and start Elasticsearch and Kibana 9.5.5. Add `version=<x.y.z>` to test another version.

```sh
make stack-restart
```

The second command deploys one integration:

```sh
make deploy-local INTEGRATION=github_security_advisories
```

It runs OpenTofu `init`, `plan`, and `apply`, then restarts the standalone Elastic Agent with Docker Compose. OpenTofu installs the integration package, then deploys the Elasticsearch resources and the Kibana rules and connectors.

I usually run both commands one after the other to start from a clean environment. They stay separate because I do not always need a new stack. When I only change a rule or a template, I redeploy the integration and keep the stack running.

### Why JSON

OpenTofu handles the deployment order and the state. The resources themselves stay in JSON because Elasticsearch and Kibana speak JSON. When I read a component template or export a detection rule from production, I get JSON in the same shape as the file in the repository. I can compare the two, or copy a production resource into the repository to reproduce a problem.

With Terraform blocks, every comparison would need a translation from HCL to the API format. That translation is easy to get wrong during an incident. Dashboards are the exception, because they need more provider logic, so they stay as OpenTofu code (unless I find a better solution).

The malware advisory notification shows how this works in practice.

## Example: a Slack alert for new malware advisories

A malware advisory in the [GitHub Advisory Database](https://github.com/advisories) describes a package version that contains malicious code, such as a compromised npm release. A security team then needs to know whether it uses that package. Even without dependency data in the stack, a Slack notification is a good first step: it gives the team a signal to investigate and check whether the package is in their environment.

The [GitHub integration](https://www.elastic.co/docs/reference/integrations/github) already collects advisories into `logs-github.security_advisories-default`. The Agent policy runs three streams (reviewed, unreviewed, and malware), and all three write to the same data stream. I needed a detection rule and a Slack connector.

### The final rule

The GitHub Agent polls every 24 hours and ingests the full advisory list each time, so the rule needs to avoid repeating the same alert on the same advisory. It also needs to ignore old advisories on the first run. The final solution is a new terms rule that alerts only when a new `ghsa_id` appears in the last 14 days and only when the advisory was published in the last 7 days. Those numbers are arbitrary, but they are easy to adjust in the JSON if the team wants a longer or shorter window.

{{< alert "lightbulb" >}}
**Tip:** you do not have to wait for the next scheduled run to test a rule. In Kibana, disable the rule and enable it again. The rule runs right away, and you see the alert and the Slack message within seconds.
{{< /alert >}}

Here is the exact rule definition from `detection_rules/github-malware-advisory-published.json`:

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

The rule's `actions` block sends the message through the Slack connector defined in `connectors/github-security-advisories-slack.json`. The webhook URL is not in that file. It comes from a Git-ignored `.env` file and reaches Kibana through a write-only OpenTofu attribute, so it is not stored in the OpenTofu state.

### Two ES|QL rules to test the ingestion path

The malware rule was the main example, but I also wanted to test ES|QL rules. I added two ingestion health rules to cover the cases where the Agent no longer collects advisories. One alerts when GitHub or the ingest pipeline returns an error. The other alerts when one advisory stream ingests nothing for 26 hours.

## What the local stack does not cover

A local stack is a single node with a small amount of data. It will not show performance problems, shard sizing issues, or behavior that only appears with production volume. It also does not show how many alerts the team will receive in a busy week. Cross-cluster search, security roles, and network rules are outside its scope too.

For detection rules, mappings, and ingest changes, these limits are acceptable. Those changes depend on the data shape and the configuration, and both are the same locally.

## What comes next

This pattern is still small and intentionally focused. I will continue expanding it to other Elastic resources, especially workflows, so the same local test loop can cover more of the configuration surface before production.
