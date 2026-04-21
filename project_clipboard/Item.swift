//
//  Item.swift
//  project_clipboard
//
//  Created by Adit's Macbook    on 14/04/26.
//

import Foundation

// MARK: - ClipboardContentType

/// Represents the kind of content captured from the system pasteboard.
///
/// Each case maps to a distinct pasteboard data type and determines
/// how the content is displayed, searched, and copied back.
enum ClipboardContentType: String, Codable, CaseIterable {
    case text
    case richText
    case url
    case file
    case image
    case unknown

    // MARK: - Display

    /// A localized, human-readable name for the content type.
    var displayName: String {
        switch self {
        case .text:      return "Teks"
        case .richText:  return "Rich Text"
        case .url:       return "URL"
        case .file:      return "File"
        case .image:     return "Gambar"
        case .unknown:   return "Lainnya"
        }
    }

    /// SF Symbol name used as the leading icon in list rows.
    var systemImageName: String {
        switch self {
        case .text:      return "text.alignleft"
        case .richText:  return "textformat"
        case .url:       return "link"
        case .file:      return "doc"
        case .image:     return "photo"
        case .unknown:   return "questionmark.square.dashed"
        }
    }

    // MARK: - Search

    /// Alternative keywords used when filtering entries by search query.
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

// MARK: - ClipboardEntry

/// A single clipboard history item persisted to disk.
///
/// Entries are ``Identifiable`` by UUID and ``Codable`` for JSON serialization.
/// Pinned entries are sorted above unpinned ones regardless of capture time.
struct ClipboardEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var capturedAt: Date = .now
    var contentType: ClipboardContentType
    var preview: String
    var value: String
    var binaryData: Data?
    var isPinned: Bool = false
}
