module NBIO
  class Streams::BasicStream
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
end
