require 'nbio'
require 'socket'

accepting = Thread::Queue.new

str = '.' * (1024 * 1024 * 2) + '.'

src_thr = Thread.new do
  TCPServer.open('localhost', 1234) do |server|
    accepting << nil
    sock = server.accept
    sock.write(str)
    sock.close
  end
end

dest_thr = Thread.new do
  TCPServer.open('localhost', 1235) do |server|
    accepting << nil
    sock = server.accept
    remaining = str.bytesize
    while str = sock.read(128 * 1024)
      sleep 0.02
      remaining -= str.bytesize
      p remaining: remaining
    end
    sock.close
  end
end

NBIO::Loop.run do |lo|
  2.times { accepting.shift }
  src = TCPSocket.open('localhost', 1234)
  dest = TCPSocket.open('localhost', 1235)
  lo.rstream(src) | lo.wstream(dest)
end

src_thr.join
dest_thr.join
