import SwiftUI

struct RefreshControl: View {
    let coordinateSpace: CoordinateSpace
    let onRefresh: () -> Void
    @State var isRefreshing: Bool = false
    @State var rotation: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            if geometry.frame(in: coordinateSpace).midY > 50 {
                Spacer()
                    .onAppear {
                        if !isRefreshing {
                            isRefreshing = true
                            withAnimation(.linear(duration: 0.5).repeatForever(autoreverses: false)) {
                                rotation = 360
                            }
                            onRefresh()
                        }
                    }
            }
            if isRefreshing {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color(hex: "00A896"))
                    .rotationEffect(.degrees(rotation))
                    .padding()
                    .background(Circle().fill(.ultraThinMaterial))
                    .shadow(color: Color.black.opacity(0.2), radius: 5)
                    .onDisappear {
                        isRefreshing = false
                        rotation = 0
                    }
            }
        }
        .frame(height: 0)
    }
}

struct RefreshControl_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            RefreshControl(coordinateSpace: .named("RefreshControl")) {
            }
            ForEach(0..<20) { i in
                Text("Item \(i)")
                    .padding()
            }
        }
        .coordinateSpace(name: "RefreshControl")
    }
}
