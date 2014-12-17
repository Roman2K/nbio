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
  written = 0
  write_next = lambda do
    begin
      written += sock.write_nonblock(str[written..-1])
    rescue IO::WaitWritable
      lo.monitor_write(sock).
        catch { |err| p err: err }.
        then { write_next.call }
    else
      if written < str.bytesize
        write_next.call 
      else
        sock.close
        server.close
      end
    end
  end
  write_next.call
end

client_thr.join
