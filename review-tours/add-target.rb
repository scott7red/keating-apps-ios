# Adds the "ReviewTour" UI-test target and a "ReviewTour" scheme to the shared Xcode project.
# It runs on the build Mac only, after tools/prepare.mjs, so the committed project and the
# App Store build never contain it. Nothing is added to the app itself: the tour drives the
# real app from outside, through the same taps a person makes.
#
#   ruby review-tours/add-target.rb <appId> [path/to/Review.storekit]
#
# With a .storekit file (the exam apps), the file goes into the test bundle, where the tour
# loads it with SKTestSession, and into the scheme's Run options.
require 'json'
require 'pathname'
require 'xcodeproj'

repo = Pathname.new(__dir__).parent.expand_path
app_id = ARGV[0] or abort('usage: ruby review-tours/add-target.rb <appId> [Review.storekit]')
storekit = ARGV[1]
app = JSON.parse(File.read(repo + 'apps.json')).find { |a| a['id'] == app_id } or abort("No app #{app_id} in apps.json")

proj_path = repo + 'native/ios/App/App.xcodeproj'
proj_dir = proj_path.dirname
project = Xcodeproj::Project.open(proj_path.to_s)
abort('The ReviewTour target is already in the project') if project.targets.any? { |t| t.name == 'ReviewTour' }
host = project.targets.find { |t| t.name == 'App' } or abort('No App target in the project')

target = project.new_target(:ui_test_bundle, 'ReviewTour', :ios, '16.0', nil, :swift)
# Swift links Foundation by itself; the gem's SDK-versioned framework path may not exist on this Xcode.
target.frameworks_build_phase.files.to_a.each(&:remove_from_project)
target.add_dependency(host)

src_dir = repo + 'review-tours/Sources'
group = project.main_group.new_group('ReviewTour', src_dir.relative_path_from(proj_dir).to_s)
sources = Dir[(src_dir + '*.swift').to_s].sort
abort("No tour sources in #{src_dir}") if sources.empty?
target.add_file_references(sources.map { |f| group.new_reference(File.basename(f)) })

if storekit
  sk = Pathname.new(storekit).expand_path
  abort("No StoreKit file at #{sk}") unless sk.file?
  sk_ref = project.main_group.new_reference(sk.relative_path_from(proj_dir).to_s)
  sk_ref.last_known_file_type = 'text'
  target.add_resources([sk_ref])
end

target.build_configurations.each do |config|
  s = config.build_settings
  %w[BUNDLE_LOADER TEST_HOST].each { |k| s.delete(k) }
  s['TEST_TARGET_NAME'] = 'App'
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['PRODUCT_BUNDLE_IDENTIFIER'] = "#{app['bundleId']}.ReviewTour"
  s['GENERATE_INFOPLIST_FILE'] = 'YES'
  s['SWIFT_VERSION'] = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
  s['TARGETED_DEVICE_FAMILY'] = '1'
  s['SDKROOT'] = 'iphoneos'
  s['DEVELOPMENT_TEAM'] = '9T738SVTZZ'
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks']
  s['SWIFT_EMIT_LOC_STRINGS'] = 'NO'
end

attributes = project.root_object.attributes
attributes['TargetAttributes'] ||= {}
attributes['TargetAttributes'][target.uuid] = { 'CreatedOnToolsVersion' => '16.0', 'TestTargetID' => host.uuid }
project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(host)
scheme.add_test_target(target)
scheme.set_launch_target(host)
scheme.test_action.build_configuration = 'Debug'
scheme.launch_action.build_configuration = 'Debug'
if storekit
  # The path is relative to the .xcodeproj, like the ones Xcode writes.
  rel = Pathname.new(storekit).expand_path.relative_path_from(proj_path).to_s
  scheme.launch_action.xml_element.add_element('StoreKitConfigurationFileReference', 'identifier' => rel)
end
scheme.save_as(proj_path.to_s, 'ReviewTour', true)

puts "Added ReviewTour (#{sources.map { |f| File.basename(f) }.join(', ')})#{storekit ? " with #{File.basename(storekit)}" : ''} for #{app['bundleId']}"
