//
//  PlexServer.swift
//  FlixorMac
//
//  Models for Plex server connections
//

import Foundation

struct PlexServer: Codable, Identifiable {
    let id: String
    let name: String
    let host: String?
    let machineIdentifier: String?
    let isActive: Bool?
    let owned: Bool?
    let presence: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case host
        case machineIdentifier
        case isActive
        case owned
        case presence
    }
}

struct PlexConnection: Codable {
    let uri: String
    let local: Bool?
    let relay: Bool?
    let IPv6: Bool?

    enum CodingKeys: String, CodingKey {
        case uri
        case local
        case relay
        case IPv6
    }
}

struct PlexConnectionsResponse: Codable {
    let connections: [PlexConnection]
}

struct PlexAuthServer: Codable {
    let clientIdentifier: String
    let token: String
    let name: String?
}
