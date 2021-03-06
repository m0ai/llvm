; RUN: llc -verify-machineinstrs < %s -mtriple=x86_64-apple-darwin | FileCheck --check-prefix=CHECK-APPLE %s
; RUN: llc -verify-machineinstrs -O0 < %s -mtriple=x86_64-apple-darwin | FileCheck --check-prefix=CHECK-O0 %s
; RUN: llc -verify-machineinstrs < %s -mtriple=i386-apple-darwin | FileCheck --check-prefix=CHECK-i386 %s

declare i8* @malloc(i64)
declare void @free(i8*)
%swift_error = type {i64, i8}

; This tests the basic usage of a swifterror parameter. "foo" is the function
; that takes a swifterror parameter and "caller" is the caller of "foo".
define float @foo(%swift_error** swifterror %error_ptr_ref) {
; CHECK-APPLE-LABEL: foo:
; CHECK-APPLE: movl $16, %edi
; CHECK-APPLE: malloc
; CHECK-APPLE: movb $1, 8(%rax)
; CHECK-APPLE: movq %rax, %r12

; CHECK-O0-LABEL: foo:
; CHECK-O0: movl $16
; CHECK-O0: malloc
; CHECK-O0: movb $1, 8(%rax)
; CHECK-O0: movq %{{.*}}, %r12
entry:
  %call = call i8* @malloc(i64 16)
  %call.0 = bitcast i8* %call to %swift_error*
  store %swift_error* %call.0, %swift_error** %error_ptr_ref
  %tmp = getelementptr inbounds i8, i8* %call, i64 8
  store i8 1, i8* %tmp
  ret float 1.0
}

; "caller" calls "foo" that takes a swifterror parameter.
define float @caller(i8* %error_ref) {
; CHECK-APPLE-LABEL: caller:
; CHECK-APPLE: xorl %r12d, %r12d
; CHECK-APPLE: callq {{.*}}foo
; CHECK-APPLE: testq %r12, %r12
; CHECK-APPLE: jne
; Access part of the error object and save it to error_ref
; CHECK-APPLE: movb 8(%r12)
; CHECK-APPLE: movq %r12, %rdi
; CHECK-APPLE: callq {{.*}}free

; CHECK-O0-LABEL: caller:
; CHECK-O0: xorl
; CHECK-O0: movl %{{.*}}, %r12d
; CHECK-O0: callq {{.*}}foo
; CHECK-O0: jne
entry:
  %error_ptr_ref = alloca swifterror %swift_error*
  store %swift_error* null, %swift_error** %error_ptr_ref
  %call = call float @foo(%swift_error** swifterror %error_ptr_ref)
  %error_from_foo = load %swift_error*, %swift_error** %error_ptr_ref
  %had_error_from_foo = icmp ne %swift_error* %error_from_foo, null
  %tmp = bitcast %swift_error* %error_from_foo to i8*
  br i1 %had_error_from_foo, label %handler, label %cont
cont:
  %v1 = getelementptr inbounds %swift_error, %swift_error* %error_from_foo, i64 0, i32 1
  %t = load i8, i8* %v1
  store i8 %t, i8* %error_ref
  br label %handler
handler:
  call void @free(i8* %tmp)
  ret float 1.0
}

; "caller2" is the caller of "foo", it calls "foo" inside a loop.
define float @caller2(i8* %error_ref) {
; CHECK-APPLE-LABEL: caller2:
; CHECK-APPLE: xorl %r12d, %r12d
; CHECK-APPLE: callq {{.*}}foo
; CHECK-APPLE: testq %r12, %r12
; CHECK-APPLE: jne
; CHECK-APPLE: ucomiss
; CHECK-APPLE: jbe
; Access part of the error object and save it to error_ref
; CHECK-APPLE: movb 8(%r12)
; CHECK-APPLE: movq %r12, %rdi
; CHECK-APPLE: callq {{.*}}free

; CHECK-O0-LABEL: caller2:
; CHECK-O0: xorl
; CHECK-O0: movl %{{.*}}, %r12d
; CHECK-O0: callq {{.*}}foo
; CHECK-O0: movq %r12, [[ID:%[a-z]+]]
; CHECK-O0: cmpq $0, %r12
; CHECK-O0: jne
entry:
  %error_ptr_ref = alloca swifterror %swift_error*
  br label %bb_loop
bb_loop:
  store %swift_error* null, %swift_error** %error_ptr_ref
  %call = call float @foo(%swift_error** swifterror %error_ptr_ref)
  %error_from_foo = load %swift_error*, %swift_error** %error_ptr_ref
  %had_error_from_foo = icmp ne %swift_error* %error_from_foo, null
  %tmp = bitcast %swift_error* %error_from_foo to i8*
  br i1 %had_error_from_foo, label %handler, label %cont
cont:
  %cmp = fcmp ogt float %call, 1.000000e+00
  br i1 %cmp, label %bb_end, label %bb_loop
bb_end:
  %v1 = getelementptr inbounds %swift_error, %swift_error* %error_from_foo, i64 0, i32 1
  %t = load i8, i8* %v1
  store i8 %t, i8* %error_ref
  br label %handler
handler:
  call void @free(i8* %tmp)
  ret float 1.0
}

