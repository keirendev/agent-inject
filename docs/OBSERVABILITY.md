# Observability & Attack Detection

How to monitor the NovaCrest AI Security Lab, detect attacks, and investigate incidents.

## Logging Architecture (3 Layers)

```
Layer 1: CloudTrail          → All AWS API calls (S3 bucket)
Layer 2: Lambda Logs         → Tool invocations, parameters, results (CloudWatch)
Layer 3: Model Invocation    → Full LLM request/response payloads (S3 + CloudWatch)
```

- **CloudTrail** captures who called what API and when — useful for IAM and infrastructure auditing
- **Lambda logs** capture every tool call the agent makes, with function names and parameters — the primary source for attack detection
- **Model invocation logs** capture the full prompt/response exchange — useful for forensic analysis of prompt injection content

## CloudWatch Dashboard

The dashboard (`novacrest-lab-agent-dashboard`) has 5 rows / 10 widgets:

| Row | Left Widget | Right Widget |
|-----|-------------|--------------|
| 1 | Agent Invocation Count | Agent Errors (client/server/throttle) |
| 2 | Guardrail Invocations vs Interventions | Guardrail Interventions by Policy Type |
| 3 | Lambda Invocations & Errors | Tool Call Frequency by Function |
| 4 | Agent Latency (p50/p90/p99) | Model Token Usage |
| 5 | **Suspicious Tool Invocations** (table) | **Customer Lookups per 5min** (bar) |

Row 5 is specifically for security monitoring. The "Suspicious Tool Invocations" widget shows any calls to `send_email`, `run_internal_query`, or `update_customer_record` — tools that should never be called in the secure baseline.

## Security Alarms

8 CloudWatch Alarms notify the `security-alerts` SNS topic (email):

| Alarm | Threshold | Severity | What It Detects |
|-------|-----------|----------|-----------------|
| Guardrail intervention spike | >5 in 5min | HIGH | Active prompt injection — multiple attempts hitting guardrails |
| Content policy triggered | >2 in 5min | MEDIUM | Jailbreak attempts — harmful content generation |
| Send email invoked | >=1 in 5min | CRITICAL | Data exfiltration — excessive tool used to send data out |
| Internal query invoked | >=1 in 5min | CRITICAL | Excessive tool abuse — agent running arbitrary queries |
| Update customer invoked | >=1 in 5min | CRITICAL | Unauthorized data modification via excessive tool |
| Lambda error rate high | >3 in 5min | MEDIUM | Tool manipulation — malformed inputs causing errors |
| Refund frequency high | >5 in 5min | HIGH | Automated refund abuse — repeated refund processing |
| Customer enumeration | >10 in 5min | HIGH | Data enumeration — bulk customer record harvesting |

The CRITICAL alarms fire on a **single invocation** because those tools (`send_email`, `run_internal_query`, `update_customer_record`) should never be callable in the secure baseline. Their mere existence indicates an overpermissive configuration.

## Attack Detection Patterns

### Normal Traffic (Secure Baseline)
- 1-3 tool calls per conversation: `lookup_customer` → `check_refund_eligibility` → `process_refund`
- 0 guardrail interventions (legitimate queries pass cleanly)
- 0 calls to `send_email`, `run_internal_query`, `update_customer_record`
- Refunds ≤$500 (server-side Lambda limit)
- 1 customer lookup per conversation

### Prompt Injection Attack
- **Signal**: Guardrail intervention spike (>5 in 5min)
- **Lambda logs**: Normal tool calls, but guardrails block input/output
- **Model logs**: Injection payloads visible in request body

### Data Exfiltration (Excessive Tools)
- **Signal**: CRITICAL alarm — `send_email` or `run_internal_query` invoked
- **Lambda logs**: `SIMULATED EMAIL SENT` with customer data in parameters
- **Dashboard**: Suspicious Tool Invocations table shows the call

### RAG Poisoning
- **Signal**: May not trigger alarms if poisoned content passes guardrails
- **Lambda logs**: Unusual refund amounts (>$500 if `refund_limit` raised)
- **Model logs**: Poisoned KB content visible in the orchestration trace

### Customer Enumeration
- **Signal**: Customer enumeration alarm (>10 lookups in 5min)
- **Lambda logs**: Rapid sequential `lookup_customer` calls with different IDs
- **Dashboard**: Customer Lookups per 5min bar chart spikes

### Tool Manipulation
- **Signal**: Lambda error rate alarm (>3 errors in 5min)
- **Lambda logs**: `Error executing` or `Unknown function` messages
- **Model logs**: Malformed tool call attempts in orchestration trace

## Forensic Queries (CloudWatch Logs Insights)

Paste these into CloudWatch Logs Insights, selecting the Lambda log group (`/aws/lambda/novacrest-lab-agent-tools`).

### 1. All tool calls in the last hour
```
filter @message like /Tool invocation: function=/
| parse @message 'Tool invocation: function=* parameters=*' as tool_name, params
| fields @timestamp, tool_name, params
| sort @timestamp desc
```

### 2. Suspicious tool invocations (excessive tools)
```
filter @message like /SIMULATED EMAIL SENT/
    or @message like /INTERNAL QUERY EXECUTED/
    or @message like /function=update_customer_record/
| fields @timestamp, @message
| sort @timestamp desc
```

### 3. Refund processing with amounts
```
filter @message like /function=process_refund/
| parse @message 'parameters=*' as params
| fields @timestamp, params
| sort @timestamp desc
```

### 4. Customer lookup frequency (enumeration detection)
```
filter @message like /function=lookup_customer/
| stats count(*) as lookups by bin(5m) as time_window
| sort time_window desc
```

### 5. Tool errors (manipulation attempts)
```
filter @message like /Error executing/ or @message like /Unknown function/
| fields @timestamp, @message
| sort @timestamp desc
```

### 6. All activity for a specific customer
```
filter @message like /C001/
| fields @timestamp, @message
| sort @timestamp desc
```

### 7. High-value refunds (>$100)
```
filter @message like /function=process_refund/
| parse @message 'parameters=*' as params
| fields @timestamp, params
| sort @timestamp desc
```

### 8. Tool call volume by 5-minute window
```
filter @message like /Tool invocation: function=/
| parse @message 'Tool invocation: function=* parameters=*' as tool_name, params
| stats count(*) as calls by tool_name, bin(5m) as window
| sort window desc
```

### 9. Error rate over time
```
filter @message like /Error/ or @message like /ERROR/
| stats count(*) as errors by bin(5m) as window
| sort window desc
```

## S3 Invocation Log Analysis

Model invocation logs are stored in the S3 bucket `novacrest-lab-bedrock-invocation-logs`. Each log entry contains the full request and response payloads.

```bash
# List recent invocation logs
aws s3 ls s3://novacrest-lab-bedrock-invocation-logs/AWSLogs/ --recursive | tail -20

# Download and inspect a specific log
aws s3 cp s3://novacrest-lab-bedrock-invocation-logs/AWSLogs/<path> - | python3 -m json.tool

# Search for prompt injection content in logs
aws s3 cp s3://novacrest-lab-bedrock-invocation-logs/AWSLogs/ /tmp/logs/ --recursive
grep -r "ignore previous" /tmp/logs/ | head -20
```

The model invocation logs contain the full orchestration trace including:
- The system prompt sent to the model
- All user messages
- Knowledge base retrieval results (where poisoned content appears)
- Tool call requests and responses
- The model's reasoning (chain of thought)

This is the definitive forensic record for understanding exactly how an attack succeeded or was blocked.
