require 'nbio'
require 'socket'

concurrency = 2

accepting = Thread::Queue.new
server_thr = Thread.new do
  Thread.current.abort_on_exception = true
  server = TCPServer.new('localhost', 1234)
  concurrency.times.map {
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

concurrency.times { accepting.shift }

lo = NBIO::Loop.new

concurrency.times do |n|
  sock = TCPSocket.new('localhost', 1234)
  lo.rstream(sock, maxlen: 20).ev.
    on(:err) { |err| p n => err }.
    on(:data) { |chunk| p n => chunk.bytesize }.
    on(:end) { sock.close }.
    on(:end) { p n => :end }
end

lo.run
server_thr.join
