// RUN: %target-swift-frontend -primary-file %s -emit-ir -target %target-swift-5.1-abi-triple -swift-version 6 -enable-upcoming-feature InferIsolatedConformances | %FileCheck %s

// REQUIRES: PTRSIZE=64
// REQUIRES: concurrency
// REQUIRES: swift_feature_InferIsolatedConformances
// UNSUPPORTED: CPU=arm64e

// A conformance implied by a conformance to a protocol that inherits 'Sendable'
// is emitted nonisolated: a plain descriptor with no flags, rather than one
// with the 'hasGlobalActorIsolation' flag (1 << 19 = 524288) and trailing
// global actor type and conformance.

@globalActor
actor MLSActor {
  static let shared = MLSActor()
}

// SecureMessaging (SwiftMLSPersister): custom global actor, 'async' witness.
protocol Persisting: Sendable {}

protocol ClientStateStorage {
  func load() async -> Int
}

@MLSActor
protocol MLSPersisting: Persisting, ClientStateStorage {}

// CHECK-DAG: @"$s46isolated_conformance_sendable_metatype_implied17SwiftMLSPersisterCAA18ClientStateStorageAAMc" = {{.*}}constant %swift.protocol_conformance_descriptor {{.*}}, i32 0 }
@MLSActor
final class SwiftMLSPersister: MLSPersisting {
  func load() async -> Int { 0 }
}

// ScreenTime (QuickActionViewModel): 'Sendable' through a typealias composition.
protocol ScreenTimeAuthenticationAccepting: AnyObject, Sendable {}

protocol ScreenTimeSettingsAuthenticatedUpdating {
  @MainActor func updatePolicy()
}

typealias ScreenTimeSettingsAuthenticating =
  ScreenTimeSettingsAuthenticatedUpdating & ScreenTimeAuthenticationAccepting

protocol AppAndWebsiteActivityPolicyProviding: ScreenTimeSettingsAuthenticating {}

// CHECK-DAG: @"$s46isolated_conformance_sendable_metatype_implied20QuickActionViewModelCAA39ScreenTimeSettingsAuthenticatedUpdatingAAMc" = {{.*}}constant %swift.protocol_conformance_descriptor {{.*}}, i32 0 }
@MainActor
final class QuickActionViewModel: AppAndWebsiteActivityPolicyProviding {
  func updatePolicy() {}
}

// Control: nothing in the chain inherits 'Sendable', so both the implied
// conformance and the one implying it are still inferred main-actor-isolated.
protocol Refreshing {
  func refresh()
}

protocol RefreshingModel: Refreshing {}

// CHECK-DAG: @"$s46isolated_conformance_sendable_metatype_implied19RefreshingViewModelCAA0F0AAMc" = {{.*}}constant { i32, i32, i32, i32, i32, i32 } {{.*}}, i32 524288, {{.*}}ScM
// CHECK-DAG: @"$s46isolated_conformance_sendable_metatype_implied19RefreshingViewModelCAA0fH0AAMc" = {{.*}}constant { i32, i32, i32, i32, i32, i32 } {{.*}}, i32 524288, {{.*}}ScM
@MainActor
final class RefreshingViewModel: RefreshingModel {
  func refresh() {}
}
