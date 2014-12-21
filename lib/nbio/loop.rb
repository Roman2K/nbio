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
    end

    def run
      until @monitored.all?(&:empty?)
        io_arrays = @monitored.map(&:values)
        handle_closes { IO.select(*io_arrays) }.
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
      (registry[io] ||= MonitoredIO.new(io, registry)).promise
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
