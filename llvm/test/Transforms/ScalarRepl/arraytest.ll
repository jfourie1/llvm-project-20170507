; RUN: if as < %s | opt -scalarrepl -mem2reg | dis | grep alloca
; RUN: then exit 1
; RUN: else exit 0
; RUN: fi

int %test() {
  %X = alloca [ 4 x int ]
  %Y = getelementptr [4x int]* %X, long 0, long 0
  store int 0, int* %Y

  %Z = load int* %Y
  ret int %Z
}
