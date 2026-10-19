#!/usr/bin/env python3
"""Generate Todoshi.xcodeproj with app + WidgetKit extension linked to TodoshiCore."""

from __future__ import annotations

from pathlib import Path
import uuid

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "Todoshi.xcodeproj"
NEXUS_ROOT = ROOT / "Todoshi"
APP_ROOT = NEXUS_ROOT
WIDGETS_ROOT = ROOT / "TodoshiWidgets"

# Stable project-level IDs
PROJECT_ID = "A10000000000000000000001"
APP_TARGET_ID = "A10000000000000000000002"
APP_SOURCES_PHASE = "A10000000000000000000003"
APP_RESOURCES_PHASE = "A10000000000000000000004"
APP_FRAMEWORKS_PHASE = "A10000000000000000000005"
APP_PRODUCT_REF = "A10000000000000000000006"
PRODUCTS_GROUP = "A10000000000000000000008"
PACKAGE_REF = "A10000000000000000000009"
APP_NEXUSCORE_BUILD = "A1000000000000000000000A"
APP_NEXUSCORE_PROD = "A1000000000000000000000B"
PROJECT_BUILD_DEBUG = "A1000000000000000000000C"
PROJECT_BUILD_RELEASE = "A1000000000000000000000D"
APP_BUILD_DEBUG = "A1000000000000000000000E"
APP_BUILD_RELEASE = "A1000000000000000000000F"
CONFIG_LIST_PROJECT = "A10000000000000000000010"
CONFIG_LIST_APP = "A10000000000000000000011"

# Widget extension IDs
WIDGET_TARGET_ID = "A20000000000000000000001"
WIDGET_SOURCES_PHASE = "A20000000000000000000002"
WIDGET_FRAMEWORKS_PHASE = "A20000000000000000000003"
WIDGET_RESOURCES_PHASE = "A20000000000000000000004"
WIDGET_PRODUCT_REF = "A20000000000000000000005"
WIDGET_NEXUSCORE_BUILD = "A20000000000000000000006"
WIDGET_NEXUSCORE_PROD = "A20000000000000000000007"
WIDGET_BUILD_DEBUG = "A20000000000000000000008"
WIDGET_BUILD_RELEASE = "A20000000000000000000009"
CONFIG_LIST_WIDGET = "A2000000000000000000000A"
EMBED_PHASE = "A2000000000000000000000B"
EMBED_WIDGET_BUILD = "A2000000000000000000000C"
CONTAINER_PROXY = "A2000000000000000000000D"
TARGET_DEPENDENCY = "A2000000000000000000000E"
FIREBASE_COPY_PHASE = "GS0000000000000000000004"
FIREBASE_PLIST_REF = "GS0000000000000000000001"
FIREBASE_PLIST_EXAMPLE_REF = "GS0000000000000000000003"

# Firebase iOS SDK (app target only)
FIREBASE_PACKAGE_REF = "FB0000000000000000000001"
FIREBASE_CORE_PROD = "FB0000000000000000000002"
FIREBASE_AUTH_PROD = "FB0000000000000000000003"
FIREBASE_FIRESTORE_PROD = "FB0000000000000000000004"
FIREBASE_CORE_BUILD = "FB0000000000000000000005"
FIREBASE_AUTH_BUILD = "FB0000000000000000000006"
FIREBASE_FIRESTORE_BUILD = "FB0000000000000000000007"

# Google Sign-In (app target only)
GOOGLE_SIGNIN_PACKAGE_REF = "GS1000000000000000000001"
GOOGLE_SIGNIN_PROD = "GS1000000000000000000002"
GOOGLE_SIGNIN_BUILD = "GS1000000000000000000003"


def uid() -> str:
    return uuid.uuid4().hex[:24].upper()


def collect_swift(root: Path) -> list[str]:
    return sorted(
        str(p.relative_to(ROOT)).replace("\\", "/")
        for p in root.rglob("*.swift")
    )


