import Foundation
import UniformTypeIdentifiers

/// The file types SmartPiP will open.
///
/// Deliberately narrow: local MOV/MP4 only, played by AVFoundation. No streaming,
/// no MKV, no third-party playback engine.
enum VideoFile {
    static let contentTypes: [UTType] = [.quickTimeMovie, .mpeg4Movie]

    static let contentTypeIdentifiers: [String] = contentTypes.map(\.identifier)

    /// Whether `url` points at a file SmartPiP can play.
    static func isSupported(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return contentTypes.contains { type.conforms(to: $0) }
    }
}
