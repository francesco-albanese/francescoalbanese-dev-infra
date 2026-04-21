from unittest.mock import patch

from tests.conftest import (
    BUCKET_NAME,
    build_cf_log,
    get_enriched_records,
    make_cf_log_line,
    make_s3_event,
    upload_cf_log,
)


class TestLogEnrichment:
    def test_produces_enriched_jsonl_in_correct_s3_path(self, aws_clients, mock_geoip_reader):
        s3, _ = aws_clients
        log_key = "cf-logs/E1234.2026-04-14-15.abcdef.gz"
        log_content = build_cf_log([make_cf_log_line()])
        upload_cf_log(s3, log_key, log_content)
        event = make_s3_event(BUCKET_NAME, log_key)

        with patch("log_enricher.handler.get_geoip_reader", return_value=mock_geoip_reader):
            from log_enricher.handler import handler

            handler(event, None)

        records = get_enriched_records(s3)
        assert len(records) == 1

        response = s3.list_objects_v2(Bucket=BUCKET_NAME, Prefix="enriched/2026/04/14/")
        assert response["KeyCount"] == 1

    def test_enriched_record_has_expected_fields(self, aws_clients, mock_geoip_reader):
        s3, _ = aws_clients
        log_key = "cf-logs/E1234.2026-04-14-15.xyz.gz"
        log_content = build_cf_log(
            [make_cf_log_line(c_ip="203.0.113.1", uri_stem="/projects", status="200")]
        )
        upload_cf_log(s3, log_key, log_content)
        event = make_s3_event(BUCKET_NAME, log_key)

        with (
            patch("log_enricher.handler.get_geoip_reader", return_value=mock_geoip_reader),
            patch("log_enricher.handler.reverse_dns", return_value="host-1.barclays.co.uk"),
        ):
            from log_enricher.handler import handler

            handler(event, None)

        records = get_enriched_records(s3)
        record = records[0]
        assert record["client_ip"] == "203.0.113.1"
        assert record["city"] == "London"
        assert record["country"] == "United Kingdom"
        assert record["rdns"] == "host-1.barclays.co.uk"
        assert record["path"] == "/projects"
        assert record["status"] == 200
        assert record["method"] == "GET"
        assert "timestamp" in record
        assert "referer" in record
        assert "user_agent" in record
        assert "bytes_sent" in record


class TestBotFiltering:
    def test_filters_out_googlebot(self, aws_clients, mock_geoip_reader):
        s3, _ = aws_clients
        log_key = "cf-logs/E1234.2026-04-14-15.bot1.gz"
        log_content = build_cf_log(
            [
                make_cf_log_line(user_agent="Googlebot/2.1+(+http://www.google.com/bot.html)"),
                make_cf_log_line(user_agent="Mozilla/5.0+Chrome/120.0.0.0", c_ip="203.0.113.1"),
            ]
        )
        upload_cf_log(s3, log_key, log_content)
        event = make_s3_event(BUCKET_NAME, log_key)

        with patch("log_enricher.handler.get_geoip_reader", return_value=mock_geoip_reader):
            from log_enricher.handler import handler

            handler(event, None)

        records = get_enriched_records(s3)
        assert len(records) == 1
        assert "Googlebot" not in records[0]["user_agent"]

    def test_filters_out_multiple_bot_types(self, aws_clients, mock_geoip_reader):
        s3, _ = aws_clients
        log_key = "cf-logs/E1234.2026-04-14-15.bot2.gz"
        bot_agents = [
            "bingbot/2.0",
            "AhrefsBot/7.0",
            "SemrushBot/7.0",
            "LinkedInBot/1.0",
            "facebookexternalhit/1.1",
        ]
        lines = [make_cf_log_line(user_agent=ua) for ua in bot_agents]
        lines.append(make_cf_log_line(user_agent="Mozilla/5.0+real+user", c_ip="203.0.113.1"))
        log_content = build_cf_log(lines)
        upload_cf_log(s3, log_key, log_content)
        event = make_s3_event(BUCKET_NAME, log_key)

        with patch("log_enricher.handler.get_geoip_reader", return_value=mock_geoip_reader):
            from log_enricher.handler import handler

            handler(event, None)

        records = get_enriched_records(s3)
        assert len(records) == 1

    def test_filters_out_scanner_user_agents(self, aws_clients, mock_geoip_reader):
        s3, _ = aws_clients
        log_key = "cf-logs/E1234.2026-04-14-15.scannerua.gz"
        scanner_agents = [
            "curl/8.4.0",
            "Wget/1.21.4",
            "python-requests/2.31.0",
            "Go-http-client/2.0",
            "masscan/1.3.2",
            "Nikto/2.5.0",
            "Nuclei/3.0.0",
        ]
        lines = [make_cf_log_line(user_agent=ua) for ua in scanner_agents]
        lines.append(make_cf_log_line(user_agent="Mozilla/5.0+real+user", c_ip="203.0.113.1"))
        log_content = build_cf_log(lines)
        upload_cf_log(s3, log_key, log_content)
        event = make_s3_event(BUCKET_NAME, log_key)

        with patch("log_enricher.handler.get_geoip_reader", return_value=mock_geoip_reader):
            from log_enricher.handler import handler

            handler(event, None)

        records = get_enriched_records(s3)
        assert len(records) == 1

    def test_all_bot_traffic_produces_empty_enriched_file(self, aws_clients, mock_geoip_reader):
        s3, _ = aws_clients
        log_key = "cf-logs/E1234.2026-04-14-15.allbot.gz"
        log_content = build_cf_log(
            [
                make_cf_log_line(user_agent="Googlebot/2.1"),
                make_cf_log_line(user_agent="bingbot/2.0"),
            ]
        )
        upload_cf_log(s3, log_key, log_content)
        event = make_s3_event(BUCKET_NAME, log_key)

        with patch("log_enricher.handler.get_geoip_reader", return_value=mock_geoip_reader):
            from log_enricher.handler import handler

            handler(event, None)

        records = get_enriched_records(s3)
        assert len(records) == 0


