import Fabric
import Foundation
import Testing

@Suite("Plugin Info Update Keys")
struct PluginInfoUpdateKeysTests
{
    private static let publicEDKey = "LS/B4r0KdYmY6Xs1UiQ5dcKdUugyv6gu3z2GxESju6c="

    /// Writes a minimal `.fabricplugin` bundle with the given extra Info.plist
    /// keys to a fresh temporary folder, so Bundle's per-URL cache never
    /// returns a stale copy.
    private func makePluginInfo(updateKeys: [String: Any]) throws -> PluginInfo
    {
        let bundleURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: "UpdateKeysTest.fabricplugin", directoryHint: .isDirectory)
        let contentsURL = bundleURL.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        var infoDictionary: [String: Any] = [
            "CFBundleIdentifier": "graphics.fabric.tests.update-keys.\(UUID().uuidString)",
            "CFBundleName": "UpdateKeysTest",
            "CFBundlePackageType": "BNDL",
            "FabricPluginAPIVersion": PluginLoader.currentAPIVersion,
            "FabricPluginNodeClasses": ["UpdateKeysTest.Node"],
        ]
        infoDictionary.merge(updateKeys) { _, updateValue in updateValue }

        let plistData = try PropertyListSerialization.data(fromPropertyList: infoDictionary, format: .xml, options: 0)
        try plistData.write(to: contentsURL.appending(path: "Info.plist"))

        let bundle = try #require(Bundle(url: bundleURL))
        return try PluginInfo(bundle: bundle)
    }

    @Test("An https feed with a public key opts in")
    func httpsFeedWithPublicKeyOptsIn() throws
    {
        let pluginInfo = try makePluginInfo(updateKeys: [
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": Self.publicEDKey,
        ])

        #expect(pluginInfo.supportsUpdates)
        #expect(pluginInfo.updateFeedURL == URL(string: "https://example.com/appcast.xml"))
        #expect(pluginInfo.updatePublicEDKey == Self.publicEDKey)
    }

    @Test("An http feed does not opt in")
    func httpFeedDoesNotOptIn() throws
    {
        let pluginInfo = try makePluginInfo(updateKeys: [
            "SUFeedURL": "http://example.com/appcast.xml",
            "SUPublicEDKey": Self.publicEDKey,
        ])

        #expect(!pluginInfo.supportsUpdates)
        #expect(pluginInfo.updateFeedURL == nil)
        #expect(pluginInfo.updatePublicEDKey == nil)
    }

    @Test("A feed without a public key does not opt in")
    func feedWithoutPublicKeyDoesNotOptIn() throws
    {
        let pluginInfo = try makePluginInfo(updateKeys: [
            "SUFeedURL": "https://example.com/appcast.xml",
        ])

        #expect(!pluginInfo.supportsUpdates)
    }

    @Test("An empty public key does not opt in")
    func emptyPublicKeyDoesNotOptIn() throws
    {
        let pluginInfo = try makePluginInfo(updateKeys: [
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": "",
        ])

        #expect(!pluginInfo.supportsUpdates)
    }

    @Test("A malformed feed URL does not opt in")
    func malformedFeedURLDoesNotOptIn() throws
    {
        let pluginInfo = try makePluginInfo(updateKeys: [
            "SUFeedURL": "not a url",
            "SUPublicEDKey": Self.publicEDKey,
        ])

        #expect(!pluginInfo.supportsUpdates)
    }

    @Test("No update keys does not opt in")
    func noUpdateKeysDoesNotOptIn() throws
    {
        let pluginInfo = try makePluginInfo(updateKeys: [:])

        #expect(!pluginInfo.supportsUpdates)
        #expect(pluginInfo.automaticallyChecksForUpdates == nil)
    }

    @Test("SUEnableAutomaticChecks is read when present", arguments: [true, false])
    func automaticChecksIsRead(enabled: Bool) throws
    {
        let pluginInfo = try makePluginInfo(updateKeys: [
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": Self.publicEDKey,
            "SUEnableAutomaticChecks": enabled,
        ])

        #expect(pluginInfo.automaticallyChecksForUpdates == enabled)
    }
}
