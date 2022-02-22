Gem::Specification.new do |s|
  s.name = 'rexslt'
  s.version = '0.8.0'
  s.summary = 'Rexslt is an XSLT processor written purely in Ruby'
  s.authors = ['James Robertson']
  s.files = Dir['lib/rexslt.rb']
  s.add_runtime_dependency('rxfreader', '~> 0.2', '>=0.2.1')
  s.add_runtime_dependency('rexle', '~> 1.5', '>=1.5.14')
  s.signing_key = '../privatekeys/rexslt.pem'
  s.cert_chain  = ['gem-public_cert.pem']
  s.license = 'MIT'
  s.email = 'digital.robertson@gmail.com'
  s.homepage = 'https://github.com/jrobertson/rexslt'
  s.required_ruby_version = '>= 2.1.2'
end

