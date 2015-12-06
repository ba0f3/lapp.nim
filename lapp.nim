import strutils
import os
import tables
export tables.`[]`

#### Simple string lexer ###
type
  LexerRef = ref Lexer
  Lexer = object
    str: string
    idx: int
  LexType = enum
    tend
    tword
    tint
    tfloat
    trange
    telipsis
    tchar
    toption
    tdivider

proc thisChar(L: LexerRef):char = L.str[L.idx]
proc next(L: LexerRef) = L.idx += 1

proc skipws(L: LexerRef) =
  while thisChar(L) in Whitespace: next(L)

proc get(L: LexerRef; t: var LexType): string =
  skipws(L)
  let c = thisChar(L)
  t = tend
  if c == '\0': return nil
  result = ""
  result.add(c)
  next(L)
  t = tchar
  case c
  of '-':  # '-", "--"
    t = toption
    if thisChar(L) == '-':
      result.add('-')
      next(L)
      if thisChar(L) == '-': # "---..."
        t = tdivider
        result.add('-')
        while thisChar(L) == '-':
          next(L)
  of Letters: # word
    t = tword
    while thisChar(L) in Letters:
      result.add(thisChar(L))
      next(L)
  of Digits: # number
    t = tint
    while thisChar(L) in Digits:
      result.add(thisChar(L))
      next(L)
    if thisChar(L) == '.':
      t = tfloat
      result.add(thisChar(L))
      next(L)
      while thisChar(L) in Digits:
        result.add(thisChar(L))
        next(L)
  of '.': # ".", "..", "..."
    if thisChar(L) == '.':
      t = trange
      result.add('.')
      next(L)
      if thisChar(L) == '.':
        t = telipsis
        result.add('.')
        next(L)
  else: discard

proc get(L: LexerRef): string =
  var t: LexType
  get(L,t)

proc reset(L: LexerRef, s: string) =
  L.str  = s
  L.idx = 0

proc newLexer(s: string): LexerRef =
  new(result)
  result.reset(s)

### a container for values ###

type
  ValueKind = enum
    vInt,
    vFloat,
    vString,
    vBool,
    vFile,
    vSeq

  ValueRef* = ref Value
  Value* = object
    case kind*: ValueKind
      of vInt: asInt*: int
      of vFloat: asFloat*: float
      of vString: asString*: string
      of vBool: asBool*: bool
      of vFile:
        asFile*: File
        fileName*: string
      of vSeq: asSeq*: seq[ValueRef]

proc boolValue(c: bool): ValueRef =  ValueRef(kind: vBool, asBool: c)

proc fileValue(f: File, name: string): ValueRef =  ValueRef(kind: vFile, asFile: f, fileName: name)

proc strValue(s: string): ValueRef =  ValueRef(kind: vString, asString: s)

proc intValue(v: int): ValueRef =   ValueRef(kind: vInt, asInt: v)

proc floatValue(v: float): ValueRef = ValueRef(kind: vFloat, asFloat: v)

proc seqValue(v: seq[ValueRef]): ValueRef = ValueRef(kind: vSeq, asSeq: v)

type
  PSpec = ref TSpec
  TSpec = object
    defVal: string
    ptype: string
    group: int
    needsValue, multiple, used: bool
var
  progname, usage: string
  aliases: array[char,string]
  parm_spec =  initTable[string,PSpec]()

proc fail(msg: string)  =
  stderr.write(progname & ": " & msg & "\n")
  quit(usage)

