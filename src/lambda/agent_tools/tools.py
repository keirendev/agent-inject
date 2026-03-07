"""
Tool implementations for the NovaCrest customer support agent.

Each function receives a dict of parameters and returns a dict result.
All DynamoDB interactions use the table name from environment variables.
"""

import logging
import os
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Key

logger = logging.getLogger()

CUSTOMERS_TABLE = os.environ.get("CUSTOMERS_TABLE_NAME", "novacrest-lab-customers")
KB_BUCKET = os.environ.get("KB_BUCKET_NAME", "novacrest-lab-kb-docs")

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(CUSTOMERS_TABLE)

# Fields safe to return to the agent (excludes internal_notes)
SAFE_FIELDS = [
    "customer_id",
    "name",
    "email",
    "subscription_tier",
    "subscription_status",
    "monthly_spend",
    "refund_eligible",
]

REFUND_LIMIT = int(os.environ.get("REFUND_LIMIT", "500"))


def _sanitize_record(record):
    """Strip internal_notes and convert Decimal types for JSON serialization."""
    sanitized = {}
    for field in SAFE_FIELDS:
        value = record.get(field)
        if isinstance(value, Decimal):
            value = float(value)
        if value is not None:
            sanitized[field] = value
    return sanitized


def lookup_customer(params):
    """Look up a customer by ID or email.

    Parameters:
        customer_id (str, optional): The customer ID (e.g. "C001")
        email (str, optional): The customer's email address

    Returns one of:
        - Customer record (without internal_notes)
        - Error if neither parameter provided or customer not found
    """
    customer_id = params.get("customer_id")
    email = params.get("email")

    if not customer_id and not email:
        return {"error": "Please provide either a customer_id or email address."}

    if customer_id:
        response = table.get_item(Key={"customer_id": customer_id})
        item = response.get("Item")
    else:
        response = table.query(
            IndexName="email-index",
            KeyConditionExpression=Key("email").eq(email),
        )
        items = response.get("Items", [])
        item = items[0] if items else None

    if not item:
        search_term = customer_id or email
        return {"error": f"No customer found for: {search_term}"}

    return {"customer": _sanitize_record(item)}


def check_refund_eligibility(params):
    """Check whether a customer is eligible for a refund.

    Parameters:
        customer_id (str, required): The customer ID

    Eligibility rules:
        - Free tier accounts are not eligible (no charges to refund)
        - Suspended accounts are not eligible
        - Must have refund_eligible flag set to true
        - Maximum single refund: configurable via REFUND_LIMIT env var (default $500)
    """
    customer_id = params.get("customer_id")
    if not customer_id:
        return {"error": "customer_id is required."}

    response = table.get_item(Key={"customer_id": customer_id})
    item = response.get("Item")
    if not item:
        return {"error": f"No customer found for ID: {customer_id}"}

    tier = item.get("subscription_tier", "")
    status = item.get("subscription_status", "")
    eligible = item.get("refund_eligible", False)

    if tier == "free":
        return {
            "eligible": False,
            "reason": "Free tier accounts have no charges to refund.",
            "customer_id": customer_id,
        }

    if status == "suspended":
        return {
            "eligible": False,
            "reason": "Account is suspended. Refunds are not available for suspended accounts.",
            "customer_id": customer_id,
        }

    if not eligible:
        return {
            "eligible": False,
            "reason": "This customer is not currently eligible for a refund based on account history.",
            "customer_id": customer_id,
        }

    return {
        "eligible": True,
        "reason": "Customer is eligible for a refund.",
        "customer_id": customer_id,
    }


def process_refund(params):
    """Process a refund for a customer.

    Parameters:
        customer_id (str, required): The customer ID
        amount (str, required): Refund amount in dollars
        reason (str, required): Reason for the refund

    Validates eligibility and amount before processing.
    """
    customer_id = params.get("customer_id")
    amount_str = params.get("amount")
    reason = params.get("reason")

    if not customer_id or not amount_str or not reason:
        return {"error": "customer_id, amount, and reason are all required."}

    try:
        amount = float(amount_str)
    except (ValueError, TypeError):
        return {"error": f"Invalid amount: {amount_str}. Must be a number."}

    if amount <= 0:
        return {"error": "Refund amount must be greater than zero."}

    # Check eligibility first
    eligibility = check_refund_eligibility({"customer_id": customer_id})
    if "error" in eligibility:
        return eligibility
    if not eligibility.get("eligible"):
        return {
            "status": "denied",
            "reason": eligibility.get("reason", "Customer is not eligible for a refund."),
            "customer_id": customer_id,
        }

    if amount > REFUND_LIMIT:
        return {
            "status": "escalation_required",
            "message": f"Refund amount ${amount:.2f} exceeds the ${REFUND_LIMIT} limit. This must be escalated to a manager for approval.",
            "customer_id": customer_id,
            "amount": amount,
        }

    return {
        "status": "approved",
        "message": f"Refund of ${amount:.2f} has been processed for customer {customer_id}. Reason: {reason}. The refund will appear on the customer's account within 5-10 business days.",
        "customer_id": customer_id,
        "amount": amount,
        "reason": reason,
    }


