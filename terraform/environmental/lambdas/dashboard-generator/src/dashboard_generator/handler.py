import json
import logging
import os
import re
from collections import defaultdict
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import TypedDict, cast
from urllib.parse import urlparse

import boto3
from botocore.config import Config

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

BUCKET = os.environ.get("ANALYTICS_BUCKET", "")
DASHBOARD_WINDOW_DAYS = 14
PRESIGN_EXPIRY_SECONDS = 3600

s3 = boto3.client("s3")
s3_presign = boto3.client("s3", config=Config(signature_version="s3v4"))

STATIC_ASSET_PATTERNS = re.compile(
    r"(?i)("
    r"^/_astro/|\.css$|\.js$|\.png$|\.svg$|\.woff2$|\.webp$|\.ico$|"
    r"^/favicon|^/robots\.txt$|^/sitemap|^/manifest|^/sw\.js$|^/og\.png$"
    r")"
)

SELF_DOMAINS = {"francescoalbanese.dev", "www.francescoalbanese.dev"}
MOBILE_PATTERNS = re.compile(r"(?i)(iphone|android|mobile|ipod|blackberry|opera mini)")

CITY_CLUSTER_MIN_IPS = 3


class EnrichedRecord(TypedDict):
    timestamp: str
    client_ip: str
    city: str
    country: str
    rdns: str
    path: str
    referer: str
    user_agent: str
    status: int
    bytes_sent: int
    method: str


def is_static_asset(path: str) -> bool:
    return bool(STATIC_ASSET_PATTERNS.search(path))


def load_records_for_prefix(prefix: str) -> list[EnrichedRecord]:
    records: list[EnrichedRecord] = []
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=BUCKET, Prefix=prefix):
        for obj in page.get("Contents", []):
            body = s3.get_object(Bucket=BUCKET, Key=obj["Key"])["Body"].read()
            for line in body.decode("utf-8").strip().split("\n"):
                if line:
                    records.append(cast(EnrichedRecord, json.loads(line)))
    return records


def load_recent_records(now: datetime, days: int = DASHBOARD_WINDOW_DAYS) -> list[EnrichedRecord]:
    # Scan a bounded window of date-partitioned prefixes instead of the whole
    # `enriched/` tree — keeps cold starts predictable as data accumulates.
    records: list[EnrichedRecord] = []
    today = now.date()
    for i in range(days):
        d = today - timedelta(days=i)
        prefix = f"enriched/{d.year}/{d.month:02d}/{d.day:02d}/"
        records.extend(load_records_for_prefix(prefix))
    return records


def compute_visits(records: list[EnrichedRecord], now: datetime) -> dict[str, int]:
    today = now.date()
    week_start = today - timedelta(days=today.weekday())
    month_start = today.replace(day=1)

    counts = {"today": 0, "this_week": 0, "this_month": 0}
    for r in records:
        ts = datetime.fromisoformat(r["timestamp"].replace("Z", "+00:00")).date()
        if ts == today:
            counts["today"] += 1
        if ts >= week_start:
            counts["this_week"] += 1
        if ts >= month_start:
            counts["this_month"] += 1
    return counts


def compute_top_cities(records: list[EnrichedRecord], limit: int = 10) -> list[dict[str, object]]:
    city_counts: dict[str, int] = defaultdict(int)
    for r in records:
        if r["city"]:
            city_counts[r["city"]] += 1
    sorted_cities = sorted(city_counts.items(), key=lambda x: x[1], reverse=True)[:limit]
    return [{"city": city, "count": count} for city, count in sorted_cities]


def compute_top_pages(records: list[EnrichedRecord], limit: int = 10) -> list[dict[str, object]]:
    page_counts: dict[str, int] = defaultdict(int)
    for r in records:
        if not is_static_asset(r["path"]):
            page_counts[r["path"]] += 1
    sorted_pages = sorted(page_counts.items(), key=lambda x: x[1], reverse=True)[:limit]
    return [{"path": path, "count": count} for path, count in sorted_pages]


