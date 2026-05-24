import Foundation
import Darwin

public struct TunnelParsedConfig: Equatable {
    public let inboundPort: Int
    public let serverAddress: String?
    public let serverPort: Int?

    public init(inboundPort: Int, serverAddress: String?, serverPort: Int?) {
        self.inboundPort = inboundPort
        self.serverAddress = serverAddress
        self.serverPort = serverPort
    }
}

public struct TunnelPreparedConfig {
    public let data: Data
    public let logMessages: [String]
    public let proxyUsesXhttp: Bool

    public init(data: Data, logMessages: [String], proxyUsesXhttp: Bool) {
        self.data = data
        self.logMessages = logMessages
        self.proxyUsesXhttp = proxyUsesXhttp
    }
}

/// Pure JSON normalizer for the macOS Packet Tunnel.
///
/// Keep this logic outside `NEPacketTunnelProvider` so we can unit-test the
/// failure-prone parts without launching a real NetworkExtension process. The
/// helper intentionally preserves proxy credentials and VLESS
/// `users[].encryption` values byte-for-byte; the XHTTP/none incident proved
/// that mutating or dropping those server-provisioned values can produce a VPN
/// that connects locally but cannot fetch HTTP bytes.
public enum TunnelXrayConfigPreparer {
    public static func parseConfig(jsonData: Data) -> TunnelParsedConfig? {
        guard
            let configJSON = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
            let inboundPort = firstLocalInboundPort(configJSON: configJSON)
        else {
            return nil
        }
        return TunnelParsedConfig(
            inboundPort: inboundPort,
            serverAddress: parseServerAddress(configJSON: configJSON),
            serverPort: parseServerPort(configJSON: configJSON)
        )
    }

