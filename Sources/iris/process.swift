import Foundation

enum Say {

    private static let queue = DispatchQueue(label: "say-queue")

    static func exec(arguments: String...) -> Int32 {
        queue.sync {
            let task = Process()
            task.launchPath = "/usr/bin/say"
            task.arguments = arguments

            task.launch()
            task.waitUntilExit()

            return task.terminationStatus
        }
    }

}
