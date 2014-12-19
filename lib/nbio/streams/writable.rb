module NBIO
  module Streams::Writable
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
