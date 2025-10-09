//
//  User.swift
//  FlixorMac
//
//  User model
//

import Foundation

struct User: Codable, Identifiable {
    let id: String
    let username: String
    let email: String?
    let thumb: String?
}

struct SessionInfo: Codable {
    let authenticated: Bool
    let user: User?
}

struct AuthResponse: Codable {
    let token: String
    let user: User
}
