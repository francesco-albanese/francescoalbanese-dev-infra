import json

from tests.conftest import (
    BUCKET_NAME,
    date_str,
    make_record,
    timestamp_str,
    upload_enriched_records,
)


def invoke_handler(s3_client):
    from dashboard_generator.handler import handler

    return handler({"requestContext": {"http": {"method": "GET"}}}, None)


def get_dashboard_data(s3_client) -> dict:
    body = s3_client.get_object(Bucket=BUCKET_NAME, Key="dashboard/data.json")["Body"].read()
    return json.loads(body)


class TestVisitsByPeriod:
    def test_counts_today_this_week_this_month(self, s3_client):
        today = date_str(0)
        yesterday = date_str(1)
        week_ago = date_str(6)
        upload_enriched_records(
            s3_client,
            today,
            [
                make_record(timestamp=timestamp_str(0)),
                make_record(timestamp=timestamp_str(0), client_ip="203.0.113.2"),
            ],
            suffix="a",
        )
        upload_enriched_records(
            s3_client,
            yesterday,
            [
                make_record(timestamp=timestamp_str(1)),
            ],
            suffix="b",
        )
        upload_enriched_records(
            s3_client,
            week_ago,
            [
                make_record(timestamp=timestamp_str(6)),
            ],
            suffix="c",
        )

        invoke_handler(s3_client)
        data = get_dashboard_data(s3_client)

        assert data["visits"]["today"] == 2
        assert data["visits"]["this_week"] >= 3
        assert data["visits"]["this_month"] >= 4


class TestTopCities:
    def test_ranks_cities_by_visit_count(self, s3_client):
        today = date_str(0)
        records = [
            make_record(city="London", client_ip="1.1.1.1", timestamp=timestamp_str(0)),
            make_record(city="London", client_ip="1.1.1.2", timestamp=timestamp_str(0)),
            make_record(city="London", client_ip="1.1.1.3", timestamp=timestamp_str(0)),
            make_record(city="New York", client_ip="2.2.2.1", timestamp=timestamp_str(0)),
        ]
        upload_enriched_records(s3_client, today, records)

        invoke_handler(s3_client)
        data = get_dashboard_data(s3_client)

        assert data["top_cities"][0]["city"] == "London"
        assert data["top_cities"][0]["count"] == 3
        assert data["top_cities"][1]["city"] == "New York"


class TestTopPages:
    def test_excludes_static_assets(self, s3_client):
        today = date_str(0)
        records = [
            make_record(path="/", timestamp=timestamp_str(0)),
            make_record(path="/projects", timestamp=timestamp_str(0)),
            make_record(path="/_astro/chunk.abc.js", timestamp=timestamp_str(0)),
            make_record(path="/favicon.ico", timestamp=timestamp_str(0)),
            make_record(path="/robots.txt", timestamp=timestamp_str(0)),
        ]
        upload_enriched_records(s3_client, today, records)

        invoke_handler(s3_client)
        data = get_dashboard_data(s3_client)

        page_paths = [p["path"] for p in data["top_pages"]]
        assert "/" in page_paths
        assert "/projects" in page_paths
        assert "/_astro/chunk.abc.js" not in page_paths
        assert "/favicon.ico" not in page_paths
        assert "/robots.txt" not in page_paths

    def test_ranks_pages_by_count(self, s3_client):
        today = date_str(0)
        records = [
            make_record(path="/", timestamp=timestamp_str(0)),
            make_record(path="/", timestamp=timestamp_str(0), client_ip="1.1.1.1"),
            make_record(path="/projects", timestamp=timestamp_str(0)),
        ]
        upload_enriched_records(s3_client, today, records)

        invoke_handler(s3_client)
        data = get_dashboard_data(s3_client)

        assert data["top_pages"][0]["path"] == "/"
        assert data["top_pages"][0]["count"] == 2


class TestDeepBrowsers:
    def test_detects_london_ip_with_3_plus_pages(self, s3_client):
        today = date_str(0)
        records = [
            make_record(
                client_ip="203.0.113.1",
                path="/",
                city="London",
                country="United Kingdom",
                rdns="host.barclays.co.uk",
                timestamp=timestamp_str(0),
            ),
            make_record(
                client_ip="203.0.113.1",
                path="/projects",
                city="London",
                country="United Kingdom",
                timestamp=timestamp_str(0),
            ),
            make_record(
                client_ip="203.0.113.1",
                path="/cv",
                city="London",
                country="United Kingdom",
                timestamp=timestamp_str(0),
            ),
        ]
        upload_enriched_records(s3_client, today, records)

        invoke_handler(s3_client)
        data = get_dashboard_data(s3_client)

        assert len(data["deep_browsers"]) == 1
        browser = data["deep_browsers"][0]
        assert browser["city"] == "London"
        assert set(browser["pages"]) == {"/", "/projects", "/cv"}

    def test_excludes_non_target_geo(self, s3_client):
        today = date_str(0)
        records = [
            make_record(
                client_ip="1.1.1.1",
                path="/",
                city="Berlin",
                country="Germany",
                timestamp=timestamp_str(0),
            ),
            make_record(
                client_ip="1.1.1.1",
                path="/projects",
                city="Berlin",
                country="Germany",
                timestamp=timestamp_str(0),
            ),
            make_record(
                client_ip="1.1.1.1",
                path="/cv",
                city="Berlin",
                country="Germany",
                timestamp=timestamp_str(0),
            ),
        ]
        upload_enriched_records(s3_client, today, records)

        invoke_handler(s3_client)
        data = get_dashboard_data(s3_client)

        assert len(data["deep_browsers"]) == 0


