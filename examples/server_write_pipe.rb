require 'nbio'
require 'socket'

client_thr = Thread.new do
  Thread.stop
  TCPSocket.open('localhost', 1234) do |sock|
    while str = sock.read(128 * 1024)
      p str: str.bytesize
      sleep 0.02
    end
  end
end

NBIO::Loop.run do |lo|
  server = TCPServer.new('localhost', 1234)
  client_thr.wakeup
  sock = server.accept
  chunks = ['.' * (10 * 1024)] * 1024 + ['.']
  drained = 0
  NBIO::Streams::Enum.new(chunks) | lo.stream_w(sock).tap { |w|
    w.ev.on(:drain) {
      drained += 1
      p drained: drained if drained % 100 == 0
    }.on(:finish) {
      sock.close
      server.close
      p :finish
    }
  }
end

client_thr.join
