//
//  CameraController.swift
//  MiniCity
//
//  Camera system with Google Maps-style multitouch controls
//

import UIKit
import simd
import CoreHaptics

/// Gesture priority system:
/// 1. Pinch (zoom) - Highest priority, cancels other gestures when detected
/// 2. Rotation - Works simultaneously with pinch
/// 3. Two-finger pan (tilt) - Medium priority
/// 4. Single-finger pan - Lowest priority, cancelled by any two-finger gesture
class CameraController: NSObject {
    
    // MARK: - Camera Properties
    
    /// Current camera position in world space
    var position = SIMD3<Float>(50, 80, 120)
    
    /// Point the camera is looking at
    var target = SIMD3<Float>(0, 0, 0)
    
    /// Camera distance from target
    var distance: Float = 100.0 {
        didSet {
            distance = clamp(distance, min: minZoom, max: maxZoom)
        }
    }
    
    /// Camera rotation angles
    var yaw: Float = 45.0  // Rotation around Y axis (degrees)
    var pitch: Float = 45.0  // Tilt angle (degrees)
    
    // MARK: - Camera Constraints
    
    let minZoom: Float = 10.0
    let maxZoom: Float = 500.0
    let minPitch: Float = 15.0  // Prevent camera from going too low
    let maxPitch: Float = 85.0  // Prevent camera from going straight down
    let worldBounds = (min: SIMD2<Float>(-200, -200), max: SIMD2<Float>(200, 200))
    
    // MARK: - Momentum Properties
    
    private var panVelocity = SIMD2<Float>(0, 0)
    private var rotationVelocity: Float = 0
    private var zoomVelocity: Float = 0
    private var tiltVelocity: Float = 0
    
    private let friction: Float = 0.92  // Deceleration factor
    private let minVelocity: Float = 0.01  // Threshold to stop momentum
    
    // MARK: - Gesture State
    
    private var lastPanTranslation = CGPoint.zero
    private var lastPinchScale: CGFloat = 1.0
    private var lastRotationAngle: CGFloat = 0
    private var initialPitch: Float = 0
    private var gestureStartDistance: Float = 0
    
    private var isPanning = false
    private var isPinching = false
    private var isRotating = false
    private var isTilting = false
    
    // MARK: - Haptic Feedback
    
