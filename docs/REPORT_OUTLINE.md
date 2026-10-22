# Report outline (3 to 5 pages)

Fill in the bracketed parts with your own screenshots and numbers after you deploy.

## 1. Problem and solution (about 1/2 page)
- Who: a small business or freelancer whose only "contact" option is a personal email address.
- Problem: inquiries get lost, there's no record, nothing notifies them quickly.
- Solution: a form that stores every inquiry and notifies the owner immediately.
- Architecture diagram (copy from README) with your name visible.

## 2. Evidence it runs (about 1/2 page)
- Screenshot: CloudFormation stack `CREATE_COMPLETE`.
- Screenshot: the live form submitted.
- Screenshot: the DynamoDB item.
- Screenshot: the email received (your name is in the footer).
- Screenshot: `smoke-test.sh` output showing the duplicate and 400 cases.
- Link to the repo, with `template.yaml` committed.

## 3. Service justification (about 1 to 1.5 pages, worth 20 points)

For each, say what it does, the alternative you rejected, and why.

| Service | Chosen because | Rejected alternative | Why rejected |
|---|---|---|---|
| S3 static site | No server to run, pennies per month | EC2 + nginx, or Amplify | EC2 costs idle time and needs patching; Amplify hides the architecture |
| API Gateway HTTP API | Cheaper and simpler than REST API; built-in CORS and throttling | REST API; Lambda Function URL | REST API costs more and has features unused here; Function URL has no throttling |
| Lambda | Runs only when a form is submitted | EC2 or a Fargate container | Idle cost and patching for a tiny workload |
| DynamoDB (on-demand) | Key-value access pattern, no capacity planning, TTL built in | RDS | Always-on cost and ops for one simple table |
| SES | Real formatted email, Reply-To the visitor | SNS email | SNS cannot format the message or set Reply-To |

Also mention: why CloudFormation and not Terraform (no extra tool, native to AWS).

## 4. Security, reliability, performance, cost (about 1.5 pages, specifics not adjectives)

**Security**
- Lambda role is least privilege: `dynamodb:PutItem`/`UpdateItem` on one table, `ses:SendEmail` on one identity.
- Input validation and length limits; request body capped at 10 KB.
- CR/LF stripped from the name before it goes into an email subject (header injection).
- Honeypot field to turn away simple bots.
- CORS locked to the site's own origin.
- Data minimization: inquiries auto-delete after 90 days (DynamoDB TTL).
- Honest gap: the S3 site is public HTTP (no HTTPS or WAF).

**Reliability**
- Idempotency: the browser sends a request id, and DynamoDB's conditional write means a double submit never creates or emails twice.
- Save first, notify second: if SES fails, the inquiry is already stored and flagged `NOTIFY_FAILED`.
- Managed, multi-AZ services, no servers to fail.
- Honest gap: no automatic retry of failed notifications (a DLQ or a retry sweep would add it).

**Performance**
- [Measured] Lambda duration and end-to-end submit time from CloudWatch (take real numbers).
- HTTP API adds low latency compared to REST API.
- Honest gap: cold starts add a few hundred ms on the first request.

**Cost**
- Show a per-1,000-inquiries estimate: Lambda, API Gateway, DynamoDB and S3 are within or near the free tier; SES is about $0.10 per 1,000 emails.
- Cost controls: log retention set to 14 days, API throttle of 5 requests/second, on-demand DynamoDB.
- Say why SMS is not built (per-message cost plus number registration).

## 5. Well-Architected self-review (about 1/2 page)

Pick three pillars. A strength and an honest weakness for each. Suggested:

| Pillar | Strength | Weakness |
|---|---|---|
| Security | Least-privilege IAM and input validation | Site is HTTP-only; no WAF or CAPTCHA |
| Reliability | Idempotent writes; save before notify | No automatic retry for failed emails |
| Cost Optimization | Everything scales to zero and stays in the free tier | SMS would add real per-message cost |

## 6. Extension: text messages (a few sentences)
- Lambda would publish to SNS SMS after the SES email.
- Tradeoffs: per-message cost, US origination-number registration, opt-out handling.
- Why it was left as an extension.

## Bonus: 5-minute walkthrough
Record: the architecture diagram, submit the form, show the email, the DynamoDB item,
the CloudFormation stack. Point out the rejected alternatives.
