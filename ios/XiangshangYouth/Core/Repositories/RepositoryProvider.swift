import Foundation

/// Keeps the Mock/Remote switch outside feature views and view models.
enum RepositoryProvider {
    /// Debug builds keep the deterministic local source, while the Release
    /// configuration is wired to the remote service. Environment variables
    /// remain available for simulator/CI overrides without allowing a release
    /// artifact to silently fall back to demo data.
    static var useRemoteDataSource = ProcessInfo.processInfo.environment["XS_USE_REMOTE_DATA_SOURCE"] == "1"
        || (Bundle.main.object(forInfoDictionaryKey: "UseRemoteDataSource") as? String) == "1"
    static func make() -> YouthRepository {
        useRemoteDataSource ? RemoteRepository() : MockRepository.shared
    }
}