    private var hapticEngine: CHHapticEngine?
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)
    
    // MARK: - Animation
    
    private var displayLink: CADisplayLink?
    private var lastUpdateTime: CFTimeInterval = 0
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupHaptics()
        startAnimationLoop()
    }
    
    deinit {
        displayLink?.invalidate()
    }
    
    // MARK: - Setup
    
    private func setupHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
        } catch {
            print("Haptic engine failed to start: \(error)")
        }
    }
    
    private func startAnimationLoop() {
        displayLink = CADisplayLink(target: self, selector: #selector(updateAnimation))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    // MARK: - Gesture Handlers
    
    func handlePan(_ gesture: UIPanGestureRecognizer, in view: UIView) {
        // Check if this is a two-finger pan (tilt gesture)
        if gesture.numberOfTouches == 2 {
            handleTilt(gesture, in: view)
            return
        }
        
        // Single finger pan
        let translation = gesture.translation(in: view)
        
        switch gesture.state {
        case .began:
            isPanning = true
            lastPanTranslation = translation
            panVelocity = .zero
            
        case .changed:
            let delta = CGPoint(x: translation.x - lastPanTranslation.x,
                              y: translation.y - lastPanTranslation.y)
            
            // Convert screen space to world space movement (inverted for natural feel)
            let panSpeed: Float = distance * 0.002
            let right = getRightVector()
            let forward = getForwardVector()
            
            let worldDelta = right * Float(delta.x) * panSpeed +
                           forward * Float(-delta.y) * panSpeed
            
            // Apply movement with boundary checking
            let newTarget = SIMD2<Float>(target.x + worldDelta.x, target.z + worldDelta.z)
            target.x = clamp(newTarget.x, min: worldBounds.min.x, max: worldBounds.max.x)
            target.z = clamp(newTarget.y, min: worldBounds.min.y, max: worldBounds.max.y)
            
            // Check for boundary hit
            if newTarget.x != target.x || newTarget.y != target.z {
                triggerBoundaryHaptic()
            }
            
            // Update velocity for momentum
            panVelocity = SIMD2<Float>(Float(delta.x), Float(delta.y)) * panSpeed
            lastPanTranslation = translation
            
        case .ended, .cancelled:
            isPanning = false
            
        default:
            break
        }
    }
    
    func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            isPinching = true
            lastPinchScale = 1.0
            gestureStartDistance = distance
            zoomVelocity = 0
            
        case .changed:
            // Apply zoom with proper scaling
            let scale = Float(gesture.scale)
            distance = gestureStartDistance / scale
            distance = clamp(distance, min: minZoom, max: maxZoom)
            
            // Calculate velocity for momentum
            let scaleDelta = Float(gesture.scale - lastPinchScale)
            zoomVelocity = -scaleDelta * distance * 0.5
            
            // Check zoom boundaries
            if distance == minZoom || distance == maxZoom {
                triggerBoundaryHaptic()
            }
            
            lastPinchScale = gesture.scale
            updateCameraPosition()
            
        case .ended, .cancelled:
            isPinching = false
            
        default:
            break
        }
    }
    
    func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        switch gesture.state {
        case .began:
            isRotating = true
            lastRotationAngle = gesture.rotation
            rotationVelocity = 0
            
        case .changed:
            let rotationDelta = Float(gesture.rotation - lastRotationAngle)
            
            // Apply rotation
            yaw -= rotationDelta * 180.0 / .pi
            yaw = fmod(yaw + 360, 360)  // Keep within 0-360 range
            
            // Update velocity for momentum
            rotationVelocity = rotationDelta * 180.0 / .pi
            lastRotationAngle = gesture.rotation
            
            // Update camera position immediately
            updateCameraPosition()
            
        case .ended, .cancelled:
            isRotating = false
            
        default:
            break
        }
    }
    
    private func handleTilt(_ gesture: UIPanGestureRecognizer, in view: UIView) {
        let translation = gesture.translation(in: view)
        
        switch gesture.state {
        case .began:
            isTilting = true
            initialPitch = pitch
            tiltVelocity = 0
            
        case .changed:
            // Vertical translation controls pitch
            let tiltDelta = Float(translation.y) * 0.1
            pitch = clamp(initialPitch - tiltDelta, min: minPitch, max: maxPitch)
            
            // Calculate velocity
            if gesture.velocity(in: view).y != 0 {
                tiltVelocity = Float(gesture.velocity(in: view).y) * 0.01
            }
            
            // Haptic feedback at limits
            if pitch == minPitch || pitch == maxPitch {
                triggerBoundaryHaptic()
            }
            
        case .ended, .cancelled:
            isTilting = false
            
        default:
            break
        }
    }
    
    // MARK: - Animation Update
    
    @objc private func updateAnimation() {
        let currentTime = CACurrentMediaTime()
        let deltaTime = lastUpdateTime == 0 ? 1.0/60.0 : currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        
        // Apply momentum when no active gestures
        if !isPanning && !isPinching && !isRotating && !isTilting {
            applyMomentum(deltaTime: Float(deltaTime))
        }
        
        // Update camera position from spherical coordinates
        updateCameraPosition()
    }
    
    private func applyMomentum(deltaTime: Float) {
        // Pan momentum
        if length(panVelocity) > minVelocity {
            let right = getRightVector()
            let forward = getForwardVector()
            
            let worldDelta = right * panVelocity.x + forward * -panVelocity.y
            
            // Apply with rubber band effect at boundaries
            var newTarget = SIMD2<Float>(target.x + worldDelta.x, target.z + worldDelta.z)
            
            // Rubber band effect
            let rubberBandStrength: Float = 0.1
            if newTarget.x < worldBounds.min.x {
                newTarget.x = worldBounds.min.x - (worldBounds.min.x - newTarget.x) * rubberBandStrength
                panVelocity.x *= -0.5  // Bounce
            } else if newTarget.x > worldBounds.max.x {
                newTarget.x = worldBounds.max.x + (newTarget.x - worldBounds.max.x) * rubberBandStrength
                panVelocity.x *= -0.5
            }
            
            if newTarget.y < worldBounds.min.y {
                newTarget.y = worldBounds.min.y - (worldBounds.min.y - newTarget.y) * rubberBandStrength
                panVelocity.y *= -0.5
            } else if newTarget.y > worldBounds.max.y {
                newTarget.y = worldBounds.max.y + (newTarget.y - worldBounds.max.y) * rubberBandStrength
                panVelocity.y *= -0.5
            }
            
            // Smoothly pull back to bounds
            target.x = mix(target.x, clamp(newTarget.x, min: worldBounds.min.x, max: worldBounds.max.x), 0.1)
            target.z = mix(target.z, clamp(newTarget.y, min: worldBounds.min.y, max: worldBounds.max.y), 0.1)
            
            panVelocity *= friction
        } else {
            panVelocity = .zero
        }
        
        // Zoom momentum
        if abs(zoomVelocity) > minVelocity {
            distance += zoomVelocity
            zoomVelocity *= friction
        } else {
            zoomVelocity = 0
        }
        
        // Rotation momentum
        if abs(rotationVelocity) > minVelocity {
            yaw -= rotationVelocity
            rotationVelocity *= friction
        } else {
            rotationVelocity = 0
        }
        
        // Tilt momentum
        if abs(tiltVelocity) > minVelocity {
            pitch = clamp(pitch - tiltVelocity * deltaTime, min: minPitch, max: maxPitch)
            tiltVelocity *= friction
        } else {
            tiltVelocity = 0
        }
    }
    
    func updateCameraPosition() {
        // Convert spherical coordinates to Cartesian
        let pitchRad = pitch * .pi / 180.0
        let yawRad = yaw * .pi / 180.0
        
        let x = distance * cos(pitchRad) * cos(yawRad)
        let y = distance * sin(pitchRad)
        let z = distance * cos(pitchRad) * sin(yawRad)
        
        position = target + SIMD3<Float>(x, y, z)
    }
    
    // MARK: - Helper Methods
    
    func getRightVector() -> SIMD3<Float> {
        let yawRad = yaw * .pi / 180.0
        return SIMD3<Float>(cos(yawRad + .pi/2), 0, sin(yawRad + .pi/2))
    }
    
    func getForwardVector() -> SIMD3<Float> {
        let yawRad = yaw * .pi / 180.0
        return SIMD3<Float>(-sin(yawRad), 0, -cos(yawRad))
    }
    
    private func triggerBoundaryHaptic() {
        impactFeedback.prepare()
        impactFeedback.impactOccurred()
    }
    
    private func clamp<T: Comparable>(_ value: T, min: T, max: T) -> T {
        return Swift.max(min, Swift.min(max, value))
    }
    
    private func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
        return a * (1.0 - t) + b * t
    }
    
    // MARK: - Public Interface
    
    /// Get view matrix for rendering
    func getViewMatrix() -> matrix_float4x4 {
        return matrix_look_at_right_hand(eye: position, target: target, up: SIMD3<Float>(0, 1, 0))
    }
    
    /// Update camera animation (called per frame)
    func update(deltaTime: TimeInterval) {
        // Animation is handled by display link
    }
    
    /// Update aspect ratio for projection
    func updateAspectRatio(_ aspectRatio: Float) {
        // Store for projection calculations if needed
    }
    
    /// Convert screen position to world position
    func screenToWorld(_ screenPoint: CGPoint, in view: UIView) -> SIMD3<Float> {
        // Simplified screen to world conversion
        let normalizedX = Float(screenPoint.x / view.bounds.width) * 2.0 - 1.0
        let normalizedY = Float(screenPoint.y / view.bounds.height) * 2.0 - 1.0
        
        // Project onto ground plane (y = 0)
        return target + SIMD3<Float>(normalizedX * distance * 0.5, 0, normalizedY * distance * 0.5)
    }
    
    /// Setup gestures for a view
    func setupGestures(for view: UIView) {
        // Gestures are set up externally in GameViewController
    }
    
    /// Reset camera to default position
    func reset() {
        position = SIMD3<Float>(50, 50, 50)
        target = SIMD3<Float>(0, 0, 0)
        distance = 100.0
        yaw = 45.0
        pitch = 45.0
        
        // Clear all velocities
        panVelocity = .zero
        rotationVelocity = 0
        zoomVelocity = 0
        tiltVelocity = 0
    }
    
    /// Focus camera on specific point with animation
    func focusOn(point: SIMD3<Float>, animated: Bool = true) {
        if animated {
            // TODO: Implement smooth animation to target
            target = point
        } else {
            target = point
        }
        updateCameraPosition()
    }
    
    func getViewDirection() -> SIMD3<Float> {
        // Calculate view direction from camera to target
        let direction = normalize(target - position)
        return direction
    }
}

// Matrix math functions are now in MathExtensions.swift