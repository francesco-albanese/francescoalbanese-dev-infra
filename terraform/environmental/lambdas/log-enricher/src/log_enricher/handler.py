import gzip
import hashlib
import json
import logging
import os
import re
import socket
from collections import defaultdict
from datetime import UTC, datetime
from io import BytesIO
from typing import Any
from urllib.parse import unquote

import boto3
import geoip2.database
import geoip2.errors

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

BUCKET = os.environ.get("ANALYTICS_BUCKET", "")
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")
GEOIP_DB_PATH = os.environ.get("GEOIP_DB_PATH", "/opt/GeoLite2-City.mmdb")

s3 = boto3.client("s3")
sns = boto3.client("sns")

BOT_PATTERNS = re.compile(
    r"(?i)("
    r"googlebot|bingbot|crawl|slurp|duckduckbot|baiduspider|yandexbot|"
    r"facebookexternalhit|twitterbot|linkedinbot|petalbot|semrushbot|"
    r"ahrefsbot|mj12bot|bytespider"
    r")"
)

STATIC_ASSET_PATTERNS = re.compile(
    r"(?i)("
    r"^/_astro/|\.css$|\.js$|\.png$|\.svg$|\.woff2$|\.webp$|\.ico$|"
    r"^/favicon|^/robots\.txt$|^/sitemap|^/manifest|^/sw\.js$|^/og\.png$"
    r")"
)

CF_LOG_FIELD_COUNT = 33

TARGET_COUNTRIES = {"United Kingdom", "United States"}


def get_geoip_reader() -> geoip2.database.Reader:
    return geoip2.database.Reader(GEOIP_DB_PATH)


def reverse_dns(ip: str) -> str:
    prev_timeout = socket.getdefaulttimeout()
    try:
        socket.setdefaulttimeout(2)
        hostname, _, _ = socket.gethostbyaddr(ip)
        return hostname
    except (TimeoutError, socket.herror, socket.gaierror, OSError):
        return ""
    finally:
        socket.setdefaulttimeout(prev_timeout)


def is_bot(user_agent: str) -> bool:
    return bool(BOT_PATTERNS.search(user_agent))


def is_static_asset(path: str) -> bool:
    return bool(STATIC_ASSET_PATTERNS.search(path))


def parse_cf_log(raw: str) -> list[dict[str, str]]:
    entries = []
    for line in raw.strip().split("\n"):
        if line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) < CF_LOG_FIELD_COUNT:
            continue
        entries.append(
            {
                "date": fields[0],
                "time": fields[1],
                "sc_bytes": fields[3],
                "c_ip": fields[4],
                "method": fields[5],
                "uri_stem": fields[7],
                "status": fields[8],
                "referer": fields[9],
                "user_agent": fields[10],
            }
        )
    return entries


def enrich_entry(entry: dict[str, str], reader: geoip2.database.Reader) -> dict[str, Any] | None:
    user_agent = unquote(entry["user_agent"].replace("+", " "))
    if is_bot(user_agent):
        return None

    ip = entry["c_ip"]
    city = ""
    country = ""

    try:
        geo = reader.city(ip)
        city = geo.city.name or ""
        country = geo.country.name or ""
    except geoip2.errors.AddressNotFoundError:
        pass

    rdns = reverse_dns(ip)
    referer = entry["referer"] if entry["referer"] != "-" else ""

    return {
        "timestamp": f"{entry['date']}T{entry['time']}Z",
        "client_ip": ip,
        "city": city,
        "country": country,
        "rdns": rdns,
        "path": entry["uri_stem"],
        "referer": unquote(referer.replace("+", " ")),
        "user_agent": user_agent,
        "status": int(entry["status"]),
        "bytes_sent": int(entry["sc_bytes"]),
        "method": entry["method"],
    }


