import CoreGraphics

/// Abstände im 4-Punkt-Raster.
public enum PaceSpacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let s: CGFloat = 12
    public static let m: CGFloat = 16
    public static let l: CGFloat = 24
    public static let xl: CGFloat = 32
    public static let xxl: CGFloat = 48
}

/// Eckenradien.
public enum PaceRadius {
    /// Kleine Kacheln und Zeilen innerhalb von Karten.
    public static let tile: CGFloat = 14
    public static let button: CGFloat = 14
    public static let card: CGFloat = 20
}