; "foo_if" is a function that takes a swifterror parameter, it sets swifterror
; under a certain condition.
define float @foo_if(%swift_error** swifterror %error_ptr_ref, i32 %cc) {
; CHECK-APPLE-LABEL: foo_if:
; CHECK-APPLE: testl %edi, %edi
; CHECK-APPLE: je
; CHECK-APPLE: movl $16, %edi
; CHECK-APPLE: malloc
; CHECK-APPLE: movb $1, 8(%rax)
; CHECK-APPLE: movq %rax, %r12
; CHECK-APPLE-NOT: %r12
; CHECK-APPLE: ret

; CHECK-O0-LABEL: foo_if:
; CHECK-O0: cmpl $0
; spill to stack
; CHECK-O0: movq %r12, {{.*}}(%rsp)
; CHECK-O0: je
; CHECK-O0: movl $16,
; CHECK-O0: malloc
; CHECK-O0: movq %rax, [[ID:%[a-z]+]]
; CHECK-O0-DAG: movb $1, 8(%rax)
; CHECK-O0-DAG: movq [[ID]], %r12
; CHECK-O0: ret
; reload from stack
; CHECK-O0: movq {{.*}}(%rsp), [[REG:%[a-z]+]]
; CHECK-O0: movq [[REG]], %r12
; CHECK-O0: ret
entry:
  %cond = icmp ne i32 %cc, 0
  br i1 %cond, label %gen_error, label %normal

gen_error:
  %call = call i8* @malloc(i64 16)
  %call.0 = bitcast i8* %call to %swift_error*
  store %swift_error* %call.0, %swift_error** %error_ptr_ref
  %tmp = getelementptr inbounds i8, i8* %call, i64 8
  store i8 1, i8* %tmp
  ret float 1.0

normal:
  ret float 0.0
}

; "foo_loop" is a function that takes a swifterror parameter, it sets swifterror
; under a certain condition inside a loop.
define float @foo_loop(%swift_error** swifterror %error_ptr_ref, i32 %cc, float %cc2) {
; CHECK-APPLE-LABEL: foo_loop:
; CHECK-APPLE: movq %r12, %rax
; CHECK-APPLE: testl
; CHECK-APPLE: je
; CHECK-APPLE: movl $16, %edi
; CHECK-APPLE: malloc
; CHECK-APPLE: movb $1, 8(%rax)
; CHECK-APPLE: ucomiss
; CHECK-APPLE: jbe
; CHECK-APPLE: movq %rax, %r12
; CHECK-APPLE: ret

; CHECK-O0-LABEL: foo_loop:
; spill to stack
; CHECK-O0: movq %r12, {{.*}}(%rsp)
; CHECK-O0: cmpl $0
; CHECK-O0: je
; CHECK-O0: movl $16,
; CHECK-O0: malloc
; CHECK-O0: movq %rax, [[ID:%[a-z0-9]+]]
; CHECK-O0: movb $1, 8([[ID]])
; CHECK-O0: jbe
; reload from stack
; CHECK-O0: movq {{.*}}(%rsp), [[REG:%[a-z0-9]+]]
; CHECK-O0: movq [[REG]], %r12
; CHECK-O0: ret
entry:
  br label %bb_loop

bb_loop:
  %cond = icmp ne i32 %cc, 0
  br i1 %cond, label %gen_error, label %bb_cont

gen_error:
  %call = call i8* @malloc(i64 16)
  %call.0 = bitcast i8* %call to %swift_error*
  store %swift_error* %call.0, %swift_error** %error_ptr_ref
  %tmp = getelementptr inbounds i8, i8* %call, i64 8
  store i8 1, i8* %tmp
  br label %bb_cont

bb_cont:
  %cmp = fcmp ogt float %cc2, 1.000000e+00
  br i1 %cmp, label %bb_end, label %bb_loop
bb_end:
  ret float 0.0
}

%struct.S = type { i32, i32, i32, i32, i32, i32 }

