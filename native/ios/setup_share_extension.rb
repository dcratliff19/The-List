# Run on your Mac: ruby setup_share_extension.rb YOUR_TEAM_ID app.yourname.thelist
require 'xcodeproj'
team, bundle = ARGV
abort 'Usage: ruby setup_share_extension.rb TEAM_ID app.yourname.thelist' unless team && bundle
Dir.chdir(__dir__)
project = Xcodeproj::Project.open('Runner.xcodeproj')
runner = project.targets.find { |t| t.name == 'Runner' }
share = project.targets.find { |t| t.name == 'ShareExtension' }
unless share
  share = project.new_target(:app_extension, 'ShareExtension', :ios, '15.0')
  group = project.main_group.new_group('ShareExtension', 'ShareExtension')
  source = group.new_file('ShareViewController.swift')
  group.new_file('Info.plist')
  group.new_file('ShareExtension.entitlements')
  share.add_file_references([source])
  runner.add_dependency(share)
  phase = runner.new_copy_files_build_phase('Embed Share Extension')
  phase.dst_subfolder_spec = '13'
  phase.add_file_reference(share.product_reference, true).settings = {'ATTRIBUTES' => ['RemoveHeadersOnCopy']}
end
[[runner, bundle], [share, bundle + '.share']].each do |target, identifier|
  target.build_configurations.each do |config|
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = identifier
    config.build_settings['DEVELOPMENT_TEAM'] = team
    config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
    config.build_settings['THE_LIST_APP_GROUP'] = 'group.' + bundle + '.shared'
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = target == runner ? 'Runner/Runner.entitlements' : 'ShareExtension/ShareExtension.entitlements'
    if target == share
      config.build_settings['INFOPLIST_FILE'] = 'ShareExtension/Info.plist'
      config.build_settings['SKIP_INSTALL'] = 'YES'
      config.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
      config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    end
  end
end
project.save
puts 'Share extension added. Enable the same App Group for both targets in Signing & Capabilities, then build on a device.'
