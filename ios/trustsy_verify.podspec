Pod::Spec.new do |s|
  s.name             = 'trustsy_verify'
  s.version          = '0.2.0'
  s.summary          = 'Flutter plugin for trustsy Verify: the native SwiftUI verification flow.'
  s.homepage         = 'https://trustsy.com'
  s.license          = { :type => 'Proprietary', :text => 'Copyright trustsy' }
  s.author           = 'trustsy'
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  # The native iOS SDK (sdk/ios/TrustsyVerify.podspec). Until it is published,
  # the app's Podfile points at it: pod 'TrustsyVerify', :path => '…/sdk/ios'.
  s.dependency 'TrustsyVerify', '~> 0.2'
  s.platform         = :ios, '17.0'
  s.swift_version    = '5.9'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
