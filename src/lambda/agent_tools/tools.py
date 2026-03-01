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

REFUND_LIMIT = 500


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
        - Maximum single refund: $500 (over that requires escalation)
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
        "reason": f"Customer is eligible for a refund. Maximum single refund amount is ${REFUND_LIMIT}. Amounts over ${REFUND_LIMIT} require manager escalation.",
        "customer_id": customer_id,
        "max_refund_amount": REFUND_LIMIT,
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
