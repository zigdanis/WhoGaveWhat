import SwiftUI
import UIKit

struct CalendarDatePicker: UIViewRepresentable {
    let selectedDate: Date
    let onSelectDate: (Date) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UICalendarView {
        let calendarView = UICalendarView()
        calendarView.calendar = .autoupdatingCurrent
        calendarView.locale = .autoupdatingCurrent
        calendarView.timeZone = .autoupdatingCurrent
        calendarView.tintColor = UIColor(Color.recv)

        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        calendarView.selectionBehavior = selection
        let components = dayComponents(for: selectedDate)
        selection.setSelected(components, animated: false)
        calendarView.setVisibleDateComponents(components, animated: false)
        calendarView.accessibilityValue = selectedDayAccessibilityValue(components)
        context.coordinator.selectedComponents = components
        return calendarView
    }

    func updateUIView(_ calendarView: UICalendarView, context: Context) {
        context.coordinator.parent = self
        let components = dayComponents(for: selectedDate)
        guard context.coordinator.selectedComponents != components,
            let selection = calendarView.selectionBehavior as? UICalendarSelectionSingleDate
        else {
            return
        }
        selection.setSelected(components, animated: false)
        calendarView.setVisibleDateComponents(components, animated: false)
        calendarView.accessibilityValue = selectedDayAccessibilityValue(components)
        context.coordinator.selectedComponents = components
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UICalendarView,
        context: Context
    ) -> CGSize? {
        let proposedWidth = proposal.width ?? uiView.intrinsicContentSize.width
        let fittingSize = uiView.systemLayoutSizeFitting(
            CGSize(width: proposedWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: proposedWidth, height: fittingSize.height)
    }

    private func dayComponents(for date: Date) -> DateComponents {
        Calendar.autoupdatingCurrent.dateComponents([.era, .year, .month, .day], from: date)
    }

    private func selectedDayAccessibilityValue(_ components: DateComponents) -> String {
        String(format: "selected-day:%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    final class Coordinator: NSObject, UICalendarSelectionSingleDateDelegate {
        var parent: CalendarDatePicker
        var selectedComponents: DateComponents?

        init(parent: CalendarDatePicker) {
            self.parent = parent
        }

        func dateSelection(
            _ selection: UICalendarSelectionSingleDate,
            didSelectDate dateComponents: DateComponents?
        ) {
            guard let dateComponents,
                let date = Calendar.autoupdatingCurrent.date(from: dateComponents)
            else { return }
            selectedComponents = dateComponents
            parent.onSelectDate(date)
        }
    }
}
