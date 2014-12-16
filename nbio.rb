require 'socket'

module NBIO
  class Promise
    def initialize
      @ev = EventEmitter.new
    end

    def then(&cb)
      @ev.on(:resolved, &cb)
      self
    end

    def catch(&cb)
      @ev.on(:rejected, &cb)
      self
    end

    def resolve(value)
      @ev.emit(:resolved, value)
      self
    end

    def reject(reason)
      @ev.emit(:rejected, reason)
      self
    end
  end

  class EventEmitter
    def initialize
      @callbacks = {}
    end

    def on(event, &cb)
      cb or raise ArgumentError, "cb missing"
      (@callbacks[event] ||= []) << cb
      self
    end

    def emit(event, *args)
      cbs = @callbacks[event] or return
      cbs.each { |cb| cb.call(*args) }
      self
    end
  end

  class Loop
    def initialize
      @reads = {}
      @writes = {}
      @wakeup_r, @wakeup_w = IO.pipe
    end

    def run
      until @reads.empty? && @writes.empty?
        rs = @reads.keys.tap { |a| a << @wakeup_r unless a.empty? }
        ws = @writes.keys
        IO.select(rs, ws).zip([@reads, @writes]) do |ios, promises|
          ios.each do |io|
            next io.read_nonblock(io.stat.size) if io == @wakeup_r
            prom = promises.delete(io) \
              or raise "IO.select returned an unhandled IO"
            prom.resolve(io)
          end
        end
      end
    end

    def monitor_read(io)
      @reads[io] ||= Promise.new.tap do
        @wakeup_w.write "\n"
      end
    end

    def read(sock, buflen=nil)
      ReadStream.new.tap do |s|
        monitor_next = lambda do
          monitor_read(sock).then do
            begin
              chunk = sock.read_nonblock(buflen || sock.stat.size)
            rescue EOFError
              s.close
            else
              s << chunk
              monitor_next.call
            end
          end
        end
        monitor_next.call
      end
    end
  end

  class ReadStream
    def initialize
      @ev = EventEmitter.new
    end

    attr_reader :ev

    def <<(data)
      @ev.emit(:data, data)
      self
    end

    def close
      @ev.emit(:close)
      nil
    end
  end
end

accepting = Thread::Queue.new
server_thr = Thread.new do
  Thread.current.abort_on_exception = true
  server = TCPServer.new('localhost', 1234)
  2.times.map do
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
  end.each(&:join)
end

2.times { accepting.shift }

io_loop = NBIO::Loop.new
sock = TCPSocket.new('localhost', 1234)
sock2 = TCPSocket.new('localhost', 1234)
io_loop.read(sock, 20).ev.on(:data) { |chunk|
  p a: chunk.bytesize
}.on(:close) {
  p a: :closed
}
io_loop.read(sock2, 20).ev.on(:data) { |chunk|
  p b: chunk.bytesize
}.on(:close) {
  p b: :closed
}

io_loop.run
server_thr.join
