module NBIO
  class EventEmitter
    def initialize
      @on = {}
      @once = {}
    end

    def on(event, &cb)
      cb or raise ArgumentError, "cb missing"
      add(event, cb, @on)
      self
    end

    def once(event, &cb)
      cb or raise ArgumentError, "cb missing"
      add(event, cb, @once)
      self
    end

    def emit(event, *args)
      [*@on[event], *@once.delete(event)].each do |cb|
        cb.call(*args)
      end
      self
    end

  private

    def add(event, cb, cbs)
      (cbs[event] ||= []) << cb
    end
  end
end
