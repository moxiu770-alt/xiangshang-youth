import Foundation
import Security

/// Persists the front-end workflow state while the remote APIs are unavailable.
/// Keeping it behind this small store lets the UI move to remote sync later without
/// replacing its interaction model.
struct LocalFeatureState: Codable, Equatable {
    var registeredActivities: Set<String> = []
    var activityRegistrations: [ActivityRegistration] = []
    var completedAssessments: Set<String> = []
    /// Completed family observations are separate from in-progress drafts so
    /// they remain reviewable and can map directly to a remote record later.
    var familyHealthRecords: [String: FamilyHealthRecord] = [:]
    var healthObservationSyncStates: [String: LocalSubmissionStatus] = [:]
    var courseProgress: [String: Double] = [:]
    /// Append-only guided-training receipts. Raw camera media is never stored.
    var followAlongSessions: [FollowAlongSessionRecord] = []
    /// Remote acknowledgement state for structured follow-along receipts.
    var followAlongSyncStates: [String: LocalSubmissionStatus] = [:]
    var supportMessages: [SupportChatMessage] = []
    var classPosts: [ClassPostDraft] = []
    var likedClassPostIDs: Set<UUID> = []
    var classPostComments: [ClassPostComment] = []
    var uploadedTaskIDs: Set<String> = []
    var checkInDates: Set<String> = []
    var healthCheckins: [HealthCheckInRecord] = []
    var healthCheckinSyncStates: [String: LocalSubmissionStatus] = [:]
    var drafts: [String: String] = [:]
    var expertAppointments: [ExpertAppointment] = []
    var courseUploads: [CourseUploadRecord] = []
    var studentTaskStatuses: [String: TaskStatus] = [:]
    /// Task state is scoped by `taskID|studentID`; the legacy map remains only
    /// for decoding old local sessions and is never authoritative for a task.
    var taskScopedStatuses: [String: TaskStatus] = [:]
    var taskScopedStatusVersions: [String: Int] = [:]
    var taskScopedSyncStates: [String: LocalSubmissionStatus] = [:]
    var taskScopedReviewNotes: [String: String] = [:]
    /// Last server task-row version observed for each student.
    var taskStatusVersions: [String: Int] = [:]
    /// Latest teacher-side queue update for each student.  The actual status
    /// remains immediately usable offline; this map only tracks remote
    /// acknowledgement and retry state.
    var taskStatusSyncStates: [String: LocalSubmissionStatus] = [:]
    var reviewNotes: [String: String] = [:]
    var sessionProfile: UserProfile?
    var sessionRole: UserRole?
    /// Registration bucket selected when this account was created.  It is kept
    /// separate from the active workbench role so later role switching does not
    /// erase the account's original access category.
    var accountBucket: UserRole? = nil
    /// Account identity is distinct from the active workbench identity.  A
    /// parent who temporarily enters a teacher/principal mock workbench must
    /// get their own name back when returning to the family workspace.
    var parentAccountName: String? = nil
    var selectedChildID: String? = nil
    var boundChildIDs: Set<String> = []
    /// Family-controlled body assessment records. Raw camera assets are never
    /// persisted here; only the completed visual tasks and parent-confirmed
    /// observations are retained.
    var bodyAssessments: [String: BodyAssessmentRecord] = [:]
    /// Append-only summary history used for honest BMI/measurement trends.
    /// Raw camera assets are never included.
    var bodyAssessmentHistory: [String: [BodyAssessmentRecord]] = [:]
    /// In-progress family assessment forms, without raw camera media.
    var bodyAssessmentDrafts: [String: BodyAssessmentDraft] = [:]
    /// Remote acknowledgement state for completed family body assessments.
    var bodyAssessmentSyncStates: [String: LocalSubmissionStatus] = [:]
    /// Auditable guardian consent for camera and child health observation.
    var healthConsents: [String: HealthConsentRecord] = [:]
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

struct FamilyHealthRecord: Codable, Identifiable, Equatable {
    var id: String { "\(childID)-\(category)" }
    let childID: String
    let category: String
    let completedAt: Date
    let entries: [String: String]
    var formVersion: String? = nil
    var submittedAt: Date? = nil
    var version: Int? = nil
    var frequency: String? = nil
    var severity: String? = nil
    var structuredAnswers: [HealthObservationAnswer]? = nil
}

struct HealthObservationAnswer: Codable, Identifiable, Equatable {
    var id: String { questionID }
    let questionID: String
    let questionType: String
    let selectedOptionIDs: [String]
    let note: String?
    let required: Bool
}

struct HealthConsentRecord: Codable, Equatable {
    let consentID: String
    let guardianUserID: String
    let childID: String
    let privacyPolicyVersion: String
    let cameraConsentVersion: String
    let algorithmNoticeVersion: String
    let agreedAt: Date
    var revokedAt: Date?
    let deviceInfo: String
    let dataRetentionNoticeAccepted: Bool
}

struct ActivityRegistration: Codable, Identifiable, Equatable {
    let id: UUID
    let activityID: String
    var contactName: String
    var phone: String
    var status: LocalSubmissionStatus
    let createdAt: Date
    var registrationID: String? = nil
    var childID: String? = nil
    var contactUserID: String? = nil
    var capacity: Int? = nil
    var remainingCapacity: Int? = nil
    var registrationStartAt: Date? = nil
    var registrationEndAt: Date? = nil
    var registrationStatus: String? = nil
    var version: Int? = nil
}

struct ExpertAppointment: Codable, Identifiable, Equatable {
    let id: UUID
    var expertName: String
    var preferredDate: String
    var note: String
    var status: LocalSubmissionStatus
    let createdAt: Date
    var expertID: String? = nil
    var appointmentID: String? = nil
    var serviceID: String? = nil
    var slotID: String? = nil
    var childID: String? = nil
    var appointmentStatus: String? = nil
    var expectedVersion: Int? = nil
    var scheduledStartAt: Date? = nil
    var scheduledEndAt: Date? = nil
}

struct CourseUploadRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let taskID: String
    var attendanceCount: Int
    var notes: String
    var attachmentName: String
    /// Stable local/file-provider reference used by the upload adapter. The
    /// display name alone is not an upload and must never be presented as one.
    var attachmentReference: String? = nil
    var status: LocalSubmissionStatus
    let createdAt: Date
}

