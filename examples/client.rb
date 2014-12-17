require 'nbio'
require 'socket'

accepting = Thread::Queue.new
server_thr = Thread.new do
  Thread.current.abort_on_exception = true
  server = TCPServer.new('localhost', 1234)
  2.times.map {
    Thread.new do
      Thread.current.abort_on_exception = true
      accepting << nil
      sock = server.accept
      5.times do
        sock.puts Time.now
        sleep 0.05
      end
      sock.close
    end
  }.each(&:join)
end

2.times { accepting.shift }

io_loop = NBIO::Loop.new
sock = TCPSocket.new('localhost', 1234)
sock2 = TCPSocket.new('localhost', 1234)
io_loop.read(sock, 20).ev.
  on(:err) { |err| p err: err }.
  on(:data) { |chunk| p a: chunk.bytesize }.
  on(:end) { p a: :end }
io_loop.read(sock2, 20).ev.
  on(:err) { |err| p err: err }.
  on(:data) { |chunk| p b: chunk.bytesize }.
  on(:end) { p b: :end }
io_loop.run
server_thr.join
