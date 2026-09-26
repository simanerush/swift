// RUN: %target-swift-frontend -typecheck -verify -target %target-swift-5.1-abi-triple -swift-version 6 -enable-upcoming-feature InferIsolatedConformances -verify-additional-prefix swift6- %s
// RUN: %target-swift-frontend -typecheck -verify -target %target-swift-5.1-abi-triple -swift-version 6 -enable-upcoming-feature InferIsolatedConformances -enable-experimental-feature NoExplicitNonIsolated -verify-additional-prefix swift6- %s
// RUN: %target-swift-frontend -typecheck -verify -target %target-swift-5.1-abi-triple -swift-version 5 -enable-upcoming-feature InferIsolatedConformances %s
// RUN: %target-swift-frontend -typecheck -verify -target %target-swift-5.1-abi-triple -swift-version 5 -enable-upcoming-feature InferIsolatedConformances -enable-experimental-feature NoExplicitNonIsolated %s

// REQUIRES: concurrency
// REQUIRES: swift_feature_InferIsolatedConformances
// REQUIRES: swift_feature_NoExplicitNonIsolated

// Deciding whether a conformance is isolated looks up its witnesses and the
// conformances it depends on, and those lookups can lead back to the
// conformance being decided. None of these may end in 'circular reference'.

// Concrete 'Iterator' and 'SubSequence' type witnesses that name the conforming
// type: 'IndexingIterator<Self>' needs 'Self: Collection'. This is
// 'RecursiveCollection' from isolated_conformance_inference.swift, run in more
// modes.
@MainActor
struct ConcreteIteratorCollection: RandomAccessCollection {
  nonisolated var startIndex: Int { 0 }
  nonisolated var endIndex: Int { 0 }
  nonisolated subscript(position: Int) -> Int { 0 }

  typealias Iterator = IndexingIterator<ConcreteIteratorCollection>
  typealias SubSequence = Slice<ConcreteIteratorCollection>
}

// The same, with every collection conformance implied by a 'Sendable'
// refinement.
protocol SendableRandomAccessCollection: RandomAccessCollection, Sendable {}

@MainActor
struct SendableConcreteIteratorCollection: SendableRandomAccessCollection {
  nonisolated var startIndex: Int { 0 }
  nonisolated var endIndex: Int { 0 }
  nonisolated subscript(position: Int) -> Int { 0 }

  typealias Iterator = IndexingIterator<SendableConcreteIteratorCollection>
  typealias SubSequence = Slice<SendableConcreteIteratorCollection>
}

// Home (DynamicColor): a 'View' that gets its 'body' from a constrained
// extension requiring 'Self: View', so matching that witness needs the 'View'
// conformance being decided. Inference that doesn't return early for a
// conformance to an isolated protocol like 'View' reported 'circular reference'
// here (ConformanceIsolationRequest -> ValueWitnessRequest(body) ->
// ConformanceIsolationRequest).
@preconcurrency @MainActor
protocol View {
  associatedtype Body: View
  nonisolated var body: Body { get }
}

extension Never: View {
  nonisolated var body: Never { fatalError() }
}

protocol Shape: Sendable {}

struct Rectangle: Shape {}

protocol ShapeStyle: Sendable {
  associatedtype Resolved: ShapeStyle = Never
  func resolve(in environment: Int) -> Resolved
}

extension Never: ShapeStyle {
  func resolve(in environment: Int) -> Never { fatalError() }
}

struct _ShapeView<Content: Shape, Style: ShapeStyle>: View {
  nonisolated var body: Never { fatalError() }
}

extension ShapeStyle where Self: View, Body == _ShapeView<Rectangle, Self> {
  var body: _ShapeView<Rectangle, Self> { _ShapeView() }
}

// The type is '@MainActor' by inference from 'View', so 'resolve(in:)' is too.
// That error is expected, and Swift 5 doesn't report it because the isolation
// is inferred.
struct DynamicColor<S>: ShapeStyle, View where S: ShapeStyle {
  // expected-swift6-error@-1 {{conformance of 'DynamicColor<S>' to protocol 'ShapeStyle' crosses into main actor-isolated code and can cause data races}}
  // expected-swift6-note@-2 {{isolate this conformance to the main actor with '@MainActor'}}
  // expected-swift6-note@-3 {{turn data races into runtime errors with '@preconcurrency'}}
  let light: S
  let dark: S

  func resolve(in environment: Int) -> some ShapeStyle {
    // expected-swift6-note@-1 {{main actor-isolated instance method 'resolve(in:)' cannot satisfy nonisolated requirement}}
    // expected-swift6-note@-2 {{mark instance method 'resolve(in:)' 'nonisolated'}}
    environment == 0 ? light.resolve(in: environment) : dark.resolve(in: environment)
  }
}
