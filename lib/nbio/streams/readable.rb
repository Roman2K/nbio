module NBIO
  module Streams
    module Readable
      def initialize(*args)
        super
        @want << :read
        monitor_readability
      end

      include PipeSource

      def pause
        @paused = true
        self
      end

      def resume
        if @paused
          @paused = false
          if @monitor_readability_on_resume
            @monitor_readability_on_resume = false
            monitor_readability
          end
        end
        self
      end

    protected

      def process_opts!(opts)
        @maxlen = opts.delete(:maxlen)
      end

    private

      def monitor_readability(ev=:read)
        if @paused
          @monitor_readability_on_resume = true
          return
        end
        @lo.public_send("monitor_#{ev}", @io).
          catch { |err| @ev.emit(:err, err) }.
          then { handle_read_ready }
      end

      def handle_read_ready
        len = @maxlen || @io.to_io.stat.size.tap { |size|
          return handle_eof if size.zero?
        }
        begin
          data = @io.read_nonblock(len)
        rescue IO::WaitWritable
          monitor_readability(:write)
        rescue EOFError
          handle_eof
        rescue SystemCallError
          @ev.emit(:err, $!)
        else
          @ev.emit(:data, data)
          monitor_readability
        end
      end

      def handle_eof
        may_close(:read)
        @ev.emit(:end)
      end
    end
  end
end
