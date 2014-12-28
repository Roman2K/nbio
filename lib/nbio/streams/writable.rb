module NBIO
  module Streams::Writable
    def initialize(*args)
      super
      @want << :write
      @buffer = Buffer.new
    end

    def write(data)
      raise "write after end" if @ended
      @buffer << data
      monitor_writability
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

    def monitor_writability(ev=:write)
      @lo.public_send("monitor_#{ev}", @io).
        catch { |err| @ev.emit(:err, err) }.
        then { handle_write_ready }
    end

    def handle_write_ready
      str = @buffer.to_s
      return @buffer.clear if str.empty?
      begin
        written = @io.write_nonblock(str)
      rescue IO::WaitReadable
        monitor_writability(:read)
      rescue SystemCallError
        @ev.emit(:err, $!)
      else
        @buffer.trim(written)
        if @buffer.empty?
          @ev.emit(:drain)
        else
          monitor_writability
        end
      end
    end

    def finish
      may_close(:write)
      @ev.emit(:finish)
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
  end
end
