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
        handle_closes {
          IO.select(rs, ws)
        }.zip([@reads, @writes]) { |ios, promises|
          ios.each do |io|
            next io.read_nonblock(io.stat.size) if io == @wakeup_r
            prom = promises.delete(io) \
              or raise "IO.select returned an unhandled IO"
            prom.resolve(io)
          end
        }
      end
    end

    def monitor_read(io)
      monitor(io, @reads)
    end

    def monitor_write(io)
      monitor(io, @writes)
    end

    def stream_r(io, maxlen=nil)
      Streams::Read.new(self, io, maxlen)
    end

    def stream_w(io)
      Streams::Write.new(self, io)
    end

    def accept(sock)
      Acceptor.new(self, sock)
    end

  private

    def monitor(io, promises)
      promises[io] ||= Promise.new.tap do
        @wakeup_w.write "\n"
      end
    end

    def handle_closes
      prom_maps = [@reads, @writes]
      begin
        yield
      rescue IOError
        prom_maps.each do |promises|
          promises.delete_if { |io,| io.closed? }
        end
        return [], [], [] if prom_maps.all?(&:empty?)
        retry
      end
    end
  end

  module Streams
    class Read
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

    class Write
      def initialize(io_loop, io)
        @io_loop = io_loop
        @io = io
        @buffer = Buffer.new
        @ev = EventEmitter.new
      end

      attr_reader :ev

      def write(data)
        raise "write after end" if @ended
        @buffer << data
        write_next
        @buffer.empty?
      end

      def end(data=nil)
        write(data) if data
        @ended = true
        if @buffer.empty?
          @ev.emit(:finish)
        else
          @ev.once(:drain) { @ev.emit(:finish) }
        end
        nil
      end

    private

      def write_next
        str = @buffer.to_s
        return @buffer.clear if str.empty?
        begin
          written = @io.write_nonblock(str)
        rescue IO::WaitWritable
          @io_loop.monitor_write(@io).
            catch { |err| @ev.emit(:err, err) }.
            then { write_next }
        else
          @buffer.trim(written)
          if @buffer.empty?
            @ev.emit(:drain)
          else
            write_next
          end
        end
      end
    end

    class Buffer
      def initialize
        @chunks = []
      end

      def <<(chunk)
        @chunks << chunk
        self
      end

      def clear
        @chunks.clear
        self
      end

      def to_s
        @chunks.join
      end

      def empty?
        @chunks.empty?
      end

      def trim(len)
        remaining = len
        while remaining > 0 && c = @chunks.first
          clen = c.bytesize
          if (keep = clen - remaining) > 0
            @chunks[0] = c.byteslice(-keep..-1)
            remaining -= (clen - keep)
          else
            @chunks.shift
            remaining -= clen
          end
        end
        self
      end
    end

    class Enum
      def initialize(enum)
        @enum = enum
        @ev = EventEmitter.new
        @paused = true
        @data_emitter = Fiber.new do
          @enum.each do |data|
            @ev.emit(:data, data)
            Fiber.yield if @paused
          end
          @ev.emit(:end)
        end
      end

      attr_reader :ev

      def pause
        @paused = true
        self
      end

      def resume
        if @paused
          @paused = false
          @data_emitter.resume
        end
        self
      end

      def |(w)
        @ev.on(:data) { |data|
          p :writing
          if !w.write(data)
            p :pause
            pause
            w.ev.once(:drain) { p :resume_drain; resume }
          end
        }.on(:end) {
          p :ended
          w.end
        }
        p :resume_init
        resume
      end
      alias pipe |
    end
  end

  class Acceptor
    def initialize(io_loop, sock)
      @io_loop = io_loop
      @sock = sock
      @ev = EventEmitter.new
      accept_next
    end

    attr_reader :ev

  private

    def accept_next
      sock = @sock.accept_nonblock
    rescue IO::WaitReadable
      @io_loop.monitor_read(@sock).
        catch { |err| @ev.emit(:err, err) }.
        then { accept_next }
    rescue SystemCallError
      @ev.emit(:err, $!)
    else
      accept_next
      @ev.emit(:conn, sock)
    end
  end

  class EventEmitter
    def initialize
      @on = {}
      @once = {}
    end

    def on(event, &cb)
      cb or raise ArgumentError, "cb missing"
      add(event, cb, @on)
      self
    end

    def once(event, &cb)
      cb or raise ArgumentError, "cb missing"
      add(event, cb, @once)
      self
    end

    def on2(event, &cb)
      on(event, &cb)
      Binding.new(self, event, cb)
    end

    def emit(event, *args)
      [@on, @once].each do |cbs|
        all = cbs[event] or next
        all.each { |cb| cb.call(*args) }
      end
      @once.delete(event)
      self
    end

    def remove_cb(event, cb)
      [@on, @once].each do |cbs|
        all = cbs[event] or next
        all.delete(cb)
      end
      self
    end

  private

    def add(event, cb, cbs)
      (cbs[event] ||= []) << cb
    end

    class Binding
      def initialize(ev, event, cb)
        @ev = ev
        @event = event
        @cb = cb
      end

      def remove
        @ev.remove_cb(@event, @cb)
        self
      end
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
