import Foundation
import XCTest
import WalletConnectUtils
import Web3
@testable import WalletConnectKMS
import WalletConnectRelay
import Combine
import WalletConnectNetworking
import WalletConnectPush
@testable import WalletConnectNotify
@testable import WalletConnectPairing
import WalletConnectIdentity
import WalletConnectSigner

final class NotifyTests: XCTestCase {

    var walletNotifyClientA: NotifyClient!

    let gmDappDomain = InputConfig.gmDappHost

    let pk = try! EthereumPrivateKey()

    var privateKey: Data {
        return Data(pk.rawPrivateKey)
    }

    var account: Account {
        return Account("eip155:1:" + pk.address.hex(eip55: true))!
    }

    private var publishers = Set<AnyCancellable>()

    func makeClientDependencies(prefix: String) -> (PairingClient, NetworkInteracting, KeychainStorageProtocol, KeyValueStorage) {
        let keychain = KeychainStorageMock()
        let keyValueStorage = RuntimeKeyValueStorage()

        let relayLogger = ConsoleLogger(prefix: prefix + " [Relay]", loggingLevel: .debug)
        let pairingLogger = ConsoleLogger(prefix: prefix + " [Pairing]", loggingLevel: .debug)
        let networkingLogger = ConsoleLogger(prefix: prefix + " [Networking]", loggingLevel: .debug)
        let kmsLogger = ConsoleLogger(prefix: prefix + " [KMS]", loggingLevel: .debug)

        let relayClient = RelayClientFactory.create(
            relayHost: InputConfig.relayHost,
            projectId: InputConfig.projectId,
            keyValueStorage: keyValueStorage,
            keychainStorage: keychain,
            socketFactory: DefaultSocketFactory(),
            logger: relayLogger)

        let networkingClient = NetworkingClientFactory.create(
            relayClient: relayClient,
            logger: networkingLogger,
            keychainStorage: keychain,
            keyValueStorage: keyValueStorage,
            kmsLogger: kmsLogger)

        let pairingClient = PairingClientFactory.create(
            logger: pairingLogger,
            keyValueStorage: keyValueStorage,
            keychainStorage: keychain,
            networkingClient: networkingClient)

        let clientId = try! networkingClient.getClientId()
        networkingLogger.debug("My client id is: \(clientId)")
        return (pairingClient, networkingClient, keychain, keyValueStorage)
    }

    func makeWalletClient(prefix: String = "🦋 Wallet: ") -> NotifyClient {
        let (pairingClient, networkingInteractor, keychain, keyValueStorage) = makeClientDependencies(prefix: prefix)
        let notifyLogger = ConsoleLogger(prefix: prefix + " [Notify]", loggingLevel: .debug)
        let pushClient = PushClientFactory.create(projectId: "",
                                                  pushHost: "echo.walletconnect.com",
                                                  keyValueStorage: keyValueStorage,
                                                  keychainStorage: keychain,
                                                  environment: .sandbox)
        let keyserverURL = URL(string: "https://keys.walletconnect.com")!
        // Note:- prod project_id do not exists on staging, we can use gmDappProjectId
        let client = NotifyClientFactory.create(projectId: InputConfig.gmDappProjectId,
                                                keyserverURL: keyserverURL,
                                                logger: notifyLogger,
                                                keyValueStorage: keyValueStorage,
                                                keychainStorage: keychain,
                                                groupKeychainStorage: KeychainStorageMock(),
                                                networkInteractor: networkingInteractor,
                                                pairingRegisterer: pairingClient,
                                                pushClient: pushClient,
                                                crypto: DefaultCryptoProvider(),
                                                notifyHost: InputConfig.notifyHost, 
                                                explorerHost: InputConfig.explorerHost)
        return client
    }

    override func setUp() {
        walletNotifyClientA = makeWalletClient()
    }

    func testWalletCreatesSubscription() async {
        let expectation = expectation(description: "expects to create notify subscription")

        walletNotifyClientA.subscriptionsPublisher
            .sink { [unowned self] subscriptions in
                guard let subscription = subscriptions.first else { return }
                Task(priority: .high) {
                    try await walletNotifyClientA.deleteSubscription(topic: subscription.topic)
                    expectation.fulfill()
                }
            }.store(in: &publishers)

        try! await walletNotifyClientA.register(account: account, domain: gmDappDomain, onSign: sign)
        try! await walletNotifyClientA.subscribe(appDomain: gmDappDomain, account: account)

        wait(for: [expectation], timeout: InputConfig.defaultTimeout)
    }