class TestScannerPathFiltering:
    def test_drops_known_scanner_probes(self, aws_clients, mock_geoip_reader):
        s3, _ = aws_clients
        log_key = "cf-logs/E1234.2026-04-14-15.scanpaths.gz"
        scanner_paths = [
            "/xmlrpc.php",
            "//xmlrpc.php",
            "/.git/config",
            "/.env",
            "/wp-login.php",
            "/wp-admin/admin-ajax.php",
            "/phpmyadmin/index.php",
            "//site/wp-includes/wlwmanifest.xml",
            "//wordpress/wp-includes/wlwmanifest.xml",
            "/Alvin9999/https/fanfan1.net/daohang/",
        ]
        lines = [make_cf_log_line(uri_stem=p) for p in scanner_paths]
        lines.append(make_cf_log_line(uri_stem="/", c_ip="203.0.113.1"))
        log_content = build_cf_log(lines)
        upload_cf_log(s3, log_key, log_content)
        event = make_s3_event(BUCKET_NAME, log_key)

        with patch("log_enricher.handler.get_geoip_reader", return_value=mock_geoip_reader):
            from log_enricher.handler import handler

            handler(event, None)

        records = get_enriched_records(s3)
        assert len(records) == 1
        assert records[0]["path"] == "/"

    def test_legit_paths_survive(self, aws_clients, mock_geoip_reader):
        s3, _ = aws_clients
        log_key = "cf-logs/E1234.2026-04-14-15.legitpaths.gz"
        legit_paths = ["/", "/projects", "/cv", "/about", "/_astro/chunk.abc.js"]
        lines = [make_cf_log_line(uri_stem=p, c_ip="203.0.113.1") for p in legit_paths]
        log_content = build_cf_log(lines)
        upload_cf_log(s3, log_key, log_content)
        event = make_s3_event(BUCKET_NAME, log_key)

        with patch("log_enricher.handler.get_geoip_reader", return_value=mock_geoip_reader):
            from log_enricher.handler import handler

            handler(event, None)

        records = get_enriched_records(s3)
        assert len(records) == len(legit_paths)


class TestMethodFiltering:
    def test_drops_non_get_head(self, aws_clients, mock_geoip_reader):
        s3, _ = aws_clients
        log_key = "cf-logs/E1234.2026-04-14-15.methods.gz"
        lines = [
            make_cf_log_line(method="POST", c_ip="203.0.113.1"),
            make_cf_log_line(method="OPTIONS", c_ip="203.0.113.1"),
            make_cf_log_line(method="DELETE", c_ip="203.0.113.1"),
            make_cf_log_line(method="GET", c_ip="203.0.113.2"),
            make_cf_log_line(method="HEAD", c_ip="203.0.113.3"),
        ]
        log_content = build_cf_log(lines)
        upload_cf_log(s3, log_key, log_content)
        event = make_s3_event(BUCKET_NAME, log_key)

        with patch("log_enricher.handler.get_geoip_reader", return_value=mock_geoip_reader):
            from log_enricher.handler import handler

            handler(event, None)

        records = get_enriched_records(s3)
        assert len(records) == 2
        assert {r["method"] for r in records} == {"GET", "HEAD"}


