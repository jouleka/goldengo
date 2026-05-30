require 'xcodeproj'
proj_path = File.join(__dir__, 'Goldengo.xcodeproj')
project = Xcodeproj::Project.new(proj_path)

# ── App target ────────────────────────────────────────────────────────────────
target = project.new_target(:application, 'Goldengo', :ios, '17.0')

# Source files
group = project.main_group.new_group('Goldengo', 'Goldengo')
Dir[File.join(__dir__, 'Goldengo', '*.swift')].each do |f|
  target.add_file_references([group.new_file(File.basename(f))])
end

# Build settings
target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.goldengo.app'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  config.build_settings['INFOPLIST_FILE'] = 'Goldengo/Info.plist'
  config.build_settings['SWIFT_VERSION'] = '6.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
end

# Project-level settings (avoid a stale SWIFT_VERSION = 5.0 fallback)
project.build_configurations.each do |config|
  config.build_settings['SWIFT_VERSION'] = '6.0'
end

# Local SPM package reference
ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
ref.relative_path = '..'
project.root_object.package_references << ref

# Product dependencies for app
%w[GoldengoFeatures GoldengoData GoldengoIntents GoldengoDesignSystem].each do |product|
  dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.product_name = product
  dep.package = ref
  target.package_product_dependencies << dep
end

# ── Widget extension target ───────────────────────────────────────────────────
widget_target = project.new_target(:app_extension, 'GoldengoWidgetExtension', :ios, '17.0')

widget_group = project.main_group.new_group('Widget', 'Widget')
Dir[File.join(__dir__, 'Widget', '*.swift')].each do |f|
  widget_target.add_file_references([widget_group.new_file(File.basename(f))])
end

widget_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.goldengo.app.widget'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  config.build_settings['INFOPLIST_FILE'] = 'Widget/Info.plist'
  config.build_settings['SWIFT_VERSION'] = '6.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
end

# SPM dependency: GoldengoData (SharedSummary lives there)
widget_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
widget_dep.product_name = 'GoldengoData'
widget_dep.package = ref
widget_target.package_product_dependencies << widget_dep

# App Group entitlements ── write entitlement files
app_group_id = 'group.com.goldengo.app'

app_entitlements = <<~XML
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
    <key>com.apple.security.application-groups</key>
    <array>
      <string>#{app_group_id}</string>
    </array>
  </dict>
  </plist>
XML

widget_entitlements = app_entitlements  # same App Group

app_ent_path = File.join(__dir__, 'Goldengo', 'Goldengo.entitlements')
widget_ent_path = File.join(__dir__, 'Widget', 'GoldengoWidgetExtension.entitlements')
File.write(app_ent_path, app_entitlements)
File.write(widget_ent_path, widget_entitlements)

target.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Goldengo/Goldengo.entitlements'
end

widget_target.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Widget/GoldengoWidgetExtension.entitlements'
end

# Add widget as dependency of the main app
target.add_dependency(widget_target)

# Embed the widget extension in the app (PlugIns destination = 13)
embed_phase = target.new_copy_files_build_phase('Embed App Extensions')
embed_phase.symbol_dst_subfolder_spec = :plug_ins
widget_ref = widget_target.product_reference
embed_file = embed_phase.add_file_reference(widget_ref)
embed_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

project.save
puts "Generated #{proj_path}"