APP_SOURCES = collect_swift(APP_ROOT)
WIDGET_SOURCES = collect_swift(WIDGETS_ROOT)
APP_RESOURCES = ["Todoshi/Resources/Assets.xcassets"]
APP_META = [
    "Todoshi/Resources/Info.plist",
    "Todoshi/Resources/Todoshi.entitlements",
    "Todoshi/Resources/GoogleService-Info.plist",
    "Todoshi/Resources/GoogleService-Info.plist.example",
]
WIDGET_META = [
    "TodoshiWidgets/Info.plist",
    "TodoshiWidgets/TodoshiWidgets.entitlements",
]

file_refs: dict[str, str] = {}
app_build_files: dict[str, str] = {}
widget_build_files: dict[str, str] = {}
group_ids: dict[str, str] = {}

for path in APP_SOURCES + WIDGET_SOURCES + APP_RESOURCES + APP_META + WIDGET_META:
    if path == "Todoshi/Resources/GoogleService-Info.plist":
        file_refs[path] = FIREBASE_PLIST_REF
    elif path == "Todoshi/Resources/GoogleService-Info.plist.example":
        file_refs[path] = FIREBASE_PLIST_EXAMPLE_REF
    else:
        file_refs[path] = uid()
for path in APP_SOURCES + APP_RESOURCES:
    app_build_files[path] = uid()
for path in WIDGET_SOURCES:
    widget_build_files[path] = uid()


def ensure_group(path: str) -> str:
    if path not in group_ids:
        group_ids[path] = uid()
    return group_ids[path]


group_children: dict[str, list[str]] = {}


def add_group_child(parent: str, marker: str) -> None:
    group_children.setdefault(parent, [])
    if marker not in group_children[parent]:
        group_children[parent].append(marker)


def register_tree(paths: list[str], root_name: str) -> None:
    ensure_group(root_name)
    group_children.setdefault(root_name, [])
    for path in paths:
        parts = Path(path).parts
        for i in range(1, len(parts)):
            parent = "/".join(parts[:i])
            child_path = "/".join(parts[: i + 1])
            ensure_group(parent)
            if i < len(parts) - 1:
                ensure_group(child_path)
                add_group_child(parent, f"G:{child_path}")
            else:
                add_group_child(parent, f"F:{path}")


register_tree(APP_SOURCES + APP_RESOURCES + APP_META, "Todoshi")
register_tree(WIDGET_SOURCES + WIDGET_META, "TodoshiWidgets")

# Ensure meta resources sit under Resources groups
for parent, paths in [
    ("Todoshi/Resources", APP_RESOURCES + APP_META),
    ("TodoshiWidgets", WIDGET_META),
]:
    ensure_group(parent)
    for path in paths:
        add_group_child(parent, f"F:{path}")

main_group = uid()
packages_group = uid()

group_objects = []
for gpath, gid in sorted(group_ids.items(), key=lambda x: x[0]):
    children_markers = group_children.get(gpath, [])
    child_lines = []
    for marker in children_markers:
        if marker.startswith("G:"):
            cp = marker[2:]
            child_lines.append(f"\t\t\t\t{group_ids[cp]} /* {Path(cp).name} */,")
        else:
            fp = marker[2:]
            child_lines.append(f"\t\t\t\t{file_refs[fp]} /* {Path(fp).name} */,")
    path_name = Path(gpath).name
    group_objects.append(
        f"""\t\t{gid} /* {path_name} */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{chr(10).join(child_lines)}
\t\t\t);
\t\t\tpath = {path_name};
\t\t\tsourceTree = "<group>";
\t\t}};"""
    )


def filetype(path: str) -> str:
    if path.endswith(".xcassets"):
        return "folder.assetcatalog"
    if path.endswith(".plist"):
        return "text.plist.xml"
    if path.endswith(".entitlements"):
        return "text.plist.entitlements"
    return "sourcecode.swift"


file_ref_entries = []
for path, fid in file_refs.items():
    name = Path(path).name
    file_ref_entries.append(
        f'\t\t{fid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {filetype(path)}; path = {name}; sourceTree = "<group>"; }};'
    )