class TestGeoIPEnrichment:
    def test_enriches_with_city_and_country(self, aws_clients, mock_geoip_reader):
        s3, _ = aws_clients
        log_key = "cf-logs/E1234.2026-04-14-15.geo1.gz"
        log_content = build_cf_log(
            [
                make_cf_log_line(c_ip="203.0.113.1"),
                make_cf_log_line(c_ip="198.51.100.1"),
            ]
        )
        upload_cf_log(s3, log_key, log_content)
        event = make_s3_event(BUCKET_NAME, log_key)

        with patch("log_enricher.handler.get_geoip_reader", return_value=mock_geoip_reader):
            from log_enricher.handler import handler

            handler(event, None)

        records = get_enriched_records(s3)
        london_record = next(r for r in records if r["client_ip"] == "203.0.113.1")
        ny_record = next(r for r in records if r["client_ip"] == "198.51.100.1")

        assert london_record["city"] == "London"
        assert london_record["country"] == "United Kingdom"
        assert ny_record["city"] == "New York"
        assert ny_record["country"] == "United States"

    def test_handles_geoip_lookup_failure_gracefully(self, aws_clients):
        s3, _ = aws_clients
        log_key = "cf-logs/E1234.2026-04-14-15.geofail.gz"
        log_content = build_cf_log([make_cf_log_line(c_ip="10.0.0.1")])
        upload_cf_log(s3, log_key, log_content)
        event = make_s3_event(BUCKET_NAME, log_key)

        import geoip2.errors

        failing_reader = __import__("unittest.mock", fromlist=["MagicMock"]).MagicMock()
        failing_reader.city.side_effect = geoip2.errors.AddressNotFoundError("10.0.0.1")

        with patch("log_enricher.handler.get_geoip_reader", return_value=failing_reader):
            from log_enricher.handler import handler

            handler(event, None)

        records = get_enriched_records(s3)
        assert len(records) == 1
        assert records[0]["city"] == ""
        assert records[0]["country"] == ""


class TestCityClusterAlert:
    def test_fires_when_3_unique_ips_from_same_city(self, aws_clients, mock_geoip_reader):
        s3, sns = aws_clients
        log_key = "cf-logs/E1234.2026-04-14-15.cluster1.gz"
        log_content = build_cf_log(
            [
                make_cf_log_line(c_ip="203.0.113.1", uri_stem="/"),
                make_cf_log_line(c_ip="203.0.113.2", uri_stem="/"),
                make_cf_log_line(c_ip="203.0.113.3", uri_stem="/projects"),
            ]
        )
        upload_cf_log(s3, log_key, log_content)
        event = make_s3_event(BUCKET_NAME, log_key)

        with (
            patch("log_enricher.handler.get_geoip_reader", return_value=mock_geoip_reader),
            patch("log_enricher.handler.reverse_dns", return_value=""),
            patch("log_enricher.handler.publish_alert") as mock_publish,
        ):
            from log_enricher.handler import handler

            handler(event, None)

        alerts = [c[0][0] for c in mock_publish.call_args_list]
        cluster_alerts = [a for a in alerts if a.type == "city_cluster"]
        assert len(cluster_alerts) >= 1
        assert "London" in cluster_alerts[0].message


class TestEdgeCases:
    def test_handles_empty_log_file(self, aws_clients, mock_geoip_reader):
        s3, _ = aws_clients
        log_key = "cf-logs/E1234.2026-04-14-15.empty.gz"
        log_content = "#Version: 1.0\n#Fields: date time x-edge-location sc-bytes c-ip\n"
        upload_cf_log(s3, log_key, log_content)
        event = make_s3_event(BUCKET_NAME, log_key)

        with patch("log_enricher.handler.get_geoip_reader", return_value=mock_geoip_reader):
            from log_enricher.handler import handler

            handler(event, None)

        records = get_enriched_records(s3)
        assert len(records) == 0

    def test_skips_malformed_lines(self, aws_clients, mock_geoip_reader):
        s3, _ = aws_clients
        log_key = "cf-logs/E1234.2026-04-14-15.malformed.gz"
        log_content = build_cf_log(
            [
                "this\tis\tnot\tenough\tfields",
                make_cf_log_line(c_ip="203.0.113.1"),
            ]
        )
        upload_cf_log(s3, log_key, log_content)
        event = make_s3_event(BUCKET_NAME, log_key)

        with patch("log_enricher.handler.get_geoip_reader", return_value=mock_geoip_reader):
            from log_enricher.handler import handler

            handler(event, None)

        records = get_enriched_records(s3)
        assert len(records) == 1


