import CoreData

final class CoreDataStack {
    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool) {
        container = NSPersistentCloudKitContainer(name: "Model")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        // Cloud disabled for v1: leave cloudKitContainerOptions nil.
        container.persistentStoreDescriptions.first?.cloudKitContainerOptions = nil
        container.loadPersistentStores { _, error in
            if let error { fatalError("Core Data load failed: \(error)") }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
