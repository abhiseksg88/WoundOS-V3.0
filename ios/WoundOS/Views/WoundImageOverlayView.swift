import UIKit
import simd

// MARK: - Wound Image Overlay View

/// Displays the captured wound image with overlay rendering:
/// - Green wound boundary outline
/// - Length (L) and Width (W) measurement lines crossing the wound
/// - Labels at measurement endpoints
///
/// Matches the clinical wound measurement screenshot with bright green
/// boundary and diagonal L/W crosshair lines.
final class WoundImageOverlayView: UIView {

    // MARK: - Configuration

    struct Configuration {
        /// Boundary points in normalized image coordinates (0...1)
        let boundaryPoints: [CGPoint]
        /// Length line endpoints in normalized coordinates
        let lengthEndpoints: (CGPoint, CGPoint)?
        /// Width line endpoints in normalized coordinates
        let widthEndpoints: (CGPoint, CGPoint)?
        /// Formatted length value (e.g., "6.54 cm")
        let lengthText: String?
        /// Formatted width value (e.g., "5.42 cm")
        let widthText: String?
        /// The wound image
        let image: UIImage?
    }

    // MARK: - Appearance

    private let boundaryColor = WOColors.boundaryGreen
    private let boundaryWidth: CGFloat = 2.5
    private let measurementLineColor = WOColors.boundaryGreen
    private let measurementLineWidth: CGFloat = 1.5
    private let labelFont = UIFont.systemFont(ofSize: 14, weight: .bold)
    private let labelBackgroundColor = UIColor.black.withAlphaComponent(0.5)

    // MARK: - Subviews

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let overlayLayer = CAShapeLayer()
    private let lengthLineLayer = CAShapeLayer()
    private let widthLineLayer = CAShapeLayer()

    private let lengthLabelStart = WOMeasurementLabel()
    private let lengthLabelEnd = WOMeasurementLabel()
    private let widthLabelStart = WOMeasurementLabel()
    private let widthLabelEnd = WOMeasurementLabel()

    private var config: Configuration?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        clipsToBounds = true
        layer.cornerRadius = WOSpacing.cardCornerRadius
        layer.cornerCurve = .continuous
        backgroundColor = .black

        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Boundary outline
        overlayLayer.fillColor = UIColor.clear.cgColor
        overlayLayer.strokeColor = boundaryColor.cgColor
        overlayLayer.lineWidth = boundaryWidth
        overlayLayer.lineJoin = .round
        overlayLayer.lineCap = .round
        layer.addSublayer(overlayLayer)

        // Length measurement line
        lengthLineLayer.fillColor = UIColor.clear.cgColor
        lengthLineLayer.strokeColor = measurementLineColor.cgColor
        lengthLineLayer.lineWidth = measurementLineWidth
        lengthLineLayer.lineDashPattern = nil
        layer.addSublayer(lengthLineLayer)

        // Width measurement line
        widthLineLayer.fillColor = UIColor.clear.cgColor
        widthLineLayer.strokeColor = measurementLineColor.cgColor
        widthLineLayer.lineWidth = measurementLineWidth
        widthLineLayer.lineDashPattern = nil
        layer.addSublayer(widthLineLayer)

        // Endpoint labels
        for label in [lengthLabelStart, lengthLabelEnd, widthLabelStart, widthLabelEnd] {
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
    }

    // MARK: - Configure

    func configure(with config: Configuration) {
        self.config = config
        imageView.image = config.image

        lengthLabelStart.text = "L"
        lengthLabelEnd.text = "L"
        widthLabelStart.text = "W"
        widthLabelEnd.text = "W"

        setNeedsLayout()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let config = config else { return }

        let viewSize = bounds.size
        guard viewSize.width > 0, viewSize.height > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Draw boundary
        if config.boundaryPoints.count >= 3 {
            let path = UIBezierPath()
            let first = denormalize(config.boundaryPoints[0], in: viewSize)
            path.move(to: first)
            for i in 1..<config.boundaryPoints.count {
                path.addLine(to: denormalize(config.boundaryPoints[i], in: viewSize))
            }
            path.close()
            overlayLayer.path = path.cgPath
        }

        // Draw length line
        if let endpoints = config.lengthEndpoints {
            let start = denormalize(endpoints.0, in: viewSize)
            let end = denormalize(endpoints.1, in: viewSize)

            let path = UIBezierPath()
            path.move(to: start)
            path.addLine(to: end)
            lengthLineLayer.path = path.cgPath

            positionLabel(lengthLabelStart, at: start, in: viewSize)
            positionLabel(lengthLabelEnd, at: end, in: viewSize)
            lengthLabelStart.isHidden = false
            lengthLabelEnd.isHidden = false
        } else {
            lengthLineLayer.path = nil
            lengthLabelStart.isHidden = true
            lengthLabelEnd.isHidden = true
        }

        // Draw width line
        if let endpoints = config.widthEndpoints {
            let start = denormalize(endpoints.0, in: viewSize)
            let end = denormalize(endpoints.1, in: viewSize)

            let path = UIBezierPath()
            path.move(to: start)
            path.addLine(to: end)
            widthLineLayer.path = path.cgPath

            positionLabel(widthLabelStart, at: start, in: viewSize)
            positionLabel(widthLabelEnd, at: end, in: viewSize)
            widthLabelStart.isHidden = false
            widthLabelEnd.isHidden = false
        } else {
            widthLineLayer.path = nil
            widthLabelStart.isHidden = true
            widthLabelEnd.isHidden = true
        }

        CATransaction.commit()
    }

    // MARK: - Helpers

    private func denormalize(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    private func positionLabel(_ label: WOMeasurementLabel, at point: CGPoint, in viewSize: CGSize) {
        let labelSize = label.intrinsicContentSize
        var x = point.x - labelSize.width / 2
        var y = point.y - labelSize.height / 2

        // Keep labels within bounds
        x = max(4, min(x, viewSize.width - labelSize.width - 4))
        y = max(4, min(y, viewSize.height - labelSize.height - 4))

        label.frame = CGRect(x: x, y: y, width: labelSize.width, height: labelSize.height)
    }
}

// MARK: - Measurement Endpoint Label

/// Small circular label ("L" or "W") placed at measurement line endpoints.
private final class WOMeasurementLabel: UILabel {

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = UIFont.systemFont(ofSize: 13, weight: .bold)
        textColor = .white
        textAlignment = .center
        backgroundColor = UIColor.black.withAlphaComponent(0.55)
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 24, height: 24)
    }
}
