// RUN: %empty-directory(%t)
// RUN: split-file %s %t

// RUN: %target-swift-frontend -typecheck -verify -target %target-swift-5.1-abi-triple -swift-version 6 -enable-upcoming-feature InferIsolatedConformances -verify-additional-prefix swift6- %t/implied.swift
// RUN: %target-swift-frontend -typecheck -verify -target %target-swift-5.1-abi-triple -swift-version 6 -enable-upcoming-feature InferIsolatedConformances -enable-experimental-feature NoExplicitNonIsolated -verify-additional-prefix swift6- %t/implied.swift
// RUN: %target-swift-frontend -typecheck -verify -target %target-swift-5.1-abi-triple -swift-version 5 -enable-upcoming-feature InferIsolatedConformances -verify-additional-prefix swift5- %t/implied.swift
// RUN: %target-swift-frontend -typecheck -verify -target %target-swift-5.1-abi-triple -swift-version 5 -enable-upcoming-feature InferIsolatedConformances -enable-experimental-feature NoExplicitNonIsolated -verify-additional-prefix swift5- %t/implied.swift

// RUN: %target-swift-frontend -typecheck -verify -target %target-swift-5.1-abi-triple -swift-version 6 -enable-upcoming-feature InferIsolatedConformances %t/no_explicit_nonisolated.swift
// RUN: %target-swift-frontend -typecheck -verify -target %target-swift-5.1-abi-triple -swift-version 6 -enable-upcoming-feature InferIsolatedConformances -enable-experimental-feature NoExplicitNonIsolated -verify-additional-prefix swift6- %t/no_explicit_nonisolated.swift
// RUN: %target-swift-frontend -typecheck -verify -target %target-swift-5.1-abi-triple -swift-version 5 -enable-upcoming-feature InferIsolatedConformances -enable-experimental-feature NoExplicitNonIsolated -verify-additional-prefix swift5- %t/no_explicit_nonisolated.swift

// '-default-isolation MainActor' enables both features on its own; they're
// passed explicitly so this doesn't depend on that.
// RUN: %target-swift-frontend -typecheck -verify -target %target-swift-5.1-abi-triple -swift-version 6 -default-isolation MainActor -enable-upcoming-feature InferIsolatedConformances -enable-experimental-feature NoExplicitNonIsolated -verify-additional-prefix swift6- %t/default_main_actor.swift
// RUN: %target-swift-frontend -typecheck -verify -target %target-swift-5.1-abi-triple -swift-version 5 -default-isolation MainActor -enable-upcoming-feature InferIsolatedConformances -enable-experimental-feature NoExplicitNonIsolated -verify-additional-prefix swift5- %t/default_main_actor.swift

// REQUIRES: concurrency
// REQUIRES: swift_feature_InferIsolatedConformances
// REQUIRES: swift_feature_NoExplicitNonIsolated

// rdar://187159435: a conformance that is implied by a conformance to a
// protocol inheriting 'SendableMetatype' (e.g. through 'Sendable') is not
// inferred to be isolated. An isolated conformance could never satisfy the
// implying protocol's 'Self: Sendable' requirement, so inferring one only
// produced "cannot satisfy conformance requirement for a 'Sendable' type
// parameter 'Self'" and "does not conform". Witness checking now diagnoses an
// isolated witness directly, or accepts it when that's safe (e.g. 'async').

//--- implied.swift

// MARK: - Implied by a 'Sendable' refinement: nonisolated

// ScreenTime (QuickActionViewModel, rdar://187629090): 'Sendable' comes in
// through a typealias composition. The witness is main-actor-isolated, but so is
// the requirement.
protocol ScreenTimeAuthenticationAccepting: AnyObject, Sendable {}

protocol ScreenTimeSettingsAuthenticatedUpdating {
  @MainActor func updatePolicy()
}

typealias ScreenTimeSettingsAuthenticating =
  ScreenTimeSettingsAuthenticatedUpdating & ScreenTimeAuthenticationAccepting

