import gzip
import json
import logging
import os
import re
import socket
from collections import defaultdict
from dataclasses import dataclass
from datetime import UTC, datetime
from io import BytesIO
from typing import TypedDict, cast
from urllib.parse import unquote

import boto3
import geoip2.database
import geoip2.errors
from botocore.exceptions import ClientError

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

# Matches YYYY-MM-DD or YYYY/MM/DD anywhere in the key — works for v1
# filenames (E1234.2026-04-14-15.abc.gz) and v2 S3 paths
# (AWSLogs/acct/CloudFront/dist/2026/04/14/...).
DATE_IN_KEY = re.compile(r"(\d{4})[-/](\d{2})[-/](\d{2})")

SLUG_STRIP = re.compile(r"[^a-z0-9]+")

TARGET_COUNTRIES = {"United Kingdom", "United States"}

DEEP_BROWSE_MIN_PAGES = 3
CITY_CLUSTER_MIN_IPS = 3


class CFEntry(TypedDict):
    date: str
    time: str
    sc_bytes: str
    c_ip: str
    method: str
    uri_stem: str
    status: str
    referer: str
    user_agent: str


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


@dataclass(frozen=True)
class Alert:
    type: str  # "deep_browse" | "city_cluster"
    dedup_id: str  # ip for deep_browse, slugified city for city_cluster
    message: str


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


def slugify(s: str) -> str:
    return SLUG_STRIP.sub("-", s.lower()).strip("-") or "unknown"


def event_date_from_key(key: str) -> datetime:
    # Prefer a date embedded in the S3 key; fall back to wall clock.
    m = DATE_IN_KEY.search(key)
    if m:
        year, month, day = map(int, m.groups())
        return datetime(year, month, day, tzinfo=UTC)
    return datetime.now(UTC)


def _pick(values: list[str], field_index: dict[str, int], name: str) -> str:
    idx = field_index.get(name)
    if idx is None or idx >= len(values):
        return ""
    return values[idx]


def parse_cf_log(raw: str) -> list[CFEntry]:
    # Parse the `#Fields:` header so we tolerate both v1 (33 cols) and v2
    # (trimmed record_fields) layouts.
    entries: list[CFEntry] = []
    field_index: dict[str, int] = {}

    for line in raw.strip().split("\n"):
        if line.startswith("#Fields:"):
            spec = line[len("#Fields:") :].strip().split()
            field_index = {name: i for i, name in enumerate(spec)}
            continue
        if line.startswith("#"):
            continue
        if not field_index:
            continue

        values = line.split("\t")

        # Reject lines that don't have all the columns the header declared —
        # catches malformed rows without coupling to a specific field count.
        if len(values) < len(field_index):
            continue

        entries.append(
            CFEntry(
                date=_pick(values, field_index, "date"),
                time=_pick(values, field_index, "time"),
                sc_bytes=_pick(values, field_index, "sc-bytes"),
                c_ip=_pick(values, field_index, "c-ip"),
                method=_pick(values, field_index, "cs-method"),
                uri_stem=_pick(values, field_index, "cs-uri-stem"),
                status=_pick(values, field_index, "sc-status"),
                referer=_pick(values, field_index, "cs(Referer)"),
                user_agent=_pick(values, field_index, "cs(User-Agent)"),
            )
        )
    return entries


def enrich_entry(
    entry: CFEntry,
    reader: geoip2.database.Reader,
    rdns_cache: dict[str, str],
) -> EnrichedRecord | None:
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

    # One rDNS lookup per unique IP per invocation — a single page view
    # generates ~30 asset requests from the same IP.
    if ip not in rdns_cache:
        rdns_cache[ip] = reverse_dns(ip)
    rdns = rdns_cache[ip]

    referer = entry["referer"] if entry["referer"] != "-" else ""

    status_raw = entry["status"]
    bytes_raw = entry["sc_bytes"]

    return EnrichedRecord(
        timestamp=f"{entry['date']}T{entry['time']}Z",
        client_ip=ip,
        city=city,
        country=country,
        rdns=rdns,
        path=entry["uri_stem"],
        referer=unquote(referer.replace("+", " ")),
        user_agent=user_agent,
        status=int(status_raw) if status_raw.isdigit() else 0,
        bytes_sent=int(bytes_raw) if bytes_raw.isdigit() else 0,
        method=entry["method"],
    )