build_file_entries = []
for path in APP_SOURCES:
    build_file_entries.append(
        f"\t\t{app_build_files[path]} /* {Path(path).name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[path]} /* {Path(path).name} */; }};"
    )
for path in APP_RESOURCES:
    build_file_entries.append(
        f"\t\t{app_build_files[path]} /* {Path(path).name} in Resources */ = {{isa = PBXBuildFile; fileRef = {file_refs[path]} /* {Path(path).name} */; }};"
    )
for path in WIDGET_SOURCES:
    build_file_entries.append(
        f"\t\t{widget_build_files[path]} /* {Path(path).name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[path]} /* {Path(path).name} */; }};"
    )
build_file_entries.append(
    f"\t\t{APP_NEXUSCORE_BUILD} /* TodoshiCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {APP_NEXUSCORE_PROD} /* TodoshiCore */; }};"
)
build_file_entries.append(
    f"\t\t{WIDGET_NEXUSCORE_BUILD} /* TodoshiCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {WIDGET_NEXUSCORE_PROD} /* TodoshiCore */; }};"
)
build_file_entries.append(
    f"\t\t{FIREBASE_CORE_BUILD} /* FirebaseCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {FIREBASE_CORE_PROD} /* FirebaseCore */; }};"
)
build_file_entries.append(
    f"\t\t{FIREBASE_AUTH_BUILD} /* FirebaseAuth in Frameworks */ = {{isa = PBXBuildFile; productRef = {FIREBASE_AUTH_PROD} /* FirebaseAuth */; }};"
)
build_file_entries.append(
    f"\t\t{FIREBASE_FIRESTORE_BUILD} /* FirebaseFirestore in Frameworks */ = {{isa = PBXBuildFile; productRef = {FIREBASE_FIRESTORE_PROD} /* FirebaseFirestore */; }};"
)
build_file_entries.append(
    f"\t\t{GOOGLE_SIGNIN_BUILD} /* GoogleSignIn in Frameworks */ = {{isa = PBXBuildFile; productRef = {GOOGLE_SIGNIN_PROD} /* GoogleSignIn */; }};"
)
build_file_entries.append(
    f"\t\t{EMBED_WIDGET_BUILD} /* TodoshiWidgets.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {WIDGET_PRODUCT_REF} /* TodoshiWidgets.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};"
)

app_source_entries = "\n".join(
    f"\t\t\t\t{app_build_files[p]} /* {Path(p).name} in Sources */," for p in APP_SOURCES
)
app_resource_entries = "\n".join(
    f"\t\t\t\t{app_build_files[p]} /* {Path(p).name} in Resources */," for p in APP_RESOURCES
)
widget_source_entries = "\n".join(
    f"\t\t\t\t{widget_build_files[p]} /* {Path(p).name} in Sources */," for p in WIDGET_SOURCES
)

