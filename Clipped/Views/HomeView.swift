import SwiftUI

/// The main view displayed when the app launches.
///
/// In SwiftUI, a `View` is a struct that conforms to the `View` protocol.
/// This is conceptually similar to a StatelessWidget in Flutter — it
/// describes what the UI should look like. SwiftUI handles the rendering.
///
/// `some View` is an "opaque return type." You don't need to specify the
/// exact type; Swift infers it. Think of it like returning `Widget` in
/// Flutter, but the compiler knows the concrete type at compile time.
struct HomeView: View {
    var body: some View {
        VStack(spacing: 12) {
            // Header
            Text("📋 Clipped")
                .font(.title)
            Text("Lightweight Clipboard Manager")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            // Status section
            VStack(alignment: .leading, spacing: 8) {
                Text("Status")
                    .font(.headline)
                Text("🟢 Ready")
                    .font(.body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            Spacer()

            // Footer note
            Text("Clipboard monitoring will be implemented in the next milestone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        // Sets the macOS window title in the title bar.
        .navigationTitle("Clipped")
    }
}

#Preview {
    HomeView()
}
