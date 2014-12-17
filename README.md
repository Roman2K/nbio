# NBIO

Non-blocking IO event loop à la Node.js in pure Ruby, strictly based on core
select() and IO classes.

## Philosophy

* Written with plain simplicity, minimalism and code clarity in mind
  * No thread-safety to keep the code simple
  * No globals disguised as C static variables, Ruby constants or class
    variables
  * No questionable defaults or constant values
* Event loop run in the current Ruby green thread
  * No implicit singleton in the background (like EventMachine, Node.js, curl
    bindings, ...)
  * Thus, support for multiple simultaneous loops, one per thread
* API inspired by that of Node.js

## Status

* Raw draft - a playground at this point
* Missing unit tests and load tests
* Short term goal: good enough balance between blocking and non-blocking calls
  * Non-blocking where it matters most (accepts, reads and writes)
  * Blocking everywhere else (like opening/closing files and sockets)
