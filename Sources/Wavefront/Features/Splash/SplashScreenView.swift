import SwiftUI
#if os(iOS)
import UIKit
#endif

/// A particle for the scatter animation
struct Particle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var scale: CGFloat
    var opacity: Double
    var rotation: Double
    var velocityX: CGFloat
    var velocityY: CGFloat
}

/// Splash screen with particle scatter animation
public struct SplashScreenView: View {
    @State private var phase: AnimationPhase = .black
    @State private var particles: [Particle] = []
    @State private var showContent = false
    @State private var screenSize: CGSize = .zero
    @Binding var isFinished: Bool
    
    let gridSize = 20
    
    enum AnimationPhase {
        case black
        case forming
        case scattering
        case revealing
    }
    
    public init(isFinished: Binding<Bool>) {
        self._isFinished = isFinished
    }
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Black background
                Color.black
                    .opacity(phase == .revealing ? 0 : 1)
                    .animation(.easeOut(duration: 0.5), value: phase)
                
                // Particles
                ForEach(particles) { particle in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 4, height: 4)
                        .scaleEffect(particle.scale)
                        .opacity(particle.opacity)
                        .rotationEffect(.degrees(particle.rotation))
                        .position(x: particle.x, y: particle.y)
                }
                
                // Logo text in center
                if phase == .forming {
                    Text("WAVEFRONT")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .opacity(phase == .forming ? 1 : 0)
                        .scaleEffect(phase == .forming ? 1 : 0.8)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: phase)
                }
            }
            .onAppear {
                screenSize = geometry.size
                startAnimation()
            }
        }
        .ignoresSafeArea()
    }
    
    private func startAnimation() {
        // Phase 2: Form particles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                phase = .forming
            }
            createFormingParticles()
        }
        
        // Phase 3: Scatter particles
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                phase = .scattering
            }
            scatterParticles()
        }
        
        // Phase 4: Reveal content
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.5)) {
                phase = .revealing
                showContent = true
            }
        }
        
        // Complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            isFinished = true
        }
    }
    
    private func createFormingParticles() {
        let centerX = screenSize.width / 2
        let centerY = screenSize.height / 2
        
        var newParticles: [Particle] = []
        let spacing: CGFloat = 15
        let rows = 8
        let cols = 12
        
        for row in 0..<rows {
            for col in 0..<cols {
                let offsetX = CGFloat(col - cols/2) * spacing
                let offsetY = CGFloat(row - rows/2) * spacing
                let startX = CGFloat.random(in: 0...screenSize.width)
                let startY = CGFloat.random(in: 0...screenSize.height)
                
                let particle = Particle(
                    x: startX,
                    y: startY,
                    scale: CGFloat.random(in: 0.3...1.0),
                    opacity: Double.random(in: 0.5...1.0),
                    rotation: Double.random(in: 0...360),
                    velocityX: (centerX + offsetX - startX) / 30,
                    velocityY: (centerY + offsetY - startY) / 30
                )
                newParticles.append(particle)
            }
        }
        
        particles = newParticles
        animateParticlesToCenter()
    }
    
    private func animateParticlesToCenter() {
        let centerX = screenSize.width / 2
        let centerY = screenSize.height / 2
        let spacing: CGFloat = 15
        let cols = 12
        
        var frameCount = 0
        let maxFrames = 30
        
        Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { timer in
            frameCount += 1
            
            if frameCount >= maxFrames {
                timer.invalidate()
                return
            }
            
            var updatedParticles: [Particle] = []
            
            for (index, var particle) in particles.enumerated() {
                let row = index / cols
                let col = index % cols
                
                let targetX = centerX + CGFloat(col - cols/2) * spacing
                let targetY = centerY + CGFloat(row - 4) * spacing
                
                particle.x += (targetX - particle.x) * 0.15
                particle.y += (targetY - particle.y) * 0.15
                particle.rotation += 5
                
                updatedParticles.append(particle)
            }
            
            particles = updatedParticles
        }
    }
    
    private func scatterParticles() {
        let centerX = screenSize.width / 2
        let centerY = screenSize.height / 2
        
        var frameCount = 0
        let maxFrames = 60
        
        Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { timer in
            frameCount += 1
            
            if frameCount >= maxFrames {
                timer.invalidate()
                particles = []
                return
            }
            
            var updatedParticles: [Particle] = []
            
            for var particle in particles {
                let dx = particle.x - centerX
                let dy = particle.y - centerY
                let distance = sqrt(dx * dx + dy * dy)
                
                if distance > 0 {
                    let speed: CGFloat = 15 + CGFloat.random(in: 0...10)
                    particle.x += (dx / distance) * speed
                    particle.y += (dy / distance) * speed
                }
                
                particle.opacity -= 0.02
                particle.scale *= 0.97
                particle.rotation += 10
                
                if particle.opacity > 0 {
                    updatedParticles.append(particle)
                }
            }
            
            particles = updatedParticles
        }
    }
}

#Preview {
    SplashScreenView(isFinished: .constant(false))
}
