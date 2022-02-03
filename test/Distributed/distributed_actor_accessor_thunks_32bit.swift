// RUN: %empty-directory(%t)
// RUN: %target-swift-frontend-emit-module -emit-module-path %t/FakeDistributedActorSystems.swiftmodule -module-name FakeDistributedActorSystems -disable-availability-checking %S/Inputs/FakeDistributedActorSystems.swift
// RUN: %target-swift-frontend -module-name distributed_actor_accessors -emit-irgen -enable-experimental-distributed -disable-availability-checking -I %t 2>&1 %s | %IRGenFileCheck %s

// UNSUPPORTED: back_deploy_concurrency
// REQUIRES: concurrency
// REQUIRES: distributed

// REQUIRES: CPU=i386

// UNSUPPORTED: OS=windows-msvc

import _Distributed
import FakeDistributedActorSystems

@available(SwiftStdlib 5.5, *)
typealias DefaultDistributedActorSystem = FakeActorSystem

enum SimpleE : Codable {
case a
}

enum E : Codable {
case a, b, c
}

enum IndirectE : Codable {
  case empty
  indirect case test(_: Int)
}

final class Obj : Codable, Sendable {
  let x: Int

  init(x: Int) {
    self.x = x
  }
}

struct LargeStruct : Codable {
  var a: Int
  var b: Int
  var c: String
  var d: Double
}

@available(SwiftStdlib 5.7, *)
public distributed actor MyActor {
  distributed func simple1(_: Int) {
  }

  // `String` would be a direct result as a struct type
  distributed func simple2(_: Int) -> String {
    return ""
  }

  // `String` is an object that gets exploded into two parameters
  distributed func simple3(_: String) -> Int {
    return 42
  }

  // Enum with a single case are special because they have an empty
  // native schema so they are dropped from parameters/result.
  distributed func single_case_enum(_ e: SimpleE) -> SimpleE {
    return e
  }

  distributed func with_indirect_enums(_: IndirectE, _: Int) -> IndirectE {
    return .empty
  }

  // Combination of multiple arguments, reference type and indirect result
  //
  // Note: Tuple types cannot be used here is either position because they
  // cannot conform to protocols.
  distributed func complex(_: [Int], _: Obj, _: String?, _: LargeStruct) -> LargeStruct {
    fatalError()
  }

  // Combination of direct and indirect arguments involving generic arguments.
  distributed func genericArgs<T: Codable, U: Codable>(_: T, _: [U]) {
  }
}

@available(SwiftStdlib 5.7, *)
public distributed actor MyOtherActor {
  distributed func empty() {
  }
}

/// ---> Thunk and distributed method accessor for `simple1`

/// Let's make sure that accessor loads the data from the buffer and calls expected accessor

// CHECK: define hidden swifttailcc void @"$s27distributed_actor_accessors7MyActorC7simple1yySiFTE"

// CHECK: define internal swifttailcc void @"$s27distributed_actor_accessors7MyActorC7simple1yySiFTETF"(%swift.context* swiftasync %0, %T27FakeDistributedActorSystems0A17InvocationDecoderC* %1, i8* %2, i8* %3, {{.*}}, %T27distributed_actor_accessors7MyActorC* [[ACTOR:%.*]])

/// Read the current offset and cast an element to `Int`

