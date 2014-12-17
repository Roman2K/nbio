require 'nbio'
require 'socket'

client_thr = Thread.new do
  Thread.stop
  sock = TCPSocket.new('localhost', 1234)
  while str = sock.read(128 * 1024)
    p str: str.bytesize
  end
  sock.close
end

NBIO::Loop.run do |lo|
  server = TCPServer.new('localhost', 1234)
  client_thr.wakeup
  sock = server.accept
  str = '.' * (1024 * 1024 + 1)
  w = lo.stream_w(sock)
  p write: w.write(str)
  w.ev.on(:err) { |err|
    p err: err
  }.on(:drain) {
    sock.close
    server.close
  }
end

client_thr.join
