function handler(event) {
	var host = event.request.headers.host.value;
	if (host === "francescoalbanese.dev") {
		return {
			statusCode: 301,
			headers: {
				location: {
					value: "https://www.francescoalbanese.dev" + event.request.uri,
				},
			},
		};
	}
	return event.request;
}
