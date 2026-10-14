import Foundation
import Combine

struct ToolApprovalRequest: Identifiable {
    let id = UUID()
    let title: String
    let details: String
}

final class ApprovalManager: ObservableObject {
    @Published private(set) var pending: ToolApprovalRequest?
    private var completion: ((Bool) -> Void)?

    func request(_ request: ToolApprovalRequest, completion: @escaping (Bool) -> Void) {
        self.completion = completion
        if Thread.isMainThread {
            pending = request
        } else {
            DispatchQueue.main.async { self.pending = request }
        }
    }

    func resolve(approved: Bool) {
        let callback = completion
        completion = nil
        pending = nil
        callback?(approved)
    }
}
