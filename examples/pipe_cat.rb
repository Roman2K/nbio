require 'nbio'

NBIO::Loop.run do |lo|
  lo.stream_r($stdin) | lo.stream_w($stdout)
end