    public static func prepare(
        jsonData: Data,
        resolveIPv4: (String) -> String? = { _ in nil }
    ) -> TunnelPreparedConfig? {
        do {
            guard var configJSON = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
                return nil
            }
            var messages: [String] = []

            if var log = configJSON["log"] as? [String: Any] {
                log["access"] = ""
                log["error"] = ""
                log["loglevel"] = "debug"
                log["dnsLog"] = false
                configJSON["log"] = log
            } else {
                configJSON["log"] = [
                    "access": "",
                    "error": "",
                    "loglevel": "debug",
                    "dnsLog": false
                ]
            }
            messages.append("Disabled XRay file log outputs for packet tunnel")

            ensureXrayDNSUsesIPv4(configJSON: &configJSON, messages: &messages)

            if var routing = configJSON["routing"] as? [String: Any] {
                routing["domainStrategy"] = "AsIs"
                configJSON["routing"] = routing
            } else {
                configJSON["routing"] = ["domainStrategy": "AsIs"]
            }

            var inbounds = configJSON["inbounds"] as? [[String: Any]] ?? []
            let localInboundTags = normalizeLocalInbounds(
                configJSON: &configJSON,
                inbounds: &inbounds,
                messages: &messages
            )

            var proxyUsesXhttp = false
            var proxyOutboundTag: String?
            if var outbounds = configJSON["outbounds"] as? [[String: Any]] {
                for index in outbounds.indices {
                    let tag = outbounds[index]["tag"] as? String
                    let protocolType = outbounds[index]["protocol"] as? String
                    guard tag == "proxy" || protocolType != "freedom" && protocolType != "blackhole" else {
                        continue
                    }
                    let candidateTag: String
                    if let tag, !tag.isEmpty {
                        candidateTag = tag
                    } else {
                        candidateTag = uniqueOutboundTag(outbounds: outbounds, preferred: "proxy")
                        outbounds[index]["tag"] = candidateTag
                        messages.append("Tagged proxy outbound as \(candidateTag) for packet tunnel routing")
                    }
                    proxyOutboundTag = candidateTag

                    var streamSettings = outbounds[index]["streamSettings"] as? [String: Any] ?? [:]
                    let network = streamSettings["network"] as? String ?? "?"
                    proxyUsesXhttp = network == "xhttp"

                    if let serverAddress = parseServerAddress(configJSON: ["outbounds": [outbounds[index]]]),
                       shouldResolve(serverAddress) {
                        if let resolvedAddress = resolveIPv4(serverAddress) {
                            upsertXrayDNSHost(
                                configJSON: &configJSON,
                                host: serverAddress,
                                address: resolvedAddress
                            )
                            messages.append("Resolved proxy server domain \(serverAddress) to IPv4 \(resolvedAddress) for packet tunnel routing")
                        } else {
                            messages.append("Keeping proxy server domain unresolved in Xray config; route exclusion resolves it separately")
                        }
                    }

                    if var sockopt = streamSettings["sockopt"] as? [String: Any],
                       sockopt.removeValue(forKey: "domainStrategy") != nil {
                        if sockopt.isEmpty {
                            streamSettings.removeValue(forKey: "sockopt")
                        } else {
                            streamSettings["sockopt"] = sockopt
                        }
                    }
                    outbounds[index]["streamSettings"] = streamSettings
                    break
                }
                configJSON["outbounds"] = outbounds
            }

            if let proxyOutboundTag,
               ensureForceProxyRule(
                configJSON: &configJSON,
                inboundTags: localInboundTags,
                outboundTag: proxyOutboundTag
               ) {
                messages.append("Forced local tunnel inbound(s) \(localInboundTags.joined(separator: ",")) to proxy outbound \(proxyOutboundTag)")
            }

            let blackholeTag = ensureBlackholeOutbound(configJSON: &configJSON)
            if ensureUdp443BlockRule(configJSON: &configJSON, outboundTag: blackholeTag) {
                messages.append("Added UDP/443 block rule to force browser TCP fallback")
            }

            let data = try JSONSerialization.data(withJSONObject: configJSON, options: [])
            return TunnelPreparedConfig(data: data, logMessages: messages, proxyUsesXhttp: proxyUsesXhttp)
        } catch {
            return nil
        }
    }

    public static func parseServerAddress(configJSON: [String: Any]) -> String? {
        guard let outbounds = configJSON["outbounds"] as? [[String: Any]] else {
            return nil
        }
        for outbound in outbounds {
            let tag = outbound["tag"] as? String
            let protocolType = outbound["protocol"] as? String
            guard tag == "proxy" || protocolType != "freedom" && protocolType != "blackhole" else {
                continue
            }
            guard let settings = outbound["settings"] as? [String: Any] else {
                continue
            }
            if let vnext = settings["vnext"] as? [[String: Any]],
               let address = vnext.first?["address"] as? String,
               !address.isEmpty {
                return address
            }
            if let servers = settings["servers"] as? [[String: Any]],
               let address = servers.first?["address"] as? String,
               !address.isEmpty {
                return address
            }
            if let address = settings["address"] as? String, !address.isEmpty {
                return address
            }
        }
        return nil
    }

    public static func parseServerPort(configJSON: [String: Any]) -> Int? {
        guard let outbounds = configJSON["outbounds"] as? [[String: Any]] else {
            return nil
        }
        for outbound in outbounds {
            let tag = outbound["tag"] as? String
            let protocolType = outbound["protocol"] as? String
            guard tag == "proxy" || protocolType != "freedom" && protocolType != "blackhole" else {
                continue
            }
            guard let settings = outbound["settings"] as? [String: Any] else {
                continue
            }
            if let vnext = settings["vnext"] as? [[String: Any]],
               let port = vnext.first?["port"] as? Int {
                return port
            }
            if let servers = settings["servers"] as? [[String: Any]],
               let port = servers.first?["port"] as? Int {
                return port
            }
            if let port = settings["port"] as? Int {
                return port
            }
        }
        return nil
    }

    private static func firstLocalInboundPort(configJSON: [String: Any]) -> Int? {
        guard let inbounds = configJSON["inbounds"] as? [[String: Any]] else {
            return nil
        }
        for inbound in inbounds {
            guard let protocolType = inbound["protocol"] as? String,
                  let port = inbound["port"] as? Int else {
                continue
            }
            if protocolType == "socks" {
                return port
            }
        }
        for inbound in inbounds {
            guard let protocolType = inbound["protocol"] as? String,
                  let port = inbound["port"] as? Int else {
                continue
            }
            if protocolType == "http" {
                return port
            }
        }
        return nil
    }

    private static func ensureXrayDNSUsesIPv4(
        configJSON: inout [String: Any],
        messages: inout [String]
    ) {
        var dns = configJSON["dns"] as? [String: Any] ?? [:]
        let previousStrategy = dns["queryStrategy"] as? String
        dns["queryStrategy"] = "UseIPv4"
        configJSON["dns"] = dns

        if previousStrategy == nil {
            messages.append("Added Xray DNS queryStrategy=UseIPv4 for packet tunnel")
        } else if previousStrategy != "UseIPv4" {
            messages.append("Changed Xray DNS queryStrategy from \(previousStrategy ?? "nil") to UseIPv4 for packet tunnel")
        }
    }

    private static func upsertXrayDNSHost(
        configJSON: inout [String: Any],
        host: String,
        address: String
    ) {
        var dns = configJSON["dns"] as? [String: Any] ?? [:]
        var hosts = dns["hosts"] as? [String: Any] ?? [:]
        hosts[host] = address
        dns["hosts"] = hosts
        dns["queryStrategy"] = "UseIPv4"
        configJSON["dns"] = dns
    }

    private static func normalizeLocalInbounds(
        configJSON: inout [String: Any],
        inbounds: inout [[String: Any]],
        messages: inout [String]
    ) -> [String] {
        let sniffing: [String: Any] = [
            "enabled": true,
            "destOverride": ["http", "tls", "quic"],
            "routeOnly": true
        ]

        var hasSocksInbound = false
        var changedSocksInbound = false
        var localInboundTags: [String] = []
        for index in inbounds.indices {
            let protocolType = inbounds[index]["protocol"] as? String
            guard protocolType == "socks" || protocolType == "http" else {
                continue
            }

            if let tag = inbounds[index]["tag"] as? String, !tag.isEmpty {
                localInboundTags.append(tag)
            } else {
                let tag = uniqueInboundTag(inbounds: inbounds, preferred: protocolType ?? "inbound")
                inbounds[index]["tag"] = tag
                localInboundTags.append(tag)
                messages.append("Tagged local \(protocolType ?? "proxy") inbound as \(tag) for packet tunnel routing")
            }
            inbounds[index]["listen"] = "127.0.0.1"
            inbounds[index]["sniffing"] = sniffing

            guard protocolType == "socks" else {
                continue
            }

            hasSocksInbound = true
            let oldSettings = inbounds[index]["settings"] as? [String: Any] ?? [:]
            var settings: [String: Any] = ["auth": "noauth", "udp": true]
            if let userLevel = oldSettings["userLevel"] as? Int {
                settings["userLevel"] = userLevel
            }
            if !NSDictionary(dictionary: oldSettings).isEqual(to: settings) {
                changedSocksInbound = true
            }
            inbounds[index]["settings"] = settings
        }

        if !hasSocksInbound {
            let port = nextAvailablePort(preferred: 10807, inbounds: inbounds)
            let tag = uniqueInboundTag(inbounds: inbounds, preferred: "socks")
            inbounds.insert([
                "tag": tag,
                "listen": "127.0.0.1",
                "port": port,
                "protocol": "socks",
                "settings": ["auth": "noauth", "udp": true],
                "sniffing": sniffing
            ], at: 0)
            localInboundTags.insert(tag, at: 0)
            messages.append("Injected local SOCKS inbound for packet tunnel on port \(port)")
        } else if changedSocksInbound {
            messages.append("Enabled UDP/noauth on local SOCKS inbound for packet tunnel")
        }

        configJSON["inbounds"] = inbounds
        return localInboundTags
    }

    private static func nextAvailablePort(preferred: Int, inbounds: [[String: Any]]) -> Int {
        let usedPorts = Set(inbounds.compactMap { $0["port"] as? Int })
        var port = preferred
        while usedPorts.contains(port) {
            port += 1
        }
        return port
    }

    private static func uniqueInboundTag(inbounds: [[String: Any]], preferred: String) -> String {
        let usedTags = Set(inbounds.compactMap { $0["tag"] as? String })
        guard usedTags.contains(preferred) else {
            return preferred
        }
        var suffix = 1
        while usedTags.contains("\(preferred)-\(suffix)") {
            suffix += 1
        }
        return "\(preferred)-\(suffix)"
    }

    private static func ensureBlackholeOutbound(configJSON: inout [String: Any]) -> String {
        var outbounds = configJSON["outbounds"] as? [[String: Any]] ?? []
        if let tag = outbounds.first(where: { outbound in
            (outbound["protocol"] as? String) == "blackhole"
        })?["tag"] as? String {
            return tag
        }

        let tag = uniqueOutboundTag(outbounds: outbounds, preferred: "blackhole")
        outbounds.append([
            "tag": tag,
            "protocol": "blackhole",
            "settings": [:]
        ])
        configJSON["outbounds"] = outbounds
        return tag
    }

    private static func uniqueOutboundTag(outbounds: [[String: Any]], preferred: String) -> String {
        let usedTags = Set(outbounds.compactMap { $0["tag"] as? String })
        guard usedTags.contains(preferred) else {
            return preferred
        }
        var suffix = 1
        while usedTags.contains("\(preferred)-\(suffix)") {
            suffix += 1
        }
        return "\(preferred)-\(suffix)"
    }

    private static func ensureUdp443BlockRule(configJSON: inout [String: Any], outboundTag: String) -> Bool {
        var routing = configJSON["routing"] as? [String: Any] ?? [:]
        var rules = routing["rules"] as? [[String: Any]] ?? []
        let alreadyExists = rules.contains { rule in
            (rule["type"] as? String) == "field" &&
            (rule["network"] as? String) == "udp" &&
            String(describing: rule["port"] ?? "") == "443" &&
            (rule["outboundTag"] as? String) == outboundTag
        }
        if alreadyExists {
            return false
        }
        rules.insert([
            "type": "field",
            "network": "udp",
            "port": "443",
            "outboundTag": outboundTag
        ], at: 0)
        routing["rules"] = rules
        configJSON["routing"] = routing
        return true
    }

    private static func ensureForceProxyRule(
        configJSON: inout [String: Any],
        inboundTags: [String],
        outboundTag: String
    ) -> Bool {
        guard !inboundTags.isEmpty else {
            return false
        }
        var routing = configJSON["routing"] as? [String: Any] ?? [:]
        var rules = routing["rules"] as? [[String: Any]] ?? []
        let sortedInboundTags = inboundTags.sorted()
        let alreadyExists = rules.contains { rule in
            (rule["type"] as? String) == "field" &&
            (rule["outboundTag"] as? String) == outboundTag &&
            ((rule["inboundTag"] as? [String]) ?? []).sorted() == sortedInboundTags
        }
        if alreadyExists {
            return false
        }
        rules.insert([
            "type": "field",
            "inboundTag": sortedInboundTags,
            "outboundTag": outboundTag
        ], at: 0)
        routing["rules"] = rules
        configJSON["routing"] = routing
        return true
    }

    private static func replaceProxyServerDomainWithIPv4(
        outbound: inout [String: Any],
        resolveIPv4: (String) -> String?
    ) -> Bool {
        guard var settings = outbound["settings"] as? [String: Any] else {
            return false
        }

        if var vnext = settings["vnext"] as? [[String: Any]],
           !vnext.isEmpty,
           let address = vnext[0]["address"] as? String,
           shouldResolve(address),
           let ip = resolveIPv4(address) {
            vnext[0]["address"] = ip
            settings["vnext"] = vnext
            outbound["settings"] = settings
            return true
        }

        if var servers = settings["servers"] as? [[String: Any]],
           !servers.isEmpty,
           let address = servers[0]["address"] as? String,
           shouldResolve(address),
           let ip = resolveIPv4(address) {
            servers[0]["address"] = ip
            settings["servers"] = servers
            outbound["settings"] = settings
            return true
        }

        if let address = settings["address"] as? String,
           shouldResolve(address),
           let ip = resolveIPv4(address) {
            settings["address"] = ip
            outbound["settings"] = settings
            return true
        }

        return false
    }

    private static func shouldResolve(_ address: String) -> Bool {
        !address.isEmpty && !isIPv4Literal(address) && !isIPv6Literal(address)
    }

    private static func isIPv4Literal(_ value: String) -> Bool {
        var address = in_addr()
        return value.withCString { inet_pton(AF_INET, $0, &address) } == 1
    }

    private static func isIPv6Literal(_ value: String) -> Bool {
        var address = in6_addr()
        return value.withCString { inet_pton(AF_INET6, $0, &address) } == 1
    }
}
