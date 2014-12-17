module NBIO
  class Loop
    def self.run
      new.tap { |lo| yield lo }.run
    end

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

    def read(io, maxlen=nil)
      ReadStream.new(self, io, maxlen)
    end
  end

  class ReadStream
    def initialize(io_loop, io, maxlen)
      @io_loop = io_loop
      @io = io
      @maxlen = maxlen
      @ev = EventEmitter.new
      monitor_next
    end

    attr_reader :ev

  private

    def monitor_next
      @io_loop.monitor_read(@io).
        catch { |err| @ev.emit(:err, err) }.
        then { handle_read_ready }
    end

    def handle_read_ready
      len = @maxlen || @io.stat.size.tap { |size|
        return @ev.emit(:end) if size.zero?
      }
      begin
        data = @io.read_nonblock(len)
      rescue IO::WaitReadable
        monitor_next
      rescue EOFError
        @ev.emit(:end)
      rescue SystemCallError
        @ev.emit(:err, $!)
      else
        monitor_next
        @ev.emit(:data, data)
      end
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
end