proc parseSpec(u: string) =
  var
    L: LexerRef
    tok: string
    groupCounter: int
    k = 1

  let lines = u.splitLines
  L = newLexer(lines[0])
  progname = L.get
  usage = u
  for line in lines[1..^1]:
    var
      isarg = false
      multiple = false
      getnext = true
      name: string
      alias: char
    L.reset(line)
    tok = L.get
    if tok == "-" or tok == "--":  # flag
      if tok == "-": #short flag
        let flag = L.get
        if len(flag) != 1: fail("short option has one character!")
        tok = L.get
        if tok == ",": # which is alias for long flag
          tok = L.get
          if tok != "--": fail("expecting long --flag")
          name = L.get
          alias = flag[0]
        else: # only short flag
          name = flag
          alias = flag[0]
          getnext = false
      else: # only long flag
        name = L.get
        alias = '\0'
    elif tok == "<":  # argument
      isarg = true
      name = L.get
      alias = chr(k)
      k += 1
      tok = L.get
      if tok != ">": fail("argument must be enclosed in <...>")
    elif tok == "---": # divider
      inc(groupCounter)
    if getnext:  tok = L.get
    if tok == ":": # allowed to have colon after flags
      tok = L.get
    if tok == nil: continue
    # default types for flags and arguments
    var
      ftype = if isarg: "string" else: "bool"
      defValue = ""
    if tok == "(": # typed flag/argument
      var t = tchar
      tok = L.get(t)
      if tok == "default":  # type from default value
        defValue = L.get(t)
        if t == tint: ftype = "int"
        elif t == tfloat: ftype = "float"
        elif t == tword:
          if defValue == "stdin": ftype = "infile"
          elif defValue == "stdout": ftype = "outfile"
          else: ftype = "string"
        else: fail("unknown default value " & tok)
      else: # explicit type
        if t == tword:
          ftype = tok
          if tok == "bool": defValue = "false"
        else: fail("unknown type " & tok)
      discard L.get(t)
      multiple = t == telipsis
    elif ftype == "bool": # no type or default
      defValue = "false"

    if name != nil:
      #echo("Param: " & name & " type: " & $ftype & " group: " & $groupCounter & " needsvalue: " & $(ftype != "bool") & " default: " & $defValue & " multiple: " & $multiple)
      let spec = PSpec(defVal:defValue, ptype: ftype, group: groupCounter, needsValue: ftype != "bool",multiple:multiple)
      aliases[alias] = name
      parm_spec[name] = spec

proc tail(s: string): string = s[1..^1]

var
  files = newSeq[File]()

proc closeFiles() {.noconv.} =
  for f in files:
    f.close()