def check_deep_browse(records: list[EnrichedRecord]) -> list[Alert]:
    ip_pages: dict[str, set[str]] = defaultdict(set)
    ip_meta: dict[str, EnrichedRecord] = {}

    for r in records:
        if r["country"] not in TARGET_COUNTRIES:
            continue
        if is_static_asset(r["path"]):
            continue
        ip_pages[r["client_ip"]].add(r["path"])
        ip_meta[r["client_ip"]] = r

    alerts: list[Alert] = []
    for ip, pages in ip_pages.items():
        if len(pages) < DEEP_BROWSE_MIN_PAGES:
            continue
        meta = ip_meta[ip]
        page_list = "\n".join(f"  \u2022 {p}" for p in sorted(pages))
        message = (
            f"\U0001f514 Deep Browse Alert \u2014 {meta['city']}, {meta['country']}\n\n"
            f"A visitor from {meta['city']} browsed {len(pages)} pages on your site:\n"
            f"{page_list}\n\n"
            f"User-Agent: {meta['user_agent']}\n"
            f"Referer: {meta['referer'] or 'direct'}\n"
            f"Reverse DNS: {meta['rdns'] or 'N/A'}\n"
            f"Time: {meta['timestamp']}"
        )
        alerts.append(Alert(type="deep_browse", dedup_id=ip, message=message))
    return alerts


def check_city_cluster(records: list[EnrichedRecord]) -> list[Alert]:
    city_ips: dict[str, set[str]] = defaultdict(set)
    for r in records:
        if r["city"]:
            city_ips[r["city"]].add(r["client_ip"])

    alerts: list[Alert] = []
    for city, ips in city_ips.items():
        if len(ips) < CITY_CLUSTER_MIN_IPS:
            continue
        message = (
            f"\U0001f514 City Cluster Alert \u2014 {city}\n\n"
            f"{len(ips)} unique visitors from {city} visited your site today."
        )
        alerts.append(Alert(type="city_cluster", dedup_id=slugify(city), message=message))
    return alerts


def marker_key(alert: Alert, date_str: str) -> str:
    return f"alerts/{alert.type}/{date_str}/{alert.dedup_id}.sent"


def alert_already_sent(key: str) -> bool:
    try:
        s3.head_object(Bucket=BUCKET, Key=key)
        return True
    except ClientError as e:
        if e.response.get("Error", {}).get("Code") in {"404", "NoSuchKey", "NotFound"}:
            return False
        raise


def mark_alert_sent(key: str) -> None:
    s3.put_object(Bucket=BUCKET, Key=key, Body=b"")


def publish_alert(alert: Alert, date_str: str) -> None:
    key = marker_key(alert, date_str)
    if alert_already_sent(key):
        return
    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject="francescoalbanese.dev \u2014 Visitor Alert",
        Message=alert.message,
    )
    mark_alert_sent(key)


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


def handler(event: dict, context: object) -> None:
    record = event["Records"][0]
    bucket = record["s3"]["bucket"]["name"]
    key = record["s3"]["object"]["key"]

    response = s3.get_object(Bucket=bucket, Key=key)
    compressed = response["Body"].read()

    with gzip.GzipFile(fileobj=BytesIO(compressed)) as gz:
        raw = gz.read().decode("utf-8")

    reader = get_geoip_reader()
    entries = parse_cf_log(raw)

    rdns_cache: dict[str, str] = {}
    enriched: list[EnrichedRecord] = []
    for entry in entries:
        record_data = enrich_entry(entry, reader, rdns_cache)
        if record_data:
            enriched.append(record_data)

    event_date = event_date_from_key(key)
    date_partition = f"{event_date.year}/{event_date.month:02d}/{event_date.day:02d}"
    date_str = event_date.strftime("%Y-%m-%d")

    filename = key.split("/")[-1].replace(".gz", ".jsonl")
    output_key = f"enriched/{date_partition}/{filename}"

    jsonl = "\n".join(json.dumps(r) for r in enriched) if enriched else ""
    s3.put_object(Bucket=BUCKET, Key=output_key, Body=jsonl.encode("utf-8"))

    day_prefix = f"enriched/{date_partition}/"
    day_records = load_records_for_prefix(day_prefix)

    for alert in check_deep_browse(day_records):
        publish_alert(alert, date_str)

    for alert in check_city_cluster(day_records):
        publish_alert(alert, date_str)

    logger.info(
        "Processed %d entries, enriched %d, day total %d",
        len(entries),
        len(enriched),
        len(day_records),
    )
