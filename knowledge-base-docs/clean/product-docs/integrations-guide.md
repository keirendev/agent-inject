# NovaCrest Integrations Guide

## Slack Integration

### Setup
1. Go to Settings > Integrations > Slack
2. Click "Connect to Slack"
3. Authorize NovaCrest in your Slack workspace
4. Choose which channels receive notifications

### Features
- **Task notifications**: Get alerts when tasks are created, assigned, or completed
- **Create tasks from Slack**: Use `/novacrest create` to create tasks from any channel
- **Status updates**: Post project status summaries to channels on a schedule
- **Link previews**: Paste a NovaCrest URL in Slack to see a rich preview

## GitHub Integration

### Setup
1. Go to Settings > Integrations > GitHub
2. Click "Connect to GitHub"
3. Select the repositories to link

### Features
- **Link PRs to tasks**: Reference a task ID in your PR title or description (e.g., `NC-123`)
- **Auto-status updates**: When a PR is merged, the linked task moves to "Done"
- **Branch creation**: Create a branch directly from a NovaCrest task
- **Commit tracking**: See all commits related to a task in the task detail view

## Google Workspace Integration

### Setup
1. Go to Settings > Integrations > Google Workspace
2. Sign in with your Google account
3. Grant permissions for Calendar and Drive

### Features
- **Google Calendar sync**: Task due dates appear on your Google Calendar
- **Google Drive attachments**: Attach Drive files directly to tasks
- **Google Meet links**: Generate meeting links from task detail views

## Zapier Integration

Connect NovaCrest to 5,000+ apps with no-code automations.

### Popular Zaps
- **Gmail > NovaCrest**: Create a task when you receive an email from a specific sender
- **NovaCrest > Google Sheets**: Log completed tasks to a spreadsheet
- **GitHub Issues > NovaCrest**: Sync GitHub issues as NovaCrest tasks
- **NovaCrest > Slack**: Custom notification rules beyond the native integration

### Setup
1. Create a Zapier account at zapier.com
2. Search for "NovaCrest" in the app directory
3. Connect your NovaCrest account using an API token
4. Build your Zap using triggers and actions

## Webhook Configuration

For custom integrations, use webhooks to receive real-time events.

See the [API Reference](api-reference.md) for webhook setup details.