pbxproj = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_file_entries)}
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		{CONTAINER_PROXY} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {PROJECT_ID} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {WIDGET_TARGET_ID};
			remoteInfo = TodoshiWidgets;
		}};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
		{EMBED_PHASE} /* Embed Foundation Extensions */ = {{
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				{EMBED_WIDGET_BUILD} /* TodoshiWidgets.appex in Embed Foundation Extensions */,
			);
			name = "Embed Foundation Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
		{APP_PRODUCT_REF} /* Todoshi.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Todoshi.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{WIDGET_PRODUCT_REF} /* TodoshiWidgets.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = TodoshiWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; }};
{chr(10).join(file_ref_entries)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{APP_FRAMEWORKS_PHASE} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{APP_NEXUSCORE_BUILD} /* TodoshiCore in Frameworks */,
				{FIREBASE_CORE_BUILD} /* FirebaseCore in Frameworks */,
				{FIREBASE_AUTH_BUILD} /* FirebaseAuth in Frameworks */,
				{FIREBASE_FIRESTORE_BUILD} /* FirebaseFirestore in Frameworks */,
				{GOOGLE_SIGNIN_BUILD} /* GoogleSignIn in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{WIDGET_FRAMEWORKS_PHASE} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{WIDGET_NEXUSCORE_BUILD} /* TodoshiCore in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{main_group} = {{
			isa = PBXGroup;
			children = (
				{group_ids['Todoshi']} /* Todoshi */,
				{group_ids['TodoshiWidgets']} /* TodoshiWidgets */,
				{PRODUCTS_GROUP} /* Products */,
				{packages_group} /* Packages */,
			);
			sourceTree = "<group>";
		}};
		{PRODUCTS_GROUP} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{APP_PRODUCT_REF} /* Todoshi.app */,
				{WIDGET_PRODUCT_REF} /* TodoshiWidgets.appex */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
		{packages_group} /* Packages */ = {{
			isa = PBXGroup;
			children = (
			);
			name = Packages;
			sourceTree = "<group>";
		}};
{chr(10).join(group_objects)}
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{APP_TARGET_ID} /* Todoshi */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {CONFIG_LIST_APP} /* Build configuration list for PBXNativeTarget "Todoshi" */;
			buildPhases = (
				{APP_SOURCES_PHASE} /* Sources */,
				{APP_FRAMEWORKS_PHASE} /* Frameworks */,
				{APP_RESOURCES_PHASE} /* Resources */,
				{FIREBASE_COPY_PHASE} /* Copy Firebase Config If Present */,
				{EMBED_PHASE} /* Embed Foundation Extensions */,
			);
			buildRules = (
			);
			dependencies = (
				{TARGET_DEPENDENCY} /* PBXTargetDependency */,
			);
			name = Todoshi;
			packageProductDependencies = (
				{APP_NEXUSCORE_PROD} /* TodoshiCore */,
				{FIREBASE_CORE_PROD} /* FirebaseCore */,
				{FIREBASE_AUTH_PROD} /* FirebaseAuth */,
				{FIREBASE_FIRESTORE_PROD} /* FirebaseFirestore */,
				{GOOGLE_SIGNIN_PROD} /* GoogleSignIn */,
			);
			productName = Todoshi;
			productReference = {APP_PRODUCT_REF} /* Todoshi.app */;
			productType = "com.apple.product-type.application";
		}};
		{WIDGET_TARGET_ID} /* TodoshiWidgets */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {CONFIG_LIST_WIDGET} /* Build configuration list for PBXNativeTarget "TodoshiWidgets" */;
			buildPhases = (
				{WIDGET_SOURCES_PHASE} /* Sources */,
				{WIDGET_FRAMEWORKS_PHASE} /* Frameworks */,
				{WIDGET_RESOURCES_PHASE} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = TodoshiWidgets;
			packageProductDependencies = (
				{WIDGET_NEXUSCORE_PROD} /* TodoshiCore */,
			);
			productName = TodoshiWidgets;
			productReference = {WIDGET_PRODUCT_REF} /* TodoshiWidgets.appex */;
			productType = "com.apple.product-type.app-extension";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{PROJECT_ID} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1700;
				LastUpgradeCheck = 1700;
				TargetAttributes = {{
					{APP_TARGET_ID} = {{
						CreatedOnToolsVersion = 17.0;
					}};
					{WIDGET_TARGET_ID} = {{
						CreatedOnToolsVersion = 17.0;
					}};
				}};
			}};
			buildConfigurationList = {CONFIG_LIST_PROJECT} /* Build configuration list for PBXProject "Todoshi" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				ar,
				Base,
			);
			mainGroup = {main_group};
			packageReferences = (
				{PACKAGE_REF} /* XCLocalSwiftPackageReference "Packages/TodoshiCore" */,
				{FIREBASE_PACKAGE_REF} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */,
				{GOOGLE_SIGNIN_PACKAGE_REF} /* XCRemoteSwiftPackageReference "GoogleSignIn-iOS" */,
			);
			productRefGroup = {PRODUCTS_GROUP} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{APP_TARGET_ID} /* Todoshi */,
				{WIDGET_TARGET_ID} /* TodoshiWidgets */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{APP_RESOURCES_PHASE} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{app_resource_entries}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{WIDGET_RESOURCES_PHASE} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXShellScriptBuildPhase section */
		{FIREBASE_COPY_PHASE} /* Copy Firebase Config If Present */ = {{
			isa = PBXShellScriptBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			inputPaths = (
				"$(SRCROOT)/Todoshi/Resources/GoogleService-Info.plist",
			);
			name = "Copy Firebase Config If Present";
			outputPaths = (
				"$(BUILT_PRODUCTS_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/GoogleService-Info.plist",
			);
			runOnlyForDeploymentPostprocessing = 0;
			shellPath = /bin/sh;
			shellScript = "FIREBASE_PLIST=\\"${{SRCROOT}}/Todoshi/Resources/GoogleService-Info.plist\\"\\nDEST=\\"${{BUILT_PRODUCTS_DIR}}/${{UNLOCALIZED_RESOURCES_FOLDER_PATH}}/GoogleService-Info.plist\\"\\nif [ -f \\"$FIREBASE_PLIST\\" ]; then\\n  cp \\"$FIREBASE_PLIST\\" \\"$DEST\\"\\nelse\\n  rm -f \\"$DEST\\"\\nfi\\n";
		}};