    func testNotifyWatchSubscriptions() async throws {
        let expectation = expectation(description: "expects client B to receive subscription created by client A")
        expectation.assertForOverFulfill = false

        let clientB = makeWalletClient(prefix: "👐🏼 Wallet B: ")
        clientB.subscriptionsPublisher.sink { subscriptions in
            guard let subscription = subscriptions.first else { return }
            Task(priority: .high) {
                try await clientB.deleteSubscription(topic: subscription.topic)
                expectation.fulfill()
            }
        }.store(in: &publishers)

        try! await walletNotifyClientA.register(account: account, domain: gmDappDomain, onSign: sign)
        try! await walletNotifyClientA.subscribe(appDomain: gmDappDomain, account: account)
        try! await clientB.register(account: account, domain: gmDappDomain, onSign: sign)

        wait(for: [expectation], timeout: InputConfig.defaultTimeout)
    }

    func testNotifySubscriptionChanged() async throws {
        let expectation = expectation(description: "expects client B to receive subscription after both clients are registered and client A creates one")
        expectation.assertForOverFulfill = false

        var subscription: NotifySubscription!

        let clientB = makeWalletClient(prefix: "👐🏼 Wallet B: ")
        clientB.subscriptionsPublisher.sink { subscriptions in
            guard let newSubscription = subscriptions.first else { return }
            subscription = newSubscription
            expectation.fulfill()
        }.store(in: &publishers)

        try! await walletNotifyClientA.register(account: account, domain: gmDappDomain, onSign: sign)
        try! await clientB.register(account: account, domain: gmDappDomain, onSign: sign)
        try! await walletNotifyClientA.subscribe(appDomain: gmDappDomain, account: account)

        wait(for: [expectation], timeout: InputConfig.defaultTimeout)

        try await clientB.deleteSubscription(topic: subscription.topic)
    }
    
    func testWalletCreatesAndUpdatesSubscription() async {
        let expectation = expectation(description: "expects to create and update notify subscription")
        expectation.assertForOverFulfill = false

        var updateScope: Set<String>!
        var didUpdate = false

        walletNotifyClientA.subscriptionsPublisher
            .sink { [unowned self] subscriptions in
                guard 
                    let subscription = subscriptions.first,
                    let scope = subscription.scope.keys.first
                else { return }

                let updatedScope = Set(subscription.scope.filter { $0.value.enabled == true }.keys)

                if !didUpdate {
                    updateScope = Set([scope])
                    didUpdate = true
                    Task(priority: .high) {
                        try await walletNotifyClientA.update(topic: subscription.topic, scope: Set([scope]))
                    }
                }
                if updateScope == updatedScope {
                    Task(priority: .high) {
                        try await walletNotifyClientA.deleteSubscription(topic: subscription.topic)
                        expectation.fulfill()
                    }
                }
            }.store(in: &publishers)

        try! await walletNotifyClientA.register(account: account, domain: gmDappDomain, onSign: sign)
        try! await walletNotifyClientA.subscribe(appDomain: gmDappDomain, account: account)

        wait(for: [expectation], timeout: InputConfig.defaultTimeout)
    }

    func testNotifyServerSubscribeAndNotifies() async throws {
        let subscribeExpectation = expectation(description: "creates notify subscription")
        let messageExpectation = expectation(description: "receives a notify message")

        var notifyMessage: NotifyMessage!

        var didNotify = false
        walletNotifyClientA.subscriptionsPublisher
            .sink { subscriptions in
                guard
                    let subscription = subscriptions.first,
                    let scope = subscription.scope.keys.first
                else { return }

                let notifier = Publisher()
                if !didNotify {
                    didNotify = true

                    let message = NotifyMessage.stub(type: scope)
                    notifyMessage = message

                    Task(priority: .high) {
                        try await notifier.notify(topic: subscription.topic, account: subscription.account, message: message)
                        subscribeExpectation.fulfill()
                    }
                }
            }.store(in: &publishers)

        walletNotifyClientA.notifyMessagePublisher
            .sink { [unowned self] notifyMessageRecord in
                XCTAssertEqual(notifyMessageRecord.message, notifyMessage)

                Task(priority: .high) {
                    try await walletNotifyClientA.deleteSubscription(topic: notifyMessageRecord.topic)
                    messageExpectation.fulfill()
                }
        }.store(in: &publishers)

        try! await walletNotifyClientA.register(account: account, domain: gmDappDomain, onSign: sign)
        try! await walletNotifyClientA.subscribe(appDomain: gmDappDomain, account: account)

        wait(for: [subscribeExpectation, messageExpectation], timeout: InputConfig.defaultTimeout)
    }

}


private extension NotifyTests {
    func sign(_ message: String) -> SigningResult {
        let signer = MessageSignerFactory(signerFactory: DefaultSignerFactory()).create(projectId: InputConfig.projectId)
        return .signed(try! signer.sign(message: message, privateKey: privateKey, type: .eip191))
    }
}
