import Foundation

private struct MobileContentManifest: Decodable {
    let dataAvailable: Bool
    let changed: Bool
    let version: Int
}

/// Persists only the last acknowledged publication version. The catalogue
/// itself remains repository-owned so a manifest failure can never make stale
/// or bundled content look authoritative in Remote mode.
private final class MobileContentManifestStore {
    private let client: ApiClient
    private let defaults: UserDefaults

    init(client: ApiClient = .shared, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
    }

    func refresh(schoolID: String?, channel: String) async throws -> MobileContentManifest {
        let scope = schoolID?.isEmpty == false ? schoolID! : "global"
        let key = "content-manifest.\(scope).\(channel)"
        let knownVersion = max(0, defaults.integer(forKey: key))
        var query = [
            URLQueryItem(name: "channel", value: channel),
            URLQueryItem(name: "knownVersion", value: String(knownVersion))
        ]
        if let schoolID, !schoolID.isEmpty { query.insert(URLQueryItem(name: "schoolId", value: schoolID), at: 0) }
        let manifest = try await client.request(
            path: "v1/mobile/content-manifest",
            query: query,
            type: MobileContentManifest.self
        )
        if manifest.dataAvailable, manifest.version >= knownVersion {
            defaults.set(manifest.version, forKey: key)
        }
        return manifest
    }
}

/// Server-catalogue and deep-link state.  Keeping this out of the session and
/// task command store makes it explicit that Remote mode never falls back to
/// bundled records when a server catalogue is empty.
@MainActor extension AppState {
    private func refreshPublishedContentManifest() async throws {
        guard repository.supportsRemoteAcknowledgement else { return }
        let schoolID = profile?.schoolID?.isEmpty == false ? profile?.schoolID : nil
        let roleChannel = selectedRole == .teacher ? "teacher" : "family"
        let store = MobileContentManifestStore()
        _ = try await store.refresh(schoolID: schoolID, channel: "mobile")
        _ = try await store.refresh(schoolID: schoolID, channel: roleChannel)
    }

    func loadActivities() async {
        activitiesLoading = true; activitiesError = nil
        defer { activitiesLoading = false }
        do {
            _ = try? await refreshPublishedContentManifest()
            remoteActivities = try await repository.loadActivities(childID: selectedChild?.id)
            activityRegistrationHistory = try await repository.loadActivityRegistrationHistory()
        } catch {
            if case ApiError.unauthorized = error { handleDashboardError(error) }
            else { activitiesError = error.localizedDescription }
        }
    }

    func loadExperts() async {
        expertsLoading = true; expertsError = nil
        defer { expertsLoading = false }
        do {
            _ = try? await refreshPublishedContentManifest()
            remoteExperts = try await repository.loadExperts()
            expertAppointmentHistory = try await repository.loadExpertAppointmentHistory()
        } catch {
            if case ApiError.unauthorized = error { handleDashboardError(error) }
            else { expertsError = error.localizedDescription }
        }
    }

    func loadExpertSlots(expertID: String) async {
        guard !expertID.isEmpty else { return }
        expertSlotErrors[expertID] = nil
        do { expertSlots[expertID] = try await repository.loadExpertSlots(expertID: expertID) }
        catch {
            if case ApiError.unauthorized = error { handleDashboardError(error) }
            else { expertSlotErrors[expertID] = error.localizedDescription }
        }
    }

    func loadClassPosts(cursor: String? = nil) async {
        guard repository.supportsRemoteAcknowledgement else { return }
        classPostsLoading = true; classPostsError = nil
        defer { classPostsLoading = false }
        let childID = selectedRole == .teacher ? nil : selectedChild?.id
        let schoolID = profile?.schoolID
        let classID = selectedRole == .teacher ? managedTeacherClasses.first?.id : selectedChild?.classID
        do {
            let page = try await repository.loadClassPosts(schoolID: schoolID, classID: classID, cursor: cursor)
            if selectedRole == .teacher {
                guard managedTeacherClasses.contains(where: { $0.id == classID }) || classID == nil else { return }
            } else {
                guard selectedChild?.id == childID, selectedChild?.classID == classID else { return }
            }
            mutateLocal { values in
                if cursor == nil { values.classPosts = page.posts }
                else { values.classPosts.append(contentsOf: page.posts) }
            }
            classPostsNextCursor = page.nextCursor
        } catch {
            if case ApiError.unauthorized = error { handleDashboardError(error) }
            else { classPostsError = error.localizedDescription }
        }
    }

    func loadClassPostAttachment(fileID: String) async {
        guard repository.supportsRemoteAcknowledgement, !fileID.isEmpty, classPostAttachmentData[fileID] == nil else { return }
        classPostAttachmentErrors[fileID] = nil
        do { classPostAttachmentData[fileID] = try await repository.loadClassPostAttachment(fileID: fileID) }
        catch { classPostAttachmentErrors[fileID] = error.localizedDescription }
    }

    func loadCourses(for child: Student) async {
        guard repository.supportsRemoteAcknowledgement else { return }
        let childID = child.id
        coursesLoading = true; coursesError = nil; remoteCourses = []; remoteCoursesChildID = childID
        defer {
            if remoteCoursesChildID == childID { coursesLoading = false }
        }
        do {
            _ = try? await refreshPublishedContentManifest()
            let courses = try await repository.loadCourses(childID: childID)
            guard remoteCoursesChildID == childID else { return }
            remoteCourses = courses
        } catch {
            guard remoteCoursesChildID == childID else { return }
            if case ApiError.unauthorized = error { handleDashboardError(error) }
            else { coursesError = error.localizedDescription }
        }
    }

    func loadLessonPlayback(lessonID: String) async throws -> PlaybackSource {
        guard repository.supportsRemoteAcknowledgement else { throw ApiError.notConfigured }
        return try await repository.loadLessonPlayback(lessonID: lessonID)
    }

    func saveRemoteLessonProgress(childID: String, lessonID: String, lastPositionMs: Int, completed: Bool, expectedVersion: Int?) async throws {
        let acknowledged = try await repository.saveLessonProgress(childID: childID, lessonID: lessonID, lastPositionMs: lastPositionMs, completed: completed, expectedVersion: expectedVersion)
        remoteCourses = remoteCourses.map { course in
            course.lessonID == acknowledged.lessonID
                ? RemoteLesson(courseID: course.courseID, moduleID: course.moduleID, lessonID: course.lessonID, title: course.title, lessonTitle: course.lessonTitle, durationMs: course.durationMs, videoSource: course.videoSource, lastPositionMs: acknowledged.lastPositionMs, completed: acknowledged.completed, version: acknowledged.version)
                : course
        }
    }

    func openRecommendedCourse(for childID: String, suggestion: CourseSuggestion) {
        courseRecommendationTarget = CourseRecommendationTarget(childID: childID, courseID: suggestion.courseID, lessonID: suggestion.lessonID, title: suggestion.title)
    }
    func openCourseTarget(for childID: String, courseID: String?, lessonID: String?, title: String) {
        courseRecommendationTarget = CourseRecommendationTarget(childID: childID, courseID: courseID, lessonID: lessonID, title: title)
    }
    func clearRecommendedCourseTarget() { courseRecommendationTarget = nil }
    func openActivityTarget(_ activityID: String) { pendingActivityID = activityID }
    func clearActivityTarget() { pendingActivityID = nil }
    func openExpertAppointmentTarget(_ appointmentID: String) { pendingExpertAppointmentID = appointmentID }
    func clearExpertAppointmentTarget() { pendingExpertAppointmentID = nil }
}