; "foo_sret" is a function that takes a swifterror parameter, it also has a sret
; parameter.
define void @foo_sret(%struct.S* sret %agg.result, i32 %val1, %swift_error** swifterror %error_ptr_ref) {
; CHECK-APPLE-LABEL: foo_sret:
; CHECK-APPLE: movq %rdi, %{{.*}}
; CHECK-APPLE: movl $16, %edi
; CHECK-APPLE: malloc
; CHECK-APPLE: movb $1, 8(%rax)
; CHECK-APPLE: movl %{{.*}}, 4(%{{.*}})
; CHECK-APPLE: movq %rax, %r12
; CHECK-APPLE: movq %{{.*}}, %rax
; CHECK-APPLE-NOT: x19

; CHECK-O0-LABEL: foo_sret:
; CHECK-O0: movl $16,
; spill sret to stack
; CHECK-O0: movq %rdi,
; CHECK-O0: movq {{.*}}, %rdi
; CHECK-O0: malloc
; CHECK-O0: movb $1, 8(%rax)
; CHECK-O0: movl %{{.*}}, 4(%{{.*}})
; CHECK-O0: movq %{{.*}}, %r12
; reload sret from stack
; CHECK-O0: movq {{.*}}(%rsp), %rax
; CHECK-O0: ret
entry:
  %call = call i8* @malloc(i64 16)
  %call.0 = bitcast i8* %call to %swift_error*
  store %swift_error* %call.0, %swift_error** %error_ptr_ref
  %tmp = getelementptr inbounds i8, i8* %call, i64 8
  store i8 1, i8* %tmp
  %v2 = getelementptr inbounds %struct.S, %struct.S* %agg.result, i32 0, i32 1
  store i32 %val1, i32* %v2
  ret void
}

; "caller3" calls "foo_sret" that takes a swifterror parameter.
define float @caller3(i8* %error_ref) {
; CHECK-APPLE-LABEL: caller3:
; CHECK-APPLE: movl $1, %esi
; CHECK-APPLE: xorl %r12d, %r12d
; CHECK-APPLE: callq {{.*}}foo_sret
; CHECK-APPLE: testq %r12, %r12
; CHECK-APPLE: jne
; Access part of the error object and save it to error_ref
; CHECK-APPLE: movb 8(%r12),
; CHECK-APPLE: movb %{{.*}},
; CHECK-APPLE: movq %r12, %rdi
; CHECK-APPLE: callq {{.*}}free

; CHECK-O0-LABEL: caller3:
; CHECK-O0: xorl
; CHECK-O0: movl {{.*}}, %r12d
; CHECK-O0: movl $1, %esi
; CHECK-O0: movq {{.*}}, %rdi
; CHECK-O0: callq {{.*}}foo_sret
; CHECK-O0: movq %r12,
; CHECK-O0: cmpq $0
; CHECK-O0: jne
; Access part of the error object and save it to error_ref
; CHECK-O0: movb 8(%{{.*}}),
; CHECK-O0: movb %{{.*}},
; reload from stack
; CHECK-O0: movq {{.*}}(%rsp), %rdi
; CHECK-O0: callq {{.*}}free
entry:
  %s = alloca %struct.S, align 8
  %error_ptr_ref = alloca swifterror %swift_error*
  store %swift_error* null, %swift_error** %error_ptr_ref
  call void @foo_sret(%struct.S* sret %s, i32 1, %swift_error** swifterror %error_ptr_ref)
  %error_from_foo = load %swift_error*, %swift_error** %error_ptr_ref
  %had_error_from_foo = icmp ne %swift_error* %error_from_foo, null
  %tmp = bitcast %swift_error* %error_from_foo to i8*
  br i1 %had_error_from_foo, label %handler, label %cont
cont:
  %v1 = getelementptr inbounds %swift_error, %swift_error* %error_from_foo, i64 0, i32 1
  %t = load i8, i8* %v1
  store i8 %t, i8* %error_ref
  br label %handler
handler:
  call void @free(i8* %tmp)
  ret float 1.0
}

