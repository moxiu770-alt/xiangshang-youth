import Foundation

struct CourseSuggestion: Identifiable, Codable {
    let id: String
    let courseID: String?
    let lessonID: String?
    let title: String
    let duration: String
    let focus: String
    let isPublicBenefit: Bool
    enum CodingKeys: String, CodingKey { case id, title, duration, focus, isPublicBenefit, courseID = "courseId", lessonID = "lessonId" }
    init(id: String, courseID: String? = nil, lessonID: String? = nil, title: String, duration: String, focus: String, isPublicBenefit: Bool) { self.id = id; self.courseID = courseID; self.lessonID = lessonID; self.title = title; self.duration = duration; self.focus = focus; self.isPublicBenefit = isPublicBenefit }
}
