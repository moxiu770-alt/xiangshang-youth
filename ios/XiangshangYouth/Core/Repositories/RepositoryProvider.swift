import Foundation

/// Keeps the Mock/Remote switch outside feature views and view models.
enum RepositoryProvider {
    /// Mock remains the safe default. Set `XS_USE_REMOTE_DATA_SOURCE=1` on the
    /// app scheme together with `XS_API_BASE_URL` during backend integration.
    /// Keeping the switch here means feature views and view models never need
    /// environment-specific branching.
    static var useRemoteDataSource = ProcessInfo.processInfo.environment["XS_USE_REMOTE_DATA_SOURCE"] == "1"
    static func make() -> YouthRepository {
        useRemoteDataSource ? RemoteRepository() : MockRepository.shared
    }
}
