module NBIO
  class Streams::BasicStream
    def initialize(lo, io, **opts)
      @lo = lo
      @io = io
      @ev = EventEmitter.new
      process_opts! opts
      opts.empty? \
        or raise ArgumentError, "unhandled opts: %p" % opts.keys
      @want = []
    end

    attr_reader :ev

  protected

    def process_opts!(opts)
    end

    def may_close(dir)
      @want.delete(dir)
      try_io(:"close_#{dir}") if @io.respond_to?(:"close_#{dir}")
      try_io(:close) if @want.empty? && !@io.closed?
    end

  private

    def try_io(m,*a,&b)
      @io.public_send(m,*a,&b)
    rescue SystemCallError
      @ev.emit(:err, $!)
    end
  end
end
