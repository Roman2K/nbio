require 'nbio'
require 'socket'

host = 'test-debit.free.fr'
path = '/1024.rnd'

NBIO::Loop.run do |io_loop|
  sock = TCPSocket.new(host, 80)
  sock.write_nonblock \
    "GET #{path} HTTP/1.0\r\n" \
    "Host: #{host}\r\n\r\n"
  io_loop.stream_r(sock).ev.
    on(:err) { |err| p err: err }.
    on(:data) { |chunk| p chunk: chunk.bytesize }.
    on(:end) { sock.close }.
    on(:end) { p :end }
end