struct LocalAppSettings: Codable, Equatable {
    var notificationsEnabled = true
    var reduceMotion = false
    /// Voice prompts apply to body capture and follow-along training. Persist
    /// the choice so a new session does not silently re-enable speech.
    var voiceGuidanceEnabled = true
    /// Optional product-improvement events are disabled until the account
    /// holder explicitly enables them in Settings.
    var analyticsEnabled = false
}

struct FollowAlongSessionRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let childID: String
    let dayID: Int
    let completedAt: Date
    let durationSeconds: Int
    let completionRatio: Double
    let qualityScore: Int
    let cameraVerified: Bool
    let visualUnits: [String: Int]
    let manualUnits: Int
    let modelVersion: String
    let mode: String
}

struct SupportChatMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let isMine: Bool
    /// A local acknowledgement is not a customer-service reply. This state
    /// makes that distinction visible until the service accepts the message.
    var status: LocalSubmissionStatus = .pendingSync
    let createdAt: Date
}

struct ClassPostDraft: Codable, Identifiable, Equatable {
    let id: UUID
    let author: String
    var content: String
    /// Local visibility is not the same as a school-side acknowledgement.
    var status: LocalSubmissionStatus = .pendingSync
    let createdAt: Date
    var postID: String? = nil
    var classID: String? = nil
    var displayName: String? = nil
    var visibilityScope: String? = nil
    var moderationStatus: String? = nil
    var isPinned: Bool? = nil
    var reportStatus: String? = nil
    var attachments: [ClassPostAttachment]? = nil
    var authorRole: String? = nil
    /// Server projection; aliases and display names are never ownership keys.
    var ownedByCurrentUser: Bool = false
}