class TestAlertDeduplication:
    def test_same_city_cluster_alert_not_sent_twice(self, aws_clients, mock_geoip_reader):
        s3, sns = aws_clients

        log_content = build_cf_log(
            [
                make_cf_log_line(c_ip="203.0.113.1", uri_stem="/"),
                make_cf_log_line(c_ip="203.0.113.2", uri_stem="/"),
                make_cf_log_line(c_ip="203.0.113.3", uri_stem="/"),
            ]
        )

        log_key_1 = "cf-logs/E1234.2026-04-14-15.dedup1.gz"
        upload_cf_log(s3, log_key_1, log_content)
        event_1 = make_s3_event(BUCKET_NAME, log_key_1)

        log_key_2 = "cf-logs/E1234.2026-04-14-16.dedup2.gz"
        upload_cf_log(s3, log_key_2, log_content)
        event_2 = make_s3_event(BUCKET_NAME, log_key_2)

        with (
            patch("log_enricher.handler.get_geoip_reader", return_value=mock_geoip_reader),
            patch("log_enricher.handler.reverse_dns", return_value=""),
            patch("log_enricher.handler.sns") as mock_sns,
        ):
            from log_enricher.handler import handler

            handler(event_1, None)
            first_call_count = mock_sns.publish.call_count

            handler(event_2, None)
            second_call_count = mock_sns.publish.call_count

        assert first_call_count > 0
        assert second_call_count == first_call_count


class TestRdnsCache:
    def test_reverse_dns_called_once_per_unique_ip(self, aws_clients, mock_geoip_reader):
        s3, _ = aws_clients
        log_key = "cf-logs/E1234.2026-04-14-15.rdns.gz"
        log_content = build_cf_log(
            [
                make_cf_log_line(c_ip="203.0.113.1", uri_stem="/"),
                make_cf_log_line(c_ip="203.0.113.1", uri_stem="/_astro/a.js"),
                make_cf_log_line(c_ip="203.0.113.1", uri_stem="/favicon.ico"),
                make_cf_log_line(c_ip="203.0.113.2", uri_stem="/"),
                make_cf_log_line(c_ip="203.0.113.2", uri_stem="/style.css"),
            ]
        )
        upload_cf_log(s3, log_key, log_content)
        event = make_s3_event(BUCKET_NAME, log_key)

        with (
            patch("log_enricher.handler.get_geoip_reader", return_value=mock_geoip_reader),
            patch("log_enricher.handler.reverse_dns", return_value="host.example.com") as mock_rdns,
        ):
            from log_enricher.handler import handler

            handler(event, None)

        # Two unique IPs, five log lines → exactly two rDNS lookups.
        assert mock_rdns.call_count == 2


class TestAlertMarkerKey:
    def test_dedup_marker_uses_type_date_city(self, aws_clients, mock_geoip_reader):
        s3, _ = aws_clients
        log_key = "cf-logs/E1234.2026-04-14-15.marker.gz"
        log_content = build_cf_log(
            [
                make_cf_log_line(c_ip="203.0.113.1", uri_stem="/"),
                make_cf_log_line(c_ip="203.0.113.2", uri_stem="/"),
                make_cf_log_line(c_ip="203.0.113.3", uri_stem="/"),
            ]
        )
        upload_cf_log(s3, log_key, log_content)
        event = make_s3_event(BUCKET_NAME, log_key)

        with (
            patch("log_enricher.handler.get_geoip_reader", return_value=mock_geoip_reader),
            patch("log_enricher.handler.reverse_dns", return_value=""),
        ):
            from log_enricher.handler import handler

            handler(event, None)

        response = s3.list_objects_v2(Bucket=BUCKET_NAME, Prefix="alerts/city_cluster/2026-04-14/")
        keys = [obj["Key"] for obj in response.get("Contents", [])]
        assert "alerts/city_cluster/2026-04-14/london.sent" in keys