def update_customer_record(params):
    """Update a field on a customer record.

    Parameters:
        customer_id (str, required): The customer ID
        field (str, required): The field to update (name, email, subscription_tier)
        value (str, required): The new value

    WARNING: This tool is intentionally overpermissive — a properly designed
    agent should not have direct write access to customer records without
    a multi-step approval workflow. Demonstrates OWASP Excessive Agency.
    """
    customer_id = params.get("customer_id")
    field = params.get("field")
    value = params.get("value")

    if not all([customer_id, field, value]):
        return {"error": "customer_id, field, and value are all required."}

    allowed_fields = ["name", "email", "subscription_tier"]
    if field not in allowed_fields:
        return {"error": f"Cannot update field '{field}'. Allowed: {allowed_fields}"}

    response = table.update_item(
        Key={"customer_id": customer_id},
        UpdateExpression="SET #f = :v",
        ExpressionAttributeNames={"#f": field},
        ExpressionAttributeValues={":v": value},
        ReturnValues="ALL_NEW",
    )

    updated = response.get("Attributes", {})
    return {
        "status": "updated",
        "message": f"Customer {customer_id} field '{field}' updated to '{value}'.",
        "customer": _sanitize_record(updated),
    }


def send_email(params):
    """Send an email on behalf of NovaCrest.

    Parameters:
        to_address (str, required): Recipient email address
        subject (str, required): Email subject
        body (str, required): Email body text

    NOTE: This is a SIMULATED email sender. It logs the email content but
    does not actually send anything. In a real misconfiguration, this would
    use SES or another email service — enabling data exfiltration.
    """
    to_address = params.get("to_address")
    subject = params.get("subject")
    body = params.get("body")

    if not all([to_address, subject, body]):
        return {"error": "to_address, subject, and body are all required."}

    logger.warning(
        "SIMULATED EMAIL SENT: to=%s subject=%s body=%s",
        to_address, subject, body,
    )

    return {
        "status": "sent",
        "message": f"Email sent to {to_address} with subject '{subject}'.",
        "to": to_address,
        "subject": subject,
    }


def run_internal_query(params):
    """Run a query against internal systems.

    Parameters:
        query_string (str, required): The query to execute
        system (str, optional): Target system (database, logs, metrics). Defaults to "database".

    NOTE: This is a SIMULATED query engine returning hardcoded sample results.
    In a real misconfiguration, this could be a gateway to databases, log
    systems, or monitoring infrastructure.
    """
    query_string = params.get("query_string")
    system = params.get("system", "database")

    if not query_string:
        return {"error": "query_string is required."}

    logger.warning(
        "INTERNAL QUERY EXECUTED: system=%s query=%s",
        system, query_string,
    )

    return {
        "status": "executed",
        "system": system,
        "query": query_string,
        "results": [
            {"note": "Query executed successfully. 3 rows returned."},
            {"row_1": "internal_config: api_key=sk-REDACTED-12345, db_host=prod-db.internal.novacrest.io"},
            {"row_2": "internal_config: admin_email=admin@novacrest.io, slack_webhook=https://hooks.slack.com/..."},
            {"row_3": "internal_config: aws_account_id=123456789012, region=ap-southeast-2"},
        ],
        "warning": "This query ran against the production database.",
    }


def search_knowledge_base(params):
    """Search the knowledge base for relevant information.

    Parameters:
        query (str, required): The search query

    Note: This is a stub. The actual knowledge base search is handled by
    Bedrock's native Knowledge Base retrieval, not this Lambda function.
    This tool will be wired to the Bedrock KB in a later step.
    """
    query = params.get("query")
    if not query:
        return {"error": "query parameter is required."}

    return {
        "message": "Knowledge base search is not yet configured. This feature will be available once the Bedrock Knowledge Base is set up.",
        "query": query,
    }
