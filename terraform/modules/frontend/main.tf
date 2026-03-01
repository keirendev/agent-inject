# -----------------------------------------------------------------------------
# Frontend module - EC2 instance running Streamlit chat UI
#
# Creates:
#   - IAM role + instance profile for EC2 (bedrock:InvokeAgent only)
#   - EC2 instance (Amazon Linux 2023, t3.micro) in public subnet
#   - User data script installs dependencies and starts Streamlit
#
# Access is restricted to operator IP via the frontend security group
# (created by the networking module). Port 8501 (Streamlit default).
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  frontend_name = "${var.project_name}-${var.environment}-frontend"
}

# =============================================================================
# IAM Role for EC2 - scoped to InvokeAgent only
# =============================================================================

resource "aws_iam_role" "frontend" {
  name = "${local.frontend_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${local.frontend_name}-role"
  }
}

resource "aws_iam_role_policy" "frontend_permissions" {
  name = "${local.frontend_name}-permissions"
  role = aws_iam_role.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeBedrockAgent"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeAgent",
        ]
        Resource = "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:agent-alias/${var.agent_id}/*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "frontend" {
  name = "${local.frontend_name}-profile"
  role = aws_iam_role.frontend.name
}

# =============================================================================
# EC2 Instance - Amazon Linux 2023 with Streamlit
# =============================================================================

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_instance" "frontend" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.frontend.name
  associate_public_ip_address = true

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    aws_region        = var.aws_region
    agent_id          = var.agent_id
    agent_alias_id    = var.agent_alias_id
    frontend_password = var.frontend_password
    app_py            = file("${path.module}/../../../src/frontend/app.py")
  }))

  tags = {
    Name = local.frontend_name
  }
}
