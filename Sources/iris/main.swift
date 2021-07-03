import ArgumentParser
import Foundation

#if os(macOS)
struct Iris: ParsableCommand {

    @Flag(help: "launches iris as a server")
    var server: Bool = false

    @Option(help: "defines the hostname used for communication")
    var hostname: String = "localhost"

    @Option(help: "port to communicate on")
    var port: UInt16 = 8888

    mutating func run() throws {
        if server {
            startServer()
        } else {
            startClient()
        }
    }

    private func startServer() {
        let server = Server(port: port)
        server.start()
        RunLoop.current.run()
    }

    private func startClient() {
        let client = Client(host: hostname, port: port)
        client.start()
        var shouldContinue = true
        repeat {
            if let say = readLine(strippingNewline: true), say != "exit", let data = say.data(using: .utf8) {
                client.send(data: data)
            } else {
                shouldContinue = false
            }
        } while (shouldContinue)
        client.stop()
    }

}

Iris.main()
#else
let errorMessage = "Only works on macOS for now"
FileHandle.standardError.write(errorMessage.data(using: .utf8)!)
exit(EXIT_FAILURE)
#endif
