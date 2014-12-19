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
end
