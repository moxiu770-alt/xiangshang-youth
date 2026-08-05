import Foundation

struct MessageItem: Identifiable, Codable { let id: String; let title: String; let content: String; let time: String; let isRead: Bool; let category: String }
