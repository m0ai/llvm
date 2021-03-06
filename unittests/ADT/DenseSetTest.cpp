//===- llvm/unittest/ADT/DenseSetTest.cpp - DenseSet unit tests --*- C++ -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//

#include "llvm/ADT/DenseSet.h"
#include "gtest/gtest.h"
#include <type_traits>

using namespace llvm;

namespace {

// Test hashing with a set of only two entries.
TEST(DenseSetTest, DoubleEntrySetTest) {
  llvm::DenseSet<unsigned> set(2);
  set.insert(0);
  set.insert(1);
  // Original failure was an infinite loop in this call:
  EXPECT_EQ(0u, set.count(2));
}

struct TestDenseSetInfo {
  static inline unsigned getEmptyKey() { return ~0; }
  static inline unsigned getTombstoneKey() { return ~0U - 1; }
  static unsigned getHashValue(const unsigned& Val) { return Val * 37U; }
  static unsigned getHashValue(const char* Val) {
    return (unsigned)(Val[0] - 'a') * 37U;
  }
  static bool isEqual(const unsigned& LHS, const unsigned& RHS) {
    return LHS == RHS;
  }
  static bool isEqual(const char* LHS, const unsigned& RHS) {
    return (unsigned)(LHS[0] - 'a') == RHS;
  }
};

// Test fixture
template <typename T> class DenseSetTest : public testing::Test {
protected:
  T Set = GetTestSet();

private:
  static T GetTestSet() {
    typename std::remove_const<T>::type Set;
    Set.insert(0);
    Set.insert(1);
    Set.insert(2);
    return Set;
  }
};

// Register these types for testing.
typedef ::testing::Types<DenseSet<unsigned, TestDenseSetInfo>,
                         const DenseSet<unsigned, TestDenseSetInfo>>
    DenseSetTestTypes;
TYPED_TEST_CASE(DenseSetTest, DenseSetTestTypes);

TYPED_TEST(DenseSetTest, FindAsTest) {
  auto &set = this->Set;
  // Size tests
  EXPECT_EQ(3u, set.size());

  // Normal lookup tests
  EXPECT_EQ(1u, set.count(1));
  EXPECT_EQ(0u, *set.find(0));
  EXPECT_EQ(1u, *set.find(1));
  EXPECT_EQ(2u, *set.find(2));
  EXPECT_TRUE(set.find(3) == set.end());

  // find_as() tests
  EXPECT_EQ(0u, *set.find_as("a"));
  EXPECT_EQ(1u, *set.find_as("b"));
  EXPECT_EQ(2u, *set.find_as("c"));
  EXPECT_TRUE(set.find_as("d") == set.end());
}

// Simple class that counts how many moves and copy happens when growing a map
struct CountCopyAndMove {
  static int Move;
  static int Copy;
  int Value;
  CountCopyAndMove(int Value) : Value(Value) {}

  CountCopyAndMove(const CountCopyAndMove &RHS) {
    Value = RHS.Value;
    Copy++;
  }
  CountCopyAndMove &operator=(const CountCopyAndMove &RHS) {
    Value = RHS.Value;
    Copy++;
    return *this;
  }
  CountCopyAndMove(CountCopyAndMove &&RHS) {
    Value = RHS.Value;
    Move++;
  }
  CountCopyAndMove &operator=(const CountCopyAndMove &&RHS) {
    Value = RHS.Value;
    Move++;
    return *this;
  }
};
int CountCopyAndMove::Copy = 0;
int CountCopyAndMove::Move = 0;
} // anonymous namespace

namespace llvm {
// Specialization required to insert a CountCopyAndMove into a DenseSet.
template <> struct DenseMapInfo<CountCopyAndMove> {
  static inline CountCopyAndMove getEmptyKey() { return CountCopyAndMove(-1); };
  static inline CountCopyAndMove getTombstoneKey() {
    return CountCopyAndMove(-2);
  };
  static unsigned getHashValue(const CountCopyAndMove &Val) {
    return Val.Value;
  }
  static bool isEqual(const CountCopyAndMove &LHS,
                      const CountCopyAndMove &RHS) {
    return LHS.Value == RHS.Value;
  }
};
}

namespace {
// Make sure reserve actually gives us enough buckets to insert N items
// without increasing allocation size.
TEST(DenseSetCustomTest, ReserveTest) {
  // Test a few different size, 48 is *not* a random choice: we need a value
  // that is 2/3 of a power of two to stress the grow() condition, and the power
  // of two has to be at least 64 because of minimum size allocation in the
  // DenseMa. 66 is a value just above the 64 default init.
  for (auto Size : {1, 2, 48, 66}) {
    DenseSet<CountCopyAndMove> Set;
    Set.reserve(Size);
    unsigned MemorySize = Set.getMemorySize();
    CountCopyAndMove::Copy = 0;
    CountCopyAndMove::Move = 0;
    for (int i = 0; i < Size; ++i)
      Set.insert(CountCopyAndMove(i));
    // Check that we didn't grow
    EXPECT_EQ(MemorySize, Set.getMemorySize());
    // Check that move was called the expected number of times
    EXPECT_EQ(Size, CountCopyAndMove::Move);
    // Check that no copy occured
    EXPECT_EQ(0, CountCopyAndMove::Copy);
  }
}
}
