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

    def stream_r(io, **opts)
      Streams::Read.new(self, io, **opts)
    end

    def stream_w(io, **opts)
      Streams::Write.new(self, io, **opts)
    end
    
    def stream_rw(io, **opts)
      Streams::Duplex.new(self, io, **opts)
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
    class BasicStream
      def initialize(lo, io, **opts)
        @lo = lo
        @io = io
        @ev = EventEmitter.new
        process_opts! opts
        opts.empty? \
          or raise ArgumentError, "unhandled opts: %p" % opts.keys
      end

      attr_reader :ev

    protected

      def process_opts!(opts)
      end
    end

    ##
    # Any object can act as a source for a pipe (the left hand side of `|`, e.g.
    # `a` in `a | b`), provided it:
    #
    # * emits `:data` and `:end` events via #ev
    # * responds to #pause (returns self)
    # * responds to #resume (returns self)
    #
    # See Read and Enum.
    #
    module PipeSource
      # Can't use keyword args because `end` is a reserved keyword.
      def pipe(w, **opts)
        end_w = opts.delete(:end) { true }
        opts.empty? \
          or raise ArgumentError, "unhandled opts: %p" % opts.keys
        ev.on(:data) do |data|
          if !w.write(data)
            pause
            w.ev.once(:drain) { resume }
          end
        end
        ev.on(:end) { w.end } if end_w
        resume
        w
      end
      alias | pipe
    end

    module Readable
      def initialize(*args)
        super
        monitor_next
      end

      include PipeSource

      def pause
        @paused = true
        self
      end

      def resume
        if @paused
          @paused = false
          if @monitor_next_on_resume
            @monitor_next_on_resume = false
            monitor_next
          end
        end
        self
      end

    protected

      def process_opts!(opts)
        @maxlen = opts.delete(:maxlen)
      end

    private

      def monitor_next
        if @paused
          @monitor_next_on_resume = true
          return
        end
        @lo.monitor_read(@io).
          catch { |err| @ev.emit(:err, err) }.
          then { handle_read_ready }
      end

      def handle_read_ready
        len = @maxlen || @io.stat.size.tap { |size|
          return handle_eof if size.zero?
        }
        begin
          data = @io.read_nonblock(len)
        rescue IO::WaitReadable
          monitor_next
        rescue EOFError
          handle_eof
        rescue SystemCallError
          @ev.emit(:err, $!)
        else
          monitor_next
          @ev.emit(:data, data)
        end
      end

      def handle_eof
        begin
          @io.close_read
        rescue SystemCallError
          @ev.emit(:err, $!)
        end
        @ev.emit(:end)
      end
    end

    module Writable
      def initialize(*args)
        super
        @buffer = Buffer.new
      end

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
          finish
        else
          @ev.once(:drain) { finish }
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
          @lo.monitor_write(@io).
            catch { |err| @ev.emit(:err, err) }.
            then { write_next }
        rescue SystemCallError
          @ev.emit(:err, $!)
        else
          @buffer.trim(written)
          if @buffer.empty?
            @ev.emit(:drain)
          else
            write_next
          end
        end
      end

      def finish
        begin
          @io.close_write
        rescue SystemCallError
          @ev.emit(:err, $!)
        end
        @ev.emit(:finish)
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

    class Read < BasicStream
      include Readable
    end

    class Write < BasicStream
      include Writable
    end

    class Duplex < BasicStream
      include Readable
      include Writable
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

      include PipeSource

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
    end
  end

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

    def emit(event, *args)
      [*@on[event], *@once.delete(event)].each do |cb|
        cb.call(*args)
      end
      self
    end

  private

    def add(event, cb, cbs)
      (cbs[event] ||= []) << cb
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
