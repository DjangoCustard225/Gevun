import Foundation

let fm = FileManager.default
let infoData = try Data(contentsOf: URL(fileURLWithPath: "Gevun/Info.plist"))
let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
guard let appVersion = info?["CFBundleShortVersionString"] as? String,
    let buildNumber = info?["CFBundleVersion"] as? String
else {
    fatalError("Gevun/Info.plist must specify the app version and build number.")
}
let sources = (fm.enumerator(atPath: "Gevun")?.allObjects as? [String] ?? [])
    .filter { $0.hasSuffix(".swift") }.sorted().map { "Gevun/" + $0 }
func id(_ value: Int) -> String { String(format: "%024X", value) }
var objects: [String] = []
var sourceRefs: [String] = []
var sourceBuilds: [String] = []
for (index, path) in sources.enumerated() {
    let ref = id(100 + index), build = id(200 + index)
    objects.append(
        "\(ref) = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"\(path)\"; sourceTree = SOURCE_ROOT; };"
    )
    objects.append("\(build) = {isa = PBXBuildFile; fileRef = \(ref); };")
    sourceRefs.append(ref); sourceBuilds.append(build)
}
objects += [
    "\(id(300)) = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Gevun/Assets.xcassets; sourceTree = SOURCE_ROOT; };",
    "\(id(301)) = {isa = PBXBuildFile; fileRef = \(id(300)); };",
    "\(id(302)) = {isa = PBXFileReference; lastKnownFileType = text.xml; path = Gevun/PrivacyInfo.xcprivacy; sourceTree = SOURCE_ROOT; };",
    "\(id(303)) = {isa = PBXBuildFile; fileRef = \(id(302)); };",
    "\(id(304)) = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Gevun/Info.plist; sourceTree = SOURCE_ROOT; };",
    "\(id(305)) = {isa = PBXFileReference; explicitFileType = wrapper.application; path = Gevun.app; sourceTree = BUILT_PRODUCTS_DIR; };",
    "\(id(306)) = {isa = PBXBuildFile; productRef = \(id(401)); };",
    "\(id(400)) = {isa = XCLocalSwiftPackageReference; relativePath = Core; };",
    "\(id(401)) = {isa = XCSwiftPackageProductDependency; package = \(id(400)); productName = GevunCore; };",
    "\(id(1)) = {isa = PBXProject; attributes = {BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2700; }; buildConfigurationList = \(id(10)); compatibilityVersion = \"Xcode 14.0\"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = \(id(2)); productRefGroup = \(id(3)); projectDirPath = \"\"; projectRoot = \"\"; packageReferences = (\(id(400))); targets = (\(id(4))); };",
    "\(id(2)) = {isa = PBXGroup; children = (\((sourceRefs + [id(300), id(302), id(304), id(3)]).joined(separator: ","))); sourceTree = \"<group>\"; };",
    "\(id(3)) = {isa = PBXGroup; children = (\(id(305))); name = Products; sourceTree = \"<group>\"; };",
    "\(id(4)) = {isa = PBXNativeTarget; buildConfigurationList = \(id(11)); buildPhases = (\(id(5)), \(id(6)), \(id(7))); buildRules = (); dependencies = (); name = Gevun; packageProductDependencies = (\(id(401))); productName = Gevun; productReference = \(id(305)); productType = \"com.apple.product-type.application\"; };",
    "\(id(5)) = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (\(sourceBuilds.joined(separator: ","))); runOnlyForDeploymentPostprocessing = 0; };",
    "\(id(6)) = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (\(id(306))); runOnlyForDeploymentPostprocessing = 0; };",
    "\(id(7)) = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (\(id(301)), \(id(303))); runOnlyForDeploymentPostprocessing = 0; };",
    "\(id(10)) = {isa = XCConfigurationList; buildConfigurations = (\(id(12)), \(id(13))); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };",
    "\(id(11)) = {isa = XCConfigurationList; buildConfigurations = (\(id(14)), \(id(15))); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };",
]
for (index, name) in ["Debug", "Release"].enumerated() {
    let projectSettings =
        "CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 27.0; SWIFT_VERSION = 5.0; SWIFT_OPTIMIZATION_LEVEL = \"\(index == 0 ? "-Onone" : "-O")\"; DEBUG_INFORMATION_FORMAT = \"\(index == 0 ? "dwarf" : "dwarf-with-dsym")\"; \(index == 0 ? "SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;" : "")"
    let appSettings =
        "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor; CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = \(buildNumber); GENERATE_INFOPLIST_FILE = YES; INFOPLIST_FILE = Gevun/Info.plist; MARKETING_VERSION = \(appVersion); PRODUCT_BUNDLE_IDENTIFIER = app.gevun.music; PRODUCT_NAME = \"$(TARGET_NAME)\"; TARGETED_DEVICE_FAMILY = \"1,2\"; LD_RUNPATH_SEARCH_PATHS = \"$(inherited) @executable_path/Frameworks\"; INFOPLIST_KEY_UILaunchScreen_Generation = YES; INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES; INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = \"UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight\"; INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = \"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight\";"
    objects.append(
        "\(id(12 + index)) = {isa = XCBuildConfiguration; buildSettings = {\(projectSettings)}; name = \(name); };")
    objects.append(
        "\(id(14 + index)) = {isa = XCBuildConfiguration; buildSettings = {\(appSettings)}; name = \(name); };")
}
try fm.createDirectory(atPath: "Gevun.xcodeproj", withIntermediateDirectories: true)
let project =
    "// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n"
    + objects.joined(separator: "\n") + "\n}; rootObject = \(id(1)); }\n"
try project.write(toFile: "Gevun.xcodeproj/project.pbxproj", atomically: true, encoding: .utf8)
let schemeDir = "Gevun.xcodeproj/xcshareddata/xcschemes"
try fm.createDirectory(atPath: schemeDir, withIntermediateDirectories: true)
let reference =
    "<BuildableReference BuildableIdentifier=\"primary\" BlueprintIdentifier=\"\(id(4))\" BuildableName=\"Gevun.app\" BlueprintName=\"Gevun\" ReferencedContainer=\"container:Gevun.xcodeproj\"/>"
let scheme = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Scheme LastUpgradeVersion="2700" version="1.3">
    <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">\(reference)</BuildActionEntry></BuildActionEntries></BuildAction>
    <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
    <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">\(reference)</BuildableProductRunnable></LaunchAction>
    <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">\(reference)</BuildableProductRunnable></ProfileAction>
    <AnalyzeAction buildConfiguration="Debug"/>
    <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
    </Scheme>
    """
try scheme.write(toFile: schemeDir + "/Gevun.xcscheme", atomically: true, encoding: .utf8)
print("Generated Gevun.xcodeproj with \(sources.count) Swift files.")