// CHECK:  [[ARG_TYPES:%.*]] = bitcast i8* %2 to %swift.type**
// CHECK-NEXT: [[DECODER:%.*]] = bitcast %T27FakeDistributedActorSystems0A17InvocationDecoderC* %1 to %swift.type**
// CHECK-NEXT: [[DECODER_METADATA:%.*]] = load %swift.type*, %swift.type** [[DECODER]]
// CHECK: [[ARG_0_TYPE_LOC:%.*]] = getelementptr inbounds %swift.type*, %swift.type** [[ARG_TYPES]], i32 0
// CHECK-NEXT: %arg_type = load %swift.type*, %swift.type** [[ARG_0_TYPE_LOC]]
// CHECK: %size = load i32, i32* {{.*}}
// CHECK: [[ARG_0_SIZE_ADJ:%.*]] = add i32 %size, 15
// CHECK-NEXT: [[ARG_0_SIZE:%.*]] = and i32 [[ARG_0_SIZE_ADJ]], -16
// CHECK-NEXT: [[ARG_0_VALUE_BUF:%.*]] = call swiftcc i8* @swift_task_alloc(i32 [[ARG_0_SIZE]])
// CHECK-NEXT: [[ARG_0_RES_SLOT:%.*]] = bitcast i8* [[ARG_0_VALUE_BUF]] to %swift.opaque*
// CHECK-NEXT: [[ENCODABLE_WITNESS:%.*]] = call i8** @swift_conformsToProtocol(%swift.type* %arg_type, %swift.protocol* @"$sSeMp")
// CHECK-NEXT: [[IS_NULL:%.*]] = icmp eq i8** [[ENCODABLE_WITNESS]], null
// CHECK-NEXT: br i1 [[IS_NULL]], label %missing-witness, label [[CONT:%.*]]
// CHECK: missing-witness:
// CHECK-NEXT: call void @llvm.trap()
// CHECK-NEXT: unreachable
// CHECK: [[DECODABLE_WITNESS:%.*]] = call i8** @swift_conformsToProtocol(%swift.type* %arg_type, %swift.protocol* @"$sSEMp")
// CHECK-NEXT: [[IS_NULL:%.*]] = icmp eq i8** [[DECODABLE_WITNESS]], null
// CHECK-NEXT: br i1 [[IS_NULL]], label %missing-witness1, label [[CONT:%.*]]
// CHECK: missing-witness1:
// CHECK-NEXT: call void @llvm.trap()
// CHECK-NEXT: unreachable
// CHECK: call swiftcc void {{.*}}(%swift.opaque* noalias nocapture sret(%swift.opaque) [[ARG_0_RES_SLOT]], %swift.type* %arg_type, i8** [[ENCODABLE_WITNESS]], i8** [[DECODABLE_WITNESS]], %T27FakeDistributedActorSystems0A17InvocationDecoderC* swiftself %1, %swift.error** noalias nocapture dereferenceable(4) %swifterror)

// CHECK: store %swift.error* null, %swift.error** %swifterror
// CHECK-NEXT: [[ARG_0_VAL_ADDR:%.*]] = bitcast i8* [[ARG_0_VALUE_BUF]] to %TSi*
// CHECK-NEXT: %._value = getelementptr inbounds %TSi, %TSi* [[ARG_0_VAL_ADDR]], i32 0, i32 0
// CHECK-NEXT: [[ARG_VAL:%.*]] = load i32, i32* %._value

/// Setup task context for async call to `simple1` thunk

// CHECK: [[CONTEXT_SIZE:%.*]] = load i32, i32* getelementptr inbounds (%swift.async_func_pointer, %swift.async_func_pointer* @"$s27distributed_actor_accessors7MyActorC7simple1yySiFTETu", i32 0, i32 1)
// CHECK-NEXT: [[THUNK_ASYNC_CONTEXT:%.*]] = call swiftcc i8* @swift_task_alloc(i32 [[CONTEXT_SIZE]])
// CHECK: [[THUNK_CONTEXT_PTR:%.*]] = bitcast i8* [[THUNK_ASYNC_CONTEXT]] to %swift.context*

/// Call distributed thunk for `simple1` and `end` async context without results

// CHECK: [[THUNK_RESULT:%.*]] = call { i8*, %swift.error* } (i32, i8*, i8*, ...) @llvm.coro.suspend.async.sl_p0i8p0s_swift.errorss(
// CHECK-SAME: i8* bitcast (void (%swift.context*, i32, %T27distributed_actor_accessors7MyActorC*)* @"$s27distributed_actor_accessors7MyActorC7simple1yySiFTE" to i8*)
// CHECK-SAME: %swift.context* [[THUNK_CONTEXT_PTR]],
// CHECK-SAME: i32 [[ARG_VAL]],
// CHECK-SAME: %T27distributed_actor_accessors7MyActorC* [[ACTOR]])

// CHECK-NEXT: [[TASK_REF:%.*]] = extractvalue { i8*, %swift.error* } [[THUNK_RESULT]], 0
// CHECK-NEXT: {{.*}} = call i8* @__swift_async_resume_project_context(i8* [[TASK_REF]])
// CHECK: {{.*}} = call i1 (i8*, i1, ...) @llvm.coro.end.async({{.*}}, %swift.context* {{.*}}, %swift.error* {{.*}})

/// ---> Thunk and distributed method accessor for `simple2`

// CHECK: define hidden swifttailcc void @"$s27distributed_actor_accessors7MyActorC7simple2ySSSiFTE"

// CHECK: define internal swifttailcc void @"$s27distributed_actor_accessors7MyActorC7simple2ySSSiFTETF"

// CHECK: [[COERCED_RESULT_SLOT:%.*]] = bitcast i8* {{.*}} to %TSS*

/// !!! - We are not going to double-check argument extraction here since it's the same as `simple1`.
// CHECK: [[NATIVE_ARG_VAL:%.*]] = load i32, i32* %._value

