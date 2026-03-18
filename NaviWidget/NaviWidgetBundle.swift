import WidgetKit
import SwiftUI

@main
struct NaviWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        NaviWidget()
        if #available(iOS 16.2, *) {
            NaviLiveActivityWidget()
        }
    }
}
