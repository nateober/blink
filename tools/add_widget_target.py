#!/usr/bin/env python3
"""Add the BlinkWidgets widget-extension target (the Live Activity's lock-screen and
Dynamic Island UI) to Blink.xcodeproj and embed it in the Blink app.

Text-level and modelled on the BlinkFileProviderExtensionUI target, because the pbxproj
libraries either crash on this project or don't know its object version. Does nothing if
the target is already there. Verify with a real `xcodebuild build` afterwards.
"""
import hashlib
import re
import sys

PROJ = "Blink.xcodeproj/project.pbxproj"
NAME = "BlinkWidgets"
MODEL = "BlinkFileProviderExtensionUI"


def oid(label):
    return hashlib.sha1(f"{NAME}:{label}".encode()).hexdigest()[:24].upper()


def main():
    s = open(PROJ).read()
    if f"/* {NAME}.appex */" in s:
        print("BlinkWidgets target already present")
        return 0

    def find(pattern, what):
        m = re.search(pattern, s, re.S)
        if not m:
            sys.exit(f"could not find {what}")
        return m

    project_id = find(r"rootObject = (\w{24})", "the project object").group(1)
    main_group = find(r"mainGroup = (\w{24})", "the main group").group(1)
    app_target = find(r"\t\t(\w{24}) /\* Blink \*/ = \{\n\t\t\tisa = PBXNativeTarget;", "the Blink target").group(1)
    attrs_ref = find(r"(\w{24}) /\* FleetActivityAttributes\.swift \*/ = \{isa = PBXFileReference", "FleetActivityAttributes.swift").group(1)
    model_list = find(r'(\w{24}) /\* Build configuration list for PBXNativeTarget "%s" \*/ = \{' % MODEL, "the model target's configurations").group(1)
    model_cfgs = re.findall(r"(\w{24}) /\* (Debug|Release) \*/,",
                            find(r"\t\t%s /\* Build configuration list.*?\n\t\t\};" % model_list, "config list").group(0))
    app_cfg_list = find(r'(\w{24}) /\* Build configuration list for PBXNativeTarget "Blink" \*/ = \{', "Blink's configurations").group(1)
    app_cfg_ids = re.findall(r"(\w{24}) /\* (Debug|Release) \*/,",
                             find(r"\t\t%s /\* Build configuration list.*?\n\t\t\};" % app_cfg_list, "Blink config list").group(0))

    def app_setting(key):
        body = find(r"\t\t%s /\* \w+ \*/ = \{.*?\n\t\t\};" % app_cfg_ids[0][0], "Blink's build settings").group(0)
        m = re.search(r"\n\t\t\t\t%s = ([^;]+);" % key, body)
        return m.group(1) if m else None

    ids = {k: oid(k) for k in (
        "product", "bundle.swift", "widget.swift", "info.plist", "group",
        "bf.bundle", "bf.widget", "bf.attrs", "bf.embed",
        "sources", "frameworks", "resources", "target", "dependency", "proxy",
        "cfglist", "cfg.Debug", "cfg.Release")}

    def insert(section_end, text):
        nonlocal s
        marker = f"/* End {section_end} section */"
        if marker not in s:
            sys.exit(f"no {section_end} section")
        s = s.replace(marker, text + marker, 1)

    insert("PBXBuildFile",
           f"\t\t{ids['bf.bundle']} /* BlinkWidgetsBundle.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {ids['bundle.swift']} /* BlinkWidgetsBundle.swift */; }};\n"
           f"\t\t{ids['bf.widget']} /* FleetActivityWidget.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {ids['widget.swift']} /* FleetActivityWidget.swift */; }};\n"
           f"\t\t{ids['bf.attrs']} /* FleetActivityAttributes.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {attrs_ref} /* FleetActivityAttributes.swift */; }};\n"
           f"\t\t{ids['bf.embed']} /* {NAME}.appex in Embed PlugIns */ = {{isa = PBXBuildFile; fileRef = {ids['product']} /* {NAME}.appex */; platformFilter = ios; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n")
    insert("PBXContainerItemProxy",
           f"\t\t{ids['proxy']} /* PBXContainerItemProxy */ = {{\n\t\t\tisa = PBXContainerItemProxy;\n"
           f"\t\t\tcontainerPortal = {project_id} /* Project object */;\n\t\t\tproxyType = 1;\n"
           f"\t\t\tremoteGlobalIDString = {ids['target']};\n\t\t\tremoteInfo = {NAME};\n\t\t}};\n")
    insert("PBXFileReference",
           f"\t\t{ids['product']} /* {NAME}.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = {NAME}.appex; sourceTree = BUILT_PRODUCTS_DIR; }};\n"
           f"\t\t{ids['bundle.swift']} /* BlinkWidgetsBundle.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = BlinkWidgetsBundle.swift; sourceTree = \"<group>\"; }};\n"
           f"\t\t{ids['widget.swift']} /* FleetActivityWidget.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FleetActivityWidget.swift; sourceTree = \"<group>\"; }};\n"
           f"\t\t{ids['info.plist']} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};\n")
    insert("PBXFrameworksBuildPhase",
           f"\t\t{ids['frameworks']} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
    insert("PBXGroup",
           f"\t\t{ids['group']} /* {NAME} */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
           f"\t\t\t\t{ids['bundle.swift']} /* BlinkWidgetsBundle.swift */,\n"
           f"\t\t\t\t{ids['widget.swift']} /* FleetActivityWidget.swift */,\n"
           f"\t\t\t\t{ids['info.plist']} /* Info.plist */,\n"
           f"\t\t\t);\n\t\t\tpath = {NAME};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    insert("PBXNativeTarget",
           f"\t\t{ids['target']} /* {NAME} */ = {{\n\t\t\tisa = PBXNativeTarget;\n"
           f"\t\t\tbuildConfigurationList = {ids['cfglist']} /* Build configuration list for PBXNativeTarget \"{NAME}\" */;\n"
           f"\t\t\tbuildPhases = (\n\t\t\t\t{ids['sources']} /* Sources */,\n\t\t\t\t{ids['frameworks']} /* Frameworks */,\n\t\t\t\t{ids['resources']} /* Resources */,\n\t\t\t);\n"
           f"\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t);\n"
           f"\t\t\tname = {NAME};\n\t\t\tproductName = {NAME};\n"
           f"\t\t\tproductReference = {ids['product']} /* {NAME}.appex */;\n"
           f"\t\t\tproductType = \"com.apple.product-type.app-extension\";\n\t\t}};\n")
    insert("PBXResourcesBuildPhase",
           f"\t\t{ids['resources']} /* Resources */ = {{\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
    insert("PBXSourcesBuildPhase",
           f"\t\t{ids['sources']} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n"
           f"\t\t\t\t{ids['bf.bundle']} /* BlinkWidgetsBundle.swift in Sources */,\n"
           f"\t\t\t\t{ids['bf.widget']} /* FleetActivityWidget.swift in Sources */,\n"
           f"\t\t\t\t{ids['bf.attrs']} /* FleetActivityAttributes.swift in Sources */,\n"
           f"\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
    insert("PBXTargetDependency",
           f"\t\t{ids['dependency']} /* PBXTargetDependency */ = {{\n\t\t\tisa = PBXTargetDependency;\n"
           f"\t\t\ttarget = {ids['target']} /* {NAME} */;\n\t\t\ttargetProxy = {ids['proxy']} /* PBXContainerItemProxy */;\n\t\t}};\n")

    # Build configurations: the model extension's, pointed at this target's files and
    # carrying the app's own version numbers (an extension must match its app).
    cfg_text = ""
    for model_id, cfg_name in model_cfgs:
        body = find(r"\t\t%s /\* %s \*/ = \{.*?\n\t\t\};\n" % (model_id, cfg_name), "model config").group(0)
        body = body.replace(model_id, ids[f"cfg.{cfg_name}"], 1)
        body = body.replace(f"INFOPLIST_FILE = {MODEL}/Info.plist;", f"INFOPLIST_FILE = {NAME}/Info.plist;")
        body = body.replace(f'"$(BUNDLE_ID).{MODEL}"', f'"$(BUNDLE_ID).{NAME}"')
        for key in ("CURRENT_PROJECT_VERSION", "MARKETING_VERSION"):
            value = app_setting(key)
            if value:
                body = re.sub(r"(\n\t\t\t\t%s = )[^;]+;" % key, lambda m: m.group(1) + value + ";", body)
        body = body.replace("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;\n",
                            "\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;\n\t\t\t\tAPPLICATION_EXTENSION_API_ONLY = YES;\n", 1)
        cfg_text += body
    insert("XCBuildConfiguration", cfg_text)
    insert("XCConfigurationList",
           f"\t\t{ids['cfglist']} /* Build configuration list for PBXNativeTarget \"{NAME}\" */ = {{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n"
           + "".join(f"\t\t\t\t{ids[f'cfg.{n}']} /* {n} */,\n" for _, n in model_cfgs)
           + "\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Debug;\n\t\t};\n")

    def add_after(anchor, addition, what):
        nonlocal s
        if anchor not in s:
            sys.exit(f"could not place {what}")
        s = s.replace(anchor, anchor + addition, 1)

    # Embedded in the app next to the other extensions, built before it, listed with the
    # project's targets and products, and visible in the navigator.
    add_after(f"/* {MODEL}.appex in Embed PlugIns */,\n",
              f"\t\t\t\t{ids['bf.embed']} /* {NAME}.appex in Embed PlugIns */,\n", "the embed phase entry")
    model_dep = find(r"(\w{24}) /\* PBXTargetDependency \*/ = \{\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = \w{24} /\* %s \*/;" % MODEL, "the model dependency").group(1)
    add_after(f"\t\t\t\t{model_dep} /* PBXTargetDependency */,\n",
              f"\t\t\t\t{ids['dependency']} /* PBXTargetDependency */,\n", "the app's dependency")
    model_target = find(r"\t\t(\w{24}) /\* %s \*/ = \{\n\t\t\tisa = PBXNativeTarget;" % MODEL, "the model target").group(1)
    add_after(f"\t\t\t\t{model_target} /* {MODEL} */,\n",
              f"\t\t\t\t{ids['target']} /* {NAME} */,\n", "the project's target list")
    model_product = find(r"(\w{24}) /\* %s\.appex \*/ = \{isa = PBXFileReference" % MODEL, "the model product").group(1)
    add_after(f"\t\t\t\t{model_product} /* {MODEL}.appex */,\n",
              f"\t\t\t\t{ids['product']} /* {NAME}.appex */,\n", "the Products group entry")
    group_head = find(r"\t\t%s(?: /\* [^*]* \*/)? = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n" % main_group, "the main group").group(0)
    add_after(group_head, f"\t\t\t\t{ids['group']} /* {NAME} */,\n", "the navigator group")

    open(PROJ, "w").write(s)
    print(f"added {NAME} target ({ids['target']}), embedded in Blink ({app_target})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