/// Setup task context for async call to `simple2` thunk

// CHECK: [[CONTEXT_SIZE:%.*]] = load i32, i32* getelementptr inbounds (%swift.async_func_pointer, %swift.async_func_pointer* @"$s27distributed_actor_accessors7MyActorC7simple2ySSSiFTETu", i32 0, i32 1)
// CHECK-NEXT: [[THUNK_ASYNC_CONTEXT:%.*]] = call swiftcc i8* @swift_task_alloc(i32 [[CONTEXT_SIZE]])
// CHECK: [[THUNK_CONTEXT_PTR:%.*]] = bitcast i8* [[THUNK_ASYNC_CONTEXT]] to %swift.context*

/// Call the thunk with extracted argument value

// CHECK: [[THUNK_RESULT:%.*]] = call { i8*, i32, i32, i32, %swift.error* } (i32, i8*, i8*, ...) @llvm.coro.suspend.async.sl_p0i8i32i32i32p0s_swift.errorss(
// CHECK-SAME: i8* bitcast (void (%swift.context*, i32, %T27distributed_actor_accessors7MyActorC*)* @"$s27distributed_actor_accessors7MyActorC7simple2ySSSiFTE" to i8*)
// CHECK-SAME: %swift.context* [[THUNK_CONTEXT_PTR]],
// CHECK-SAME: i32 [[NATIVE_ARG_VAL]],
// CHECK-SAME: %T27distributed_actor_accessors7MyActorC* [[ACTOR]])

// CHECK-NEXT: [[TASK_REF:%.*]] = extractvalue { i8*, i32, i32, i32, %swift.error* } [[THUNK_RESULT]], 0
// CHECK-NEXT: {{.*}} = call i8* @__swift_async_resume_project_context(i8* [[TASK_REF]])

/// Initialize the result buffer with values produced by the thunk

// CHECK: %._guts2 = getelementptr inbounds %TSS, %TSS* [[COERCED_RESULT_SLOT]], i32 0, i32 0
// CHECK: store i32 {{.*}}, i32* %._guts2._object._count._value
// CHECK: store i8 {{.*}}, i8* %._guts2._object._discriminator._value
// CHECK: store i16 {{.*}}, i16* %._guts2._object._flags._value, align 2

// CHECK: {{.*}} = call i1 (i8*, i1, ...) @llvm.coro.end.async({{.*}}, %swift.context* {{.*}}, %swift.error* {{.*}})

/// ---> Thunk and distributed method accessor for `simple3`

// CHECK: define hidden swifttailcc void @"$s27distributed_actor_accessors7MyActorC7simple3ySiSSFTE"

/// !!! in `simple3` interesting bits are: argument value extraction (because string is exploded into N arguments) and call to distributed thunk
// CHECK: define internal swifttailcc void @"$s27distributed_actor_accessors7MyActorC7simple3ySiSSFTETF"(%swift.context* swiftasync {{.*}}, %T27FakeDistributedActorSystems0A17InvocationDecoderC* [[ARG_DECODER:%.*]], i8* [[ARG_TYPES:%.*]], i8* [[RESULT_BUFF:%.*]], i8* [[SUBS:%.*]], i8* [[WITNESS_TABLES:%.*]], i32 [[NUM_WITNESS_TABLES:%.*]], %T27distributed_actor_accessors7MyActorC* [[ACTOR:%.*]])

// CHECK: [[TYPED_RESULT_BUFF:%.*]] = bitcast i8* [[RESULT_BUFF]] to %TSi*

// CHECK: [[ARG_SIZE:%.*]] = and i32 {{.*}}, -16
// CHECK: [[ARG_BUF:%.*]] = call swiftcc i8* @swift_task_alloc(i32 [[ARG_SIZE]])
// CHECK: [[ARG_0_VALUE:%.*]] = bitcast i8* [[ARG_BUF]] to %TSS*
// CHECK-NEXT: %._guts = getelementptr inbounds %TSS, %TSS* [[ARG_0_VALUE]], i32 0, i32 0

// CHECK: [[STR_SIZE:%.*]] = load i32, i32* %._guts._object._count._value
// CHECK-NEXT:  %._guts._object._variant = getelementptr inbounds %Ts13_StringObjectV, %Ts13_StringObjectV* %._guts._object, i32 0, i32 1
// CHECK-NEXT: [[NATIVE_STR_VAL_PTR:%.*]] = bitcast %Ts13_StringObjectV7VariantO* %._guts._object._variant to i32*
// CHECK-NEXT: [[STR_VAL:%.*]] = load i32, i32* [[NATIVE_STR_VAL_PTR]]

