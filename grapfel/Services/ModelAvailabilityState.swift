import Foundation
import FoundationModels

@Observable
@MainActor
final class ModelAvailabilityState {
    static let shared = ModelAvailabilityState()

    enum Status: Equatable {
        case checking
        case available
        case unavailable(Reason)
    }

    enum Reason: Equatable {
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady

        var title: String {
            switch self {
            case .deviceNotEligible:
                return "Apple Intelligence isn't supported"
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence is turned off"
            case .modelNotReady:
                return "On-device model not ready"
            }
        }

        var message: String {
            switch self {
            case .deviceNotEligible:
                return "Grapfel requires an Apple silicon Mac that supports Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Enable Apple Intelligence in System Settings, then return to Grapfel and try again."
            case .modelNotReady:
                return "macOS is still preparing the on-device model. Keep your Mac connected to power and try again shortly."
            }
        }
    }

    var status: Status = .checking
    var hotKeyRegistrationMessage: String?

    var isAvailable: Bool { status == .available }

    private init() {}

    func refresh() {
        let model = FoundationModelConfiguration.makeModel(
            permissiveContentTransformations: UserDefaults.standard.bool(
                forKey: UserDefaultsKey.permissiveContentTransformations
            )
        )
        switch model.availability {
        case .available:
            status = .available
        case .unavailable(.deviceNotEligible):
            status = .unavailable(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled):
            status = .unavailable(.appleIntelligenceNotEnabled)
        case .unavailable(.modelNotReady):
            status = .unavailable(.modelNotReady)
        case .unavailable:
            status = .unavailable(.modelNotReady)
        }
    }
}