; This is a caller with multiple swifterror values, it calls "foo" twice, each
; time with a different swifterror value, from "alloca swifterror".
define float @caller_with_multiple_swifterror_values(i8* %error_ref, i8* %error_ref2) {
; CHECK-APPLE-LABEL: caller_with_multiple_swifterror_values:

; The first swifterror value:
; CHECK-APPLE: xorl %r12d, %r12d
; CHECK-APPLE: callq {{.*}}foo
; CHECK-APPLE: testq %r12, %r12
; CHECK-APPLE: jne
; Access part of the error object and save it to error_ref
; CHECK-APPLE: movb 8(%r12)
; CHECK-APPLE: movq %r12, %rdi
; CHECK-APPLE: callq {{.*}}free

; The second swifterror value:
; CHECK-APPLE: xorl %r12d, %r12d
; CHECK-APPLE: callq {{.*}}foo
; CHECK-APPLE: testq %r12, %r12
; CHECK-APPLE: jne
; Access part of the error object and save it to error_ref
; CHECK-APPLE: movb 8(%r12)
; CHECK-APPLE: movq %r12, %rdi
; CHECK-APPLE: callq {{.*}}free

; CHECK-O0-LABEL: caller_with_multiple_swifterror_values:

; The first swifterror value:
; CHECK-O0: xorl
; CHECK-O0: movl %{{.*}}, %r12d
; CHECK-O0: callq {{.*}}foo
; CHECK-O0: jne

; The second swifterror value:
; CHECK-O0: xorl
; CHECK-O0: movl %{{.*}}, %r12d
; CHECK-O0: callq {{.*}}foo
; CHECK-O0: jne
entry:
  %error_ptr_ref = alloca swifterror %swift_error*
  store %swift_error* null, %swift_error** %error_ptr_ref
  %call = call float @foo(%swift_error** swifterror %error_ptr_ref)
  %error_from_foo = load %swift_error*, %swift_error** %error_ptr_ref
  %had_error_from_foo = icmp ne %swift_error* %error_from_foo, null
  %tmp = bitcast %swift_error* %error_from_foo to i8*
  br i1 %had_error_from_foo, label %handler, label %cont
cont:
  %v1 = getelementptr inbounds %swift_error, %swift_error* %error_from_foo, i64 0, i32 1
  %t = load i8, i8* %v1
  store i8 %t, i8* %error_ref
  br label %handler
handler:
  call void @free(i8* %tmp)

  %error_ptr_ref2 = alloca swifterror %swift_error*
  store %swift_error* null, %swift_error** %error_ptr_ref2
  %call2 = call float @foo(%swift_error** swifterror %error_ptr_ref2)
  %error_from_foo2 = load %swift_error*, %swift_error** %error_ptr_ref2
  %had_error_from_foo2 = icmp ne %swift_error* %error_from_foo2, null
  %bitcast2 = bitcast %swift_error* %error_from_foo2 to i8*
  br i1 %had_error_from_foo2, label %handler2, label %cont2
cont2:
  %v2 = getelementptr inbounds %swift_error, %swift_error* %error_from_foo2, i64 0, i32 1
  %t2 = load i8, i8* %v2
  store i8 %t2, i8* %error_ref2
  br label %handler2
handler2:
  call void @free(i8* %bitcast2)

  ret float 1.0
}

%swift.refcounted = type opaque

; This test checks that we don't create bad phi nodes as part of swifterror
; isel. We used to fail machine ir verification.
; CHECK-APPLE: _swifterror_isel
; CHECK-O0: _swifterror_isel
define void @swifterror_isel(%swift.refcounted*) {
entry:
  %swifterror = alloca swifterror %swift_error*, align 8
  br i1 undef, label %5, label %1

  %2 = phi i16 [ %4, %1 ], [ undef, %entry ]
  %3 = call i1 undef(i16 %2, %swift.refcounted* swiftself %0, %swift_error** nocapture swifterror %swifterror)
  %4 = load i16, i16* undef, align 2
  br label %1

  ret void
}

; This tests the basic usage of a swifterror parameter with swiftcc.
define swiftcc float @foo_swiftcc(%swift_error** swifterror %error_ptr_ref) {
; CHECK-APPLE-LABEL: foo_swiftcc:
; CHECK-APPLE: movl $16, %edi
; CHECK-APPLE: malloc
; CHECK-APPLE: movb $1, 8(%rax)
; CHECK-APPLE: movq %rax, %r12

; CHECK-O0-LABEL: foo_swiftcc:
; CHECK-O0: movl $16
; CHECK-O0: malloc
; CHECK-O0: movb $1, 8(%rax)
; CHECK-O0: movq %{{.*}}, %r12
entry:
  %call = call i8* @malloc(i64 16)
  %call.0 = bitcast i8* %call to %swift_error*
  store %swift_error* %call.0, %swift_error** %error_ptr_ref
  %tmp = getelementptr inbounds i8, i8* %call, i64 8
  store i8 1, i8* %tmp
  ret float 1.0
}

declare swiftcc float @moo(%swift_error** swifterror)

