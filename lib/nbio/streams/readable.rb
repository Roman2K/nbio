module NBIO
  module Streams
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
  end
end
