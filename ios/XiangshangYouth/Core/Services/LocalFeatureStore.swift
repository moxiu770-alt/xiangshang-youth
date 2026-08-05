import Foundation

/// Persists the front-end workflow state while the remote APIs are unavailable.
/// Keeping it behind this small store lets the UI move to remote sync later without
/// replacing its interaction model.
struct LocalFeatureState: Codable, Equatable {
    var registeredActivities: Set<String> = []
    var activityRegistrations: [ActivityRegistration] = []
    var completedAssessments: Set<String> = []
    var courseProgress: [String: Double] = [:]
    var supportMessages: [SupportChatMessage] = []
    var classPosts: [ClassPostDraft] = []
    var uploadedTaskIDs: Set<String> = []
    var checkInDates: Set<String> = []
    var drafts: [String: String] = [:]
    var expertAppointments: [ExpertAppointment] = []
    var courseUploads: [CourseUploadRecord] = []
    var studentTaskStatuses: [String: TaskStatus] = [:]
    var reviewNotes: [String: String] = [:]
    var sessionProfile: UserProfile?
    var sessionRole: UserRole?
    var selectedChildID: String? = nil
    var boundChildIDs: Set<String> = []
    /// Message ids opened by the user.  Mock messages remain immutable, so the
    /// local read set is the client-side source of truth until MessageApi is live.
    var readMessageIDs: Set<String> = []
    var settings = LocalAppSettings()
}

enum LocalSubmissionStatus: String, Codable, Equatable {
    case draft, submitting, submitted, failed
}

struct ActivityRegistration: Codable, Identifiable, Equatable {
    let id: UUID
    let activityID: String
    var contactName: String
    var phone: String
    var status: LocalSubmissionStatus
    let createdAt: Date
}

struct ExpertAppointment: Codable, Identifiable, Equatable {
    let id: UUID
    let expertName: String
    let preferredDate: String
    let note: String
    var status: LocalSubmissionStatus
    let createdAt: Date
}

struct CourseUploadRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let taskID: String
    var attendanceCount: Int
    var notes: String
    var attachmentName: String
    var status: LocalSubmissionStatus
    let createdAt: Date
}

struct LocalAppSettings: Codable, Equatable {
    var notificationsEnabled = true
    var reduceMotion = false
}

struct SupportChatMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let isMine: Bool
    let createdAt: Date
}

struct ClassPostDraft: Codable, Identifiable, Equatable {
    let id: UUID
    let author: String
    var content: String
    let createdAt: Date
}

@MainActor
final class LocalFeatureStore: ObservableObject {
    @Published private(set) var state: LocalFeatureState
    private let key = "xiangshang.local-feature-state.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let decoded = Self.decodePersistedState(data) {
            state = decoded
        } else {
            state = LocalFeatureState()
        }
    }

    func update(_ body: (inout LocalFeatureState) -> Void) {
        body(&state)
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: key) }
    }

    func reset() { state = LocalFeatureState(); defaults.removeObject(forKey: key) }

    /// Adds defaults introduced after v1 without discarding existing drafts or
    /// submissions when users update the app.
    private static func decodePersistedState(_ data: Data) -> LocalFeatureState? {
        let decoder = JSONDecoder()
        if let current = try? decoder.decode(LocalFeatureState.self, from: data) { return current }
        guard var legacy = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if legacy["reviewNotes"] == nil { legacy["reviewNotes"] = [String: String]() }
        if legacy["selectedChildID"] == nil { legacy["selectedChildID"] = NSNull() }
        if legacy["boundChildIDs"] == nil { legacy["boundChildIDs"] = [String]() }
        if legacy["readMessageIDs"] == nil { legacy["readMessageIDs"] = [String]() }
        guard let migrated = try? JSONSerialization.data(withJSONObject: legacy) else { return nil }
        return try? decoder.decode(LocalFeatureState.self, from: migrated)
    }
}
