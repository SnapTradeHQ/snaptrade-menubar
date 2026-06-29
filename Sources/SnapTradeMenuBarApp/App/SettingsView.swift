import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: PortfolioViewModel

    var body: some View {
        Form {
            Picker("SnapTrade Environment", selection: $viewModel.config.environment) {
                ForEach(SnapTradeEnvironment.allCases) { environment in
                    Text(environment.label).tag(environment)
                }
            }

            TextField("OAuth Client ID", text: $viewModel.config.clientID)
                .textFieldStyle(.roundedBorder)

            Picker("Auth Flow", selection: $viewModel.config.authFlow) {
                ForEach(AuthFlow.allCases) { flow in
                    Text(flow.label).tag(flow)
                }
            }

            Picker("Redirect Mode", selection: $viewModel.config.redirectMode) {
                ForEach(RedirectMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            Picker("Refresh Interval", selection: $viewModel.config.refreshInterval) {
                ForEach(RefreshInterval.allCases) { interval in
                    Text(interval.label).tag(interval)
                }
            }

            TextField("Read-only scopes", text: $viewModel.config.scope)
                .textFieldStyle(.roundedBorder)

            DisclosureGroup("Endpoint Overrides") {
                TextField("OAuth Metadata URL", text: $viewModel.config.metadataEndpoint)
                    .textFieldStyle(.roundedBorder)
                TextField("Authorize URL", text: $viewModel.config.authorizationEndpoint)
                    .textFieldStyle(.roundedBorder)
                TextField("Token URL", text: $viewModel.config.tokenEndpoint)
                    .textFieldStyle(.roundedBorder)
                TextField("Revoke URL", text: $viewModel.config.revokeEndpoint)
                    .textFieldStyle(.roundedBorder)
                TextField("API Base URL", text: $viewModel.config.apiBaseURL)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
