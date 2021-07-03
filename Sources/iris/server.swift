#if os(macOS)
import Dispatch
import Foundation
import Network

final class Server {

    let listener: NWListener

    private var connections: [Connection.ID: Connection]

    init(port: UInt16) {
        self.listener = try! NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        self.connections = [:]
    }

}

private extension Server {

    final class Connection: Identifiable {

        typealias DidStopHandler = (CompletionReason) -> Void

        enum CompletionReason {
            case explicitStop
            case isComplete
            case didFail(Error)
        }

        let id: Int

        let connection: NWConnection

        let mtu: Int

        var didStopHandler: DidStopHandler?

        private static var connectionsCount = 0

        init(_ connection: NWConnection, mtu: Int = 65535) {
            defer {
                Self.connectionsCount += 1
            }
            self.id = Self.connectionsCount
            self.connection = connection
            self.mtu = mtu
        }

    }

}

extension Server {

    func start(queue: DispatchQueue = .main) {
        listener.stateUpdateHandler = { [weak self] in self?.stateUpdateHandler($0) }
        listener.newConnectionHandler = { [weak self] in self?.newConnectionHandler($0) }
        listener.start(queue: queue)
    }

    func stop() {
        listener.stateUpdateHandler = nil
        listener.newConnectionHandler = nil
        listener.cancel()
        for connection in connections.values {
            connection.stop(reason: .explicitStop)
        }
        connections.removeAll()
    }

}

private extension Server {

    func stateUpdateHandler(_ state: NWListener.State) {
        switch state {
        case .ready:
            print("[server] ready and listening on port \(listener.port!)")
        case .failed(let error):
            print("[server] failed with error \(error.localizedDescription)")
            exit(EXIT_FAILURE)
        case .setup, .waiting(_):
            break
        case .cancelled:
            print("[server] cancelled")
        @unknown default:
            fatalError()
        }
    }

    func newConnectionHandler(_ connection: NWConnection) {
        let connection = Connection(connection)
        let id = connection.id
        connections[id] = connection
        connection.didStopHandler = { [weak self] in self?.didStopHandler($0, id) }
        connection.start()
    }

    func didStopHandler(_ reason: Connection.CompletionReason, _ connectionId: Connection.ID) {
        print("[server] connection \(self) did stop")
        connections.removeValue(forKey: connectionId)
    }

}

private extension Server.Connection {

    func start(queue: DispatchQueue = .main) {
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

    func send(data: Data) {
        connection.send(content: data, completion: .contentProcessed({ [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.stop(reason: .didFail(error))
                return
            }
            print("[server] successfully sent \(data.count) bytes to client \(self)")
        }))
    }

    func receiveMessage() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: mtu) { [weak self] data, _, complete, error in
            self?.handleReceiveMessage(data: data, isComplete: complete, error: error)
        }
    }

    func handleReceiveMessage(data: Data?, isComplete: Bool, error: Error?) {
        if let data = data, !data.isEmpty, let message = String(data: data, encoding: .utf8) {
            print("[server] received message from connection \(self), adding it to the queue")
            let result = Say.exec(arguments: message)
            if result == 0, let reply = "your message has been played".data(using: .utf8) {
                send(data: reply)
            }
        }
        if isComplete {
            stop(reason: .isComplete)
        } else if let error = error {
            stop(reason: .didFail(error))
        } else {
            receiveMessage()
        }
    }

}

private extension Server.Connection {

    func stateUpdateHandler(_ state: NWConnection.State) {
        switch state {
        case .ready:
            print("[server] connection \(self) established")
        case .waiting(let error):
            print("[server] waiting with error: \(error.localizedDescription)")
        case .failed(let error):
            print("[server] failed with error: \(error.localizedDescription)")
        case .preparing, .setup:
            break
        case .cancelled:
            print("[server] connection \(self) cancelled")
        @unknown default:
            fatalError()
        }
    }

}

extension Server.Connection: CustomStringConvertible {

    var description: String {
        switch connection.endpoint {
        case .hostPort(let host, _):
            return "#\(id)(\(host))"
        default:
            return "#\(id)(\(connection.endpoint))"
        }
    }

}
#endif
