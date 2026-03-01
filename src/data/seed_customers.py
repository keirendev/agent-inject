#!/usr/bin/env python3
"""
Populate the NovaCrest customers DynamoDB table with fake data.

Usage:
    python3 seed_customers.py [--table-name TABLE] [--region REGION]

Defaults to novacrest-lab-customers in ap-southeast-2.
"""

import argparse
import json
import sys
from decimal import Decimal
from pathlib import Path

import boto3


def load_customers(path: Path) -> list[dict]:
    """Load customer records from JSON, converting floats to Decimal for DynamoDB."""
    with open(path) as f:
        records = json.load(f, parse_float=Decimal)
    return records


def seed_table(table_name: str, region: str, records: list[dict]) -> None:
    """Write customer records to DynamoDB using batch_write_item."""
    dynamodb = boto3.resource("dynamodb", region_name=region)
    table = dynamodb.Table(table_name)

    with table.batch_writer() as batch:
        for record in records:
            batch.put_item(Item=record)

    print(f"Loaded {len(records)} customers into {table_name}")


def main():
    parser = argparse.ArgumentParser(description="Seed NovaCrest customer data")
    parser.add_argument(
        "--table-name",
        default="novacrest-lab-customers",
        help="DynamoDB table name (default: novacrest-lab-customers)",
    )
    parser.add_argument(
        "--region",
        default="ap-southeast-2",
        help="AWS region (default: ap-southeast-2)",
    )
    args = parser.parse_args()

    customers_file = Path(__file__).parent / "customers.json"
    if not customers_file.exists():
        print(f"Error: {customers_file} not found", file=sys.stderr)
        sys.exit(1)

    records = load_customers(customers_file)
    seed_table(args.table_name, args.region, records)


if __name__ == "__main__":
    main()
