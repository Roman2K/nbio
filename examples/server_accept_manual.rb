require 'nbio'
require 'socket'

host, port = 'localhost', 1234

NBIO::Loop.run do |lo|
  server = TCPServer.new(host, port)
  puts "Listening on #{host}:#{port}"
  accept_next = lambda do
    begin
      sock = server.accept_nonblock
    rescue IO::WaitReadable
      lo.monitor_read(server).
        catch { |err| p err: err }.
        then { accept_next.call }
    else
      accept_next.call
      sock.write_nonblock("#{Time.now}\n")
      sock.close
    end
  end
  accept_next.call
end
