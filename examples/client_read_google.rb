require 'nbio'
require 'socket'

lo = NBIO::Loop.new
sock = TCPSocket.new('google.com', 80)
sock.write_nonblock("GET / HTTP/1.0\r\n\r\n")
lo.rstream(sock).ev.
  on(:err) { |err| p err: err }.
  on(:data) { |chunk| p chunk: chunk }.
  on(:end) { sock.close }.
  on(:end) { p :end }
lo.run
