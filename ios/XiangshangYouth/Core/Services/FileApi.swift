import Foundation
import UIKit
import UniformTypeIdentifiers

/// Owns the two-step file contract used by the central service. The course
/// command receives a server-side file id only after the bytes have reached
/// private storage; a filename or a local URL is never mistaken for an upload.
struct FileApi {
    private let client: ApiClient
    private static let maximumBytes = 20 * 1024 * 1024

    init(client: ApiClient = .shared) { self.client = client }

    func uploadCourseAttachment(localReference: String, displayName: String) async throws -> String {
        try await uploadAttachment(localReference: localReference, displayName: displayName, purpose: "course_upload_attachment")
    }

    func uploadClassPostAttachment(localReference: String, displayName: String) async throws -> String {
        try await uploadAttachment(localReference: localReference, displayName: displayName, purpose: "class_post_attachment")
    }

    func downloadClassPostAttachment(fileID: String) async throws -> Data {
        guard !fileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CourseAttachmentError.unavailable }
        return try await client.download(path: "v1/files/\(fileID)/content")
    }

    private func uploadAttachment(localReference: String, displayName: String, purpose: String) async throws -> String {
        guard let url = URL(string: localReference), url.isFileURL else { throw CourseAttachmentError.unavailable }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do { data = try Data(contentsOf: url, options: .mappedIfSafe) }
        catch { throw CourseAttachmentError.unavailable }
        guard !data.isEmpty else { throw CourseAttachmentError.empty }
        guard data.count <= Self.maximumBytes else { throw CourseAttachmentError.tooLarge }

        let mimeType = Self.mimeType(for: url)
        let ticket: FileUploadTicket = try await client.request(
            path: "v1/files/presign",
            method: "POST",
            body: FilePresignRequest(fileName: displayName, contentType: mimeType, fileSize: data.count, purpose: purpose),
            type: FileUploadTicket.self
        )
        let uploadRequest = client.makeRequest(
            path: "v1/files/\(ticket.id)/content",
            method: "PUT",
            body: data,
            contentType: mimeType
        )
        let receipt: FileUploadReceipt = try await client.request(uploadRequest, type: FileUploadReceipt.self)
        guard receipt.status == "uploaded" else { throw ApiError.invalidResponse }
        return receipt.id
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "mp4": return "video/mp4"
        default: return "application/octet-stream"
        }
    }
}

enum CourseAttachmentError: LocalizedError {
    case unavailable, empty, tooLarge

    var errorDescription: String? {
        switch self {
        case .unavailable: "附件无法读取，请重新选择照片后提交。"
        case .empty: "所选附件为空，请重新选择照片。"
        case .tooLarge: "附件超过 20MB，请压缩后重新选择。"
        }
    }
}

/// Copies source images into the app container at selection time. This avoids
/// relying on temporary picker permissions when an offline draft is reopened.
enum CourseAttachmentStore {
    static func persistImportedFile(_ source: URL) throws -> (name: String, reference: String) {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: source, options: .mappedIfSafe)
        guard !data.isEmpty else { throw CourseAttachmentError.empty }
        guard data.count <= 20 * 1024 * 1024 else { throw CourseAttachmentError.tooLarge }
        let ext = source.pathExtension.lowercased().isEmpty ? "jpg" : source.pathExtension.lowercased()
        let name = "课堂照片-\(UUID().uuidString).\(ext)"
        let destination = try destinationURL(name: name)
        try data.write(to: destination, options: .atomic)
        return (name, destination.absoluteString)
    }

    static func persistCameraImage(_ image: UIImage) throws -> (name: String, reference: String) {
        guard let data = image.jpegData(compressionQuality: 0.86) else { throw CourseAttachmentError.unavailable }
        return try persistImageData(data, suggestedName: "课堂照片-\(UUID().uuidString).jpg")
    }

    static func persistImageData(_ data: Data, suggestedName: String = "班级圈照片.jpg") throws -> (name: String, reference: String) {
        try persistMediaData(data, suggestedName: suggestedName)
    }

    /// Copies a selected image or MP4 clip into the private app container. The
    /// local reference is only a draft input; the backend returns the upload id.
    static func persistMediaData(_ data: Data, suggestedName: String) throws -> (name: String, reference: String) {
        guard !data.isEmpty else { throw CourseAttachmentError.empty }
        guard data.count <= 20 * 1024 * 1024 else { throw CourseAttachmentError.tooLarge }
        let trimmed = suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? "班级圈照片-\(UUID().uuidString).jpg" : trimmed
        let name = baseName.contains(".") ? baseName : "\(baseName).jpg"
        let destination = try destinationURL(name: name)
        try data.write(to: destination, options: .atomic)
        return (name, destination.absoluteString)
    }

    static func mediaKind(for contentTypes: [UTType]) throws -> (type: String, extension: String) {
        if contentTypes.contains(where: { $0.conforms(to: .mpeg4Movie) }) { return ("video", "mp4") }
        if contentTypes.contains(where: { $0.conforms(to: .png) }) { return ("image", "png") }
        if contentTypes.contains(where: { $0.conforms(to: .jpeg) || $0.conforms(to: .image) }) { return ("image", "jpg") }
        throw CourseAttachmentError.unavailable
    }

    private static func destinationURL(name: String) throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("CourseAttachments", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(name, isDirectory: false)
    }
}

private struct FilePresignRequest: Encodable {
    let fileName: String
    let contentType: String
    let fileSize: Int
    let purpose: String
}

private struct FileUploadTicket: Decodable { let id: String }
private struct FileUploadReceipt: Decodable { let id: String; let status: String }
