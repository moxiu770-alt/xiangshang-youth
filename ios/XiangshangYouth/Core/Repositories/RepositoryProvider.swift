import Foundation

/// Keeps the Mock/Remote switch outside feature views and view models.
enum RepositoryProvider {
    static var useRemoteDataSource = false
    static func make() -> YouthRepository {
        useRemoteDataSource ? RemoteRepository() : MockRepository.shared
    }
}
