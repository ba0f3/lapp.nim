import lapp, tables
from os import paramStr, paramCount

# This is a trivial example trying to cover all features of lapp.

let help = """
  example [options] command filenames
    
    -r  Just an optional single character flag. Show the args using repr.
    -t,--test  Or with additional long variant, no whitespace there.
    -n: A colon can be added, but has no meaning, instead () specifies further.
    -N (default 10) And it can take a value, and have a default value.
    -f (default 0.04) And be a float
    -s (default banana) Or a string
    -x (int) And it can be typed with int, string, float, stdin, stdout - without a
            default value. This implies that the option is mandatory!
    -X (int...) And allow multiples.
    -v,--verbose: (bool...) Verbosity level, "..." means can be multiple.
    -o,--out (default stdout) A file to direct to.
    <command> Arguments are string by default.
    <file>: (default stdin...) One or more files or stdin by default

    
    The first line in this help text is arbitrary, or rather
    its only the lines (trimmed) beginning with '-' or '<' that constitute
    the speciciation, so this text is also ignored.
    
    Things we know are not working:
      ranges. The lexer in lapp does it, but there is no more support.
  """


# This part is for build testing lapp, we run a bunch of asserts
if paramCount() == 1 and paramStr(1) == "test":
  var args = parseArguments(help, @["example", "-x1", "-X4", "cmd"])
  assert(args["r"].asBool == false)
  assert(args["test"].asBool == false)
  assert(args["n"].asBool == false)
  assert(args["N"].asInt == 10)
  assert(args["f"].asFloat == 0.04)
  assert(args["s"].asString == "banana")
  assert(args["x"].asInt == 1)
  assert(args["X"].asSeq[0].asInt == 4)
  assert(args["verbose"].asSeq.len == 1)
  assert(args["verbose"].asSeq[0].asBool == false)
  assert(args["out"].filename == "stdout")
  assert(args["command"].asString == "cmd")
  assert(args["file"].asSeq.len == 1)
  assert(args["file"].asSeq[0].filename == "stdin")
else:

  # We call `parse` in lapp with our help text as argument.
  # This will both parse the help text above and then, parse the
  # arguments passed to this program. A table is returned
  # with all command line elements in it, keyed by their name
  # and with a PValue as value.
  var args = parse(help)

  # Let's examine what we got using repr
  echo "A bit messy, but shows exactly what we got:\n\n"
  for k,v in args:
    echo "Parameter: " & k & " PValue: " & repr(v)

  # Or print out a bit cleaner
  echo "Parameters and their values more readable:"
  echo "r == " & $args["r"].asBool
  echo "test == " & $args["test"].asBool  # Long name is used as key, if its specified
  echo "n == " & $args["n"].asBool
  echo "N == " & $args["N"].asInt
  echo "f == " & $args["f"].asFloat
  echo "s == " & $args["s"].asString
  echo "x == " & $args["x"].asInt
  echo "X == " & $args["X"].asSeq.map(proc(x:PValue):int = x.asInt)
  echo "verbose == " & $args["verbose"].asSeq.len
  echo "out == " & $args["out"].filename
  echo "command == " & $args["command"].asString
  echo "file == " & $args["file"].asSeq.map(proc(x:PValue):string = x.filename)
