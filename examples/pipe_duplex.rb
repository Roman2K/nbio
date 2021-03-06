require 'nbio'
require 'socket'

client_thr = Thread.new do
  Thread.current.abort_on_exception = true
  NBIO::Loop.run do |lo|
    Thread.stop
    transform = TCPSocket.new('localhost', 1234)
    input = NBIO::Streams::Enum.new(["Transform me!\n"])
    input | lo.rwstream(transform) | lo.wstream($stdout)
  end
end

TCPServer.open('localhost', 1234) do |server|
  client_thr.wakeup
  sock = server.accept
  result = sock.gets.tap { |input| p input: input }.upcase
  sock.write(result)
  sock.close
end

client_thr.join
