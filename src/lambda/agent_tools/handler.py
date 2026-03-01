"""
Bedrock Agent Action Group handler.

Routes incoming action group invocations to the appropriate tool function
and returns responses in the format Bedrock expects.
"""

import json
import logging
import os

from tools import lookup_customer, check_refund_eligibility, process_refund, search_knowledge_base

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Tool function registry
TOOLS = {
    "lookup_customer": lookup_customer,
    "check_refund_eligibility": check_refund_eligibility,
    "process_refund": process_refund,
    "search_knowledge_base": search_knowledge_base,
}


def extract_parameters(event):
    """Extract parameters from Bedrock Agent event into a dict."""
    params = {}
    for param in event.get("parameters", []):
        params[param["name"]] = param["value"]
    return params


def build_response(event, body):
    """Build the response object Bedrock Agent expects."""
    return {
        "messageVersion": "1.0",
        "response": {
            "actionGroup": event.get("actionGroup", ""),
            "function": event.get("function", ""),
            "functionResponse": {
                "responseBody": {
                    "TEXT": {
                        "body": json.dumps(body) if isinstance(body, dict) else str(body)
                    }
                }
            },
        },
    }


def lambda_handler(event, context):
    """Main Lambda entry point for Bedrock Agent Action Group."""
    function_name = event.get("function", "")
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
