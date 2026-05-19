import Foundation

extension HTTPURLResponse {
    /// Returns `true` if `statusCode` is in range 200...299.
    /// Otherwise `false`.
    var isSuccessful: Bool {
        200 ... 299 ~= statusCode
    }
}

extension Client {
    func sendRequest(
        to urlString: String,
        input: Data?,
        queryParams: [String: Any]? = nil,
        options: RunOptions,
        includeQueuePriority: Bool = true
    ) async throws -> Data {
        guard var url = URL(string: urlString) else {
            throw FalError.invalidUrl(url: urlString)
        }

        if let queryParams,
           !queryParams.isEmpty,
           var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        {
            let additionalQueryItems = queryParams.map {
                URLQueryItem(name: $0.key, value: String(describing: $0.value))
            }
            let additionalNames = Set(additionalQueryItems.map(\.name))
            let existingQueryItems = (urlComponents.queryItems ?? []).filter { !additionalNames.contains($0.name) }
            urlComponents.queryItems = existingQueryItems + additionalQueryItems
            url = urlComponents.url ?? url
        }

        let targetUrl = url
        if let requestProxy = config.requestProxy {
            guard let proxyUrl = URL(string: requestProxy) else {
                throw FalError.invalidUrl(url: requestProxy)
            }
            url = proxyUrl
        }

        var request = URLRequest(url: url, timeoutInterval: options.timeoutInterval)
        request.httpMethod = options.httpMethod.rawValue.uppercased()
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(userAgent, forHTTPHeaderField: "user-agent")
        options.applyHeaders(to: &request, includeQueuePriority: includeQueuePriority)

        // setup credentials if available
        if shouldApplyAuthorizationHeader {
            let credentials = config.credentials.rawValue
            if !credentials.isEmpty {
                let authValue = switch config.authScheme {
                case .key:
                    "Key \(credentials)"
                case .bearer:
                    "Bearer \(credentials)"
                }
                request.setValue(authValue, forHTTPHeaderField: "authorization")
            }
        }

        // setup the request proxy if available
        if config.requestProxy != nil {
            request.setValue(targetUrl.absoluteString, forHTTPHeaderField: "x-fal-target-url")
        }

        if input != nil, options.httpMethod != .get {
            request.httpBody = input
        }
        let transportResponse = try await resolvedHTTPTransport.data(for: request)
        try checkResponseStatus(for: transportResponse.response, withData: transportResponse.data)
        return transportResponse.data
    }

    private var shouldApplyAuthorizationHeader: Bool {
        guard let requestProxy = config.requestProxy else {
            return true
        }
        guard config.authScheme == .bearer,
              let url = URL(string: requestProxy)
        else {
            return false
        }
        return url.scheme == "https" || url.isLoopback
    }

    func checkResponseStatus(for response: URLResponse, withData data: Data) throws {
        guard response is HTTPURLResponse else {
            throw FalError.invalidResultFormat
        }
        if let httpResponse = response as? HTTPURLResponse, !httpResponse.isSuccessful {
            let errorPayload = try? Payload.create(fromJSON: data)
            let statusCode = httpResponse.statusCode
            let headers = httpResponse.falDiagnosticHeaders
            let message = errorPayload?["detail"].stringValue
                ?? errorPayload?.stringValue
                ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
            let httpError = FalHTTPError(
                statusCode: statusCode,
                message: message,
                payload: errorPayload,
                requestId: headers["x-fal-request-id"],
                errorType: headers["x-fal-error-type"] ?? errorPayload?["error_type"].stringValue,
                requestTimeoutType: headers["x-fal-request-timeout-type"],
                headers: headers
            )
            throw FalError.httpError(httpError)
        }
    }

    var userAgent: String {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        return "fal.ai/swift-client 0.1.0 - \(osVersion)"
    }
}

private extension RunOptions {
    func applyHeaders(to request: inout URLRequest, includeQueuePriority: Bool) {
        for (name, value) in headers {
            guard !name.isProtectedCallerHeader else {
                continue
            }
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let startTimeout {
            request.setValue(startTimeout.headerNumberValue, forHTTPHeaderField: "X-Fal-Request-Timeout")
        }
        if let hint {
            request.setValue(hint, forHTTPHeaderField: "X-Fal-Runner-Hint")
        }
        if includeQueuePriority, let queuePriority {
            request.setValue(queuePriority.rawValue, forHTTPHeaderField: "X-Fal-Queue-Priority")
        }
        if isRetryDisabled {
            request.setValue("1", forHTTPHeaderField: "X-Fal-No-Retry")
        }
        if let storesInputOutput {
            request.setValue(storesInputOutput ? "1" : "0", forHTTPHeaderField: "X-Fal-Store-IO")
        }
        if let objectLifecyclePreference {
            request.setValue(objectLifecyclePreference.headerValue, forHTTPHeaderField: "X-Fal-Object-Lifecycle-Preference")
        }
        if isFallbackDisabled {
            request.setValue("true", forHTTPHeaderField: "x-app-fal-disable-fallback")
        }
    }
}

private extension String {
    var isProtectedCallerHeader: Bool {
        switch lowercased() {
        case "authorization",
             "proxy-authorization",
             "cookie",
             "host",
             "x-fal-target-url":
            return true
        default:
            return false
        }
    }
}

private extension FalObjectLifecyclePreference {
    var headerValue: String {
        "{\"expiration_duration_seconds\":\(expirationDuration.headerNumberValue)}"
    }
}

private extension TimeInterval {
    var headerNumberValue: String {
        if isFinite,
           self >= TimeInterval(Int.min),
           self <= TimeInterval(Int.max),
           rounded(.towardZero) == self
        {
            return String(Int(self))
        }
        return String(self)
    }
}

private extension HTTPURLResponse {
    var falDiagnosticHeaders: [String: String] {
        let allowedHeaders: Set<String> = [
            "x-fal-request-id",
            "x-fal-error-type",
            "x-fal-request-timeout-type",
        ]
        return allHeaderFields.reduce(into: [:]) { headers, entry in
            let name = String(describing: entry.key).lowercased()
            if allowedHeaders.contains(name) {
                headers[name] = String(describing: entry.value)
            }
        }
    }
}

private extension URL {
    var isLoopback: Bool {
        guard let host else {
            return false
        }
        return host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
    }
}
