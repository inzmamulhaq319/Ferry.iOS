//
//  ShutterSlider.swift
//  Ferrey
//
//  Created by Junaid on 27/08/2025.
//

import SwiftUI

struct ShutterSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    
    // Configuration
    private let trackHeight: CGFloat = 30
    private let thumbSize: CGFloat = 22
    private let tickCount = 16
    var cornerRadius: CGFloat = 10   // 🔹 configurable corner radius
    
    init(value: Binding<Double>, range: ClosedRange<Double>, cornerRadius: CGFloat = 10) {
        self._value = value
        self.range = range
        self.cornerRadius = cornerRadius
    }
    
    private var sliderPosition: CGFloat {
        guard range.lowerBound > 0, range.upperBound > 0, value > 0 else { return 0 }
        let logMin = log(range.lowerBound)
        let logMax = log(range.upperBound)
        guard (logMax - logMin) > 0 else { return 0 }
        let logValue = log(value)
        return CGFloat((logValue - logMin) / (logMax - logMin))
    }
    
    private func updateValue(fromDragLocation location: CGPoint, in geometry: GeometryProxy) {
        let newSliderPosition = min(max(0, location.x / (geometry.size.width - thumbSize)), 1)
        let logMin = log(range.lowerBound)
        let logMax = log(range.upperBound)
        let newLogValue = logMin + Double(newSliderPosition) * (logMax - logMin)
        self.value = exp(newLogValue)
    }
    
    private func formatValue(_ value: Double) -> String {
        let denominator = Int(1.0 / value)
        return "1/\(denominator)"
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Text("S \(formatValue(value))")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.white.opacity(0.25))
                    
                    // Tick Marks
                    HStack(spacing: 0) {
                        ForEach(0..<tickCount) { index in
                            Rectangle()
                                .fill(Color.white.opacity(0.5))
                                .frame(width: 1, height: trackHeight-12)
                            if index < tickCount - 1 {
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, (geometry.size.width - thumbSize) / CGFloat(tickCount - 1) / 2)
                    .frame(height: trackHeight)
                    
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.black.opacity(0.5))
                        .frame(width: thumbSize, height: trackHeight)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .stroke(Color.white, lineWidth: 1.5)
                        )
                        .offset(x: sliderPosition * (geometry.size.width - thumbSize))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { gestureValue in
                                    updateValue(fromDragLocation: gestureValue.location, in: geometry)
                                }
                        )
                }
            }
            .frame(height: trackHeight)
        }
    }
}
