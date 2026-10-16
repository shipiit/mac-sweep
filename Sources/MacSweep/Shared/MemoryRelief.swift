import Darwin

enum MemoryRelief {
    /// Returns freed heap pages to macOS after big transient work (scans, decoding), so the
    /// footprint shown in Activity Monitor drops back down instead of staying at its peak.
    static func release() {
        malloc_zone_pressure_relief(nil, 0)
    }
}
