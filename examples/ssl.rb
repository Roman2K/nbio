require 'nbio'
require 'openssl'
require 'socket'

client_thr = Thread.new do
  Thread.current.abort_on_exception = true
  Thread.stop
  NBIO::Loop.run do |lo|
    key = OpenSSL::PKey::RSA.new(1024)
    ctx = OpenSSL::SSL::SSLContext.new.tap do |c|
      c.key = key
      c.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    sock = TCPSocket.new('localhost', 1234)
    ssock = OpenSSL::SSL::SSLSocket.new(sock, ctx)
    ssock.connect
    received = ""
    s = lo.rwstream(ssock, maxlen: 1024)
    s.write("Ping\n")
    s.ev.
      on(:err) { |err| p err: err }.
      on(:data) { |data| received << data }.
      on(:data) { |data| s.end("Pong\n") if received == "Ping\n" }.
      on(:data) { |data| p from_server: data, received: received }.
      on(:end) { p :end }.
      on(:drain) { p :drain }.
      on(:finish) { p :finish }
  end
end

key = OpenSSL::PKey::RSA.new(1024)
cert = OpenSSL::X509::Certificate.new.tap do |c|
  c.version = 1
  c.serial = 0
  c.subject = OpenSSL::X509::Name.parse("/DC=test/CN=Test")
  c.issuer = c.subject
  c.public_key = key.public_key
  c.not_before = Time.now
  c.not_after = c.not_before + 5*60
  c.sign(key, OpenSSL::Digest::SHA1.new)
end
ctx = OpenSSL::SSL::SSLContext.new.tap do |c|
  c.key = key
  c.cert = cert
end
server = TCPServer.new('0.0.0.0', 1234)
client_thr.wakeup
sserver = OpenSSL::SSL::SSLServer.new(server, ctx)
sock = sserver.accept
p from_client: sock.gets
sock.write("Ping\n")
p from_client: sock.gets
sock.write("Pong\n")
sock.close
server.close

client_thr.join
