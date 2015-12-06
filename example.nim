import lapp, tables, sequtils
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
  assert(args.getOrDefault("r").asBool == false)
  assert(args.getOrDefault("test").asBool == false)
  assert(args.getOrDefault("n").asBool == false)
  assert(args.getOrDefault("N").asInt == 10)
  assert(args.getOrDefault("f").asFloat == 0.04)
  assert(args.getOrDefault("s").asString == "banana")
  assert(args.getOrDefault("x").asInt == 1)
  assert(args.getOrDefault("X").asSeq[0].asInt == 4)
  assert(args.getOrDefault("verbose").asSeq.len == 1)
  assert(args.getOrDefault("verbose").asSeq[0].asBool == false)
  assert(args.getOrDefault("out").filename == "stdout")
  assert(args.getOrDefault("command").asString == "cmd")
  assert(args.getOrDefault("file").asSeq.len == 1)
  assert(args.getOrDefault("file").asSeq[0].filename == "stdin")
else:

  # We call `parse` in lapp with our help text as argument.
  # This will both parse the help text above and then, parse the
  # arguments passed to this program. A table is returned
  # with all command line elements in it, keyed by their name
  # and with a ValueRef as value.
  var args = parse(help)

  # Let's examine what we got using repr
  echo "A bit messy, but shows exactly what we got:\n\n"
  for k,v in args:
    echo "Parameter: " & k & " ValueRef: " & repr(v)

  # Or print out a bit cleaner
  echo "Parameters and their values more readable:"
  echo "r == " & $args.getOrDefault("r").asBool
  echo "test == " & $args.getOrDefault("test").asBool  # Long name is used as key, if its specified
  echo "n == " & $args.getOrDefault("n").asBool
  echo "N == " & $args.getOrDefault("N").asInt
  echo "f == " & $args.getOrDefault("f").asFloat
  echo "s == " & $args.getOrDefault("s").asString
  echo "x == " & $args.getOrDefault("x").asInt
  echo "X == " & $args.getOrDefault("X").asSeq.map(proc(x: ValueRef): int = x.asInt)
  echo "verbose == " & $args.getOrDefault("verbose").asSeq.len
  echo "out == " & $args.getOrDefault("out").filename
  echo "command == " & $args.getOrDefault("command").asString
  echo "file == " & $args.getOrDefault("file").asSeq.map(proc(x: ValueRef): string = x.filename)
