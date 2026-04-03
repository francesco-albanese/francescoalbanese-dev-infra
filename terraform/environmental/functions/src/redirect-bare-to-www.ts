export function handler(
	event: AWSCloudFrontFunction.Event,
): AWSCloudFrontFunction.Request | AWSCloudFrontFunction.Response {
	const host = event.request.headers.host.value;

	if (host === __DOMAIN__) {
		return {
			statusCode: 301,
			headers: {
				location: {
					value: "https://www." + __DOMAIN__ + event.request.uri,
				},
			},
		};
	}

	return event.request;
}
