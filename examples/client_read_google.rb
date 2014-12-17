require 'nbio'
require 'socket'

io_loop = NBIO::Loop.new
sock = TCPSocket.new('google.com', 80)
sock.write_nonblock("GET / HTTP/1.0\r\n\r\n")
io_loop.stream_r(sock).ev.
  on(:err) { |err| p err: err }.
  on(:data) { |chunk| p chunk: chunk }.
  on(:end) { sock.close }.
  on(:end) { p :end }
io_loop.run
