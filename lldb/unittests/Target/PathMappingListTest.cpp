//===-- PathMappingListTest.cpp ---------------------------------*- C++ -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//

#include "llvm/ADT/ArrayRef.h"
#include "lldb/Target/PathMappingList.h"
#include "lldb/Utility/FileSpec.h"
#include "gtest/gtest.h"
#include <utility>

using namespace lldb_private;

namespace {
  struct Matches {
    ConstString original;
    ConstString remapped;
    Matches(const char *o, const char *r) : original(o),
        remapped(r) {}
  };
  
  void TestPathMappings(const PathMappingList &map,
                        llvm::ArrayRef<Matches> matches,
                        llvm::ArrayRef<ConstString> fails) {
    ConstString actual_remapped;
    for (const auto &fail: fails) {
      EXPECT_FALSE(map.RemapPath(fail, actual_remapped));
    }
    for (const auto &match: matches) {
      FileSpec orig_spec(match.original.GetStringRef(), false);
      std::string orig_normalized = orig_spec.GetPath();
      EXPECT_TRUE(map.RemapPath(match.original, actual_remapped));
      EXPECT_EQ(actual_remapped, match.remapped);
      FileSpec remapped_spec(match.remapped.GetStringRef(), false);
      FileSpec unmapped_spec;
      EXPECT_TRUE(map.ReverseRemapPath(remapped_spec, unmapped_spec));
      std::string unmapped_path = unmapped_spec.GetPath();
      EXPECT_EQ(unmapped_path, orig_normalized);
    }
  }
}

TEST(PathMappingListTest, RelativeTests) {
  Matches matches[] = {
    {".", "/tmp"},
    {"./", "/tmp"},
    {"./////", "/tmp"},
    {"./foo.c", "/tmp/foo.c"},
    {"foo.c", "/tmp/foo.c"},
    {"./bar/foo.c", "/tmp/bar/foo.c"},
    {"bar/foo.c", "/tmp/bar/foo.c"},
  };
  ConstString fails[] = {
    ConstString("/a"),
    ConstString("/"),
  };
  PathMappingList map;
  map.Append(ConstString("."), ConstString("/tmp"), false);
  TestPathMappings(map, matches, fails);
  PathMappingList map2;
  map2.Append(ConstString(""), ConstString("/tmp"), false);
  TestPathMappings(map, matches, fails);
}

TEST(PathMappingListTest, AbsoluteTests) {
  PathMappingList map;
  map.Append(ConstString("/old"), ConstString("/new"), false);
  Matches matches[] = {
    {"/old", "/new"},
    {"/old/", "/new"},
    {"/old/foo/.", "/new/foo"},
    {"/old/foo.c", "/new/foo.c"},
    {"/old/foo.c/.", "/new/foo.c"},
    {"/old/./foo.c", "/new/foo.c"},
  };
  ConstString fails[] = {
    ConstString("/foo"),
    ConstString("/"),
    ConstString("foo.c"),
    ConstString("./foo.c"),
    ConstString("../foo.c"),
    ConstString("../bar/foo.c"),
  };
  TestPathMappings(map, matches, fails);
}

TEST(PathMappingListTest, RemapRoot) {
  PathMappingList map;
  map.Append(ConstString("/"), ConstString("/new"), false);
  Matches matches[] = {
    {"/old", "/new/old"},
    {"/old/", "/new/old"},
    {"/old/foo/.", "/new/old/foo"},
    {"/old/foo.c", "/new/old/foo.c"},
    {"/old/foo.c/.", "/new/old/foo.c"},
    {"/old/./foo.c", "/new/old/foo.c"},
  };
  ConstString fails[] = {
    ConstString("foo.c"),
    ConstString("./foo.c"),
    ConstString("../foo.c"),
    ConstString("../bar/foo.c"),
  };
  TestPathMappings(map, matches, fails);
}
