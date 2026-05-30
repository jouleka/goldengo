require 'xcodeproj'
proj_path = File.join(__dir__, 'Goldengo.xcodeproj')
project = Xcodeproj::Project.new(proj_path)

target = project.new_target(:application, 'Goldengo', :ios, '17.0')

# Source files
group = project.main_group.new_group('Goldengo', 'Goldengo')
Dir[File.join(__dir__, 'Goldengo', '*.swift')].each do |f|
  target.add_file_references([group.new_file(File.basename(f))])
end

# Build settings
target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.goldengo.app'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['SWIFT_VERSION'] = '6.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
end

# Local SPM package reference
ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
ref.relative_path = '..'
project.root_object.package_references << ref

# Product dependencies
%w[GoldengoFeatures GoldengoData GoldengoIntents GoldengoDesignSystem].each do |product|
  dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.product_name = product
  dep.package = ref
  target.package_product_dependencies << dep
end

project.save
puts "Generated #{proj_path}"
