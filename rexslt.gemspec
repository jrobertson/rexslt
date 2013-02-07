Gem::Specification.new do |s|
  s.name = 'rexslt'
  s.version = '0.4.1'
  s.summary = 'Rexslt is an XSLT processor written purely in Ruby'
  s.authors = ['James Robertson']
  s.files = Dir['lib/**/*.rb']
  s.add_dependency('rxfhelper')
  s.add_dependency('rexle') 
  s.signing_key = '../privatekeys/rexslt.pem'
  s.cert_chain  = ['gem-public_cert.pem']
end

