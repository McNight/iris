#if os(macOS)
import Dispatch
import struct Foundation.Data
import Network

final class Client {

    private let connection: Connection

    init(host: String, port: UInt16) {
        self.connection = Connection(NWConnection(host: .init(host), port: .init(rawValue: port)!, using: .tcp))
    }

}

private extension Client {

    final class Connection {

        typealias DidStopHandler = (CompletionReason) -> Void

        enum CompletionReason {
            case explicitStop
            case isComplete
            case didFail(Error)
        }

        let connection: NWConnection

        let queue: DispatchQueue

        var didStopHandler: DidStopHandler?

        init(_ connection: NWConnection) {
            self.connection = connection
            self.queue = DispatchQueue(label: "client_connection_queue")
        }

    }

}

extension Client {

    func start() {
        connection.start()
    }

    func stop() {
        connection.stop(reason: .explicitStop)
    }

    func send(data: Data) {
        connection.send(data: data)
    }

}

private extension Client.Connection {

    func start() {
        connection.stateUpdateHandler = { [weak self] in self?.stateUpdateHandler($0) }
        receiveMessage()
        connection.start(queue: queue)
    }

    func stop(reason: CompletionReason) {
        defer {
            didStopHandler = nil
        }
        connection.cancel()
        didStopHandler?(reason)
    }

    func receiveMessage() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            self?.handleReceiveMessage(data: data, isComplete: complete, error: error)
        }
    }

    func handleReceiveMessage(data: Data?, isComplete: Bool, error: Error?) {
        if let data = data, !data.isEmpty, let message = String(data: data, encoding: .utf8) {
            print("[client] data received: \(message)")
        }
        if isComplete {
            stop(reason: .isComplete)
        } else if let error = error {
            stop(reason: .didFail(error))
        } else {
            receiveMessage()
        }
    }

    func send(data: Data) {
        connection.send(content: data, completion: .contentProcessed({ [weak self] error in
            if let error = error {
                self?.stop(reason: .didFail(error))
                return
            }
            print("[client] successfully sent \(data.count) bytes to server")
        }))
    }

}

private extension Client.Connection {

    func stateUpdateHandler(_ state: NWConnection.State) {
        switch state {
        case .ready:
            print("[client] now connected to \(connection.endpoint)")
        case .failed(let error):
            print("[client] failed with error: \(error.localizedDescription)")
            stop(reason: .didFail(error))
        case .preparing, .setup, .waiting:
            break
        case .cancelled:
            print("[client] connection stopped, server might have been stopped ?")
        @unknown default:
            fatalError()
        }
    }

}
#endif