class TestReferrers:
    def test_groups_by_domain(self, s3_client):
        today = date_str(0)
        records = [
            make_record(referer="https://linkedin.com/in/someone", timestamp=timestamp_str(0)),
            make_record(
                referer="https://linkedin.com/in/other",
                timestamp=timestamp_str(0),
                client_ip="1.1.1.1",
            ),
            make_record(
                referer="https://google.com/search?q=test",
                timestamp=timestamp_str(0),
                client_ip="2.2.2.2",
            ),
        ]
        upload_enriched_records(s3_client, today, records)

        invoke_handler(s3_client)
        data = get_dashboard_data(s3_client)

        referrers = {r["domain"]: r["count"] for r in data["referrers"]}
        assert referrers["linkedin.com"] == 2
        assert referrers["google.com"] == 1

    def test_excludes_empty_and_self_referrers(self, s3_client):
        today = date_str(0)
        records = [
            make_record(referer="", timestamp=timestamp_str(0)),
            make_record(referer="-", timestamp=timestamp_str(0), client_ip="1.1.1.1"),
            make_record(
                referer="https://francescoalbanese.dev/projects",
                timestamp=timestamp_str(0),
                client_ip="2.2.2.2",
            ),
            make_record(
                referer="https://linkedin.com",
                timestamp=timestamp_str(0),
                client_ip="3.3.3.3",
            ),
        ]
        upload_enriched_records(s3_client, today, records)

        invoke_handler(s3_client)
        data = get_dashboard_data(s3_client)

        domains = [r["domain"] for r in data["referrers"]]
        assert "francescoalbanese.dev" not in domains
        assert "" not in domains
        assert "-" not in domains


class TestUABreakdown:
    def test_categorizes_desktop_and_mobile(self, s3_client):
        today = date_str(0)
        records = [
            make_record(
                user_agent="Mozilla/5.0 (Windows NT 10.0) Chrome/120",
                timestamp=timestamp_str(0),
            ),
            make_record(
                user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X) Safari/605",
                timestamp=timestamp_str(0),
                client_ip="1.1.1.1",
            ),
            make_record(
                user_agent="Mozilla/5.0 (iPhone; CPU iPhone OS) Mobile Safari",
                timestamp=timestamp_str(0),
                client_ip="2.2.2.2",
            ),
        ]
        upload_enriched_records(s3_client, today, records)

        invoke_handler(s3_client)
        data = get_dashboard_data(s3_client)

        breakdown = {item["category"]: item["percentage"] for item in data["ua_breakdown"]}
        assert "Desktop" in breakdown
        assert "Mobile" in breakdown


class TestDailyTrend:
    def test_fills_zero_days(self, s3_client):
        today = date_str(0)
        three_days_ago = date_str(3)
        upload_enriched_records(
            s3_client,
            today,
            [
                make_record(timestamp=timestamp_str(0)),
            ],
            suffix="a",
        )
        upload_enriched_records(
            s3_client,
            three_days_ago,
            [
                make_record(timestamp=timestamp_str(3)),
            ],
            suffix="b",
        )

        invoke_handler(s3_client)
        data = get_dashboard_data(s3_client)

        assert len(data["daily_trend"]) == 30
        today_entry = next(d for d in data["daily_trend"] if d["date"] == today)
        assert today_entry["count"] == 1

        yesterday = date_str(1)
        yesterday_entry = next(d for d in data["daily_trend"] if d["date"] == yesterday)
        assert yesterday_entry["count"] == 0


class TestHandlerResponse:
    def test_returns_302_with_presigned_url(self, s3_client):
        today = date_str(0)
        upload_enriched_records(s3_client, today, [make_record(timestamp=timestamp_str(0))])

        response = invoke_handler(s3_client)

        assert response["statusCode"] == 302
        assert "Location" in response["headers"]
        assert "dashboard/index.html" in response["headers"]["Location"]

    def test_writes_dashboard_html_to_s3(self, s3_client):
        today = date_str(0)
        upload_enriched_records(s3_client, today, [make_record(timestamp=timestamp_str(0))])

        invoke_handler(s3_client)

        response = s3_client.get_object(Bucket=BUCKET_NAME, Key="dashboard/index.html")
        html = response["Body"].read().decode("utf-8")
        assert "francescoalbanese.dev" in html
        assert "chart.js" in html.lower() or "Chart" in html

    def test_writes_dashboard_data_json_to_s3(self, s3_client):
        today = date_str(0)
        upload_enriched_records(s3_client, today, [make_record(timestamp=timestamp_str(0))])

        invoke_handler(s3_client)

        data = get_dashboard_data(s3_client)
        assert "visits" in data
        assert "top_cities" in data
        assert "top_pages" in data
        assert "daily_trend" in data


class TestEdgeCases:
    def test_handles_no_data(self, s3_client):
        response = invoke_handler(s3_client)

        assert response["statusCode"] == 302
        data = get_dashboard_data(s3_client)
        assert data["visits"]["today"] == 0
        assert data["top_cities"] == []
        assert data["top_pages"] == []

    def test_handles_single_day_of_data(self, s3_client):
        today = date_str(0)
        upload_enriched_records(
            s3_client,
            today,
            [
                make_record(timestamp=timestamp_str(0)),
            ],
        )

        response = invoke_handler(s3_client)

        assert response["statusCode"] == 302
        data = get_dashboard_data(s3_client)
        assert data["visits"]["today"] == 1
