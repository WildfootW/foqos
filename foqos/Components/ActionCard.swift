import SwiftUI

struct ActionCard: View {
    let icon: String
    let count: Int?
    let label: String
    let color: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            action()
        }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(color)
                            .frame(width: 32, height: 32)
                        Image(systemName: icon)
                            .foregroundColor(.white)
                            .font(.system(size: 18))
                    }
                    Spacer()
                    if let count = count {
                        Text("\(count)")
                            .font(.title)
                            .fontWeight(.bold)
                    }
                }
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 0)
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.2)) {
                self.isPressed = pressing
            }
        }, perform: { })
    }
}

#Preview {
    ActionCard(icon: "hand.raised.fill", count: 8, label: "Blocked Apps", color: .red) {
        print("action card pressed")
    }
}

