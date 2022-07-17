import strutils, base64, json, parser, sequtils

const VERSION = "1.0"

proc doVersion(option: Option): string =
  if option.showVersion:
    return VERSION
  elif option.showVersionJson:
    let mes = %* {
      "program": "njo",
      "author": "uga-rosa",
      "repo": "https://github.com/uga-rosa/nimjo",
      "version": VERSION
    }
    if option.pretty:
      return mes.pretty
    else:
      return $mes
  else:
    return ""

proc doHelp() =
  echo """Usage: njo [-a] [-B] [-d keydelim] [-p] [-e] [-n] [-v] [-V] [-f file] [--] [-s|-n|-b] [word...]
      word is key=value or key@value
      -a creates an array of words
      -B disable boolean true/false/null detection
      -d key will be object path separated by keydelim
      -f load file as JSON object or array
      -p pretty-prints JSON on output
      -e quit if stdin is empty do not wait for input
      -s coerce type guessing to string
      -b coerce type guessing to bool
      -n coerce type guessing to number
      -v show version
      -V show version in JSON"""

proc parseValueDefault(s: string, option: Option): JsonNode =
  if s == "":
    return newJNull()

  let fileValue = if s.startsWith("@"): 1
  elif s.startsWith("%"): 2
  elif s.startsWith(":"): 3
  else: 0

  if fileValue > 0:
    let fname = s[1 .. ^1]
    let content = fname.readFile
    case fileValue
    of 1: return content.newJString
    of 2: return content.encode.newJString
    of 3: return content.parseJson
    else: discard

  if not option.disableParseBoolString:
    if s == "true":
      return newJBool(true)
    elif s == "false":
      return newJBool(false)
    elif s == "null":
      return newJNull()

  if s.startsWith("{") or s.startsWith("["):
    return s.parseJson

  try:
    return s.parseInt.newJInt
  except ValueError:
    discard
  try:
    return s.parseFloat.newJFloat
  except ValueError:
    discard

  return newJString(s)

proc parseValueString(s: string): JsonNode =
  return s.newJString()

proc parseValueNumber(s: string): JsonNode =
  try:
    return s.parseInt.newJInt
  except ValueError:
    discard
  try:
    return s.parseFloat.newJFloat
  except ValueError:
    discard
  return s.len.newJInt

proc parseValueBool(s: string, option: Option): JsonNode =
  if not option.disableParseBoolString:
    case s
    of "true": return newJBool(true)
    of "false", "null": return newJBool(false)
    else: discard
  return newJBool(s != "")

proc parseValue(arg: Arg, option: Option): JsonNode =
  let s = arg.value
  case arg.coercion
  of Default: return parseValueDefault(s, option)
  of String: return parseValueString(s)
  of Number: return parseValueNumber(s)
  of Bool: return parseValueBool(s, option)
    
proc doArray(args: Args, option: Option, jnode = newJArray()): JsonNode =
  result = jnode
  for arg in args:
    result.add(parseValue(arg, option))

proc doObject(args: Args, option: Option, jnode = newJObject()): JsonNode =
  result = jnode
  for arg in args:
    if arg.value.find("=") >= 0:
      var kv = arg.value.split("=", 2)

      if kv[0].endsWith(":"):
        # When the := operator is used in a word, the name to the right of := is a file containing JSON which is parsed and assigned to the key left of the operator.
        # The file may be specified as - to read from jo's standard input.
        kv[0] = kv[0][0..^2]
        kv[1] = kv[1].readFile

      if option.delimiter != '\x00' and kv[0].find(option.delimiter) >= 0:
        let
          keys = kv[0].split(option.delimiter)
          value = Arg(value: kv[1], coercion: arg.coercion).parseValue(option)
        var obj = result
        for i in 0..keys.len-2:
          let key = keys[i]
          if not obj.hasKey(key) or obj[key].kind != JObject:
            obj[key] = newJObject()
          obj = obj[key]
        obj[keys[^1]] = value
        continue

      let
        arrayIndex = kv[0].find("[]")
        objectIndex = (kv[0].find("["), kv[0].find("]"))

      if arrayIndex >= 0:
        # Array
        let
          key = kv[0][0..arrayIndex-1]
          value = Arg(value: kv[1], coercion: arg.coercion).parseValue(option)
        if result.hasKey(key) and result[key].kind == JArray:
          result[key].add(value)
        else:
          var newarr = newJArray()
          newarr.add(value)
          result.add(key, newarr)
      elif objectIndex[0] >= 0 and objectIndex[1] >= 0:
        let
          key = kv[0][0..objectIndex[0]-1]
          childKey = kv[0][objectIndex[0]+1..objectIndex[1]-1]
          value = Arg(value: kv[1], coercion: arg.coercion).parseValue(option)
        if result.hasKey(key) and result[key].kind == JObject:
          result[key].add(childKey, value)
        else:
          var newObj = newJObject()
          newObj.add(childKey, value)
          result.add(key, newObj)
      else:
        let newArg = Arg(value: kv[1], coercion: arg.coercion)
        result.add(kv[0], parseValue(newArg, option))
    elif arg.value.find("@") >= 0:
      # jo treats key@value specifically as boolean JSON elements: if the value begins with T, t, or the numeric value is greater than zero, the result is true, else false.
      let kv = arg.value.split("@", 2)
      var value: bool
      if kv[1].startsWith("t") or kv[1].startsWith("T"):
        value = true
      else:
        try:
          let num = kv[1].parseFloat
          value = num > 0
        except ValueError:
          value = false
      result.add(kv[0], newJBool(value))
    else:
      raiseAssert("each word must be `key=value` or `key@value`")

proc doFile(file: File, args: Args, option: Option): JsonNode =
  try:
    let contentFile = file.readAll.parseJson
    case contentFile.kind
    of JObject: return doObject(args, option, contentFile)
    of JArray: return doArray(args, option, contentFile)
    else:
      echo "Input JSON not an array or object: " & $contentFile
      doHelp()
  except IOError:
    echo "Cannot open " & option.file & " for reading"
    doHelp()
  except JsonParsingError:
    echo "Cannot parse to json format"
    doHelp()

proc run() =
  let (option, args) = parse()

  if option.help:
    doHelp()
    return

  if option.showVersion or option.showVersionJson:
    echo doVersion(option)
    return

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

  if option.pretty:
    echo jnode.pretty
  else:
    echo $jnode

when isMainModule:
  run()