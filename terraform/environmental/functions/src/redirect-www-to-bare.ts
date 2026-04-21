// Scanner probes. Unanchored: scanners fan out across nested prefixes
// (`/site/wp-includes/...`) and send leading double-slashes (`//xmlrpc.php`).
const SCANNER_PATH =
	/\/xmlrpc\.php|\/\.git(\/|$)|\/\.env|\/\.aws|\/\.ssh|\/\.vscode|\/\.DS_Store|\/wp-(admin|login|content|includes|config)|\/wlwmanifest\.xml|\/phpmyadmin|\/adminer|\/phpinfo|^\/\/|:\/\/|\/https?\//i;

// Non-human clients. Narrow regex by design — 1ms CPU budget.
const BOT_UA =
	/curl|wget|python-requests|python-urllib|go-http-client|okhttp|libwww-perl|masscan|nmap|nikto|nuclei|zgrab|scrapy|httpx|gobuster|feroxbuster/i;

const FORBIDDEN: AWSCloudFrontFunction.Response = {
	statusCode: 403,
	statusDescription: "Forbidden",
};

export function handler(
	event: AWSCloudFrontFunction.Event,
): AWSCloudFrontFunction.Request | AWSCloudFrontFunction.Response {
	const uri = event.request.uri;
	if (SCANNER_PATH.test(uri)) {
		return FORBIDDEN;
	}

	const ua = event.request.headers["user-agent"]?.value ?? "";
	if (BOT_UA.test(ua)) {
		return FORBIDDEN;
	}

	const host = event.request.headers.host.value;
	if (host === "www." + __DOMAIN__) {
		return {
			statusCode: 301,
			headers: {
				location: {
					value: "https://" + __DOMAIN__ + uri,
				},
			},
		};
	}

	return event.request;
}
