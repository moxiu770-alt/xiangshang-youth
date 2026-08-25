import Foundation

struct MessageItem: Identifiable, Codable {
    let id: String
    let title: String
    let content: String
    let time: String
    let isRead: Bool
    let category: String
    let messageType: String?
    let businessID: String?
    let businessRoute: String?
    let childID: String?
    let taskID: String?
    let courseID: String?
    let lessonID: String?
    let actionLabel: String?
    let readAt: String?
    let expiresAt: String?

    init(id: String, title: String, content: String, time: String, isRead: Bool, category: String, messageType: String? = nil, businessID: String? = nil, businessRoute: String? = nil, childID: String? = nil, taskID: String? = nil, courseID: String? = nil, lessonID: String? = nil, actionLabel: String? = nil, readAt: String? = nil, expiresAt: String? = nil) {
        self.id = id; self.title = title; self.content = content; self.time = time; self.isRead = isRead; self.category = category
        self.messageType = messageType; self.businessID = businessID; self.businessRoute = businessRoute; self.childID = childID; self.taskID = taskID; self.courseID = courseID; self.lessonID = lessonID; self.actionLabel = actionLabel; self.readAt = readAt; self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey { case id, title, content, time, isRead, category, messageType, actionLabel, readAt, expiresAt; case businessID = "businessId"; case businessRoute; case childID = "childId"; case taskID = "taskId"; case courseID = "courseId"; case lessonID = "lessonId" }
}