/// Setup task context for async call to `simple3` thunk

// CHECK: [[CONTEXT_SIZE:%.*]] = load i32, i32* getelementptr inbounds (%swift.async_func_pointer, %swift.async_func_pointer* @"$s27distributed_actor_accessors7MyActorC7simple3ySiSSFTETu", i32 0, i32 1)
// CHECK-NEXT: [[THUNK_ASYNC_CONTEXT:%.*]] = call swiftcc i8* @swift_task_alloc(i32 [[CONTEXT_SIZE]])

// CHECK: [[TMP_STR_ARG:%.*]] = bitcast { i32, i32, i32 }* %temp-coercion.coerced to %TSS*
// CHECK-NEXT: %._guts2 = getelementptr inbounds %TSS, %TSS* [[TMP_STR_ARG]], i32 0, i32 0

// CHECK: store i32 {{.*}}, i32* %._guts2._object._count._value
// CHECK: [[VARIANT:%.*]] = bitcast %Ts13_StringObjectV7VariantO* %._guts2._object._variant to i32*
// CHECK-NEXT: store i32 {{.*}}, i32* [[VARIANT]]

// CHECK: [[STR_ARG_SIZE_PTR:%.*]] = getelementptr inbounds { i32, i32, i32 }, { i32, i32, i32 }* %temp-coercion.coerced, i32 0, i32 0
// CHECK: [[STR_ARG_SIZE:%.*]] = load i32, i32* [[STR_ARG_SIZE_PTR]]

// CHECK: [[STR_ARG_VAL_PTR:%.*]] = getelementptr inbounds { i32, i32, i32 }, { i32, i32, i32 }* %temp-coercion.coerced, i32 0, i32 1
// CHECK: [[STR_ARG_VAL:%.*]] = load i32, i32* [[STR_ARG_VAL_PTR]]

// CHECK: [[STR_ARG_FLAGS_PTR:%.*]] = getelementptr inbounds { i32, i32, i32 }, { i32, i32, i32 }* %temp-coercion.coerced, i32 0, i32 2
// CHECK: [[STR_ARG_FLAGS:%.*]] = load i32, i32* [[STR_ARG_FLAGS_PTR]]

/// Call distributed thunk with exploaded string value

// CHECK: [[THUNK_CONTEXT_PTR:%.*]] = bitcast i8* [[THUNK_ASYNC_CONTEXT]] to %swift.context*

// CHECK: [[THUNK_RESULT:%.*]] = call { i8*, i32, %swift.error* } (i32, i8*, i8*, ...) @llvm.coro.suspend.async.sl_p0i8i32p0s_swift.errorss(
// CHECK-SAME: i8* bitcast (void (%swift.context*, i32, i32, i32, %T27distributed_actor_accessors7MyActorC*)* @"$s27distributed_actor_accessors7MyActorC7simple3ySiSSFTE" to i8*),
// CHECK-SAME: %swift.context* [[THUNK_CONTEXT_PTR]],
// CHECK-SAME: i32 [[STR_ARG_SIZE]],
// CHECK-SAME: i32 [[STR_ARG_VAL]],
// CHECK_SAME: i32 [[STR_ARG_FLAGS]],
// CHECK-SAME: %T27distributed_actor_accessors7MyActorC* [[ACTOR]])

// CHECK-NEXT: [[TASK_REF:%.*]] = extractvalue { i8*, i32, %swift.error* } [[THUNK_RESULT]], 0
// CHECK-NEXT: {{.*}} = call i8* @__swift_async_resume_project_context(i8* [[TASK_REF]])
// CHECK: [[INT_RES:%.*]] = extractvalue { i8*, i32, %swift.error* } [[THUNK_RESULT]], 1
// CHECK: %._value = getelementptr inbounds %TSi, %TSi* [[TYPED_RESULT_BUFF]], i32 0, i32 0
// CHECK: store i32 [[INT_RES]], i32* %._value
// CHECK: {{.*}} = call i1 (i8*, i1, ...) @llvm.coro.end.async({{.*}}, %swift.context* {{.*}}, %swift.error* {{.*}})

/// --> Thunk and distributed method accessor for `single_case_enum`

// CHECK: define hidden swifttailcc void @"$s27distributed_actor_accessors7MyActorC16single_case_enumyAA7SimpleEOAFFTE"

