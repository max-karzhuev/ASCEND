#!/usr/bin/env python3
"""Generate the checked-in, dependency-free multiplatform Xcode project."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[1]
project = root / 'ASCEND.xcodeproj'
project.mkdir(exist_ok=True)
def ident(value): return hashlib.sha256(value.encode()).hexdigest()[:24].upper()
def quoted(value): return json.dumps(str(value))
objects = []
def add(key, body): objects.append(f'{ident(key)} = {{ {body} }};')
sources = sorted([*root.glob('Sources/AscendCore/*.swift'), *root.glob('App/*.swift'), *root.glob('Shared/*.swift')])
resources = ['Assets.xcassets', 'Configuration/PrivacyInfo.xcprivacy']
refs, builds = [], []
for file in sources:
    relative = str(file.relative_to(root)); key = 'file:' + relative
    add(key, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(relative)}; sourceTree = "<group>";')
    add('build:' + relative, f'isa = PBXBuildFile; fileRef = {ident(key)};')
    refs.append(ident(key)); builds.append(ident('build:' + relative))
resource_builds = []
for relative in resources:
    filetype = 'folder.assetcatalog' if relative.endswith('xcassets') else 'text.xml'
    add('file:' + relative, f'isa = PBXFileReference; lastKnownFileType = {filetype}; path = {quoted(relative)}; sourceTree = "<group>";')
    add('build:' + relative, f'isa = PBXBuildFile; fileRef = {ident("file:" + relative)};')
    refs.append(ident('file:' + relative)); resource_builds.append(ident('build:' + relative))
add('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ASCEND.app; sourceTree = BUILT_PRODUCTS_DIR;')
widget_files = ['Widget/TodayWidget.swift', 'Widget/TasksWidget.swift', 'Widget/CalendarWidget.swift', 'App/CalendarGlow.swift', 'Shared/WidgetSummary.swift', 'Shared/ThemeColor.swift', 'Sources/AscendCore/Theme.swift']
widget_builds = []
for path in widget_files:
    if path.startswith('Widget/'):
        add('file:' + path, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(path)}; sourceTree = "<group>";')
        refs.append(ident('file:' + path))
    add('widgetbuild:' + path, f'isa = PBXBuildFile; fileRef = {ident("file:" + path)};')
    widget_builds.append(ident('widgetbuild:' + path))
add('widgetsource', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(widget_builds)},); runOnlyForDeploymentPostprocessing = 0;')
add('widgetproduct', 'isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; path = ASCENDWidget.appex; sourceTree = BUILT_PRODUCTS_DIR;')
add('widgetembed', f'isa = PBXBuildFile; fileRef = {ident("widgetproduct")}; platformFilters = (macos,); settings = {{ ATTRIBUTES = (RemoveHeadersOnCopy,); }};')
add('extensions', f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = ({ident("widgetembed")},); name = "Embed Mac Widget"; runOnlyForDeploymentPostprocessing = 0;')
add('widgetproxy', f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {ident("widgettarget")}; remoteInfo = ASCENDWidget;')
add('widgetdep', f'isa = PBXTargetDependency; platformFilters = (macos,); target = {ident("widgettarget")}; targetProxy = {ident("widgetproxy")};')
add('widgettarget', f'isa = PBXNativeTarget; buildConfigurationList = {ident("widgetconfiglist")}; buildPhases = ({ident("widgetsource")},); buildRules = (); dependencies = (); name = ASCENDWidget; productName = ASCENDWidget; productReference = {ident("widgetproduct")}; productType = "com.apple.product-type.app-extension";')
add('products', f'isa = PBXGroup; children = ({ident("product")},{ident("widgetproduct")},); name = Products; sourceTree = "<group>";')
add('rootgroup', f'isa = PBXGroup; children = ({",".join(refs)},{ident("products")},); sourceTree = "<group>";')
add('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
add('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(resource_builds)},); runOnlyForDeploymentPostprocessing = 0;')
add('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
configs = ['Debug', 'Release', 'CloudDebug', 'CloudRelease']
for name in configs:
    debug, cloud = 'Debug' in name, name.startswith('Cloud')
    settings = {
        'PRODUCT_NAME': 'ASCEND', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.example.ascend',
        'SWIFT_VERSION': '5.0', 'MACOSX_DEPLOYMENT_TARGET': '14.0', 'IPHONEOS_DEPLOYMENT_TARGET': '17.0',
        'SUPPORTED_PLATFORMS': 'macosx iphoneos iphonesimulator', 'SDKROOT': 'auto',
        'TARGETED_DEVICE_FAMILY': '1,2', 'SUPPORTS_MACCATALYST': 'NO', 'SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD': 'NO',
        'INFOPLIST_FILE': 'Configuration/Info.plist', 'GENERATE_INFOPLIST_FILE': 'NO',
        'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon', 'CODE_SIGN_STYLE': 'Automatic',
        'CODE_SIGN_ENTITLEMENTS': 'Configuration/Cloud.entitlements' if cloud else 'Configuration/Local.entitlements',
        'ASCEND_CLOUD_CONTAINER': 'iCloud.com.example.ascend' if cloud else '',
        'ASCEND_CLOUD_ENVIRONMENT': 'Development' if debug else 'Production',
        'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if debug else '-O',
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG' if debug else '',
        'DEBUG_INFORMATION_FORMAT': 'dwarf' if debug else 'dwarf-with-dsym',
        'ENABLE_HARDENED_RUNTIME': 'YES', 'COMBINE_HIDPI_IMAGES': 'YES',
        'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks @executable_path/../Frameworks',
        'ENABLE_USER_SCRIPT_SANDBOXING': 'YES', 'SWIFT_EMIT_LOC_STRINGS': 'YES',
    }
    settings['"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]"'] = 'Configuration/CloudMac.entitlements' if cloud else 'Configuration/LocalMac.entitlements'
    widget_settings = {
        'SDKROOT': 'macosx', 'SUPPORTED_PLATFORMS': 'macosx', 'PRODUCT_NAME': 'ASCENDWidget',
        'PRODUCT_BUNDLE_IDENTIFIER': '$(ASCEND_BASE_IDENTIFIER).widget', 'SWIFT_VERSION': '5.0',
        'INFOPLIST_FILE': 'Widget/Info.plist', 'MACOSX_DEPLOYMENT_TARGET': '14.0',
        'CODE_SIGN_ENTITLEMENTS': 'Widget/Widget.entitlements' if cloud else 'Widget/Local.entitlements', 'SKIP_INSTALL': 'YES',
        'APPLICATION_EXTENSION_API_ONLY': 'YES', 'ENABLE_HARDENED_RUNTIME': 'YES',
        'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/../Frameworks @executable_path/../../../../Frameworks'
    }
    widget_body = ' '.join(f'{k} = {quoted(v)};' for k,v in widget_settings.items())
    add('widgetconfig:' + name, f'isa = XCBuildConfiguration; buildSettings = {{ {widget_body} }}; name = {name};')
    settings['PRODUCT_BUNDLE_IDENTIFIER'] = '$(ASCEND_BASE_IDENTIFIER)'
    body = ' '.join(f'{k} = {quoted(v)};' for k,v in settings.items())
    add('targetconfig:' + name, f'isa = XCBuildConfiguration; buildSettings = {{ {body} }}; name = {name};')
    add('projectconfig:' + name, f'isa = XCBuildConfiguration; buildSettings = {{ ASCEND_BASE_IDENTIFIER = com.example.ascend; ASCEND_WIDGET_GROUP = {quoted("group.$(ASCEND_BASE_IDENTIFIER).widget" if cloud else "")}; CLANG_ENABLE_MODULES = YES; SWIFT_STRICT_CONCURRENCY = targeted; }}; name = {name};')
for prefix in ['target', 'project', 'widget']:
    add(prefix + 'configlist', f'isa = XCConfigurationList; buildConfigurations = ({",".join(ident(prefix + "config:" + c) for c in configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
add('target', f'isa = PBXNativeTarget; buildConfigurationList = {ident("targetconfiglist")}; buildPhases = ({ident("sources")},{ident("frameworks")},{ident("resources")},{ident("extensions")},); buildRules = (); dependencies = ({ident("widgetdep")},); name = ASCEND; productName = ASCEND; productReference = {ident("product")}; productType = "com.apple.product-type.application";')
add('project', f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1620; }}; buildConfigurationList = {ident("projectconfiglist")}; compatibilityVersion = "Xcode 15.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base,); mainGroup = {ident("rootgroup")}; productRefGroup = {ident("products")}; projectDirPath = ""; projectRoot = ""; targets = ({ident("target")},{ident("widgettarget")},);')
(project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 60; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {ident("project")}; }}\n')
schemes = project / 'xcshareddata/xcschemes'; schemes.mkdir(parents=True, exist_ok=True)
for name,debug,release in [('ASCEND','Debug','Release'),('ASCEND-Cloud','CloudDebug','CloudRelease')]:
    ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident("target")}" BuildableName="ASCEND.app" BlueprintName="ASCEND" ReferencedContainer="container:ASCEND.xcodeproj"/>'
    (schemes / (name + '.xcscheme')).write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1620" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="{debug}" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
<LaunchAction buildConfiguration="{debug}" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="{release}" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="{debug}"/><ArchiveAction buildConfiguration="{release}" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated ASCEND.xcodeproj with', len(sources), 'Swift source files')
