// MARK: - LaunchAtLoginManager.swift
// SMAppService によるログイン時起動の管理。
// timeSlice/Sources/timeSliceApp/AppStateSupport.swift の LaunchAtLoginManager をそのまま移植。

import ServiceManagement

public enum LaunchAtLoginManager {
    public static func resolveServiceStatus() -> SMAppService.Status {
        SMAppService.mainApp.status
    }

    public static func resolveRegistrationState() -> Bool {
        resolveRegistrationState(serviceStatus: resolveServiceStatus())
    }

    public static func resolveRegistrationState(serviceStatus: SMAppService.Status) -> Bool {
        switch serviceStatus {
        case .enabled, .requiresApproval:
            return true
        default:
            return false
        }
    }

    public static func updateRegistration(isEnabled: Bool) throws {
        let currentValue = resolveRegistrationState()
        guard currentValue != isEnabled else {
            return
        }

        if isEnabled {
            try SMAppService.mainApp.register()
            return
        }
        try SMAppService.mainApp.unregister()
    }
}
