import Darwin
import Network
import XCTest
@testable import IntervalTracker

@MainActor
final class LoopbackCallbackTests: XCTestCase {
    private final class Received: @unchecked Sendable {
        private let lock = NSLock()
        private var targets: [String] = []

        var all: [String] { lock.withLock { targets } }

        func add(_ target: String) {
            lock.withLock { targets.append(target) }
        }
    }

    func testTheBrowsersRequestIsHandedOverAndTheBrowserIsSentToTheCallbackScheme() async throws {
        let received = Received()
        let listener = try await LoopbackCallback.start(reply: .redirect(WebSignIn.done)) { received.add($0) }
        defer { listener.stop() }
        XCTAssertNotEqual(listener.port, 0, "the system chose a port")

        let reply = try await get("http://127.0.0.1:\(listener.port)/auth/callback?code=the-code&state=the-state")

        XCTAssertEqual(reply.status, 302)
        XCTAssertEqual(reply.location, "intervals-auth://done")
        XCTAssertEqual(received.all, ["/auth/callback?code=the-code&state=the-state"])
    }

    func testASafariSignInGetsAPageThatSendsTheUserBack() async throws {
        let received = Received()
        let listener = try await LoopbackCallback.start(reply: .page("Signed in. Go back to Intervals.")) { received.add($0) }
        defer { listener.stop() }

        let reply = try await get("http://127.0.0.1:\(listener.port)/auth/callback?code=the-code&state=the-state")

        XCTAssertEqual(reply.status, 200)
        XCTAssertTrue(reply.body.contains("Signed in. Go back to Intervals."), reply.body)
        XCTAssertEqual(received.all.count, 1)
    }

    func testAnyOtherRequestIsTurnedAway() async throws {
        let received = Received()
        let listener = try await LoopbackCallback.start(reply: .redirect(WebSignIn.done)) { received.add($0) }
        defer { listener.stop() }

        for path in ["/", "/favicon.ico", "/auth/callback/more?code=the-code", "/other?code=the-code&state=the-state"] {
            let reply = try await get("http://127.0.0.1:\(listener.port)\(path)")
            XCTAssertEqual(reply.status, 404, path)
            XCTAssertNil(reply.location, path)
        }
        XCTAssertEqual(received.all, [])
    }

    func testTwoListenersGetDifferentPorts() async throws {
        let first = try await LoopbackCallback.start(reply: .redirect(WebSignIn.done)) { _ in }
        let second = try await LoopbackCallback.start(reply: .redirect(WebSignIn.done)) { _ in }
        defer {
            first.stop()
            second.stop()
        }
        XCTAssertNotEqual(first.port, second.port)
    }

    /// Another app on the phone can connect and never finish its request. Stopping the listener
    /// has to drop that connection, not leave it open for as long as the other app likes.
    func testAnUnfinishedRequestIsDroppedWhenTheListenerStops() async throws {
        let listener = try await LoopbackCallback.start(reply: .redirect(WebSignIn.done)) { _ in }
        let port = try XCTUnwrap(NWEndpoint.Port(rawValue: listener.port))
        let connection = NWConnection(host: .ipv4(.loopback), port: port, using: .tcp)
        defer { connection.cancel() }
        let closed = expectation(description: "the listener closed the connection")
        connection.stateUpdateHandler = { state in
            guard case .ready = state else { return }
            connection.send(content: Data("GET /auth/callback?code=".utf8), completion: .contentProcessed { _ in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, isComplete, error in
                    if data == nil, isComplete || error != nil { closed.fulfill() }
                }
                // After the listener has taken the connection in, so that the stop is what closes it.
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { listener.stop() }
            })
        }
        connection.start(queue: .global())
        await fulfillment(of: [closed], timeout: 5)
    }

    func testNothingAnswersAfterTheListenerStops() async throws {
        let listener = try await LoopbackCallback.start(reply: .redirect(WebSignIn.done)) { _ in }
        let address = "http://127.0.0.1:\(listener.port)/auth/callback?code=the-code&state=the-state"
        let before = try await get(address)
        XCTAssertEqual(before.status, 302)

        listener.stop()

        var refused = false
        for _ in 0..<100 where !refused {
            refused = (try? await get(address)) == nil
            if !refused { try await Task.sleep(for: .milliseconds(50)) }
        }
        XCTAssertTrue(refused, "the port stayed open after stop")
    }

    /// The listener must not be reachable from the network. A second socket can take the same port on
    /// the machine's network address only if the listener does not hold that address, which it would
    /// if it were bound to every address.
    func testTheListenerHoldsItsPortOnTheLoopbackAddressOnly() async throws {
        let address = try XCTUnwrap(Self.addressOnTheNetwork(), "this machine has no network address to try")
        let listener = try await LoopbackCallback.start(reply: .redirect(WebSignIn.done)) { _ in }
        defer { listener.stop() }

        XCTAssertFalse(Self.canBind("127.0.0.1", listener.port), "the listener holds the loopback address")
        XCTAssertTrue(Self.canBind(address, listener.port), "the listener also holds \(address), so the network can reach it")
    }

    private static func canBind(_ address: String, _ port: UInt16) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(descriptor) }
        var name = sockaddr_in()
        name.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        name.sin_family = sa_family_t(AF_INET)
        name.sin_port = port.bigEndian
        inet_pton(AF_INET, address, &name.sin_addr)
        return withUnsafePointer(to: &name) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    private static func addressOnTheNetwork() -> String? {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return nil }
        defer { freeifaddrs(first) }
        for interface in sequence(first: first, next: { $0?.pointee.ifa_next }) {
            guard let interface, let address = interface.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
                  interface.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0, interface.pointee.ifa_flags & UInt32(IFF_UP) != 0
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            return String(cString: host)
        }
        return nil
    }
}
