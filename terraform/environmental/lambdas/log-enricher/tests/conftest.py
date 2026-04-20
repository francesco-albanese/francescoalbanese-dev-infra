import gzip
import json
import os
from unittest.mock import MagicMock

import boto3
import pytest
from moto import mock_aws

BUCKET_NAME = "test-analytics-bucket"
SNS_TOPIC_ARN = "arn:aws:sns:eu-west-2:123456789012:test-alerts"

CF_LOG_HEADER = (
    "#Version: 1.0\n"
    "#Fields: date time x-edge-location sc-bytes c-ip cs-method cs(Host) "
    "cs-uri-stem sc-status cs(Referer) cs(User-Agent) cs-uri-query cs(Cookie) "
    "x-edge-result-type x-edge-request-id x-host-header cs-protocol cs-bytes "
    "time-taken x-forwarded-for ssl-protocol ssl-cipher "
    "x-edge-response-result-type cs-protocol-version fle-status "
    "fle-encrypted-fields c-port time-to-first-byte "
    "x-edge-detailed-result-type sc-content-type sc-content-len "
    "sc-range-start sc-range-end\n"
)


def make_cf_log_line(
    date: str = "2026-04-14",
    time: str = "15:23:00",
    edge_location: str = "LHR62-C1",
    sc_bytes: str = "12345",
    c_ip: str = "203.0.113.1",
    method: str = "GET",
    host: str = "francescoalbanese.dev",
    uri_stem: str = "/",
    status: str = "200",
    referer: str = "https://linkedin.com/in/someone",
    user_agent: str = "Mozilla/5.0+(Windows+NT+10.0;+Win64;+x64)+Chrome/120.0.0.0",
    query: str = "-",
    cookie: str = "-",
    result_type: str = "Hit",
    request_id: str = "abc123",
    x_host: str = "francescoalbanese.dev",
    protocol: str = "https",
    cs_bytes: str = "500",
    time_taken: str = "0.001",
    forwarded_for: str = "-",
    ssl_protocol: str = "TLSv1.3",
    ssl_cipher: str = "TLS_AES_128_GCM_SHA256",
    edge_response_result: str = "Hit",
    protocol_version: str = "HTTP/2.0",
    fle_status: str = "-",
    fle_encrypted: str = "-",
    c_port: str = "54321",
    ttfb: str = "0.001",
    detailed_result: str = "Hit",
    content_type: str = "text/html",
    content_len: str = "12345",
    range_start: str = "-",
    range_end: str = "-",
) -> str:
    return "\t".join(
        [
            date,
            time,
            edge_location,
            sc_bytes,
            c_ip,
            method,
            host,
            uri_stem,
            status,
            referer,
            user_agent,
            query,
            cookie,
            result_type,
            request_id,
            x_host,
            protocol,
            cs_bytes,
            time_taken,
            forwarded_for,
            ssl_protocol,
            ssl_cipher,
            edge_response_result,
            protocol_version,
            fle_status,
            fle_encrypted,
            c_port,
            ttfb,
            detailed_result,
            content_type,
            content_len,
            range_start,
            range_end,
        ]
    )


def build_cf_log(lines: list[str]) -> str:
    return CF_LOG_HEADER + "\n".join(lines) + "\n"


@pytest.fixture
def mock_geoip_reader():
    reader = MagicMock()

    def city_lookup(ip: str):
        cities = {
            "203.0.113.1": ("London", "United Kingdom"),
            "203.0.113.2": ("London", "United Kingdom"),
            "203.0.113.3": ("London", "United Kingdom"),
            "203.0.113.4": ("London", "United Kingdom"),
            "198.51.100.1": ("New York", "United States"),
            "198.51.100.2": ("New York", "United States"),
            "198.51.100.3": ("New York", "United States"),
            "192.0.2.1": ("Berlin", "Germany"),
        }
        city_name, country_name = cities.get(ip, ("Unknown", "Unknown"))

        result = MagicMock()
        result.city.name = city_name
        result.country.name = country_name
        result.location.latitude = 51.5074 if city_name == "London" else 40.7128
        result.location.longitude = -0.1278 if city_name == "London" else -74.0060
        return result

    reader.city.side_effect = city_lookup
    return reader


@pytest.fixture
def aws_env(monkeypatch):
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_SECURITY_TOKEN", "testing")
    monkeypatch.setenv("AWS_SESSION_TOKEN", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "eu-west-2")
    monkeypatch.setenv("ANALYTICS_BUCKET", BUCKET_NAME)
    monkeypatch.setenv("SNS_TOPIC_ARN", SNS_TOPIC_ARN)
    monkeypatch.setenv("GEOIP_DB_PATH", "/tmp/fake.mmdb")


@pytest.fixture
def s3_client(aws_env):
    with mock_aws():
        client = boto3.client("s3", region_name="eu-west-2")
        client.create_bucket(
            Bucket=BUCKET_NAME,
            CreateBucketConfiguration={"LocationConstraint": "eu-west-2"},
        )
        yield client


@pytest.fixture
def sns_client(aws_env):
    with mock_aws():
        client = boto3.client("sns", region_name="eu-west-2")
        client.create_topic(Name="test-alerts")
        yield client


@pytest.fixture
def aws_clients(aws_env):
    with mock_aws():
        s3 = boto3.client("s3", region_name="eu-west-2")
        s3.create_bucket(
            Bucket=BUCKET_NAME,
            CreateBucketConfiguration={"LocationConstraint": "eu-west-2"},
        )
        sns = boto3.client("sns", region_name="eu-west-2")
        topic = sns.create_topic(Name="test-alerts")
        os.environ["SNS_TOPIC_ARN"] = topic["TopicArn"]
        yield s3, sns


def upload_cf_log(s3_client, key: str, log_content: str):
    compressed = gzip.compress(log_content.encode("utf-8"))
    s3_client.put_object(Bucket=BUCKET_NAME, Key=key, Body=compressed)


def make_s3_event(bucket: str, key: str) -> dict:
    return {
        "Records": [
            {
                "s3": {
                    "bucket": {"name": bucket},
                    "object": {"key": key},
                }
            }
        ]
    }


def get_enriched_records(s3_client, prefix: str = "enriched/") -> list[dict]:
    response = s3_client.list_objects_v2(Bucket=BUCKET_NAME, Prefix=prefix)
    records = []
    for obj in response.get("Contents", []):
        body = s3_client.get_object(Bucket=BUCKET_NAME, Key=obj["Key"])["Body"].read()
        for line in body.decode("utf-8").strip().split("\n"):
            if line:
                records.append(json.loads(line))
    return records
