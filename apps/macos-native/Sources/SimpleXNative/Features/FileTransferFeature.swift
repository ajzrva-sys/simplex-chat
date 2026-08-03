import Foundation
import Observation

struct SimpleXFileTransferRepository: FileTransferRepository {
    let core: SimpleXCore

    func receive(fileID: Int64, context: UserContext) async throws {
        try await core.receiveFile(fileID: fileID, remoteHostID: context.remoteHostID)
    }

    func cancel(fileID: Int64, context: UserContext) async throws {
        try await core.cancelFile(fileID: fileID, remoteHostID: context.remoteHostID)
    }

    func retry(fileID: Int64, context: UserContext) async throws {
        try await receive(fileID: fileID, context: context)
    }
}

@MainActor
@Observable
final class FileTransferViewModel {
    enum Action: Equatable, Sendable {
        case receiving
        case retrying
        case cancelling
    }

    struct Operation: Equatable, Sendable {
        var action: Action?
        var errorMessage: String?

        var isRunning: Bool { action != nil }
    }

    private(set) var operations: [Int64: Operation] = [:]

    private let repository: any FileTransferRepository
    private var tasks: [Int64: Task<Void, Never>] = [:]

    init(repository: any FileTransferRepository) {
        self.repository = repository
    }

    func operation(for fileID: Int64) -> Operation? {
        operations[fileID]
    }

    @discardableResult
    func receive(fileID: Int64, context: UserContext) -> Task<Void, Never> {
        perform(.receiving, fileID: fileID) { repository in
            try await repository.receive(fileID: fileID, context: context)
        }
    }

    @discardableResult
    func retry(fileID: Int64, context: UserContext) -> Task<Void, Never> {
        perform(.retrying, fileID: fileID) { repository in
            try await repository.retry(fileID: fileID, context: context)
        }
    }

    @discardableResult
    func cancel(fileID: Int64, context: UserContext) -> Task<Void, Never> {
        perform(.cancelling, fileID: fileID) { repository in
            try await repository.cancel(fileID: fileID, context: context)
        }
    }

    func clearError(fileID: Int64) {
        guard operations[fileID]?.errorMessage != nil else { return }
        operations[fileID] = nil
    }

    private func perform(
        _ action: Action,
        fileID: Int64,
        operation: @escaping @Sendable (any FileTransferRepository) async throws -> Void
    ) -> Task<Void, Never> {
        guard tasks[fileID] == nil else { return tasks[fileID]! }
        operations[fileID] = Operation(action: action, errorMessage: nil)

        let repository = repository
        let task = Task { [weak self] in
            defer { self?.tasks[fileID] = nil }
            do {
                try await operation(repository)
                try Task.checkCancellation()
                self?.operations[fileID] = nil
            } catch is CancellationError {
                return
            } catch {
                self?.operations[fileID] = Operation(
                    action: nil,
                    errorMessage: error.localizedDescription
                )
            }
        }
        tasks[fileID] = task
        return task
    }
}
