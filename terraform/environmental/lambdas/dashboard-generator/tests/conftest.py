import json
from datetime import UTC, datetime, timedelta

import boto3
import pytest
from moto import mock_aws

BUCKET_NAME = "test-analytics-bucket"


def make_record(
    timestamp: str = "2026-04-14T15:23:00Z",
    client_ip: str = "203.0.113.1",
    city: str = "London",
    country: str = "United Kingdom",
    rdns: str = "",
    path: str = "/",
    referer: str = "https://linkedin.com/in/someone",
    user_agent: str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0",
    status: int = 200,
    bytes_sent: int = 12345,
    method: str = "GET",
) -> dict:
    return {
        "timestamp": timestamp,
        "client_ip": client_ip,
        "city": city,
        "country": country,
        "rdns": rdns,
        "path": path,
        "referer": referer,
        "user_agent": user_agent,
        "status": status,
        "bytes_sent": bytes_sent,
        "method": method,
    }


def upload_enriched_records(s3_client, date_str: str, records: list[dict], suffix: str = "data"):
    year, month, day = date_str.split("-")
    key = f"enriched/{year}/{month}/{day}/{suffix}.jsonl"
    body = "\n".join(json.dumps(r) for r in records)
    s3_client.put_object(Bucket=BUCKET_NAME, Key=key, Body=body.encode("utf-8"))


@pytest.fixture
def aws_env(monkeypatch):
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_SECURITY_TOKEN", "testing")
    monkeypatch.setenv("AWS_SESSION_TOKEN", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "eu-west-2")
    monkeypatch.setenv("ANALYTICS_BUCKET", BUCKET_NAME)


@pytest.fixture
def s3_client(aws_env):
    with mock_aws():
        client = boto3.client("s3", region_name="eu-west-2")
        client.create_bucket(
            Bucket=BUCKET_NAME,
            CreateBucketConfiguration={"LocationConstraint": "eu-west-2"},
        )
        yield client


def date_str(days_ago: int = 0) -> str:
    return (datetime.now(UTC) - timedelta(days=days_ago)).strftime("%Y-%m-%d")


def timestamp_str(days_ago: int = 0, hour: int = 15) -> str:
    dt = datetime.now(UTC) - timedelta(days=days_ago)
    return dt.replace(hour=hour, minute=0, second=0).strftime("%Y-%m-%dT%H:%M:%SZ")
