import Foundation
import Combine

protocol NotifyStoring {
    func getAllSubscriptions() -> [NotifySubscription]
    func getSubscriptions(account: Account) -> [NotifySubscription]
    func getSubscription(topic: String) -> NotifySubscription?
    func setSubscription(_ subscription: NotifySubscription) async throws
    func deleteSubscription(topic: String) async throws
    func clearDatabase(account: Account)
}

final class NotifyStorage: NotifyStoring {

    private var publishers = Set<AnyCancellable>()

    private let subscriptionStore: KeyedDatabase<NotifySubscription>
    private let messagesStore: KeyedDatabase<NotifyMessageRecord>

    private let newSubscriptionSubject = PassthroughSubject<NotifySubscription, Never>()
    private let updateSubscriptionSubject = PassthroughSubject<NotifySubscription, Never>()
    private let deleteSubscriptionSubject = PassthroughSubject<String, Never>()
    private let subscriptionsSubject = PassthroughSubject<[NotifySubscription], Never>()
    private let messagesSubject = PassthroughSubject<[NotifyMessageRecord], Never>()

    private let accountProvider: NotifyAccountProvider

    var newSubscriptionPublisher: AnyPublisher<NotifySubscription, Never> {
        return newSubscriptionSubject.eraseToAnyPublisher()
    }

    var updateSubscriptionPublisher: AnyPublisher<NotifySubscription, Never> {
        return updateSubscriptionSubject.eraseToAnyPublisher()
    }

    var deleteSubscriptionPublisher: AnyPublisher<String, Never> {
        return deleteSubscriptionSubject.eraseToAnyPublisher()
    }

    var subscriptionsPublisher: AnyPublisher<[NotifySubscription], Never> {
        return subscriptionsSubject.eraseToAnyPublisher()
    }

    init(subscriptionStore: KeyedDatabase<NotifySubscription>, messagesStore: KeyedDatabase<NotifyMessageRecord>, accountProvider: NotifyAccountProvider) {
        self.subscriptionStore = subscriptionStore
        self.messagesStore = messagesStore
        self.accountProvider = accountProvider

        setupSubscriptions()
    }

    // MARK: Subscriptions

    func getAllSubscriptions() -> [NotifySubscription] {
        return subscriptionStore.getAll()
    }

    func getSubscriptions(account: Account) -> [NotifySubscription] {
        return subscriptionStore.getAll(for: account.absoluteString)
    }

    func getSubscription(topic: String) -> NotifySubscription? {
        return subscriptionStore.getAll().first(where: { $0.topic == topic })
    }

    func setSubscription(_ subscription: NotifySubscription) {
        subscriptionStore.set(element: subscription, for: subscription.account.absoluteString)
        newSubscriptionSubject.send(subscription)
    }

    func replaceAllSubscriptions(_ subscriptions: [NotifySubscription], account: Account) {
        subscriptionStore.replace(elements: subscriptions, for: account.absoluteString)
    }

    func deleteSubscription(topic: String) throws {
        guard let subscription = getSubscription(topic: topic) else {
            throw Errors.subscriptionNotFound
        }
        subscriptionStore.delete(id: topic, for: subscription.account.absoluteString)
        deleteSubscriptionSubject.send(topic)
    }

    func clearDatabase(account: Account) {
        for subscription in getSubscriptions(account: account) {
            deleteMessages(topic: subscription.topic)
        }
        subscriptionStore.deleteAll(for: account.absoluteString)
    }

    func updateSubscription(_ subscription: NotifySubscription, scope: [String: ScopeValue], expiry: UInt64) {
        let expiry = Date(timeIntervalSince1970: TimeInterval(expiry))
        let updated = NotifySubscription(topic: subscription.topic, account: subscription.account, relay: subscription.relay, metadata: subscription.metadata, scope: scope, expiry: expiry, symKey: subscription.symKey, appAuthenticationKey: subscription.appAuthenticationKey)
        subscriptionStore.set(element: updated, for: updated.account.absoluteString)
        updateSubscriptionSubject.send(updated)
    }

    // MARK: Messages

    func messagesPublisher(topic: String) -> AnyPublisher<[NotifyMessageRecord], Never> {
        return messagesSubject
            .map { $0.filter { $0.topic == topic } }
            .eraseToAnyPublisher()
    }

    func getMessages(topic: String) -> [NotifyMessageRecord] {
        return messagesStore.getAll(for: topic)
            .sorted{$0.publishedAt > $1.publishedAt}
    }

    func deleteMessages(topic: String) {
        messagesStore.deleteAll(for: topic)
    }

    func deleteMessage(id: String) {
        guard let result = messagesStore.find(id: id) else { return }
        messagesStore.delete(id: id, for: result.key)
    }

    func setMessage(_ record: NotifyMessageRecord) {
        messagesStore.set(element: record, for: record.topic)
    }
}

private extension NotifyStorage {

    enum Errors: Error {
        case subscriptionNotFound
    }

    func setupSubscriptions() {
        messagesStore.onUpdate = { [unowned self] in
            messagesSubject.send(messagesStore.getAll())
        }

        subscriptionStore.onUpdate = { [unowned self] in
            guard let account = try? accountProvider.getCurrentAccount() else { return }
            subscriptionsSubject.send(getSubscriptions(account: account))
        }
    }
}
