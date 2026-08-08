import Foundation
import Security

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
    var likedClassPostIDs: Set<UUID> = []
    var classPostComments: [ClassPostComment] = []
    var uploadedTaskIDs: Set<String> = []
    var checkInDates: Set<String> = []
    var drafts: [String: String] = [:]
    var expertAppointments: [ExpertAppointment] = []
    var courseUploads: [CourseUploadRecord] = []
    var studentTaskStatuses: [String: TaskStatus] = [:]
    /// Latest teacher-side queue update for each student.  The actual status
    /// remains immediately usable offline; this map only tracks remote
    /// acknowledgement and retry state.
    var taskStatusSyncStates: [String: LocalSubmissionStatus] = [:]
    var reviewNotes: [String: String] = [:]
    var sessionProfile: UserProfile?
    var sessionRole: UserRole?
    /// Account identity is distinct from the active workbench identity.  A
    /// parent who temporarily enters a teacher/principal mock workbench must
    /// get their own name back when returning to the family workspace.
    var parentAccountName: String? = nil
    var selectedChildID: String? = nil
    var boundChildIDs: Set<String> = []
    /// Keep dashboard context across a relaunch. These are presentation
    /// preferences only; the authoritative task and permission data remains
    /// repository-owned once remote mode is enabled.
    var selectedPrincipalTaskID: String? = nil
    var teacherUsesSportsWorkbench = false
    /// Message ids opened by the user.  Mock messages remain immutable, so the
    /// local read set is the client-side source of truth until MessageApi is live.
    var readMessageIDs: Set<String> = []
    var settings = LocalAppSettings()
}

enum LocalSubmissionStatus: String, Codable, Equatable {
    case draft, submitting, submitted, failed
    /// Accepted by the local Mock workflow but not acknowledged by the remote service.
    /// `submitted` remains decodable for state created by earlier builds.
    case pendingSync
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

struct ClassPostComment: Codable, Identifiable, Equatable {
    let id: UUID
    let postID: UUID
    let author: String
    let text: String
    let createdAt: Date
}

@MainActor
final class LocalFeatureStore: ObservableObject {
    @Published private(set) var state: LocalFeatureState
    private let key = "xiangshang.local-feature-state.v1"
    private let defaults: UserDefaults
    private let secureStore: KeychainStateStore?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Test suites and migration fixtures intentionally stay isolated in their
        // supplied UserDefaults. The production standard store uses Keychain so
        // drafts, child bindings and health workflow state are not plain text.
        self.secureStore = defaults === UserDefaults.standard ? KeychainStateStore() : nil
        let persisted = secureStore?.read() ?? defaults.data(forKey: key)
        if let data = persisted, let decoded = Self.decodePersistedState(data) {
            state = decoded
            if secureStore != nil, defaults.data(forKey: key) != nil {
                secureStore?.write(data)
                defaults.removeObject(forKey: key)
            }
        } else {
            state = LocalFeatureState()
        }
    }

    func update(_ body: (inout LocalFeatureState) -> Void) {
        body(&state)
        if let data = try? JSONEncoder().encode(state) {
            if let secureStore { secureStore.write(data) }
            else { defaults.set(data, forKey: key) }
        }
    }

    func reset() { state = LocalFeatureState(); secureStore?.remove(); defaults.removeObject(forKey: key) }

    /// Adds defaults introduced after v1 without discarding existing drafts or
    /// submissions when users update the app.
    private static func decodePersistedState(_ data: Data) -> LocalFeatureState? {
        let decoder = JSONDecoder()
        if let current = try? decoder.decode(LocalFeatureState.self, from: data) { return current }
        guard var legacy = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if legacy["reviewNotes"] == nil { legacy["reviewNotes"] = [String: String]() }
        if legacy["taskStatusSyncStates"] == nil { legacy["taskStatusSyncStates"] = [String: String]() }
        if legacy["parentAccountName"] == nil { legacy["parentAccountName"] = NSNull() }
        if legacy["selectedChildID"] == nil { legacy["selectedChildID"] = NSNull() }
        if legacy["boundChildIDs"] == nil { legacy["boundChildIDs"] = [String]() }
        if legacy["selectedPrincipalTaskID"] == nil { legacy["selectedPrincipalTaskID"] = NSNull() }
        if legacy["teacherUsesSportsWorkbench"] == nil { legacy["teacherUsesSportsWorkbench"] = false }
        if legacy["readMessageIDs"] == nil { legacy["readMessageIDs"] = [String]() }
        if legacy["likedClassPostIDs"] == nil { legacy["likedClassPostIDs"] = [String]() }
        if legacy["classPostComments"] == nil { legacy["classPostComments"] = [[String: Any]]() }
        guard let migrated = try? JSONSerialization.data(withJSONObject: legacy) else { return nil }
        return try? decoder.decode(LocalFeatureState.self, from: migrated)
    }
}

/// Keychain-backed local workflow state. The payload is small and contains only
/// client-side drafts/statuses; it is not a replacement for server-side health
/// record storage once the remote repository is enabled.
private struct KeychainStateStore {
    private let service = Bundle.main.bundleIdentifier ?? "com.xiangshang.youth"
    private let account = "local-feature-state"

    func read() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func write(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) != errSecSuccess {
            var add = query
            add.merge(attributes) { _, new in new }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    func remove() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
