//
//  Item.swift
//  project_clipboard
//
//  Created by Adit's Macbook    on 14/04/26.
//

import Foundation

enum ClipboardContentType: String, Codable, CaseIterable {
    case text
    case richText
    case url
    case file
    case image
    case unknown

    var displayName: String {
        switch self {
        case .text:
            return "Teks"
        case .richText:
            return "Rich Text"
        case .url:
            return "URL"
        case .file:
            return "File"
        case .image:
            return "Gambar"
        case .unknown:
            return "Lainnya"
        }
    }

    var systemImageName: String {
        switch self {
        case .text:
            return "text.alignleft"
        case .richText:
            return "textformat"
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

    var searchAliases: [String] {
        switch self {
        case .text:
            return ["teks", "text", "plain text", "string"]
        case .richText:
            return ["rich text", "rtf", "formatted text", "teks kaya"]
        case .url:
            return ["url", "link", "tautan", "alamat web"]
        case .file:
            return ["file", "dokumen", "path", "folder"]
        case .image:
            return ["gambar", "image", "foto", "photo", "png", "jpg"]
        case .unknown:
            return ["lainnya", "unknown"]
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
