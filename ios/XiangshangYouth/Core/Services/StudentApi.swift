import Foundation
import CryptoKit
struct StudentApi {
    let client: ApiClient
    init(client: ApiClient = .shared) { self.client = client }
    func students(schoolID: String) async throws -> [Student] {
        try await client.request(path: "v1/schools/\(schoolID)/students", type: [Student].self)
    }
    func bindChild(studentID: String, bindingCode: String) async throws -> ParentChild {
        try await client.request(path: "v1/students/\(studentID)/bind", method: "POST", query: [URLQueryItem(name: "code", value: bindingCode)], type: ParentChild.self)
    }
    func bindChild(name: String, bindingCode: String) async throws -> ParentChild {
        try await client.request(path: "v1/students/bind", method: "POST", body: BindingRequest(studentName: name, code: bindingCode), type: ParentChild.self)
    }
    func grantConsent(studentID: String, version: String) async throws {
        try await client.send(path: "v1/students/\(studentID)/consent", method: "POST", body: ConsentRequest(consentVersion: version, purpose: "body_assessment", granted: true), idempotencyKey: "consent-\(studentID)-\(version)")
    }
    func grantConsent(_ consent: HealthConsentRecord) async throws {
        try await client.send(path: "v1/students/\(consent.childID)/consent", method: "POST", body: ConsentRequest(consent: consent), idempotencyKey: "consent-\(consent.consentID)")
    }
    func revokeConsent(studentID: String, version: String) async throws {
        try await client.send(path: "v1/students/\(studentID)/consent", method: "POST", body: ConsentRequest(consentVersion: version, purpose: "body_assessment", granted: false), idempotencyKey: "consent-revoke-\(studentID)-\(version)")
    }
}

private struct BindingRequest: Encodable { let studentName: String; let code: String }
private struct ConsentRequest: Encodable {
    let consentVersion: String
    let purpose: String
    let granted: Bool
    let consentID: String
    let privacyPolicyVersion: String
    let cameraConsentVersion: String
    let algorithmNoticeVersion: String
    let deviceInfoHash: String
    let appVersion: String
    let dataRetentionNoticeAccepted: Bool
    init(consentVersion: String, purpose: String, granted: Bool) {
        self.consentVersion = consentVersion; self.purpose = purpose; self.granted = granted
        consentID = UUID().uuidString; privacyPolicyVersion = consentVersion; cameraConsentVersion = consentVersion
        algorithmNoticeVersion = "posture-screening-v1"; deviceInfoHash = ""; appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"; dataRetentionNoticeAccepted = true
    }
    init(consent: HealthConsentRecord) {
        consentVersion = consent.privacyPolicyVersion; purpose = "body_assessment"; granted = true
        consentID = consent.consentID; privacyPolicyVersion = consent.privacyPolicyVersion
        cameraConsentVersion = consent.cameraConsentVersion; algorithmNoticeVersion = consent.algorithmNoticeVersion
        deviceInfoHash = SHA256.hash(data: Data(consent.deviceInfo.utf8)).map { String(format: "%02x", $0) }.joined()
        appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        dataRetentionNoticeAccepted = consent.dataRetentionNoticeAccepted
    }
    enum CodingKeys: String, CodingKey { case consentVersion, purpose, granted, privacyPolicyVersion, cameraConsentVersion, algorithmNoticeVersion, deviceInfoHash, appVersion, dataRetentionNoticeAccepted; case consentID = "consentId" }
}