// CHECK: define internal swifttailcc void @"$s27distributed_actor_accessors7MyActorC16single_case_enumyAA7SimpleEOAFFTETF"(%swift.context* swiftasync %0, %T27FakeDistributedActorSystems0A17InvocationDecoderC* [[ARG_DECODER:%.*]], i8* [[ARG_TYPES:%.*]], i8* [[RESULT_BUFF:%.*]], i8* [[SUBS:%.*]], i8* [[WITNESS_TABLES:%.*]], i32 [[NUM_WITNESS_TABLES:%.*]], %T27distributed_actor_accessors7MyActorC* [[ACTOR:%.*]])

/// Let's check that the call doesn't have any arguments and returns nothing.

// SKIP: [[THUNK_REF:%.*]] = bitcast void (%swift.context*, %T27distributed_actor_accessors7MyActorC*)* {{.*}} to i8*
// SKIP: {{.*}} = call { i8*, %swift.error* } (i32, i8*, i8*, ...) @llvm.coro.suspend.async.sl_p0i8p0s_swift.errorss({{.*}}, i8* [[THUNK_REF]], %swift.context* {{.*}}, %T27distributed_actor_accessors7MyActorC* {{.*}})
// SKIP: {{.*}} = call i1 (i8*, i1, ...) @llvm.coro.end.async({{.*}}, i8* {{.*}}, %swift.context* {{.*}}, %swift.error* {{.*}})

/// --> Thunk and distributed method accessor for `with_indirect_enums`

// CHECK: define hidden swifttailcc void @"$s27distributed_actor_accessors7MyActorC19with_indirect_enumsyAA9IndirectEOAF_SitFTE"
// CHECK: define internal swifttailcc void @"$s27distributed_actor_accessors7MyActorC19with_indirect_enumsyAA9IndirectEOAF_SitFTETF"

/// First, Load both arguments from the buffer.

// CHECK: [[TYPED_RESULT_BUFF:%.*]] = bitcast i8* [[RESULT_BUFF]] to %T27distributed_actor_accessors9IndirectEO*

// CHECK: [[ARG_0_SIZE:%.*]] = and i32 {{.*}}, -16
// CHECK-NEXT: [[ARG_0_BUF:%.*]] = call swiftcc i8* @swift_task_alloc(i32 [[ARG_0_SIZE]])

// CHECK: [[ARG_0_VAL_ADDR:%.*]] = bitcast i8* [[ARG_0_BUF]] to %T27distributed_actor_accessors9IndirectEO*
// CHECK-NEXT: [[NATIVE_ENUM_VAL_ADDR:%.*]] = bitcast %T27distributed_actor_accessors9IndirectEO* [[ARG_0_VAL_ADDR]] to i32*
// CHECK-NEXT: [[NATIVE_ENUM_VAL:%.*]] = load i32, i32* [[NATIVE_ENUM_VAL_ADDR]]

// CHECK: [[ARG_1_SIZE:%.*]] = and i32 {{.*}}, -16
// CHECK-NEXT: [[ARG_1_BUF:%.*]] = call swiftcc i8* @swift_task_alloc(i32 [[ARG_1_SIZE]])

// CHECK: [[ARG_1_VAL_ADDR:%.*]] = bitcast i8* [[ARG_1_BUF]] to %TSi*
// CHECK-NEXT: %._value = getelementptr inbounds %TSi, %TSi* [[ARG_1_VAL_ADDR]], i32 0, i32 0
// CHECK-NEXT: [[NATIVE_INT_VAL:%.*]] = load i32, i32* %._value

/// Call distributed thunk with extracted arguments.

// CHECK: [[THUNK_RESULT:%.*]] = call { i8*, i32, %swift.error* } (i32, i8*, i8*, ...) @llvm.coro.suspend.async.sl_p0i8i32p0s_swift.errorss({{.*}}, %swift.context* {{.*}}, i32 [[NATIVE_ENUM_VAL]], i32 [[NATIVE_INT_VAL]], %T27distributed_actor_accessors7MyActorC* {{.*}})
// CHECK-NEXT: [[TASK_REF:%.*]] = extractvalue { i8*, i32, %swift.error* } [[THUNK_RESULT]], 0
// CHECK-NEXT: {{.*}} = call i8* @__swift_async_resume_project_context(i8* [[TASK_REF]])
// CHECK: [[ENUM_RESULT:%.*]] = extractvalue { i8*, i32, %swift.error* } [[THUNK_RESULT]], 1
// CHECK: [[NATIVE_RESULT_PTR:%.*]] = bitcast %T27distributed_actor_accessors9IndirectEO* [[TYPED_RESULT_BUFF]] to i32*
// CHECK-NEXT: store i32 [[ENUM_RESULT]], i32* [[NATIVE_RESULT_PTR]]

