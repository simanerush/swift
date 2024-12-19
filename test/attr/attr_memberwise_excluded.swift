// RUN: %target-typecheck-verify-swift

struct X {
  @_memberwiseInitIgnored
  var foo = 0
}

func foo() {
  let _ = X(foo: 1) // expected-error {{argument passed to call that takes no arguments}}
}

struct Y {
  @_memberwiseInitIgnored
  var foo = 0
  var bar: String
  @_memberwiseInitIgnored
  private var other: Bool = true
}

func bar() {
  let _ = X(foo: 1) // expected-error {{argument passed to call that takes no arguments}}
  let _ = Y(foo: 1, bar: "b") // expected-error {{extra argument 'foo' in call}}
}
