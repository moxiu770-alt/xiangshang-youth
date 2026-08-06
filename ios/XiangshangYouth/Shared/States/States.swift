import SwiftUI

struct LoadingStateView: View { var body: some View { VStack(spacing: 12) { ProgressView(); Text("正在加载数据…").foregroundStyle(AppTheme.muted) }.frame(maxWidth: .infinity, maxHeight: .infinity).padding() } }
struct EmptyStateView: View { let title: String; let detail: String; var body: some View { ContentUnavailableView(title, systemImage: "tray", description: Text(detail)) } }
struct ErrorStateView: View {
    let message: String
    let retry: () -> Void
    let dismiss: (() -> Void)?

    init(message: String, retry: @escaping () -> Void, dismiss: (() -> Void)? = nil) {
        self.message = message
        self.retry = retry
        self.dismiss = dismiss
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(AppTheme.danger)
            Text("加载失败").font(.headline)
            Text(message).font(.subheadline).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("重新加载", action: retry).buttonStyle(.borderedProminent)
                if let dismiss {
                    Button("关闭", action: dismiss).buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityElement(children: .contain)
    }
}