proc parseArguments*(usage: string, args: seq[string]): Table[string,ValueRef] =
  var
    vars = initTable[string,ValueRef]()
    n = len(args) - 1
    i = 1
    k = 1
    flag,value, arg: string
    info: PSpec
    short: bool
    flagvalues: seq[seq[string]]

  proc next(): string =
    if i > n: fail("an option required a value!")
    result = args[i]
    i += 1

  proc get_alias(c: char): string =
    result = aliases[c]
    if result == nil:
      n = ord(c)
      if n < 20:
        fail("no such argument: " & $n)
      else:
        fail("no such option: " & c)

  proc get_spec(name: string): PSpec =
    result = parm_spec[name]
    if result == nil:
      fail("no such option: " & name)

  newSeq(flagvalues, 0)
  parseSpec(usage)
  addQuitProc(closeFiles)

  # Collect failures
  var failures = newSeq[string]()

  # parse the flags and arguments
  while i <= n:
    arg = next()
    if arg[0] == '-':  #flag
      short = arg[1] != '-'
      arg = arg.tail
      if short: # all short args are aliases, even if only to themselves
        flag = get_alias(arg[0])
      else:
        flag = arg[1..high(arg)]
      info = get_spec(flag)
      if info.needsValue:
        if short and len(arg) > 1: # value can follow short flag
          value = arg.tail
        else:  # grab next argument
          value = next()
      else:
        value = "true"
        if short and len(arg) > 0: # short flags can be combined
          for c in arg.tail:
            let f = get_alias(c)
            let i = get_spec(f)
            if i.needsValue:
              failures.add("option " & f & " needs a value")
            flagvalues.add(@[f,"true"])
            i.used = true
    else: # argument (stored as \001, \002, etc
      flag = get_alias(chr(k))
      value = arg
      info = get_spec(flag)
      # don't move on if this is a varags last param
      if not info.multiple:  k += 1
    flagvalues.add(@[flag,value])
    info.used = true

  # Some options disables checking
  var enableChecks = true
  for flag,info in parm_spec:
    if info.used:
      if flag == "help" or flag == "version":
        enableChecks = false

  # Check maximum group used
  var maxGroup = 0
  for item in flagvalues:
    info = get_spec(item[0])
    if maxGroup < info.group:
      maxGroup = info.group

  # any flags not mentioned?
  for flag,info in parm_spec:
    if not info.used:
      # Is there no default and we have used options in this group?
      if info.defVal == "" and info.group <= maxGroup:
        failures.add("required option or argument missing: " & flag)
      else:
        flagvalues.add(@[flag,info.defVal])

  if enableChecks:
    # any failures up until now - then we fail
    if failures.len > 0:
      fail(failures.join("\n") & "\n")

  # cool, we have the info, can convert known flags
  for item in flagvalues:
    var pval: ValueRef;
    let
      flag = item[0]
      value = item[1]
      info = get_spec(flag)
    case info.ptype
    of "int":
      var v: int
      try:
        v = value.parseInt
      except:
        fail("bad integer for " & flag)
      pval = intValue(v)
    of "float":
      var v: float
      try:
        v = value.parseFloat
      except:
        fail("bad float for " & flag)
      pval = floatValue(v)
    of "bool":
      pval = boolValue(value.parseBool)
    of "string":
      pval = strValue(value)
    of "infile","outfile": # we open files for the app...
      var f: File
      try:
        if info.ptype == "infile":
          if value == "stdin":
            f = stdin
          else:
            f = open(value, fmRead)
        else:
          if value == "stdout":
            f = stdout
          else:
            f = open(value, fmWrite)
        # they will be closed automatically on program exit
        files.add(f)
      except:
        fail("cannot open " & value)
      pval = fileValue(f,value)
    else: discard

    var oval = vars.getOrDefault(flag)
    if info.multiple: # multiple flags are sequence values
      if oval == nil: # first value!
        pval = seqValue(@[pval])
      else: # just add to existing sequence
        oval.asSeq.add(pval)
        pval = oval
    elif oval != nil: # cannot repeat a single flag!
      fail("cannot use '" & flag & "' more than once")
    vars[flag] = pval

  return vars

proc parse*(usage: string): Table[string,ValueRef] =
  var
    args: seq[string]
    n = paramCount()
  newSeq(args,n+1)
  for i in 0..n:
    args[i] = paramStr(i)
  return parseArguments(usage,args)

# Helper proc for verbosity level.
proc verbosityLevel*(args: Table[string, ValueRef]): int =
  if args.hasKey("verbose"):
    let verbosity = args["verbose"].asSeq
    result = verbosity.len
    if not verbosity[0].asBool:
      result = 0
  else:
    result = 0

# Helper to check if we should show version
proc showVersion*(args: Table[string, ValueRef]): bool =
  args["version"].asBool

# Helper to check if we should show help
proc showHelp*(args: Table[string, ValueRef]): bool =
  args["help"].asBool


# Typical usage
when isMainModule:
  let help = """
  head [flags] files... [out]
    -h,--help                     Show this help
    --version                     Show version
    -n: (default 10)              Number of lines to show
    -v,--verbose: (bool...)       Verbosity level, ignored
    -o,--out: (default stdout)    Optional outfile, defaults to stdout
    <files>: (default stdin...)   Files to take head of
  """
  # On parsing failure this will show usage automatically
  var args = parse(help)

  # These two are special, they short out
  if args.showHelp: quit(help)
  if args.showVersion: quit("Version: 1.99")

  # Ok, so what did we get...
  let n = args["n"].asInt

  # This one is a helper
  let v = verbosityLevel(args)

  echo "Lines to show: " & $n
  echo "Verbosity level: " & $verbosityLevel(args)

  let myfiles = args["files"].asSeq
  var outFile = args["out"].asFile

  for f in myfiles:
    for i in 1..n:
      writeln(outFile, string(f.asFile.readLine()))