protocol AppAndWebsiteActivityPolicyProviding: ScreenTimeSettingsAuthenticating {}

@MainActor
final class QuickActionViewModel: AppAndWebsiteActivityPolicyProviding {
  func updatePolicy() {}
}

// SecureMessaging (SwiftMLSPersister): a custom global actor, and an 'async'
// witness, which can be called from any isolation.
@globalActor
actor MLSActor {
  static let shared = MLSActor()
}

protocol Persisting: Sendable {}

protocol ClientStateStorage {
  func load() async -> Int
}

@MLSActor
protocol MLSPersisting: Persisting, ClientStateStorage {}

@MLSActor
final class SwiftMLSPersister: MLSPersisting {
  func load() async -> Int { 0 }
}

// MobilePhone (FaceTimeVoicemailManager): 'Sendable' and the protocol whose
// conformance is implied are composed in the inheritance clause.
@globalActor
actor VoicemailActor {
  static let shared = VoicemailActor()
}

protocol VoicemailManager_Objc: Sendable {}

protocol VoicemailManager_UnreadCount {
  func countOfUnreadMessages() async -> UInt
}

@VoicemailActor
protocol VoicemailManager: VoicemailManager_Objc & VoicemailManager_UnreadCount {}

@VoicemailActor
final class FaceTimeVoicemailManager: VoicemailManager {
  func countOfUnreadMessages() async -> UInt { 0 }
}

// The same shape with a synchronous requirement: the isolated witness is
// diagnosed itself, rather than as a failure to conform to the refinement.
protocol VoicemailManager_MessageCount {
  func countOfMessages() -> UInt
}

@VoicemailActor
protocol SyncVoicemailManager: VoicemailManager_Objc & VoicemailManager_MessageCount {}

@VoicemailActor
final class SyncVoicemailManagerImpl: SyncVoicemailManager {
  // expected-swift6-error@-1 {{conformance of 'SyncVoicemailManagerImpl' to protocol 'VoicemailManager_MessageCount' crosses into global actor 'VoicemailActor'-isolated code and can cause data races}}
  // expected-swift5-warning@-2 {{conformance of 'SyncVoicemailManagerImpl' to protocol 'VoicemailManager_MessageCount' crosses into global actor 'VoicemailActor'-isolated code and can cause data races; this is an error in the Swift 6 language mode}}
  // expected-note@-3 {{isolate this conformance to the global actor 'VoicemailActor' with '@VoicemailActor'}}
  // expected-note@-4 {{turn data races into runtime errors with '@preconcurrency'}}
  func countOfMessages() -> UInt { 0 }
  // expected-note@-1 {{global actor 'VoicemailActor'-isolated instance method 'countOfMessages()' cannot satisfy nonisolated requirement}}
  // expected-note@-2 {{mark instance method 'countOfMessages()' 'nonisolated'}}
}

// Not from the corpus: 'Sendable' two refinements up. 'Leaf' is implied by
// 'Middle', which is implied by 'Root', so the whole chain is walked.
protocol Leaf {
  func leaf()
}

protocol Middle: Leaf {}

protocol Root: Middle, Sendable {}

@MainActor
final class RootConformer: Root {
  // expected-swift6-error@-1 {{conformance of 'RootConformer' to protocol 'Leaf' crosses into main actor-isolated code and can cause data races}}
  // expected-swift5-warning@-2 {{conformance of 'RootConformer' to protocol 'Leaf' crosses into main actor-isolated code and can cause data races; this is an error in the Swift 6 language mode}}
  // expected-note@-3 {{isolate this conformance to the main actor with '@MainActor'}}
  // expected-note@-4 {{turn data races into runtime errors with '@preconcurrency'}}
  func leaf() {}
  // expected-note@-1 {{main actor-isolated instance method 'leaf()' cannot satisfy nonisolated requirement}}
  // expected-note@-2 {{mark instance method 'leaf()' 'nonisolated'}}
}

