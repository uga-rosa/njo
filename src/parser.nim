import os, strutils

type
  Option* = object
    pretty*: bool
    array*: bool
    disableParseBoolString*: bool
    ignoreEmptyStdin*: bool
    dontCreateNullElement*: bool
    showVersion*: bool
    showVersionJson*: bool
    delimiter*: char
    file*: string
    help*: bool
  Arg* = object
    value*: string
    coercion*: Coercion
  Args* = seq[Arg]
  Coercion* = enum
    String
    Number
    Bool
    Default

proc parse*(): (Option, Args) =
  let cmdArgs = os.commandLineParams()
  # `njo -ap 1 2` => ["-ap", "1", "2"]
  var
    option: Option
    args: Args
    afterGlobal = false
    i = 0
    cmdArg: string

  while i < cmdArgs.len:
    defer: i.inc
    cmdArg = cmdArgs[i]

    if cmdArg == "--help" or cmdArg == "-h":
      option.help = true
      break

    if cmdArg == "--":
      afterGlobal = true
      continue

    if afterGlobal:
      var coer = Default
      if cmdArg.startsWith("-"):
        case cmdArg
        of "-s": coer = String
        of "-n": coer = Number
        of "-b": coer = Bool
        else:
          echo "Invalid type coercion: " & $cmdArg
          option.help = true
          break
        i.inc
        cmdArg = cmdArgs[i]
      args.add(Arg(value: cmdArg, coercion: coer))
    elif cmdArg.startsWith("-"):
      for j in 1..cmdArg.len-1:
        let short = cmdArg[j]
        case short
        of 'p': option.pretty = true
        of 'a': option.array = true
        of 'B': option.disableParseBoolString = true
        of 'e': option.ignoreEmptyStdin = true
        of 'n': option.dontCreateNullElement = true
        of 'v': option.showVersion = true
        of 'V': option.showVersionJson = true
        of 'd':
          # `-d.` => ["-d."]
          # `-d .` => ["-d", "."]
          option.delimiter = if j+1 <= cmdArg.len-1: cmdArg[j+1]
          else:
            i.inc
            cmdArgs[i][0]
          break
        of 'f':
          option.file = if j+1 <= cmdArg.len-1: cmdArg[j+1..^1]
          else:
            i.inc
            cmdArgs[i]
          break
        else:
          echo "Invalid option: " & $cmdArg[1]
          option.help = true
          break
    else:
      args.add(Arg(value: cmdArg, coercion: Default))

  return (option, args)
