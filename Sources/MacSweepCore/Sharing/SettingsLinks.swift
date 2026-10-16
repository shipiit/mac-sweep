import Foundation

/// System Settings deep links used by the sharing, wireless and backup audits.
public enum SettingsLinks {
    public static let sharing = "x-apple.systempreferences:com.apple.Sharing-Settings.extension"
    public static let firewall = "x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall"
    public static let wifi = "x-apple.systempreferences:com.apple.wifi-settings-extension"
    public static let bluetooth = "x-apple.systempreferences:com.apple.BluetoothSettings"
    public static let airDrop = "x-apple.systempreferences:com.apple.AirDrop-Handoff-Settings.extension"
    public static let timeMachine = "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension"

    public static let all = [sharing, firewall, wifi, bluetooth, airDrop, timeMachine]
}
