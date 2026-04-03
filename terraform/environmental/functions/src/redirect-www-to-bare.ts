export function handler(
	event: AWSCloudFrontFunction.Event,
): AWSCloudFrontFunction.Request | AWSCloudFrontFunction.Response {
	const host = event.request.headers.host.value;

	if (host === "www." + __DOMAIN__) {
		return {
			statusCode: 301,
			headers: {
				location: {
					value: "https://" + __DOMAIN__ + event.request.uri,
				},
			},
		};
	}

	return event.request;
}
