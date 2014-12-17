require 'nbio'
require 'socket'

NBIO::Loop.run do |lo|
  server = TCPServer.new('localhost', 1234)
  accept_next = lambda do
    begin
      sock = server.accept_nonblock
    rescue IO::WaitReadable
      lo.monitor_read(server).
        catch { |err| raise err }.
        then { accept_next.call }
    else
      accept_next.call
      sock.write_nonblock("#{Time.now}\n")
      sock.close
    end
  end
  accept_next.call
end