def check_deep_browse(records: list[dict[str, Any]]) -> list[str]:
    ip_pages: dict[str, set[str]] = defaultdict(set)
    ip_meta: dict[str, dict[str, Any]] = {}

    for r in records:
        if r["country"] not in TARGET_COUNTRIES:
            continue
        path = r["path"]
        if is_static_asset(path):
            continue
        ip_pages[r["client_ip"]].add(path)
        ip_meta[r["client_ip"]] = r

    alerts = []
    for ip, pages in ip_pages.items():
        if len(pages) >= 3:
            meta = ip_meta[ip]
            page_list = "\n".join(f"  \u2022 {p}" for p in sorted(pages))
            alerts.append(
                f"\U0001f514 Deep Browse Alert \u2014 {meta['city']}, {meta['country']}\n\n"
                f"A visitor from {meta['city']} browsed {len(pages)} pages on your site:\n"
                f"{page_list}\n\n"
                f"User-Agent: {meta['user_agent']}\n"
                f"Referer: {meta['referer'] or 'direct'}\n"
                f"Reverse DNS: {meta['rdns'] or 'N/A'}\n"
                f"Time: {meta['timestamp']}"
            )
    return alerts


def check_city_cluster(records: list[dict[str, Any]]) -> list[str]:
    city_ips: dict[str, set[str]] = defaultdict(set)
    for r in records:
        if r["city"]:
            city_ips[r["city"]].add(r["client_ip"])

    alerts = []
    for city, ips in city_ips.items():
        if len(ips) >= 3:
            alerts.append(
                f"\U0001f514 City Cluster Alert \u2014 {city}\n\n"
                f"{len(ips)} unique visitors from {city} visited your site today."
            )
    return alerts


def alert_already_sent(alert_hash: str, today_prefix: str) -> bool:
    marker_key = f"alerts/{today_prefix}{alert_hash}.sent"
    try:
        s3.head_object(Bucket=BUCKET, Key=marker_key)
        return True
    except s3.exceptions.ClientError:
        return False


def mark_alert_sent(alert_hash: str, today_prefix: str) -> None:
    marker_key = f"alerts/{today_prefix}{alert_hash}.sent"
    s3.put_object(Bucket=BUCKET, Key=marker_key, Body=b"")


def publish_alert(message: str, today_prefix: str = "") -> None:
    alert_hash = hashlib.sha256(message.encode()).hexdigest()[:16]
    if today_prefix and alert_already_sent(alert_hash, today_prefix):
        return
    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject="francescoalbanese.dev \u2014 Visitor Alert",
        Message=message,
    )
    if today_prefix:
        mark_alert_sent(alert_hash, today_prefix)


def load_todays_records(today_prefix: str) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=BUCKET, Prefix=today_prefix):
        for obj in page.get("Contents", []):
            body = s3.get_object(Bucket=BUCKET, Key=obj["Key"])["Body"].read()
            for line in body.decode("utf-8").strip().split("\n"):
                if line:
                    records.append(json.loads(line))
    return records


def handler(event: dict, context: Any) -> None:
    record = event["Records"][0]
    bucket = record["s3"]["bucket"]["name"]
    key = record["s3"]["object"]["key"]

    response = s3.get_object(Bucket=bucket, Key=key)
    compressed = response["Body"].read()

    with gzip.GzipFile(fileobj=BytesIO(compressed)) as gz:
        raw = gz.read().decode("utf-8")

    reader = get_geoip_reader()
    entries = parse_cf_log(raw)

    enriched: list[dict[str, Any]] = []
    for entry in entries:
        record_data = enrich_entry(entry, reader)
        if record_data:
            enriched.append(record_data)

    now = datetime.now(UTC)
    filename = key.split("/")[-1].replace(".gz", ".jsonl")
    output_key = f"enriched/{now.year}/{now.month:02d}/{now.day:02d}/{filename}"

    jsonl = "\n".join(json.dumps(r) for r in enriched) if enriched else ""
    s3.put_object(Bucket=BUCKET, Key=output_key, Body=jsonl.encode("utf-8"))

    today_prefix = f"enriched/{now.year}/{now.month:02d}/{now.day:02d}/"
    all_today = load_todays_records(today_prefix)

    alert_date_prefix = f"{now.year}/{now.month:02d}/{now.day:02d}/"
    for alert in check_deep_browse(all_today):
        publish_alert(alert, alert_date_prefix)

    for alert in check_city_cluster(all_today):
        publish_alert(alert, alert_date_prefix)

    logger.info(
        "Processed %d entries, enriched %d, total today %d",
        len(entries),
        len(enriched),
        len(all_today),
    )