// CHECK: {{.*}} = call i1 (i8*, i1, ...) @llvm.coro.end.async({{.*}}, %swift.context* {{.*}}, %swift.error* {{.*}})

/// ---> Thunk and distributed method for `complex`

// CHECK: define hidden swifttailcc void @"$s27distributed_actor_accessors7MyActorC7complexyAA11LargeStructVSaySiG_AA3ObjCSSSgAFtFTE"

// CHECK: define internal swifttailcc void @"$s27distributed_actor_accessors7MyActorC7complexyAA11LargeStructVSaySiG_AA3ObjCSSSgAFtFTETF"(%swift.context* swiftasync {{.*}}, %T27FakeDistributedActorSystems0A17InvocationDecoderC* [[ARG_DECODER:%.*]], i8* [[ARG_TYPES:%.*]], i8* [[RESULT_BUFF:%.*]], i8* [[SUBS:%.*]], i8* [[WITNESS_TABLES:%.*]], i32 [[NUM_WITNESS_TABLES:%.*]], %T27distributed_actor_accessors7MyActorC* [[ACTOR:%.*]])

/// First, let's check that all of the different argument types here are loaded correctly.

/// Cast result buffer to the expected result type (in this case its indirect opaque pointer)
// CHECK: [[TYPED_RESULT_BUFF:%.*]] = bitcast i8* [[RESULT_BUFF]] to %swift.opaque*

/// -> [Int]

// CHECK: [[ARG_0_SIZE:%.*]] = and i32 {{.*}}, -16
// CHECK-NEXT: [[ARG_0_BUF:%.*]] = call swiftcc i8* @swift_task_alloc(i32 [[ARG_0_SIZE]])

// CHECK: [[ARG_0_VAL_ADDR:%.*]] = bitcast i8* [[ARG_0_BUF]] to %TSa*
// CHECK-NEXT: %._buffer = getelementptr inbounds %TSa, %TSa* [[ARG_0_VAL_ADDR]], i32 0, i32 0
// CHECK: [[NATIVE_ARR_VAL:%.*]] = load [[ARR_STORAGE_TYPE:%.*]], [[ARR_STORAGE_TYPE]]* %._buffer._storage

/// -> Obj

// CHECK: [[ARG_1_SIZE:%.*]] = and i32 {{.*}}, -16
// CHECK-NEXT: [[ARG_1_BUF:%.*]] = call swiftcc i8* @swift_task_alloc(i32 [[ARG_1_SIZE]])

// CHECK: [[OBJ_PTR:%.*]] = bitcast i8* [[ARG_1_BUF]] to %T27distributed_actor_accessors3ObjC**
// CHECK-NEXT: [[NATIVE_OBJ_VAL:%.*]] = load %T27distributed_actor_accessors3ObjC*, %T27distributed_actor_accessors3ObjC** [[OBJ_PTR]]

/// -> String?

// CHECK: [[ARG_2_SIZE:%.*]] = and i32 {{.*}}, -16
// CHECK-NEXT: [[ARG_2_BUF:%.*]] = call swiftcc i8* @swift_task_alloc(i32 [[ARG_2_SIZE]])

// CHECK: [[OPT_PTR:%.*]] = bitcast i8* [[ARG_2_BUF]] to %TSSSg*
// CHECK-NEXT: [[NATIVE_OPT_PTR:%.*]] = bitcast %TSSSg* [[OPT_PTR]] to { i32, i32, i32 }*
// CHECK-NEXT: [[NATIVE_OPT_VAL_0_PTR:%.*]] = getelementptr inbounds { i32, i32, i32 }, { i32, i32, i32 }* [[NATIVE_OPT_PTR]], i32 0, i32 0
// CHECK-NEXT: [[NATIVE_OPT_VAL_0:%.*]] = load i32, i32* [[NATIVE_OPT_VAL_0_PTR]]
// CHECK-NEXT: [[NATIVE_OPT_VAL_1_PTR:%.*]] = getelementptr inbounds { i32, i32, i32 }, { i32, i32, i32 }* [[NATIVE_OPT_PTR]], i32 0, i32 1
// CHECK-NEXT: [[NATIVE_OPT_VAL_1:%.*]] = load i32, i32* [[NATIVE_OPT_VAL_1_PTR]]
// CHECK-NEXT: [[NATIVE_OPT_VAL_2_PTR:%.*]] = getelementptr inbounds { i32, i32, i32 }, { i32, i32, i32 }* [[NATIVE_OPT_PTR]], i32 0, i32 2
// CHECK-NEXT: [[NATIVE_OPT_VAL_2:%.*]] = load i32, i32* [[NATIVE_OPT_VAL_2_PTR]]