// The stdlib collection protocols, all implied by one refinement. The isolated
// subscript is reported against each protocol that requires it.
protocol SendableRandomAccessCollection: RandomAccessCollection, Sendable {}

@MainActor
struct IsolatedSubscriptCollection: SendableRandomAccessCollection {
  // expected-swift6-error@-1 {{conformance of 'IsolatedSubscriptCollection' to protocol 'RandomAccessCollection' crosses into main actor-isolated code and can cause data races}}
  // expected-swift6-error@-2 {{conformance of 'IsolatedSubscriptCollection' to protocol 'BidirectionalCollection' crosses into main actor-isolated code and can cause data races}}
  // expected-swift6-error@-3 {{conformance of 'IsolatedSubscriptCollection' to protocol 'Collection' crosses into main actor-isolated code and can cause data races}}
  // expected-swift5-warning@-4 {{conformance of 'IsolatedSubscriptCollection' to protocol 'RandomAccessCollection' crosses into main actor-isolated code and can cause data races; this is an error in the Swift 6 language mode}}
  // expected-swift5-warning@-5 {{conformance of 'IsolatedSubscriptCollection' to protocol 'BidirectionalCollection' crosses into main actor-isolated code and can cause data races; this is an error in the Swift 6 language mode}}
  // expected-swift5-warning@-6 {{conformance of 'IsolatedSubscriptCollection' to protocol 'Collection' crosses into main actor-isolated code and can cause data races; this is an error in the Swift 6 language mode}}
  // expected-note@-7 3 {{isolate this conformance to the main actor with '@MainActor'}}
  // expected-note@-8 3 {{turn data races into runtime errors with '@preconcurrency'}}
  nonisolated var startIndex: Int { 0 }
  nonisolated var endIndex: Int { 0 }
  subscript(position: Int) -> Int { 0 }
  // expected-note@-1 3 {{main actor-isolated subscript 'subscript(_:)' cannot satisfy nonisolated requirement}}
  // expected-note@-2 3 {{mark subscript 'subscript(_:)' 'nonisolated'}}

  typealias Iterator = IndexingIterator<IsolatedSubscriptCollection>
  typealias SubSequence = Slice<IsolatedSubscriptCollection>
}

// PhoneFaceTime_CommunicationsUICore (ActivityWrapper). In Swift 5 nothing is
// diagnosed: the class's isolation is inferred from the protocol, not written.
@MainActor
protocol ActivityWrapperProtocol: CustomStringConvertible, Sendable {
  func end() async
}

final class ImpliedDescriptionActivityWrapper: ActivityWrapperProtocol {
  // expected-swift6-error@-1 {{conformance of 'ImpliedDescriptionActivityWrapper' to protocol 'CustomStringConvertible' crosses into main actor-isolated code and can cause data races}}
  // expected-swift6-note@-2 {{isolate this conformance to the main actor with '@MainActor'}}
  // expected-swift6-note@-3 {{turn data races into runtime errors with '@preconcurrency'}}
  func end() async {}
  var description: String { "" }
  // expected-swift6-note@-1 {{main actor-isolated property 'description' cannot satisfy nonisolated requirement}}
  // expected-swift6-note@-2 {{mark property 'description' 'nonisolated'}}
}

// FIXME: Known gap. Restating the conformance in an extension makes it
// explicit rather than implied, so it's still inferred isolated and reported
// the old way, in both language modes.
final class RestatedDescriptionActivityWrapper: ActivityWrapperProtocol {
  // expected-error@-1 {{type 'RestatedDescriptionActivityWrapper' does not conform to protocol 'ActivityWrapperProtocol'}}
  // expected-error@-2 {{main actor-isolated conformance of 'RestatedDescriptionActivityWrapper' to 'CustomStringConvertible' cannot satisfy conformance requirement for a 'Sendable' type parameter 'Self'}}
  // expected-note@-3 {{requirement specified as 'Self' : 'CustomStringConvertible' [with Self = RestatedDescriptionActivityWrapper]}}
  func end() async {}
}

