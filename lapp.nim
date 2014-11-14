import strutils
import os
import tables
export tables.`[]`

#### Simple string lexer ###
type
  PLexer = ref TLexer
  TLexer = object
    str: string
    idx: int
  TLexType = enum
    tend
    tword
    tint
    tfloat
    trange
    telipsis
    tchar

proc thisChar(L: PLexer):char = L.str[L.idx]
proc next(L: PLexer) = L.idx += 1

proc skipws(L: PLexer) =
  while thisChar(L) in Whitespace: next(L)
    
proc get(L: PLexer; t: var TLexType): string =
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
    if thisChar(L) == '-':
      result.add('-')
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
    
proc get(L: PLexer): string = 
  var t: TLexType
  get(L,t)
    
proc reset(L: PLexer, s: string) =
  L.str  = s
  L.idx = 0

proc newLexer(s: string): PLexer =
  new(result)
  result.reset(s)
    
### a container for values ###
    
type
  TValueKind = enum
    vInt,
    vFloat,
    vString,
    vBool,
    vFile,
    vSeq

  PValue* = ref TValue
  TValue* = object
    case kind*: TValueKind
      of vInt: asInt*: int
      of vFloat: asFloat*: float
      of vString: asString*: string
      of vBool: asBool*: bool
      of vFile:
        asFile*: File
        fileName*: string
      of vSeq: asSeq*: seq[PValue]

proc boolValue(c: bool): PValue =  PValue(kind: vBool, asBool: c)
    
proc fileValue(f: File, name: string): PValue =  PValue(kind: vFile, asFile: f, fileName: name)
    
proc strValue(s: string): PValue =  PValue(kind: vString, asString: s) 
    
proc intValue(v: int): PValue =   PValue(kind: vInt, asInt: v)
    
proc floatValue(v: float): PValue = PValue(kind: vFloat, asFloat: v)
    
proc seqValue(v: seq[PValue]): PValue = PValue(kind: vSeq, asSeq: v)

const MAX_FILES = 30
    
type
  PSpec = ref TSpec
  TSpec = object
    defVal: string
    ptype: string
    needsValue, multiple, used: bool
var
  progname, usage: string
  aliases: array[char,string]
  parm_spec =  initTable[string,PSpec]()

proc fail(msg: string)  =
  stderr.writeln(progname & ": " & msg)
  quit(usage)

proc parseSpec(u: string) =    
  var
    L: PLexer
    tok: string
    k = 1
      
  let lines = u.splitLines
  L = newLexer(lines[0])
  progname = L.get
  usage = u
  for line in lines[1..(-1)]:
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
      # echo("Param: " & name & " type: " & $ftype & " needsvalue: " & $(ftype != "bool") & " default: " & $defValue & " multiple: " & $multiple)
      let spec = PSpec(defVal:defValue, ptype: ftype, needsValue: ftype != "bool",multiple:multiple)
      aliases[alias] = name        
      parm_spec[name] = spec

proc tail(s: string): string = s[1..(-1)]

var 
  files = newSeq[File]()

proc closeFiles() {.noconv.} =
  for f in files:
    f.close()

proc parseArguments*(usage: string, args: seq[string]): Table[string,PValue] =
  var
    vars = initTable[string,PValue]()
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
            if i.needsValue: fail("needs value! " & f)
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
      
  # any flags not mentioned?
  for flag,info in parm_spec:
    if not info.used:
      if info.defVal == "": # no default!
        fail("required option or argument missing: " & flag)
      flagvalues.add(@[flag,info.defVal])
          
  # cool, we have the info, can convert known flags
  for item in flagvalues:
    var pval: PValue;
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
    
    var oval = vars[flag]
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

proc parse*(usage: string): Table[string,PValue] =
  var 
    args: seq[string]
    n = paramCount()
  newSeq(args,n+1)
  for i in 0..n:
    args[i] = paramStr(i)
  return parseArguments(usage,args)    

when isMainModule:
  var args = parse"""
  head [flags] file [out]
    -n: (default 10) number of lines
    -v,--verbose: (bool...) verbosity level 
    -a,--alpha  useless parm
    <file>: (default stdin...)
    <out>: (default stdout)
  """

  echo args["n"].asInt
  echo args["alpha"].asBool
  
  for v in args["verbose"].asSeq:
    echo "got ",v.asBool
  
  let myfiles = args["files"].asSeq
  for f in myfiles:
    echo f.asFile.readLine()
        