/// -> LargeStruct (passed indirectly)

// CHECK: [[ARG_3_SIZE:%.*]] = and i32 {{.*}}, -16
// CHECK-NEXT: [[ARG_3_BUF:%.*]] = call swiftcc i8* @swift_task_alloc(i32 [[ARG_3_SIZE]])
// CHECK-NEXT: [[ARG_3_OPAQUE_PTR:%.*]] = bitcast i8* [[ARG_3_BUF]] to %swift.opaque*

// CHECK: [[INDIRECT_RESULT_BUFF:%.*]] = bitcast %swift.opaque* [[TYPED_RESULT_BUFF]] to %T27distributed_actor_accessors11LargeStructV*

// CHECK: [[STRUCT_PTR:%.*]] = bitcast %swift.opaque* [[ARG_3_OPAQUE_PTR]] to %T27distributed_actor_accessors11LargeStructV*

/// Now let's make sure that distributed thunk call uses the arguments correctly

// CHECK: [[THUNK_RESULT:%.*]] = call { i8*, %swift.error* } (i32, i8*, i8*, ...) @llvm.coro.suspend.async.sl_p0i8p0s_swift.errorss({{.*}}, %T27distributed_actor_accessors11LargeStructV* [[INDIRECT_RESULT_BUFF]], %swift.context* {{.*}}, {{.*}} [[NATIVE_ARR_VAL]], %T27distributed_actor_accessors3ObjC* [[NATIVE_OBJ_VAL]], i32 [[NATIVE_OPT_VAL_0]], i32 [[NATIVE_OPT_VAL_1]], i32 [[NATIVE_OPT_VAL_2]], %T27distributed_actor_accessors11LargeStructV* [[STRUCT_PTR]], %T27distributed_actor_accessors7MyActorC* {{.*}})

/// RESULT is returned indirectly so there is nothing to pass to `end`

// CHECK: {{.*}} = call i1 (i8*, i1, ...) @llvm.coro.end.async({{.*}}, %swift.context* {{.*}}, %swift.error* {{.*}})


/// ---> Accessor for `genericArgs`

// CHECK: define internal swifttailcc void @"$s27distributed_actor_accessors7MyActorC11genericArgsyyx_Sayq_GtSeRzSERzSeR_SER_r0_lFTETF"(%swift.context* swiftasync %0, %T27FakeDistributedActorSystems0A17InvocationDecoderC* [[ARG_DECODER:%.*]], i8* [[ARG_TYPES:%.*]], i8* [[RESULT_BUF:%.*]], i8* [[GENERIC_SUBS:%.*]], i8* [[WITNESS_TABLES:%.*]], i32 [[NUM_WITNESS_TABLES:%.*]], %T27distributed_actor_accessors7MyActorC* [[ACTOR:%.*]])

/// ---> Load `T`

// CHECK: [[ARG_0_SIZE:%.*]] = and i32 {{.*}}, -16
// CHECK-NEXT: [[ARG_0_BUF:%.*]] = call swiftcc i8* @swift_task_alloc(i32 [[ARG_0_SIZE]])
// CHECK: [[TYPED_ARG_0:%.*]] = bitcast i8* [[ARG_0_BUF]] to %swift.opaque*

/// ---> Load `[U]`

// CHECK: [[ARG_1_SIZE:%.*]] = and i32 {{.*}}, -16
// CHECK-NEXT: [[ARG_1_BUF:%.*]] = call swiftcc i8* @swift_task_alloc(i32 [[ARG_1_SIZE]])

// CHECK: [[ARR_ARG_1:%.*]] = bitcast i8* [[ARG_1_BUF]] to %TSa*
// CHECK-NEXT: %._buffer = getelementptr inbounds %TSa, %TSa* [[ARR_ARG_1]], i32 0, i32 0
// CHECK-NEXT: %._buffer._storage = getelementptr inbounds %Ts12_ArrayBufferV, %Ts12_ArrayBufferV* %._buffer, i32 0, i32 0
// CHECK-NEXT: %._buffer._storage.rawValue = getelementptr inbounds %Ts14_BridgeStorageV, %Ts14_BridgeStorageV* %._buffer._storage, i32 0, i32 0
// CHECK-NEXT: [[TYPED_ARG_1:%.*]] = load %swift.bridge*, %swift.bridge** %._buffer._storage.rawValue

/// ---> Load generic argument substitutions from the caller-provided buffer

