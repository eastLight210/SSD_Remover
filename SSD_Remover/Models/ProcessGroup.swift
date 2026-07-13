import Foundation

enum ProcessCategory: String, Sendable, CaseIterable {
    case spotlight
    case system
    case user
}

struct ProcessGroup: Identifiable, Equatable, Sendable {
    let category: ProcessCategory
    let processes: [BlockingProcess]
    var isSelected: Bool

    var id: ProcessCategory { category }

    init(category: ProcessCategory, processes: [BlockingProcess], isSelected: Bool = false) {
        self.category = category
        self.processes = processes
        self.isSelected = isSelected
    }
}