extension RestatedDescriptionActivityWrapper: CustomStringConvertible {
  var description: String { "" }
}

// MARK: - No 'Sendable' refinement: still inferred isolated

protocol Refreshing {
  func refresh()
}

protocol RefreshingModel: Refreshing {}

@MainActor
final class RefreshingViewModel: RefreshingModel {
  func refresh() {}
}

// 'Sendable' on the conforming type, rather than on a protocol that implies the
// conformance, doesn't stop the inference.
@MainActor
final class SendableRefreshingViewModel: Sendable, RefreshingModel {
  func refresh() {}
}

// MARK: - Uses from a nonisolated context

nonisolated func useUpdating<T: ScreenTimeSettingsAuthenticatedUpdating>(_: T.Type) {}
nonisolated func useClientStateStorage<T: ClientStateStorage>(_: T.Type) {}
nonisolated func useUnreadCount<T: VoicemailManager_UnreadCount>(_: T.Type) {}
nonisolated func useLeaf<T: Leaf>(_: T.Type) {}
nonisolated func useRandomAccessCollection<T: RandomAccessCollection>(_: T.Type) {}
nonisolated func useRefreshing<T: Refreshing>(_: T.Type) {}
nonisolated func useRefreshingModel<T: RefreshingModel>(_: T.Type) {}

nonisolated func testUsesFromNonisolatedContext() {
  useUpdating(QuickActionViewModel.self)
  useClientStateStorage(SwiftMLSPersister.self)
  useUnreadCount(FaceTimeVoicemailManager.self)
  useLeaf(RootConformer.self)
  useRandomAccessCollection(IsolatedSubscriptCollection.self)

  useRefreshing(RefreshingViewModel.self)
  // expected-swift6-error@-1 {{main actor-isolated conformance of 'RefreshingViewModel' to 'Refreshing' cannot be used in nonisolated context}}
  // expected-swift5-warning@-2 {{main actor-isolated conformance of 'RefreshingViewModel' to 'Refreshing' cannot be used in nonisolated context; this is an error in the Swift 6 language mode}}
  useRefreshingModel(RefreshingViewModel.self)
  // expected-swift6-error@-1 {{main actor-isolated conformance of 'RefreshingViewModel' to 'RefreshingModel' cannot be used in nonisolated context}}
  // expected-swift5-warning@-2 {{main actor-isolated conformance of 'RefreshingViewModel' to 'RefreshingModel' cannot be used in nonisolated context; this is an error in the Swift 6 language mode}}
  useRefreshing(SendableRefreshingViewModel.self)
  // expected-swift6-error@-1 {{main actor-isolated conformance of 'SendableRefreshingViewModel' to 'Refreshing' cannot be used in nonisolated context}}
  // expected-swift5-warning@-2 {{main actor-isolated conformance of 'SendableRefreshingViewModel' to 'Refreshing' cannot be used in nonisolated context; this is an error in the Swift 6 language mode}}
}

//--- no_explicit_nonisolated.swift

// Isolated protocols with a 'nonisolated' requirement. Their conformances are
// never inferred isolated (the protocol is isolated), before or after the
// 'Sendable' check, so these only change with NoExplicitNonIsolated, under
// which the requirement's 'nonisolated' no longer carries over to the witness.

// GreenTorch (ContactsProvider): implied through 'DataProvider: Sendable'.
@globalActor
actor DataActor {
  static let shared = DataActor()
}

struct Logger: Sendable {}

@DataActor
protocol SubscriptionManaging: AnyObject {
  nonisolated static var logger: Logger { get }
}

@DataActor
protocol DataProvider: SubscriptionManaging, Sendable {}