// CHECK: [[GENERIC_SUBS_BUF:%.*]] = bitcast i8* [[GENERIC_SUBS]] to %swift.type**
// CHECK-NEXT: [[SUB_T_ADDR:%.*]] = getelementptr inbounds %swift.type*, %swift.type** [[GENERIC_SUBS_BUF]], i32 0
// CHECK-NEXT: [[SUB_T:%.*]] = load %swift.type*, %swift.type** [[SUB_T_ADDR]]
// CHECK-NEXT: [[SUB_U_ADDR:%.*]] = getelementptr inbounds %swift.type*, %swift.type** [[GENERIC_SUBS_BUF]], i32 1
// CHECK-NEXT: [[SUB_U:%.*]] = load %swift.type*, %swift.type** [[SUB_U_ADDR]]

/// --> Load witness tables from caller-provided buffer

/// First, check whether the number of witness tables matches expected

// CHECK: [[IS_INCORRECT_WITNESSES:%.*]] = icmp ne i32 [[NUM_WITNESS_TABLES]], 4
// CHECK-NEXT: br i1 [[IS_INCORRECT_WITNESSES]], label %incorrect-witness-tables, label [[LOAD_WITNESS_TABLES:%.*]]
// CHECK: incorrect-witness-tables:
// CHECK-NEXT: unreachable

// CHECK: [[WITNESS_BUF:%.*]] = bitcast i8* [[WITNESS_TABLES]] to i8**
// CHECK-NEXT: [[T_ENCODABLE:%.*]] = getelementptr inbounds i8*, i8** [[WITNESS_BUF]], i32 0
// CHECK-NEXT: [[T_DECODABLE:%.*]] = getelementptr inbounds i8*, i8** [[WITNESS_BUF]], i32 1
// CHECK-NEXT: [[U_ENCODABLE:%.*]] = getelementptr inbounds i8*, i8** [[WITNESS_BUF]], i32 2
// CHECK-NEXT: [[U_DECODABLE:%.*]] = getelementptr inbounds i8*, i8** [[WITNESS_BUF]], i32 3

/// ---> Check that distributed thunk code is formed correctly

// CHECK: [[THUNK_RESULT:%.*]] = call { i8*, %swift.error* } (i32, i8*, i8*, ...) @llvm.coro.suspend.async.sl_p0i8p0s_swift.errorss({{.*}}, %swift.context* {{.*}}, %swift.opaque* [[TYPED_ARG_0]], %swift.bridge* [[TYPED_ARG_1]], %swift.type* [[SUB_T]], %swift.type* [[SUB_U]], i8** [[T_ENCODABLE]], i8** [[T_DECODABLE]], i8** [[U_ENCODABLE]], i8** [[U_DECODABLE]], %T27distributed_actor_accessors7MyActorC* [[ACTOR]])


/// ---> Thunk and distributed method for `MyOtherActor.empty`

/// Let's check that there is no offset allocation here since parameter list is empty

// CHECK: define internal swifttailcc void @"$s27distributed_actor_accessors12MyOtherActorC5emptyyyFTETF"(%swift.context* swiftasync {{.*}}, %T27FakeDistributedActorSystems0A17InvocationDecoderC* [[ARG_DECODER:%.*]], i8* [[ARG_TYPES:%.*]], i8* [[RESULT_BUFF:%.*]], i8* [[SUBS:%.*]], i8* [[WITNESS_TABLES:%.*]], i32 [[NUM_WITNESS_TABLES:%.*]], %T27distributed_actor_accessors12MyOtherActorC* {{.*}})
// CHECK-NEXT: entry:
// CHECK-NEXT: {{.*}} = alloca %swift.context*
// CHECK-NEXT: %swifterror = alloca %swift.error*
// CHECK-NEXT: {{.*}} = call token @llvm.coro.id.async(i32 12, i32 16, i32 0, i8* bitcast (%swift.async_func_pointer* @"$s27distributed_actor_accessors12MyOtherActorC5emptyyyFTETFTu" to i8*))
// CHECK-NEXT: {{.*}} = call i8* @llvm.coro.begin(token {{%.*}}, i8* null)
// CHECK-NEXT: store %swift.context* {{.*}}, %swift.context** {{.*}}
// CHECK-NEXT: store %swift.error* null, %swift.error** %swifterror
// CHECK-NEXT: {{.*}} = bitcast i8* [[RESULT_BUFF]] to %swift.opaque*
// CHECK-NEXT: {{.*}} = load i32, i32* getelementptr inbounds (%swift.async_func_pointer, %swift.async_func_pointer* @"$s27distributed_actor_accessors12MyOtherActorC5emptyyyFTETu", i32 0, i32 1)
