//
//  GameViewController.swift
//  MiniCity
//
//  Created by Griffin on 8/9/25.
//

import UIKit
import MetalKit

class GameViewController: UIViewController, UIGestureRecognizerDelegate {

    var gameController: CityGameController!
    var mtkView: MTKView!
    var cameraController: CameraController!
    
    // Simple camera test variables
    var cameraAngle: Float = 0

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = view as? MTKView else {
            print("View of Gameview controller is not an MTKView")
            return
        }
        
        self.mtkView = mtkView

        // Select the device to render with.  We choose the default device
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported")
            return
        }
        
        mtkView.device = defaultDevice
        mtkView.backgroundColor = UIColor(red: 0.53, green: 0.81, blue: 0.98, alpha: 1.0) // Sky blue

        // Initialize the new game controller
        gameController = CityGameController()
        gameController.setup(with: mtkView)
        
        // Get camera controller from game controller
        cameraController = gameController.cameraController
        
        // Setup simple gesture recognizers
        setupSimpleGestures()
        
        // Enable keyboard for simulator testing
        setupKeyboardControls()
        
        print("GameViewController setup complete with Metal engine")
        print("View size: \(view.bounds)")
        print("MTKView: \(mtkView)")
    }
    
    func setupKeyboardControls() {
        // Add keyboard commands for simulator testing
        let commands = [
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(moveForward)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(moveBackward)),
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(moveLeft)),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(moveRight)),
            UIKeyCommand(input: "=", modifierFlags: [], action: #selector(zoomIn)),
            UIKeyCommand(input: "-", modifierFlags: [], action: #selector(zoomOut)),
            UIKeyCommand(input: "r", modifierFlags: [], action: #selector(resetCamera)),
            UIKeyCommand(input: "q", modifierFlags: [], action: #selector(rotateLeft)),
            UIKeyCommand(input: "e", modifierFlags: [], action: #selector(rotateRight))
        ]
        
        commands.forEach { addKeyCommand($0) }
        print("Keyboard controls added (arrows to pan, +/- to zoom, q/e to rotate, r to reset)")
    }
    
    @objc func moveForward() {
        print("Key: Move forward")
        simulatePan(deltaX: 0, deltaY: -10)
    }
    
    @objc func moveBackward() {
        print("Key: Move backward")
        simulatePan(deltaX: 0, deltaY: 10)
    }
    
    @objc func moveLeft() {
        print("Key: Move left")
        simulatePan(deltaX: -10, deltaY: 0)
    }
    
    @objc func moveRight() {
        print("Key: Move right")
        simulatePan(deltaX: 10, deltaY: 0)
    }
    
    func simulatePan(deltaX: CGFloat, deltaY: CGFloat) {
        // Directly manipulate camera target for keyboard control
        let panSpeed: Float = cameraController.distance * 0.002
        let right = cameraController.getRightVector()
        let forward = cameraController.getForwardVector()
        
        let worldDelta = right * Float(deltaX) * panSpeed +
                        forward * Float(-deltaY) * panSpeed
        
        cameraController.target.x += worldDelta.x
        cameraController.target.z += worldDelta.z
        cameraController.updateCameraPosition()
    }
    
    @objc func zoomIn() {
        print("Key: Zoom in")
        cameraController.distance *= 0.9
        cameraController.distance = max(cameraController.minZoom, cameraController.distance)
        cameraController.updateCameraPosition()
    }
    
    @objc func zoomOut() {
        print("Key: Zoom out")
        cameraController.distance *= 1.1
        cameraController.distance = min(cameraController.maxZoom, cameraController.distance)
        cameraController.updateCameraPosition()
    }
    
    @objc func resetCamera() {
        print("Key: Reset camera")
        cameraController.reset()
    }
    
    @objc func rotateLeft() {
        print("Key: Rotate left")
        // Direct manipulation of camera yaw
        let rotationSpeed: Float = 5.0 // degrees
        cameraController.yaw += rotationSpeed
        cameraController.updateCameraPosition()
    }
    
    @objc func rotateRight() {
        print("Key: Rotate right")
        // Direct manipulation of camera yaw
        let rotationSpeed: Float = 5.0 // degrees
        cameraController.yaw -= rotationSpeed
        cameraController.updateCameraPosition()
    }
    
    
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    func setupSimpleGestures() {
        // Start with a simple tap gesture to test
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tapGesture)
        view.isUserInteractionEnabled = true
        
        // Simple pan gesture
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleSimplePan(_:)))
        view.addGestureRecognizer(panGesture)
        
        // Pinch gesture
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handleSimplePinch(_:)))
        view.addGestureRecognizer(pinchGesture)
        
        // Rotation gesture for camera rotation
        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        view.addGestureRecognizer(rotationGesture)
        
        // Allow simultaneous gestures
        pinchGesture.delegate = self
        rotationGesture.delegate = self
        panGesture.delegate = self
        
        // Add scroll wheel support for zoom (simulator)
        let scrollGesture = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        scrollGesture.minimumNumberOfTouches = 2
        scrollGesture.maximumNumberOfTouches = 2
        view.addGestureRecognizer(scrollGesture)
        
        print("Gestures added to view")
        print("User interaction enabled: \(view.isUserInteractionEnabled)")
    }
    
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        print("TAP DETECTED at \(gesture.location(in: view))")
        
        // Rotate camera as a test
        cameraAngle += 30
        
        // Direct camera manipulation for testing
        if let camera = gameController.cameraController {
            camera.reset()
            print("Camera reset triggered")
        }
    }
    
    @objc func handleSimplePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: view)
        let translation = gesture.translation(in: view)
        
        print("PAN: state=\(gesture.state.rawValue), location=\(location), translation=\(translation)")
        
        if let camera = gameController.cameraController {
            camera.handlePan(gesture, in: view)
        }
    }
    
    @objc func handleSimplePinch(_ gesture: UIPinchGestureRecognizer) {
        print("PINCH: state=\(gesture.state.rawValue), scale=\(gesture.scale)")
        
        if let camera = gameController.cameraController {
            camera.handlePinch(gesture)
        }
    }
    
    @objc func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        print("ROTATION: state=\(gesture.state.rawValue), rotation=\(gesture.rotation)")
        
        if let camera = gameController.cameraController {
            camera.handleRotation(gesture)
        }
    }
    
    @objc func handleScroll(_ gesture: UIPanGestureRecognizer) {
        // Two-finger scroll for zoom in simulator
        let translation = gesture.translation(in: view)
        let zoomDelta = Float(translation.y) * 0.01
        
        if let camera = gameController.cameraController {
            camera.distance *= (1.0 + zoomDelta)
            camera.distance = max(camera.minZoom, min(camera.maxZoom, camera.distance))
            camera.updateCameraPosition()
        }
        
        gesture.setTranslation(.zero, in: view)
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    // MARK: - UIGestureRecognizerDelegate
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow pinch and rotation to work together
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        print("touchesBegan: \(touches.count) touches")
        super.touchesBegan(touches, with: event)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        print("touchesMoved: \(touches.count) touches")
        super.touchesMoved(touches, with: event)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        print("touchesEnded: \(touches.count) touches")
        super.touchesEnded(touches, with: event)
    }
}