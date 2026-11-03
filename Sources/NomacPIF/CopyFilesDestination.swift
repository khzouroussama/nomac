/// A copy-files phase's `destinationSubfolder` by the `dstSubfolder` name Xcode 26 and later write
/// in place of `dstSubfolderSpec` (envelope-experiments `dst-subfolders`). xcodebuild aborts on
/// any other name, `AbsolutePath`, `JavaResources` and `XPCServices` included, `-list` too.
public enum CopyFilesDestination {
    public static let byName = [
        "None": "", "Wrapper": "$(WRAPPER_NAME)", "Executables": "$(EXECUTABLE_FOLDER_PATH)", "Resources": "$(UNLOCALIZED_RESOURCES_FOLDER_PATH)",
        "Frameworks": "$(FRAMEWORKS_FOLDER_PATH)", "SharedFrameworks": "$(SHARED_FRAMEWORKS_FOLDER_PATH)", "SharedSupport": "$(SHARED_SUPPORT_FOLDER_PATH)",
        "PlugIns": "$(PLUGINS_FOLDER_PATH)", "Product": "<builtProductsDir>",
    ]
}
