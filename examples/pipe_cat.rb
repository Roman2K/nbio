require 'nbio'

NBIO::Loop.run do |lo|
  lo.rstream($stdin) | lo.wstream($stdout)
end