; Test parameter forwarding.
define swiftcc float @forward_swifterror(%swift_error** swifterror %error_ptr_ref) {
; CHECK-APPLE-LABEL: forward_swifterror:
; CHECK-APPLE: pushq %rax
; CHECK-APPLE: callq _moo
; CHECK-APPLE: popq %rax
; CHECK-APPLE: retq

; CHECK-O0-LABEL: forward_swifterror:
; CHECK-O0: pushq %rax
; CHECK-O0:  callq _moo
; CHECK-O0: popq %rax
; CHECK-O0:  retq

entry:
  %call = call swiftcc float @moo(%swift_error** swifterror %error_ptr_ref)
  ret float %call
}

define swiftcc float @conditionally_forward_swifterror(%swift_error** swifterror %error_ptr_ref, i32 %cc) {
; CHECK-APPLE-LABEL: conditionally_forward_swifterror:
; CHECK-APPLE:  pushq %rax
; CHECK-APPLE:	testl %edi, %edi
; CHECK-APPLE:  je

; CHECK-APPLE:  callq _moo
; CHECK-APPLE:  popq %rax
; CHECK-APPLE:  retq

; CHECK-APPLE:  xorps %xmm0, %xmm0
; CHECK-APPLE:  popq %rax
; CHECK-APPLE:  retq

; CHECK-O0-LABEL: conditionally_forward_swifterror:
; CHECK-O0:  subq $24, %rsp
; CHECK-O0:  movq %r12, [[REG1:%[a-z0-9]+]]
; CHECK-O0:  cmpl $0, %edi
; CHECK-O0-DAG:  movq [[REG1]], [[STK:[0-9]+]](%rsp)
; CHECK-O0-DAG:  movq %r12, [[STK2:[0-9]+]](%rsp)
; CHECK-O0:  je

; CHECK-O0:  movq [[STK2]](%rsp), [[REG:%[a-z0-9]+]]
; CHECK-O0:  movq [[REG]], %r12
; CHECK-O0:  callq _moo
; CHECK-O0:  addq $24, %rsp
; CHECK-O0:  retq

; CHECK-O0:  movq [[STK2]](%rsp), [[REG:%[a-z0-9]+]]
; CHECK-O0:  xorps %xmm0, %xmm0
; CHECK-O0:  movq [[REG]], %r12
; CHECK-O0:  addq $24, %rsp
; CHECK-O0:  retq
entry:
  %cond = icmp ne i32 %cc, 0
  br i1 %cond, label %gen_error, label %normal

gen_error:
  %call = call swiftcc float @moo(%swift_error** swifterror %error_ptr_ref)
  ret float %call

normal:
  ret float 0.0
}

; Check that we don't blow up on tail calling swifterror argument functions.
define float @tailcallswifterror(%swift_error** swifterror %error_ptr_ref) {
entry:
  %0 = tail call float @tailcallswifterror(%swift_error** swifterror %error_ptr_ref)
  ret float %0
}
define swiftcc float @tailcallswifterror_swiftcc(%swift_error** swifterror %error_ptr_ref) {
entry:
  %0 = tail call swiftcc float @tailcallswifterror_swiftcc(%swift_error** swifterror %error_ptr_ref)
  ret float %0
}

; Check that we can handle an empty function with swifterror argument.
; CHECK-i386-LABEL: empty_swiftcc:
; CHECK-i386:  movl    4(%esp), %eax
; CHECK-i386:  movl    8(%esp), %edx
; CHECK-i386:  movl    12(%esp), %ecx
; CHECK-i386:  retl
; CHECK-APPLE-LABEL: empty_swiftcc:
; CHECK-APPLE:  movl    %edx, %ecx
; CHECK-APPLE:  movl    %edi, %eax
; CHECK-APPLE:  movl    %esi, %edx
; CHECK-APPLE:  retq
define swiftcc {i32, i32, i32} @empty_swiftcc({i32, i32, i32} , %swift_error** swifterror %error_ptr_ref) {
entry:
  ret {i32, i32, i32} %0
}

; Make sure we can handle the case when isel generates new machine basic blocks.
; CHECK-APPLE-LABEL: dont_crash_on_new_isel_blocks:
; CHECK-APPLE: pushq   %rax
; CHECK-APPLE: xorl    %eax, %eax
; CHECK-APPLE: testb   %al, %al
; CHECK-APPLE: jne
; CHECK-APPLE: callq   *%rax
; CHECK-APPLE: popq    %rax
; CHECK-APPLE: ret

define swiftcc void @dont_crash_on_new_isel_blocks(%swift_error** nocapture swifterror, i1, i8**) {
entry:
  %3 = or i1 false, %1
  br i1 %3, label %cont, label %falsebb

falsebb:
  %4 = load i8*, i8** %2, align 8
  br label %cont

cont:
  tail call swiftcc void undef(%swift_error** nocapture swifterror %0)
  ret void
}
