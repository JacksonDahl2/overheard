import OverheardKit
import SwiftUI

extension EnvironmentValues {
    /// How journal pages look (sizes, spacing, tilt, names). `.standard` unless the Debug-only
    /// Page tuning screen is trying out other values.
    @Entry var pageStyle: PageStyle = .standard
}