@DataActor
final class ContactsProvider: DataProvider {
  // expected-swift6-error@-1 {{conformance of 'ContactsProvider' to protocol 'SubscriptionManaging' crosses into global actor 'DataActor'-isolated code and can cause data races}}
  // expected-swift5-warning@-2 {{conformance of 'ContactsProvider' to protocol 'SubscriptionManaging' crosses into global actor 'DataActor'-isolated code and can cause data races; this is an error in the Swift 6 language mode}}
  // expected-swift6-note@-3 {{isolate this conformance to the global actor 'DataActor' with '@DataActor'}}
  // expected-swift5-note@-4 {{isolate this conformance to the global actor 'DataActor' with '@DataActor'}}
  // expected-swift6-note@-5 {{turn data races into runtime errors with '@preconcurrency'}}
  // expected-swift5-note@-6 {{turn data races into runtime errors with '@preconcurrency'}}
  static let logger = Logger()
  // expected-swift6-note@-1 {{global actor 'DataActor'-isolated static property 'logger' cannot satisfy nonisolated requirement}}
  // expected-swift5-note@-2 {{global actor 'DataActor'-isolated static property 'logger' cannot satisfy nonisolated requirement}}
}

@DataActor
final class NonisolatedLoggerContactsProvider: DataProvider {
  nonisolated static let logger = Logger()
}

// ExtensionFoundation (AppExtensionConfiguration): an explicit conformance to a
// '@MainActor' protocol that is itself 'Sendable'. The fix for the world build
// is in the client (rdar://188409038).
final class NSXPCConnection: @unchecked Sendable {}

@preconcurrency @MainActor
protocol AppExtensionConfiguration: Sendable {
  nonisolated func accept(connection: NSXPCConnection) -> Bool
}

// DoorsDevice (PlaceholderConfiguration): isolation inferred from the protocol.
struct PlaceholderConfiguration: AppExtensionConfiguration {
  // expected-swift6-error@-1 {{conformance of 'PlaceholderConfiguration' to protocol 'AppExtensionConfiguration' crosses into main actor-isolated code and can cause data races}}
  // expected-swift6-note@-2 {{isolate this conformance to the main actor with '@MainActor'}}
  // expected-swift6-note@-3 {{turn data races into runtime errors with '@preconcurrency'}}
  func accept(connection _: NSXPCConnection) -> Bool { false }
  // expected-swift6-note@-1 {{main actor-isolated instance method 'accept(connection:)' cannot satisfy nonisolated requirement}}
  // expected-swift6-note@-2 {{mark instance method 'accept(connection:)' 'nonisolated'}}
}

// MediaRemote_NowPlaying (RemoteMediaSessionExtensionConfiguration): explicitly
// '@MainActor' type, conformance in an extension.
@MainActor
final class RemoteMediaSessionExtensionConfiguration {
  let handler: NSXPCConnection
  init(handler: NSXPCConnection) { self.handler = handler }
}

extension RemoteMediaSessionExtensionConfiguration: AppExtensionConfiguration {
  // expected-swift6-error@-1 {{conformance of 'RemoteMediaSessionExtensionConfiguration' to protocol 'AppExtensionConfiguration' crosses into main actor-isolated code and can cause data races}}
  // expected-swift5-warning@-2 {{conformance of 'RemoteMediaSessionExtensionConfiguration' to protocol 'AppExtensionConfiguration' crosses into main actor-isolated code and can cause data races; this is an error in the Swift 6 language mode}}
  // expected-swift6-note@-3 {{isolate this conformance to the main actor with '@MainActor'}}
  // expected-swift5-note@-4 {{isolate this conformance to the main actor with '@MainActor'}}
  // expected-swift6-note@-5 {{turn data races into runtime errors with '@preconcurrency'}}
  // expected-swift5-note@-6 {{turn data races into runtime errors with '@preconcurrency'}}
  func accept(connection: NSXPCConnection) -> Bool { true }
  // expected-swift6-note@-1 {{main actor-isolated instance method 'accept(connection:)' cannot satisfy nonisolated requirement}}
  // expected-swift5-note@-2 {{main actor-isolated instance method 'accept(connection:)' cannot satisfy nonisolated requirement}}
  // expected-swift6-note@-3 {{mark instance method 'accept(connection:)' 'nonisolated'}}
  // expected-swift5-note@-4 {{mark instance method 'accept(connection:)' 'nonisolated'}}
}

