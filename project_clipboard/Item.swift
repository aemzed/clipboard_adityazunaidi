//
//  Item.swift
//  project_clipboard
//
//  Created by Adit's Macbook    on 14/04/26.
//

import Foundation

enum ClipboardContentType: String, Codable, CaseIterable {
    case text
    case url
    case file
    case image
    case unknown

    var displayName: String {
        switch self {
        case .text:
            return "Text"
        case .url:
            return "URL"
        case .file:
            return "File"
        case .image:
            return "Image"
        case .unknown:
            return "Unknown"
        }
    }

    var systemImageName: String {
        switch self {
        case .text:
            return "text.alignleft"
        case .url:
            return "link"
        case .file:
            return "doc"
        case .image:
            return "photo"
        case .unknown:
            return "questionmark.square.dashed"
        }
    }
}

struct ClipboardEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var capturedAt: Date = .now
    var contentType: ClipboardContentType
    var preview: String
    var value: String
    var binaryData: Data?
    var isPinned: Bool = false
}
