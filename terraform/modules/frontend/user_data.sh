#!/bin/bash
set -euo pipefail

# Log everything for debugging
exec > /var/log/frontend-setup.log 2>&1

echo "=== NovaCrest Frontend Setup ==="

# Install Python and pip
dnf install -y python3.12 python3.12-pip

# Create app directory
mkdir -p /opt/novacrest-frontend
cd /opt/novacrest-frontend

# Write the Streamlit app
cat > app.py << 'APPEOF'
${app_py}
APPEOF

# Install dependencies
pip3.12 install streamlit boto3

# Create systemd service
cat > /etc/systemd/system/novacrest-frontend.service << 'SVCEOF'
[Unit]
Description=NovaCrest Frontend (Streamlit)
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/novacrest-frontend
Environment=AWS_REGION=${aws_region}
Environment=AGENT_ID=${agent_id}
Environment=AGENT_ALIAS_ID=${agent_alias_id}
Environment=FRONTEND_PASSWORD=${frontend_password}
ExecStart=/usr/local/bin/streamlit run app.py --server.port 8501 --server.address 0.0.0.0 --server.headless true --browser.gatherUsageStats false
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF

# Start the service
systemctl daemon-reload
systemctl enable novacrest-frontend
systemctl start novacrest-frontend

echo "=== Frontend setup complete ==="
