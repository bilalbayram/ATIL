import Foundation

enum DefaultAppTarget: Hashable {
    case urlScheme(String)
    case contentType(String)
    case filenameExtension(String)
}

enum DefaultAppCategory: String, CaseIterable, Identifiable {
    case browser
    case email
    case plainText
    case markdown
    case json
    case sourceCode
    case pdf
    case image
    case archive
    case audio
    case video

    var id: String { rawValue }

    var title: String {
        switch self {
        case .browser: "Browser"
        case .email: "Email"
        case .plainText: "Plain Text"
        case .markdown: "Markdown"
        case .json: "JSON"
        case .sourceCode: "Source Code"
        case .pdf: "PDF"
        case .image: "Image"
        case .archive: "Archive"
        case .audio: "Audio"
        case .video: "Video"
        }
    }

    var subtitle: String {
        switch self {
        case .browser: "Open web links"
        case .email: "Open email links"
        case .plainText: "Open text files"
        case .markdown: "Open Markdown files"
        case .json: "Open JSON files"
        case .sourceCode: "Open source files"
        case .pdf: "Open PDF documents"
        case .image: "Open image files"
        case .archive: "Open archive files"
        case .audio: "Open audio files"
        case .video: "Open video files"
        }
    }

    var targets: [DefaultAppTarget] {
        switch self {
        case .browser:
            [.urlScheme("http"), .urlScheme("https")]
        case .email:
            [.urlScheme("mailto")]
        case .plainText:
            [.contentType("public.plain-text")]
        case .markdown:
            [.filenameExtension("md")]
        case .json:
            [.contentType("public.json")]
        case .sourceCode:
            [.contentType("public.source-code")]
        case .pdf:
            [.contentType("com.adobe.pdf")]
        case .image:
            [.contentType("public.image")]
        case .archive:
            [.contentType("public.archive")]
        case .audio:
            [.contentType("public.audio")]
        case .video:
            [.contentType("public.movie")]
        }
    }
}

struct DefaultAppOption: Identifiable, Hashable {
    let appURL: URL
    let bundleIdentifier: String?
    let displayName: String

    var id: String {
        bundleIdentifier ?? appURL.path
    }
}

enum DefaultAppCurrentSelection: Equatable {
    case none
    case app(DefaultAppOption)
    case multiple
}

struct DefaultAppCategoryState: Identifiable, Equatable {
    let category: DefaultAppCategory
    let currentSelection: DefaultAppCurrentSelection
    let candidates: [DefaultAppOption]

    var id: String { category.id }

    var selectedAppID: String? {
        guard case .app(let app) = currentSelection else { return nil }
        return app.id
    }

    var currentDisplayName: String {
        switch currentSelection {
        case .none:
            "No Default"
        case .app(let app):
            app.displayName
        case .multiple:
            "Multiple Apps"
        }
    }

    var currentIconPath: String? {
        guard case .app(let app) = currentSelection else { return nil }
        return app.appURL.path
    }

    var isUnavailable: Bool {
        candidates.isEmpty
    }
}

struct DefaultAppApplyResult {
    let state: DefaultAppCategoryState
    let error: Error?
}
