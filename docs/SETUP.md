# Environment Setup Guide

Step-by-step guide to setting up the development environment for the NovaCrest AI Security Lab.

## Prerequisites

| Tool | Minimum Version | Purpose |
|------|----------------|---------|
| AWS CLI | v2.x | Interact with AWS services |
| Terraform | v1.5+ | Infrastructure as Code |
| Python | 3.11+ | Lambda functions, scripts, frontend |
| pip | 24.x+ | Python package management |
| git | 2.x | Version control |
| gh | 2.x | GitHub CLI for issues/PRs |

## 1. Install Tools

### AWS CLI v2 (Linux)

```bash
cd /tmp
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip
aws --version
```

For macOS:
```bash
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /
```

### Terraform (Linux — Ubuntu/Debian)

```bash
wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install terraform
terraform --version
```

For macOS:
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

### Python 3.11+

Most systems have Python 3.11+ already. Check with:
```bash
python3 --version
```

If not installed (Ubuntu/Debian):
```bash
sudo apt install python3 python3-pip python3-venv
```

## 2. AWS Account Setup

### Create an IAM User

1. Log into the [AWS Console](https://console.aws.amazon.com)
2. Go to **IAM** > **Users** > **Create user**
3. Name: `lab-operator`
4. Attach policy: **AdministratorAccess** (will be scoped down later via a dedicated `lab-admin` role in Terraform)
5. Create the user, then go to **Security credentials** > **Create access key**
6. Choose **Command Line Interface (CLI)** and create the key
7. Copy both the **Access Key ID** and **Secret Access Key**

### Configure AWS CLI

```bash
aws configure
```

Enter:
- **Access Key ID**: your key
- **Secret Access Key**: your secret
- **Default region**: your preferred region (e.g., `ap-southeast-2` or `us-east-1`)
- **Default output format**: `json`

Verify:
```bash
aws sts get-caller-identity
```

Should return your account ID and user ARN.

### Enable MFA (Recommended)

In the AWS Console, go to **IAM** > **Users** > your user > **Security credentials** > **Assign MFA device**.

## 3. Enable Bedrock Model Access

You must explicitly enable each model in the AWS Console:

1. Go to **Amazon Bedrock** in the AWS Console (ensure correct region)
2. Click **Model access** in the left sidebar
3. Click **Manage model access**
4. Enable:
   - **Amazon Nova Lite** (primary testing model — cheap)
   - **Amazon Nova Micro** (cheapest, for iteration)
   - **Amazon Titan Text Embeddings V2** (for the knowledge base vector store)
   - **Anthropic Claude Sonnet** (for final validation runs)
5. Click **Save changes**

Model access is usually granted within minutes but can take up to 24 hours.

### Verify Model Access

```bash
echo '{"inferenceConfig":{"maxTokens":10},"messages":[{"role":"user","content":[{"text":"hi"}]}]}' | \
  base64 -w0 | \
  xargs -I {} aws bedrock-runtime invoke-model \
    --model-id amazon.nova-micro-v1:0 \
    --body '{}' \
    --content-type application/json \
    --accept application/json \
    /tmp/bedrock-test.json && \
  cat /tmp/bedrock-test.json
```

You should see a JSON response with `"stopReason":"max_tokens"`.

## 4. Clone and Configure the Repo

```bash
git clone git@github.com:keirendev/agent-inject.git
cd agent-inject
cp .env.example .env
# Edit .env with your values:
#   - AWS_REGION: your region
#   - AWS_ACCOUNT_ID: from `aws sts get-caller-identity`
#   - OPERATOR_IP: from `curl -s https://checkip.amazonaws.com`
```

## 5. Supported Regions

Bedrock is available in multiple regions. This lab has been tested with:

| Region | Code | Notes |
|--------|------|-------|
| Sydney | `ap-southeast-2` | Primary development region |
| N. Virginia | `us-east-1` | Widest model selection |

Choose a region where all required models (Nova, Titan Embeddings, Claude) are available.
