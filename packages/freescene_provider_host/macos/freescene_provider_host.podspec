Pod::Spec.new do |s|
  s.name = 'freescene_provider_host'
  s.version = '1.0.0'
  s.summary = 'FreeScene in-process provider module.'
  s.homepage = 'https://github.com/RarogVA/freescene'
  s.author = 'FreeScene'
  s.license = { :file => '../LICENSE' }
  s.source = { :path => '.' }
  s.source_files = 'freescene_provider_host/Sources/freescene_provider_host/**/*.{h,m}'
  s.public_header_files = 'freescene_provider_host/Sources/freescene_provider_host/include/*.h'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '13.0'
  s.frameworks = 'WebKit'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