/* End PBXShellScriptBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{APP_SOURCES_PHASE} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{app_source_entries}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{WIDGET_SOURCES_PHASE} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{widget_source_entries}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		{TARGET_DEPENDENCY} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {WIDGET_TARGET_ID} /* TodoshiWidgets */;
			targetProxy = {CONTAINER_PROXY} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		{PROJECT_BUILD_DEBUG} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_OPTIMIZATION_LEVEL = 0;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
			}};
			name = Debug;
		}};
		{PROJECT_BUILD_RELEASE} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				SDKROOT = iphoneos;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_VERSION = 5.0;
				VALIDATE_PRODUCT = YES;
			}};
			name = Release;
		}};
		{APP_BUILD_DEBUG} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_ENTITLEMENTS = Todoshi/Resources/Todoshi.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 3;
				DEVELOPMENT_TEAM = "";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Todoshi/Resources/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 0.1.1;
				PRODUCT_BUNDLE_IDENTIFIER = com.anashamad.Todoshi;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_STRICT_CONCURRENCY = complete;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Debug;
		}};
		{APP_BUILD_RELEASE} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_ENTITLEMENTS = Todoshi/Resources/Todoshi.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 3;
				DEVELOPMENT_TEAM = "";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Todoshi/Resources/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 0.1.1;
				PRODUCT_BUNDLE_IDENTIFIER = com.anashamad.Todoshi;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_STRICT_CONCURRENCY = complete;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Release;
		}};
		{WIDGET_BUILD_DEBUG} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				APPLICATION_EXTENSION_API_ONLY = YES;
				CODE_SIGN_ENTITLEMENTS = TodoshiWidgets/TodoshiWidgets.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 3;
				DEVELOPMENT_TEAM = "";
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = TodoshiWidgets/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 0.1.1;
				PRODUCT_BUNDLE_IDENTIFIER = com.anashamad.Todoshi.widgets;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_STRICT_CONCURRENCY = complete;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Debug;
		}};
		{WIDGET_BUILD_RELEASE} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				APPLICATION_EXTENSION_API_ONLY = YES;
				CODE_SIGN_ENTITLEMENTS = TodoshiWidgets/TodoshiWidgets.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 3;
				DEVELOPMENT_TEAM = "";
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = TodoshiWidgets/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 0.1.1;
				PRODUCT_BUNDLE_IDENTIFIER = com.anashamad.Todoshi.widgets;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_STRICT_CONCURRENCY = complete;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{CONFIG_LIST_PROJECT} /* Build configuration list for PBXProject "Todoshi" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{PROJECT_BUILD_DEBUG} /* Debug */,
				{PROJECT_BUILD_RELEASE} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{CONFIG_LIST_APP} /* Build configuration list for PBXNativeTarget "Todoshi" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{APP_BUILD_DEBUG} /* Debug */,
				{APP_BUILD_RELEASE} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{CONFIG_LIST_WIDGET} /* Build configuration list for PBXNativeTarget "TodoshiWidgets" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{WIDGET_BUILD_DEBUG} /* Debug */,
				{WIDGET_BUILD_RELEASE} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
		{PACKAGE_REF} /* XCLocalSwiftPackageReference "Packages/TodoshiCore" */ = {{
			isa = XCLocalSwiftPackageReference;
			relativePath = Packages/TodoshiCore;
		}};
