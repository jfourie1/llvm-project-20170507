// RUN: clang %s -std=c90 -verify &&
// RUN: clang %s -std=c99

int f (int z) { 
  if (z + sizeof (enum {a}))        // expected-note {{previous definition is here}}
    return 1 + sizeof (enum {a});   // expected-error {{redefinition of enumerator 'a'}}
  return 0; 
}
