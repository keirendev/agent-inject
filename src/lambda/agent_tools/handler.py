"""
Bedrock Agent Action Group handler.

Routes incoming action group invocations to the appropriate tool function
and returns responses in the format Bedrock expects.
"""

import json
import logging
import os

from tools import (
    lookup_customer, check_refund_eligibility, process_refund,
    search_knowledge_base, update_customer_record, send_email,
    run_internal_query,
)

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Tool function registry
TOOLS = {
    "lookup_customer": lookup_customer,
    "check_refund_eligibility": check_refund_eligibility,
    "process_refund": process_refund,
    "search_knowledge_base": search_knowledge_base,
    "update_customer_record": update_customer_record,
    "send_email": send_email,
    "run_internal_query": run_internal_query,
}


def extract_parameters(event):
    """Extract parameters from Bedrock Agent event into a dict."""
    params = {}
    for param in event.get("parameters", []):
        params[param["name"]] = param["value"]
    return params


def build_response(event, body):
    """Build the response object Bedrock Agent expects.

    Supports both function-based and OpenAPI-based action groups:
    - Function schema: event has "function" key → response uses "function"
    - OpenAPI schema: event has "apiPath" key → response uses "apiPath" + "httpMethod"
    """
    body_str = json.dumps(body) if isinstance(body, dict) else str(body)

    # Detect format from the event — OpenAPI sends apiPath, function schema sends function
    if "apiPath" in event:
        return {
            "messageVersion": "1.0",
            "response": {
                "actionGroup": event.get("actionGroup", ""),
                "apiPath": event.get("apiPath", ""),
                "httpMethod": event.get("httpMethod", "POST"),
                "httpStatusCode": 200,
                "responseBody": {
                    "application/json": {
                        "body": body_str,
                    }
                },
            },
        }

    return {
        "messageVersion": "1.0",
        "response": {
            "actionGroup": event.get("actionGroup", ""),
            "function": event.get("function", ""),
            "functionResponse": {
                "responseBody": {
                    "TEXT": {
                        "body": body_str,
                    }
                }
            },
        },
    }


def lambda_handler(event, context):
    """Main Lambda entry point for Bedrock Agent Action Group."""
    # Support both function schema ("function" key) and OpenAPI schema ("apiPath" key)
    function_name = event.get("function", "")
    if not function_name and "apiPath" in event:
        # OpenAPI format: apiPath is like "/lookup_customer"
        function_name = event.get("apiPath", "").lstrip("/")
    parameters = extract_parameters(event)

    logger.info(
        "Tool invocation: function=%s parameters=%s",
        function_name,
        json.dumps(parameters),
    )

    tool_fn = TOOLS.get(function_name)
    if not tool_fn:
        logger.error("Unknown function: %s", function_name)
        result = {"error": f"Unknown function: {function_name}"}
        return build_response(event, result)

    try:
        result = tool_fn(parameters)
    except Exception:
        logger.exception("Error executing %s", function_name)
        result = {"error": f"Internal error executing {function_name}. Please try again."}

    logger.info(
        "Tool result: function=%s result=%s",
        function_name,
        json.dumps(result) if isinstance(result, dict) else str(result),
    )

    return build_response(event, result)
