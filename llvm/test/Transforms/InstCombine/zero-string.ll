; NOTE: Assertions have been autogenerated by utils/update_test_checks.py
; RUN: opt < %s -instcombine  -S | FileCheck %s

declare i32 @strlen(i8* nocapture)
declare noalias i8* @calloc(i32, i32)
declare noalias i8* @malloc(i32)

define i32 @calloc_strlen() {
; CHECK-LABEL: @calloc_strlen(
; CHECK-NEXT:    ret i32 0
;
  %call = tail call noalias i8* @calloc(i32 10, i32 1)
  %call1 = tail call i32 @strlen(i8* %call)
  ret i32 %call1
}

define i32 @calloc_strlen_not_const_nmemb(i32 %n) {
; CHECK-LABEL: @calloc_strlen_not_const_nmemb(
; CHECK-NEXT:    [[CALL:%.*]] = tail call noalias i8* @calloc(i32 [[N:%.*]], i32 10)
; CHECK-NEXT:    [[CALL1:%.*]] = tail call i32 @strlen(i8* [[CALL]])
; CHECK-NEXT:    ret i32 [[CALL1]]
;
  %call = tail call noalias i8* @calloc(i32 %n, i32 10)
  %call1 = tail call i32 @strlen(i8* %call) #4
  ret i32 %call1
}


define i32 @calloc_strlen_not_const_size(i32 %size) {
; CHECK-LABEL: @calloc_strlen_not_const_size(
; CHECK-NEXT:    [[CALL:%.*]] = tail call noalias i8* @calloc(i32 1, i32 [[SIZE:%.*]])
; CHECK-NEXT:    [[CALL1:%.*]] = tail call i32 @strlen(i8* [[CALL]])
; CHECK-NEXT:    ret i32 [[CALL1]]
;
  %call = tail call noalias i8* @calloc(i32 1, i32 %size)
  %call1 = tail call i32 @strlen(i8* %call) #4
  ret i32 %call1
}


define i32 @calloc_strlen_not_const_args(i32 %n, i32 %size) {
; CHECK-LABEL: @calloc_strlen_not_const_args(
; CHECK-NEXT:    [[CALL:%.*]] = tail call noalias i8* @calloc(i32 [[N:%.*]], i32 [[SIZE:%.*]])
; CHECK-NEXT:    [[CALL1:%.*]] = tail call i32 @strlen(i8* [[CALL]])
; CHECK-NEXT:    ret i32 [[CALL1]]
;
  %call = tail call noalias i8* @calloc(i32 %n, i32 %size)
  %call1 = tail call i32 @strlen(i8* %call) #4
  ret i32 %call1
}


define i32 @malloc_strlen() {
; CHECK-LABEL: @malloc_strlen(
; CHECK-NEXT:    [[CALL:%.*]] = tail call noalias i8* @malloc(i32 10)
; CHECK-NEXT:    [[CALL1:%.*]] = tail call i32 @strlen(i8* [[CALL]])
; CHECK-NEXT:    ret i32 [[CALL1]]
;
  %call = tail call noalias i8* @malloc(i32 10)
  %call1 = tail call i32 @strlen(i8* %call)
  ret i32 %call1
}

