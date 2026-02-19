//
//  SmallThumbSlider.swift
//  Ferrey
//
//  Created by Junaid on 10/08/2025.
//


import SwiftUI

struct SmallThumbSlider: UIViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider(frame: .zero)
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.thumbTintColor = .white
        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = .gray
        slider.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        slider.setThumbImage(makeSmallThumb(), for: .normal)
        return slider
    }

    func updateUIView(_ uiView: UISlider, context: Context) {
        uiView.value = Float(value)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    class Coordinator: NSObject {
        @Binding var value: Double
        init(value: Binding<Double>) { _value = value }
        @objc func valueChanged(_ sender: UISlider) {
            value = Double(sender.value)
        }
    }

    private func makeSmallThumb() -> UIImage {
        let size: CGFloat = 20 // knob size
        UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), false, 0.0)
        UIColor.white.setFill()
        UIBezierPath(ovalIn: CGRect(origin: .zero, size: CGSize(width: size, height: size))).fill()
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return image
    }
}
