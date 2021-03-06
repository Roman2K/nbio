require 'nbio'
require 'socket'

client_thr = Thread.new do
  Thread.stop
  sock = TCPSocket.new('localhost', 1234)
  p sock.read
  sock.close
end

NBIO::Loop.run do |lo|
  server = TCPServer.new('localhost', 1234)
  client_thr.wakeup
  lo.monitor_read(server).
    catch { |err| p err: err }.
    then {
      sock = server.accept_nonblock
      sock.write_nonblock("#{Time.now}\n")
      sock.close
    }
end

client_thr.join
