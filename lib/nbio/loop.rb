module NBIO
  class Loop
    def self.run
      new.tap { |lo| yield lo }.run
    end

    def initialize
      @monitored = [
        @reads = {},
        @writes = {},
      ]
      @wakeup_pipe = WakeupPipe.new
    end

    def run
      until @monitored.all?(&:empty?)
        arrays = @monitored.map(&:values).tap { |reads,| reads << @wakeup_pipe }
        handle_closes { IO.select(*arrays) }.
          flatten.
          each(&:handle_actionable)
      end
    end

    def monitor_read(io)
      monitor(io, @reads)
    end

    def monitor_write(io)
      monitor(io, @writes)
    end

    def rstream(io, **opts)
      Streams::Read.new(self, io, **opts)
    end

    def wstream(io, **opts)
      Streams::Write.new(self, io, **opts)
    end

    def rwstream(io, **opts)
      Streams::Duplex.new(self, io, **opts)
    end

    def accept(sock)
      Acceptor.new(self, sock)
    end

  private

    def monitor(io, registry)
      (registry[io] ||= MonitoredIO.new(io, registry).tap {
        @wakeup_pipe.wake_up
      }).promise
    end

    def handle_closes
      yield
    rescue IOError
      @monitored.each do |mios|
        mios.delete_if { |io,| io.closed? }
      end
      return [], [], [] if @monitored.all?(&:empty?)
      retry
    end

    class WakeupPipe
      def initialize
        @r, @w = IO.pipe
      end

      def to_io
        @r
      end

      def handle_actionable
        @r.read_nonblock(@r.stat.size)
        nil
      end

      def wake_up
        @w.write("\n")
        self
      end
    end

    class MonitoredIO
      def initialize(io, registry)
        @io = io
        @registry = registry
        @promise = Promise.new
      end

      attr_reader :promise

      def to_io
        @io
      end

      def handle_actionable
        @registry.delete(@io)
        @promise.resolve(@io)
        nil
      end
    end
  end
end