struct ClassPostAttachment: Codable, Identifiable, Equatable {
    let id: String
    let type: String
    let objectID: String?
    let localReference: String?
    let thumbnailObjectID: String?
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
    /// A failed Keychain write must be visible to the app. Keeping the current
    /// value in memory is useful for recovery, but it is not safe to present it
    /// as a durable draft until the next successful write.
    @Published private(set) var persistenceError: String? = nil
    private let key = "xiangshang.local-feature-state.v1"
    private let defaults: UserDefaults
    private let secureStore: KeychainStateStore?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Test suites and migration fixtures intentionally stay isolated in their
        // supplied UserDefaults. The production standard store uses Keychain so
        // drafts, child bindings and health workflow state are not plain text.
        // Unsigned simulator apps have no Keychain access group on some Xcode/
        // runtime combinations; using the simulator's isolated app container
        // keeps visual and UI tests deterministic without weakening a signed
        // device build's storage policy.
        #if targetEnvironment(simulator)
        self.secureStore = nil
        #else
        self.secureStore = defaults === UserDefaults.standard ? KeychainStateStore() : nil
        #endif
        let persisted = secureStore?.read() ?? defaults.data(forKey: key)
        if let data = persisted, let decoded = Self.decodePersistedState(data) {
            state = decoded
            if let secureStore, defaults.data(forKey: key) != nil {
                // Never delete the legacy copy unless Keychain accepted the
                // migrated payload. A transient Keychain failure must not turn
                // an app update into data loss.
                if secureStore.write(data) {
                    defaults.removeObject(forKey: key)
                } else {
                    persistenceError = "本机安全存储暂不可用，已保留旧版本本机数据。"
                }
            }
        } else {
            state = LocalFeatureState()
        }
    }

    @discardableResult
    func update(_ body: (inout LocalFeatureState) -> Void) -> Bool {
        body(&state)
        guard let data = try? JSONEncoder().encode(state) else {
            persistenceError = "本机安全存储暂不可用，最近一次操作尚未落盘。"
            return false
        }
        let persisted: Bool
        if let secureStore { persisted = secureStore.write(data) }
        else { defaults.set(data, forKey: key); persisted = true }
        persistenceError = persisted ? nil : "本机安全存储暂不可用，最近一次操作尚未落盘。"
        return persisted
    }

    func reset() { state = LocalFeatureState(); persistenceError = nil; secureStore?.remove(); defaults.removeObject(forKey: key) }

    /// Adds defaults introduced after v1 without discarding existing drafts or
    /// submissions when users update the app.
    private static func decodePersistedState(_ data: Data) -> LocalFeatureState? {
        let decoder = JSONDecoder()
        if var current = try? decoder.decode(LocalFeatureState.self, from: data) {
            // A pre-v2 record has only a student ID, so it cannot safely be
            // attributed to a task. Drop that unsafe projection rather than
            // inventing an "unscoped" task and leaking it into another task.
            current.studentTaskStatuses = [:]
            current.taskStatusVersions = [:]
            current.taskStatusSyncStates = [:]
            current.reviewNotes = [:]
            // A short-lived earlier migration used `unscoped|studentId` as a
            // placeholder. It is not a valid composite identity and must not
            // survive into the retry queue.
            current.taskScopedStatuses = current.taskScopedStatuses.filter { !$0.key.hasPrefix("unscoped|") && !$0.key.hasPrefix("missing-task|") }
            current.taskScopedStatusVersions = current.taskScopedStatusVersions.filter { !$0.key.hasPrefix("unscoped|") && !$0.key.hasPrefix("missing-task|") }
            current.taskScopedSyncStates = current.taskScopedSyncStates.filter { !$0.key.hasPrefix("unscoped|") && !$0.key.hasPrefix("missing-task|") }
            current.taskScopedReviewNotes = current.taskScopedReviewNotes.filter { !$0.key.hasPrefix("unscoped|") && !$0.key.hasPrefix("missing-task|") }
            if current.followAlongSyncStates.isEmpty && !current.followAlongSessions.isEmpty {
                current.followAlongSyncStates = Dictionary(uniqueKeysWithValues: current.followAlongSessions.map { ($0.id.uuidString, .submitted) })
            }
            return current
        }
        guard var legacy = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if legacy["reviewNotes"] == nil { legacy["reviewNotes"] = [String: String]() }
        if legacy["taskStatusSyncStates"] == nil { legacy["taskStatusSyncStates"] = [String: String]() }
        if legacy["taskStatusVersions"] == nil { legacy["taskStatusVersions"] = [String: Int]() }
        if legacy["parentAccountName"] == nil { legacy["parentAccountName"] = NSNull() }
        if legacy["selectedChildID"] == nil { legacy["selectedChildID"] = NSNull() }
        if legacy["boundChildIDs"] == nil { legacy["boundChildIDs"] = [String]() }
        if legacy["bodyAssessments"] == nil { legacy["bodyAssessments"] = [String: Any]() }
        if legacy["familyHealthRecords"] == nil { legacy["familyHealthRecords"] = [String: Any]() }
        if legacy["healthObservationSyncStates"] == nil { legacy["healthObservationSyncStates"] = [String: String]() }
        if legacy["bodyAssessmentHistory"] == nil { legacy["bodyAssessmentHistory"] = [String: Any]() }
        if legacy["bodyAssessmentDrafts"] == nil { legacy["bodyAssessmentDrafts"] = [String: Any]() }
        if legacy["bodyAssessmentSyncStates"] == nil { legacy["bodyAssessmentSyncStates"] = [String: String]() }
        if legacy["healthConsents"] == nil { legacy["healthConsents"] = [String: Any]() }
        if legacy["followAlongSessions"] == nil { legacy["followAlongSessions"] = [[String: Any]]() }
        if legacy["followAlongSyncStates"] == nil { legacy["followAlongSyncStates"] = [String: String]() }
        if legacy["healthCheckins"] == nil { legacy["healthCheckins"] = [[String: Any]]() }
        if legacy["healthCheckinSyncStates"] == nil { legacy["healthCheckinSyncStates"] = [String: String]() }
        func addCaptureHints(_ value: Any?) -> Any? {
            guard var record = value as? [String: Any] else { return value }
            if record["captureObservationHints"] == nil { record["captureObservationHints"] = [String: String]() }
            return record
        }
        if let records = legacy["bodyAssessments"] as? [String: Any] {
            legacy["bodyAssessments"] = Dictionary(uniqueKeysWithValues: records.map { ($0.key, addCaptureHints($0.value) as Any) })
        }
        if let drafts = legacy["bodyAssessmentDrafts"] as? [String: Any] {
            legacy["bodyAssessmentDrafts"] = Dictionary(uniqueKeysWithValues: drafts.map { ($0.key, addCaptureHints($0.value) as Any) })
        }
        if let histories = legacy["bodyAssessmentHistory"] as? [String: Any] {
            legacy["bodyAssessmentHistory"] = Dictionary(uniqueKeysWithValues: histories.map { key, value in
                let migrated = (value as? [Any])?.map { addCaptureHints($0) as Any } ?? value
                return (key, migrated)
            })
        }
        if legacy["selectedPrincipalTaskID"] == nil { legacy["selectedPrincipalTaskID"] = NSNull() }
        if legacy["teacherUsesSportsWorkbench"] == nil { legacy["teacherUsesSportsWorkbench"] = false }
        if legacy["readMessageIDs"] == nil { legacy["readMessageIDs"] = [String]() }
        if legacy["likedClassPostIDs"] == nil { legacy["likedClassPostIDs"] = [String]() }
        if legacy["classPostComments"] == nil { legacy["classPostComments"] = [[String: Any]]() }
        // LocalAppSettings gained voiceGuidanceEnabled after v1. A missing
        // nested key must be migrated explicitly because synthesized Codable
        // otherwise rejects the whole persisted session.
        if var settings = legacy["settings"] as? [String: Any] {
            if settings["notificationsEnabled"] == nil { settings["notificationsEnabled"] = true }
            if settings["reduceMotion"] == nil { settings["reduceMotion"] = false }
            if settings["voiceGuidanceEnabled"] == nil { settings["voiceGuidanceEnabled"] = true }
            if settings["analyticsEnabled"] == nil { settings["analyticsEnabled"] = false }
            legacy["settings"] = settings
        } else {
            legacy["settings"] = ["notificationsEnabled": true, "reduceMotion": false, "voiceGuidanceEnabled": true, "analyticsEnabled": false]
        }
        if let messages = legacy["supportMessages"] as? [[String: Any]] {
            legacy["supportMessages"] = messages.map { message in
                var migrated = message
                if migrated["status"] == nil {
                    migrated["status"] = ((migrated["isMine"] as? Bool) == true
                        ? LocalSubmissionStatus.pendingSync.rawValue
                        : LocalSubmissionStatus.submitted.rawValue)
                }
                return migrated
            }
        }
        if let posts = legacy["classPosts"] as? [[String: Any]] {
            legacy["classPosts"] = posts.map { post in
                var migrated = post
                if migrated["status"] == nil { migrated["status"] = LocalSubmissionStatus.pendingSync.rawValue }
                return migrated
            }
        }
        guard let migrated = try? JSONSerialization.data(withJSONObject: legacy) else { return nil }
        guard var current = try? decoder.decode(LocalFeatureState.self, from: migrated) else { return nil }
        current.studentTaskStatuses = [:]
        current.taskStatusVersions = [:]
        current.taskStatusSyncStates = [:]
        current.reviewNotes = [:]
        return current
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

    @discardableResult
    func write(_ data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }
        var add = query
        add.merge(attributes) { _, new in new }
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
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
