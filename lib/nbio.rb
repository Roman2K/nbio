module NBIO
  autoload :Loop,         'nbio/loop'
  autoload :Acceptor,     'nbio/acceptor'
  autoload :EventEmitter, 'nbio/event_emitter'
  autoload :Promise,      'nbio/promise'

  module Streams
    autoload :BasicStream,  'nbio/streams/basic_stream'
    autoload :PipeSource,   'nbio/streams/pipe_source'
    autoload :Readable,     'nbio/streams/readable'
    autoload :Writable,     'nbio/streams/writable'
    autoload :Enum,         'nbio/streams/enum'

    class Read < BasicStream
      include Readable
    end

    class Write < BasicStream
      include Writable
    end

    class Duplex < BasicStream
      include Readable
      include Writable
    end
  end
end
