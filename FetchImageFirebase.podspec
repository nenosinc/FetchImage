Pod::Spec.new do |s|
  s.name             = 'FetchImageFirebase'
  s.version          = '1.7.1'
  s.summary          = 'Download images using Firebase and Nuke, display them in SwiftUI.'
  
  s.description      = 'FetchImageFirebase makes it easy to download images using Firebase and Nuke, and then display them in SwiftUI apps.'

  s.homepage         = 'https://github.com/nenosllc/FetchImage'
  s.screenshots     = 'https://user-images.githubusercontent.com/1567433/110703387-b6c58000-81c1-11eb-806d-8f9d97dc5ecd.png'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'neons, llc' => 'sam@nenos.one' }
  s.source           = { :git => 'https://github.com/nenosllc/FetchImage.git', :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/nenosapps'

  s.ios.deployment_target = '14.0'
  s.swift_versions   = '5.3'

  s.source_files = 'Source/**/*'
  
  s.frameworks = 'SwiftUI', 'Foundation'
  s.dependency 'Firebase/Storage'
  s.dependency 'Nuke'
end
