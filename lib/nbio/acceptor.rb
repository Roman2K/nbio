module NBIO
  class Acceptor
    def initialize(lo, sock)
      @lo = lo
      @sock = sock
      @ev = EventEmitter.new
      accept_next
    end

    attr_reader :ev

  private

    def accept_next
      sock = @sock.accept_nonblock
    rescue IO::WaitReadable
      @lo.monitor_read(@sock).
        catch { |err| @ev.emit(:err, err) }.
        then { accept_next }
    rescue SystemCallError
      @ev.emit(:err, $!)
    else
      accept_next
      @ev.emit(:conn, sock)
    end
  end
end