def compute_referrers(records: list[EnrichedRecord], limit: int = 10) -> list[dict[str, object]]:
    domain_counts: dict[str, int] = defaultdict(int)
    for r in records:
        referer = r.get("referer", "")
        if not referer or referer == "-":
            continue
        try:
            domain = urlparse(referer).netloc
        except ValueError:
            continue
        if not domain or domain in SELF_DOMAINS:
            continue
        domain_counts[domain] += 1
    sorted_domains = sorted(domain_counts.items(), key=lambda x: x[1], reverse=True)[:limit]
    return [{"domain": domain, "count": count} for domain, count in sorted_domains]


def compute_ua_breakdown(records: list[EnrichedRecord]) -> list[dict[str, object]]:
    total = len(records)
    if total == 0:
        return []

    categories = {"Desktop": 0, "Mobile": 0, "Other": 0}
    for r in records:
        ua = r.get("user_agent", "")
        if MOBILE_PATTERNS.search(ua):
            categories["Mobile"] += 1
        elif "Mozilla" in ua or "Chrome" in ua or "Safari" in ua:
            categories["Desktop"] += 1
        else:
            categories["Other"] += 1

    return [
        {"category": cat, "count": count, "percentage": round(count / total * 100, 1)}
        for cat, count in categories.items()
        if count > 0
    ]


def compute_daily_trend(
    records: list[EnrichedRecord], now: datetime, days: int = DASHBOARD_WINDOW_DAYS
) -> list[dict[str, object]]:
    date_counts: dict[str, int] = defaultdict(int)
    for r in records:
        date = r["timestamp"][:10]
        date_counts[date] += 1

    trend: list[dict[str, object]] = []
    for i in range(days - 1, -1, -1):
        day = (now - timedelta(days=i)).strftime("%Y-%m-%d")
        trend.append({"date": day, "count": date_counts.get(day, 0)})
    return trend


def compute_alert_history(records: list[EnrichedRecord]) -> list[dict[str, object]]:
    alerts: list[dict[str, object]] = []
    city_ips: dict[str, set[str]] = defaultdict(set)
    for r in records:
        if r["city"]:
            city_ips[r["city"]].add(r["client_ip"])
    for city, ips in city_ips.items():
        if len(ips) < CITY_CLUSTER_MIN_IPS:
            continue
        alerts.append({"type": "city_cluster", "city": city, "unique_visitors": len(ips)})
    return alerts


def handler(event: dict, context: object) -> dict:
    now = datetime.now(UTC)
    records = load_recent_records(now)

    dashboard_data = {
        "generated_at": now.isoformat(),
        "total_records": len(records),
        "window_days": DASHBOARD_WINDOW_DAYS,
        "visits": compute_visits(records, now),
        "top_cities": compute_top_cities(records),
        "top_pages": compute_top_pages(records),
        "referrers": compute_referrers(records),
        "ua_breakdown": compute_ua_breakdown(records),
        "daily_trend": compute_daily_trend(records, now),
        "alert_history": compute_alert_history(records),
    }

    s3.put_object(
        Bucket=BUCKET,
        Key="dashboard/data.json",
        Body=json.dumps(dashboard_data, indent=2).encode("utf-8"),
        ContentType="application/json",
    )

    # Escape `</` so a user-generated string can't close the inline <script>.
    safe_json = json.dumps(dashboard_data).replace("</", "\\u003c/")

    template_path = Path(__file__).parent / "template.html"
    html = template_path.read_text()
    html = html.replace(
        "const DATA_URL = 'data.json';",
        f"const INLINE_DATA = {safe_json};",
    )

    s3.put_object(
        Bucket=BUCKET,
        Key="dashboard/index.html",
        Body=html.encode("utf-8"),
        ContentType="text/html",
    )

    presigned_url = s3_presign.generate_presigned_url(
        "get_object",
        Params={"Bucket": BUCKET, "Key": "dashboard/index.html"},
        ExpiresIn=PRESIGN_EXPIRY_SECONDS,
    )

    logger.info("Dashboard generated with %d records", len(records))

    return {
        "statusCode": 302,
        "headers": {"Location": presigned_url},
    }
