module NBIO
  ##
  # Any object can act as a source for a pipe (the left hand side of `|`, e.g.
  # `a` in `a | b`), provided it:
  #
  # * emits `:data` and `:end` events via #ev
  # * responds to #pause (returns self)
  # * responds to #resume (returns self)
  #
  # See Read and Enum.
  #
  module Streams::PipeSource
    # Can't use keyword args because `end` is a reserved keyword.
    def pipe(w, **opts)
      end_w = opts.delete(:end) { true }
      opts.empty? \
        or raise ArgumentError, "unhandled opts: %p" % opts.keys
      ev.on(:data) do |data|
        if !w.write(data)
          pause
          w.ev.once(:drain) { resume }
        end
      end
      ev.on(:end) { w.end } if end_w
      resume
      w
    end
    alias | pipe
  end
end
