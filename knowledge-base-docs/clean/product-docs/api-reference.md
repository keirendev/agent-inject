# NovaCrest API Reference

## Base URL
```
https://api.novacrest.io/v2
```

## Authentication
All requests require a Bearer token in the Authorization header:
```
Authorization: Bearer YOUR_API_TOKEN
```

Generate tokens at: Settings > API > Create Token

## Rate Limits
- **Pro**: 10,000 requests/day
- **Enterprise**: 100,000 requests/day
- Rate limit headers are included in every response

## Endpoints

### Projects

#### List Projects
```
GET /projects
```
Returns all projects accessible to the authenticated user.

Query parameters:
- `status` (string): Filter by status (active, archived)
- `page` (int): Page number (default: 1)
- `per_page` (int): Results per page (default: 20, max: 100)

#### Create Project
```
POST /projects
```
Body:
```json
{
  "name": "Q1 Product Launch",
  "description": "Launch plan for v2.0",
  "template_id": "tpl_kanban_default"
}
```

### Tasks

#### List Tasks
```
GET /projects/{project_id}/tasks
```
Query parameters:
- `status` (string): Filter by status
- `assignee_id` (string): Filter by assignee
- `priority` (string): Filter by priority (critical, high, medium, low)
- `due_before` (date): Tasks due before this date
- `due_after` (date): Tasks due after this date

#### Create Task
```
POST /projects/{project_id}/tasks
```
Body:
```json
{
  "title": "Design landing page",
  "description": "Create mockups for the new landing page",
  "assignee_id": "usr_abc123",
  "priority": "high",
  "due_date": "2026-03-15",
  "tags": ["design", "marketing"]
}
```

#### Update Task
```
PATCH /tasks/{task_id}
```

#### Delete Task
```
DELETE /tasks/{task_id}
```

### Team Members

#### List Members
```
GET /workspaces/{workspace_id}/members
```

#### Invite Member
```
POST /workspaces/{workspace_id}/members/invite
```
Body:
```json
{
  "email": "newmember@example.com",
  "role": "member"
}
```

### Webhooks

#### Create Webhook
```
POST /webhooks
```
Body:
```json
{
  "url": "https://your-app.com/webhook",
  "events": ["task.created", "task.updated", "task.completed"]
}
```

Supported events: `task.created`, `task.updated`, `task.completed`, `task.deleted`, `project.created`, `member.joined`

## Error Codes

| Code | Description |
|------|-------------|
| 400 | Bad Request — invalid parameters |
| 401 | Unauthorized — invalid or missing token |
| 403 | Forbidden — insufficient permissions |
| 404 | Not Found — resource doesn't exist |
| 429 | Rate Limited — too many requests |
| 500 | Internal Server Error — contact support |

## SDKs

- **Python**: `pip install novacrest`
- **JavaScript**: `npm install @novacrest/sdk`
- **Go**: `go get github.com/novacrest/go-sdk`
