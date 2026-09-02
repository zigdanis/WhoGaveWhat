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
        context.coordinator.selectedComponents = components
        return calendarView
    }

    func updateUIView(_ calendarView: UICalendarView, context: Context) {
        context.coordinator.parent = self
        let components = dayComponents(for: selectedDate)
        guard context.coordinator.selectedComponents != components,
              let selection = calendarView.selectionBehavior as? UICalendarSelectionSingleDate else {
            return
        }
        selection.setSelected(components, animated: false)
        context.coordinator.selectedComponents = components
    }

    private func dayComponents(for date: Date) -> DateComponents {
        Calendar.autoupdatingCurrent.dateComponents([.era, .year, .month, .day], from: date)
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
                  let date = Calendar.autoupdatingCurrent.date(from: dateComponents) else { return }
            selectedComponents = dateComponents
            parent.onSelectDate(date)
        }
    }
}