/* End XCLocalSwiftPackageReference section */

/* Begin XCRemoteSwiftPackageReference section */
		{FIREBASE_PACKAGE_REF} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */ = {{
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/firebase/firebase-ios-sdk";
			requirement = {{
				kind = upToNextMajorVersion;
				minimumVersion = 11.0.0;
			}};
		}};
		{GOOGLE_SIGNIN_PACKAGE_REF} /* XCRemoteSwiftPackageReference "GoogleSignIn-iOS" */ = {{
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/google/GoogleSignIn-iOS";
			requirement = {{
				kind = upToNextMajorVersion;
				minimumVersion = 8.0.0;
			}};
		}};
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		{APP_NEXUSCORE_PROD} /* TodoshiCore */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {PACKAGE_REF} /* XCLocalSwiftPackageReference "Packages/TodoshiCore" */;
			productName = TodoshiCore;
		}};
		{WIDGET_NEXUSCORE_PROD} /* TodoshiCore */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {PACKAGE_REF} /* XCLocalSwiftPackageReference "Packages/TodoshiCore" */;
			productName = TodoshiCore;
		}};
		{FIREBASE_CORE_PROD} /* FirebaseCore */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {FIREBASE_PACKAGE_REF} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */;
			productName = FirebaseCore;
		}};
		{FIREBASE_AUTH_PROD} /* FirebaseAuth */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {FIREBASE_PACKAGE_REF} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */;
			productName = FirebaseAuth;
		}};
		{FIREBASE_FIRESTORE_PROD} /* FirebaseFirestore */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {FIREBASE_PACKAGE_REF} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */;
			productName = FirebaseFirestore;
		}};
		{GOOGLE_SIGNIN_PROD} /* GoogleSignIn */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {GOOGLE_SIGNIN_PACKAGE_REF} /* XCRemoteSwiftPackageReference "GoogleSignIn-iOS" */;
			productName = GoogleSignIn;
		}};
/* End XCSwiftPackageProductDependency section */
	}};
	rootObject = {PROJECT_ID} /* Project object */;
}}
"""

PROJECT.mkdir(parents=True, exist_ok=True)
(PROJECT / "project.pbxproj").write_text(pbxproj)

# Ensure a shared scheme builds the app (and embeds widgets).
schemes = PROJECT / "xcshareddata" / "xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1700"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{APP_TARGET_ID}"
               BuildableName = "Todoshi.app"
               BlueprintName = "Todoshi"
               ReferencedContainer = "container:Todoshi.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{APP_TARGET_ID}"
            BuildableName = "Todoshi.app"
            BlueprintName = "Todoshi"
            ReferencedContainer = "container:Todoshi.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{APP_TARGET_ID}"
            BuildableName = "Todoshi.app"
            BlueprintName = "Todoshi"
            ReferencedContainer = "container:Todoshi.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
(schemes / "Todoshi.xcscheme").write_text(scheme)

print(f"Wrote {PROJECT / 'project.pbxproj'}")
print(f"App sources ({len(APP_SOURCES)}), widget sources ({len(WIDGET_SOURCES)})")
for s in APP_SOURCES:
    print(f"  app: {s}")
for s in WIDGET_SOURCES:
    print(f"  widget: {s}")
