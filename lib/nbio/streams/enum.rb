module NBIO
  module Streams
    class Enum
      def initialize(enum)
        @enum = enum
        @ev = EventEmitter.new
        @paused = true
        @data_emitter = Fiber.new do
          @enum.each do |data|
            @ev.emit(:data, data)
            Fiber.yield if @paused
          end
          @ev.emit(:end)
        end
      end

      attr_reader :ev

      include PipeSource

      def pause
        @paused = true
        self
      end

      def resume
        if @paused
          @paused = false
          @data_emitter.resume
        end
        self
      end
    end
  end
end
