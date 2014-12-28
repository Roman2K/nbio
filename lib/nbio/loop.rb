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
      loop do
        handle_closes {
          io_arrays = @monitored.map(&:values)
          return if io_arrays.all?(&:empty?)
          IO.select(*io_arrays)
        }.flatten.each(&:handle_ready)
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
        @io.to_io
      end

      def handle_ready
        @registry.delete(@io)
        @promise.resolve(@io)
        nil
      end
    end
  end
end
