import Foundation

@testable import ProjectWorkspacesCore

final class InMemoryStateStore: StateStoring {
    private var storedState: LayoutState?
    private let lock = NSLock()

    func load() -> Result<StateStoreLoadOutcome, StateStoreError> {
        lock.lock()
        defer { lock.unlock() }
        if let storedState {
            return .success(.loaded(storedState))
        }
        return .success(.missing)
    }

    func save(_ state: LayoutState) -> Result<Void, StateStoreError> {
        lock.lock()
        storedState = state
        lock.unlock()
        return .success(())
    }
}
