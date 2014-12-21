module NBIO
  class Acceptor
    def initialize(lo, sock)
      @lo = lo
      @sock = sock
      @ev = EventEmitter.new
      monitor_next
    end

    attr_reader :ev

  private

    def monitor_next
      @lo.monitor_read(@sock).
        catch { |err| @ev.emit(:err, err) }.
        then { handle_accept_ready }
    end

    def handle_accept_ready
      sock = @sock.accept_nonblock
    rescue SystemCallError
      @ev.emit(:err, $!)
    else
      monitor_next
      @ev.emit(:conn, sock)
    end
  end
end
