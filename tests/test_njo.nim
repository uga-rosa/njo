import unittest, ../src/njo, ../src/parser, json, strutils, sequtils

type
  inputExpect = object
    input: seq[string]
    expect: string
  inputExpects = seq[inputExpect]

proc builder(s: seq[seq[string]]): inputExpects =
  for i in 0..s.len-1:
    var input = s[i]
    let expect = input.pop
    result.add(inputExpect(input: input, expect: expect))

let data = builder(@[
  @[
    "tst=1457081292",
    "lat=12.3456",
    "cc=FR",
    "badfloat=3.14159.26",
    """name="JP Mens"""",
    "nada=",
    "coffee@T",
    """{"tst":1457081292,"lat":12.3456,"cc":"FR","badfloat":"3.14159.26","name":"JP Mens","nada":null,"coffee":true}""",
  ],
  @[
    "switch=true",
    "morning@0",
    """{"switch":true,"morning":false}""",
  ],
  @[
    "-B",
    "switch=true",
    "morning@0",
    """{"switch":"true","morning":false}""",
  ],
  @[
    "-p",
    "name=Jane",
    "point[]=1",
    "point[]=2",
    "geo[lat]=10",
    "geo[lon]=20",
    """{
  "name": "Jane",
  "point": [
    1,
    2
  ],
  "geo": {
    "lat": 10,
    "lon": 20
  }
}""",
  ],
  @[
    "-p", "-d.",
    "name=Jane",
    "point[]=1",
    "point[]=2",
    "geo.lat=10",
    "geo.lon=20",
    """{
  "name": "Jane",
  "point": [
    1,
    2
  ],
  "geo": {
    "lat": 10,
    "lon": 20
  }
}""",
  ],
  @[
    "-p", "--",
    "-s", "a=true",
    "b=true",
    "-s", "c=123",
    "d=123",
    "-b", """e="1"""",
    "-b", """f="true""""",
    "-n", """g=This is a test""",
    "-b", """h=This is a test""",
    """{
  "a": "true",
  "b": true,
  "c": "123",
  "d": 123,
  "e": true,
  "f": true,
  "g": 14,
  "h": true
}""",
  ],
  @[
    "-a", "--",
    "-s", "123",
    "-n", "This is a test",
    "-b", "C_Rocks",
    "456",
    """["123",14,true,456]""",
  ],
  @[
    "greet=@tests/data.txt",
    """{"greet":"hello world"}""",
  ],
  @[
    "type=base64",
    "greet=%tests/data.txt",
    """{"type":"base64","greet":"aGVsbG8gd29ybGQK"}""",
  ],
  @[
    "json=:tests/data.json",
    """{"json":{"field1":123,"field2":"abc"}}""",
  ],
  @[
    "-a",
    "bin",
    "LICENSE",
    "njo.nimble",
    "README.md",
    "src",
    "tests",
    """["bin","LICENSE","njo.nimble","README.md","src","tests"]"""
  ],
  @[
    "-a",
    ":tests/data.json",
    ":tests/data2.json",
    """[{"field1":123,"field2":"abc"},[123,456,789]]"""
  ],
  @[
    "-f", "tests/data2.json",
    "1",
    "[123,456,789,1]",
  ],
])

proc runTest(data: inputExpects) =
  for d in data:
    let (option, args) = parse(d.input)

    var jnode: JsonNode
    if option.file != "":
      let file = if option.file == "-": stdin
      else: option.file.open
      jnode = doFile(file, args, option)
    else:
      var a: Args
      if args.len == 0:
        if option.ignoreEmptyStdin:
          return
        var input = stdin.readAll
        if input == "":
          a = @[]
        else:
          input.removeSuffix
          a = input.split("\n").mapIt(Arg(value: it, coercion: Default))
      else:
        a = args

      if option.array:
        jnode = doArray(a, option)
      else:
        jnode = doObject(a, option)

    if jnode == nil:
      return

    let actual = if option.pretty: jnode.pretty
    else: $jnode

    check d.expect == actual

runTest(data)
