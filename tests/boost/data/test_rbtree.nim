import unittest, boost.data.rbtree, sets, random, sequtils, algorithm

suite "RBTree":
  
  test "RBTree - initialization":
    let t = newRBTree[int, void]()
    check: t.len == 0 
    # Value's type is void
    check: not compiles(toSeq(t.values()))
    # But we have keys always
    check: compiles(toSeq(t.keys()))
    var x = 0
    for k in t:
      inc x
    check: x == 0

  test "RBTree - insert (internal)":
    var t = newRBTree[int]()
    t.add(1)
    t.add(2)
    t.add(3)
    t.add(4)
    t.add(5)

    check: t.root.k == 2
    check: t.root.l.k == 1
    check: t.root.l.l.isNil and t.root.l.r.isNil
    check: t.root.r.k == 4
    check: t.root.r.l.k == 3
    check: t.root.r.l.l.isNil and t.root.r.l.r.isNil
    check: t.root.r.r.k == 5

    t.add(6)
    t.add(7)
    t.add(8)

    check: t.root.k == 4
    check: t.root.l.k == 2
    check: t.root.l.l.k == 1

  test "RBTree - insert":
    var t = newRBTree[int, string]()
    for i in 1..100:
      t.add(i, $i)
    for i in 1..100:
      t.add(i, $i)
    check: t.len == 100
    check: toSeq(t.keys()) == toSeq(1..100)
    check: toSeq(t.values()) == toSeq(1..100).mapIt($it)
    for i in 1..100:
      check: t.hasKey(i)
    check: t.min == 1
    check: t.max == 100

  test "RBTree - delete (internal)":
    var t = newRBTree[int]()
    t.add(1)
    t.add(2)
    t.add(3)
    t.add(4)
    t.add(5)

    var res = t.root.bstDelete(t.root)
    check: res.root.k == 3
    check: res.root.l.p == res.root
    check: res.root.r.p == res.root
    res = res.root.bstDelete(res.root.l)
    check: res.root.l.isNil
    res = res.root.bstDelete(res.root.r)
    check: res.root.r.k == 5