struct ExplicitlyNonisolatedConfiguration: AppExtensionConfiguration {
  nonisolated func accept(connection _: NSXPCConnection) -> Bool { false }
}

//--- default_main_actor.swift

// Protocols are main-actor-isolated by default in this mode, and a conformance
// to an isolated protocol is never inferred isolated, so the ones below are
// 'nonisolated'.
nonisolated protocol Loading {
  func load()
}

nonisolated protocol SendableLoading: Loading, Sendable {}

nonisolated protocol CachedLoading: Loading {}

// Conformance in an extension of a main-actor type.
struct ExtensionLoader {}

extension ExtensionLoader: SendableLoading {
  // expected-swift6-error@-1 {{conformance of 'ExtensionLoader' to protocol 'Loading' crosses into main actor-isolated code and can cause data races}}
  // expected-swift5-warning@-2 {{conformance of 'ExtensionLoader' to protocol 'Loading' crosses into main actor-isolated code and can cause data races; this is an error in the Swift 6 language mode}}
  // expected-note@-3 {{isolate this conformance to the main actor with '@MainActor'}}
  // expected-note@-4 {{turn data races into runtime errors with '@preconcurrency'}}
  @MainActor func load() {}
  // expected-note@-1 {{main actor-isolated instance method 'load()' cannot satisfy nonisolated requirement}}
}

@MainActor
final class ClassLoader: SendableLoading {
  // expected-swift6-error@-1 {{conformance of 'ClassLoader' to protocol 'Loading' crosses into main actor-isolated code and can cause data races}}
  // expected-swift5-warning@-2 {{conformance of 'ClassLoader' to protocol 'Loading' crosses into main actor-isolated code and can cause data races; this is an error in the Swift 6 language mode}}
  // expected-note@-3 {{isolate this conformance to the main actor with '@MainActor'}}
  // expected-note@-4 {{turn data races into runtime errors with '@preconcurrency'}}
  @MainActor func load() {}
  // expected-note@-1 {{main actor-isolated instance method 'load()' cannot satisfy nonisolated requirement}}
}

// A 'nonisolated' type conformed in an extension. Newly diagnosed: without the
// 'Sendable' check the witness was accepted as if the conformance would be
// main-actor-isolated, while the conformance itself was nonisolated.
nonisolated struct NonisolatedLoader {}

extension NonisolatedLoader: SendableLoading {
  // expected-swift6-error@-1 {{conformance of 'NonisolatedLoader' to protocol 'Loading' crosses into main actor-isolated code and can cause data races}}
  // expected-swift5-warning@-2 {{conformance of 'NonisolatedLoader' to protocol 'Loading' crosses into main actor-isolated code and can cause data races; this is an error in the Swift 6 language mode}}
  // expected-note@-3 {{isolate this conformance to the main actor with '@MainActor'}}
  // expected-note@-4 {{turn data races into runtime errors with '@preconcurrency'}}
  @MainActor func load() {}
  // expected-note@-1 {{main actor-isolated instance method 'load()' cannot satisfy nonisolated requirement}}
}

// No 'Sendable' refinement: still inferred isolated.
struct CachedExtensionLoader {}

extension CachedExtensionLoader: CachedLoading {
  @MainActor func load() {}
}

nonisolated func useLoading<T: Loading>(_: T.Type) {}

nonisolated func testUsesFromNonisolatedContext() {
  useLoading(ExtensionLoader.self)
  useLoading(ClassLoader.self)
  useLoading(NonisolatedLoader.self)

  useLoading(CachedExtensionLoader.self)
  // expected-swift6-error@-1 {{main actor-isolated conformance of 'CachedExtensionLoader' to 'Loading' cannot be used in nonisolated context}}
  // expected-swift5-warning@-2 {{main actor-isolated conformance of 'CachedExtensionLoader' to 'Loading' cannot be used in nonisolated context; this is an error in the Swift 6 language mode}}
}
