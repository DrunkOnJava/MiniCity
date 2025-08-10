//
//  HUDOverlay.swift
//  MiniCity
//
//  HUD overlay system for building placement and city management
//

import UIKit
import simd

// Using BuildingType from CityGameController
typealias HUDBuildingType = BuildingType

enum BuildingCategory: CaseIterable {
    case residential
    case commercial
    case industrial
    case park
    case road
    
    var name: String {
        switch self {
        case .residential: return "Residential"
        case .commercial: return "Commercial"
        case .industrial: return "Industrial"
        case .park: return "Park"
        case .road: return "Road"
        }
    }
    
    var icon: String {
        switch self {
        case .residential: return "🏠"
        case .commercial: return "🏢"
        case .industrial: return "🏭"
        case .park: return "🌳"
        case .road: return "🛣️"
        }
    }
    
    var color: UIColor {
        switch self {
        case .residential: return UIColor(red: 0.2, green: 0.6, blue: 0.2, alpha: 1.0)
        case .commercial: return UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0)
        case .industrial: return UIColor(red: 0.7, green: 0.5, blue: 0.2, alpha: 1.0)
        case .park: return UIColor(red: 0.3, green: 0.7, blue: 0.3, alpha: 1.0)
        case .road: return UIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0)
        }
    }
}

protocol HUDOverlayDelegate: AnyObject {
    func hudOverlay(_ overlay: HUDOverlay, didSelectBuildingType type: BuildingCategory)
    func hudOverlay(_ overlay: HUDOverlay, didPlaceBuildingAt position: SIMD3<Float>)
    func hudOverlayDidToggleSimulation(_ overlay: HUDOverlay)
    func hudOverlayDidRequestStats(_ overlay: HUDOverlay)
}

class HUDOverlay: UIView {
    
    weak var delegate: HUDOverlayDelegate?
    
    private var selectedBuildingType: BuildingCategory?
    private var isPlacementMode = false
    private var isSimulationRunning = false
    
    // UI Components
    private let buildingPanel = UIStackView()
    private let statsPanel = UIView()
    private let controlPanel = UIStackView()
    private let placementCursor = UIView()
    
    // Stats labels
    private let populationLabel = UILabel()
    private let moneyLabel = UILabel()
    private let timeLabel = UILabel()
    private let fpsLabel = UILabel()
    
    // Building buttons
    private var buildingButtons: [UIButton] = []
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        isUserInteractionEnabled = true
        backgroundColor = .clear
        
        setupBuildingPanel()
        setupStatsPanel()
        setupControlPanel()
        setupPlacementCursor()
    }
    
    private func setupBuildingPanel() {
        buildingPanel.axis = .horizontal
        buildingPanel.spacing = 10
        buildingPanel.distribution = .fillEqually
        buildingPanel.backgroundColor = UIColor(white: 0, alpha: 0.7)
        buildingPanel.layer.cornerRadius = 10
        buildingPanel.isLayoutMarginsRelativeArrangement = true
        buildingPanel.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        
        addSubview(buildingPanel)
        buildingPanel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            buildingPanel.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
            buildingPanel.centerXAnchor.constraint(equalTo: centerXAnchor),
            buildingPanel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.8),
            buildingPanel.heightAnchor.constraint(equalToConstant: 80)
        ])
        
        // Create building type buttons
        for buildingType in BuildingCategory.allCases {
            let button = createBuildingButton(for: buildingType)
            buildingButtons.append(button)
            buildingPanel.addArrangedSubview(button)
        }
    }
    
    private func createBuildingButton(for type: BuildingCategory) -> UIButton {
        let button = UIButton(type: .system)
        button.backgroundColor = type.color.withAlphaComponent(0.3)
        button.layer.cornerRadius = 8
        button.layer.borderWidth = 2
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        
        // Create vertical stack for icon and label
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.isUserInteractionEnabled = false
        
        let iconLabel = UILabel()
        iconLabel.text = type.icon
        iconLabel.font = .systemFont(ofSize: 24)
        
        let nameLabel = UILabel()
        nameLabel.text = type.name
        nameLabel.font = .systemFont(ofSize: 10)
        nameLabel.textColor = .white
        
        stack.addArrangedSubview(iconLabel)
        stack.addArrangedSubview(nameLabel)
        
        button.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
        
        button.tag = BuildingCategory.allCases.firstIndex(of: type) ?? 0
        button.addTarget(self, action: #selector(buildingButtonTapped(_:)), for: .touchUpInside)
        
        return button
    }
    
    private func setupStatsPanel() {
        statsPanel.backgroundColor = UIColor(white: 0, alpha: 0.7)
        statsPanel.layer.cornerRadius = 10
        
        addSubview(statsPanel)
        statsPanel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statsPanel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
            statsPanel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            statsPanel.widthAnchor.constraint(equalToConstant: 200),
            statsPanel.heightAnchor.constraint(equalToConstant: 120)
        ])
        
        // Setup stats labels
        let statsStack = UIStackView()
        statsStack.axis = .vertical
        statsStack.spacing = 8
        statsStack.distribution = .fillEqually
        
        populationLabel.text = "👥 Population: 0"
        populationLabel.textColor = .white
        populationLabel.font = .systemFont(ofSize: 14)
        
        moneyLabel.text = "💰 Money: $10,000"
        moneyLabel.textColor = .white
        moneyLabel.font = .systemFont(ofSize: 14)
        
        timeLabel.text = "🕐 Day 1, 12:00"
        timeLabel.textColor = .white
        timeLabel.font = .systemFont(ofSize: 14)
        
        fpsLabel.text = "FPS: 60"
        fpsLabel.textColor = .green
        fpsLabel.font = .systemFont(ofSize: 12)
        
        statsStack.addArrangedSubview(populationLabel)
        statsStack.addArrangedSubview(moneyLabel)
        statsStack.addArrangedSubview(timeLabel)
        statsStack.addArrangedSubview(fpsLabel)
        
        statsPanel.addSubview(statsStack)
        statsStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statsStack.topAnchor.constraint(equalTo: statsPanel.topAnchor, constant: 10),
            statsStack.leadingAnchor.constraint(equalTo: statsPanel.leadingAnchor, constant: 10),
            statsStack.trailingAnchor.constraint(equalTo: statsPanel.trailingAnchor, constant: -10),
            statsStack.bottomAnchor.constraint(equalTo: statsPanel.bottomAnchor, constant: -10)
        ])
    }
    
    private func setupControlPanel() {
        controlPanel.axis = .vertical
        controlPanel.spacing = 10
        controlPanel.backgroundColor = UIColor(white: 0, alpha: 0.7)
        controlPanel.layer.cornerRadius = 10
        controlPanel.isLayoutMarginsRelativeArrangement = true
        controlPanel.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        
        addSubview(controlPanel)
        controlPanel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controlPanel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
            controlPanel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            controlPanel.widthAnchor.constraint(equalToConstant: 60)
        ])
        
        // Play/Pause button
        let playButton = UIButton(type: .system)
        playButton.setTitle("▶️", for: .normal)
        playButton.titleLabel?.font = .systemFont(ofSize: 24)
        playButton.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        playButton.layer.cornerRadius = 20
        playButton.addTarget(self, action: #selector(toggleSimulation), for: .touchUpInside)
        NSLayoutConstraint.activate([
            playButton.widthAnchor.constraint(equalToConstant: 40),
            playButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        // Stats button
        let statsButton = UIButton(type: .system)
        statsButton.setTitle("📊", for: .normal)
        statsButton.titleLabel?.font = .systemFont(ofSize: 24)
        statsButton.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        statsButton.layer.cornerRadius = 20
        statsButton.addTarget(self, action: #selector(showStats), for: .touchUpInside)
        NSLayoutConstraint.activate([
            statsButton.widthAnchor.constraint(equalToConstant: 40),
            statsButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        controlPanel.addArrangedSubview(playButton)
        controlPanel.addArrangedSubview(statsButton)
    }
    
    private func setupPlacementCursor() {
        placementCursor.backgroundColor = UIColor.green.withAlphaComponent(0.3)
        placementCursor.layer.borderColor = UIColor.green.cgColor
        placementCursor.layer.borderWidth = 2
        placementCursor.isHidden = true
        placementCursor.isUserInteractionEnabled = false
        
        addSubview(placementCursor)
        placementCursor.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
    }
    
    // MARK: - Actions
    
    @objc private func buildingButtonTapped(_ sender: UIButton) {
        let index = sender.tag
        guard index < BuildingCategory.allCases.count else { return }
        
        let buildingType = BuildingCategory.allCases[index]
        selectBuildingType(buildingType)
    }
    
    private func selectBuildingType(_ type: BuildingCategory) {
        // Update button states
        for (index, button) in buildingButtons.enumerated() {
            let buttonType = BuildingCategory.allCases[index]
            if buttonType == type {
                button.layer.borderColor = UIColor.yellow.cgColor
                button.layer.borderWidth = 3
                button.alpha = 1.0
            } else {
                button.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
                button.layer.borderWidth = 2
                button.alpha = 0.7
            }
        }
        
        selectedBuildingType = type
        isPlacementMode = true
        placementCursor.isHidden = false
        
        delegate?.hudOverlay(self, didSelectBuildingType: type)
    }
    
    @objc private func toggleSimulation() {
        isSimulationRunning.toggle()
        delegate?.hudOverlayDidToggleSimulation(self)
        
        // Update button appearance
        if let button = controlPanel.arrangedSubviews.first as? UIButton {
            button.setTitle(isSimulationRunning ? "⏸" : "▶️", for: .normal)
        }
    }
    
    @objc private func showStats() {
        delegate?.hudOverlayDidRequestStats(self)
    }
    
    // MARK: - Public Methods
    
    func updateStats(population: Int, money: Int, day: Int, hour: Int, fps: Int) {
        populationLabel.text = "👥 Population: \(population)"
        moneyLabel.text = "💰 Money: $\(money)"
        timeLabel.text = String(format: "🕐 Day %d, %02d:00", day, hour)
        fpsLabel.text = "FPS: \(fps)"
        
        // Update FPS color
        if fps >= 50 {
            fpsLabel.textColor = .green
        } else if fps >= 30 {
            fpsLabel.textColor = .yellow
        } else {
            fpsLabel.textColor = .red
        }
    }
    
    func movePlacementCursor(to position: CGPoint) {
        guard isPlacementMode else { return }
        placementCursor.center = position
    }
    
    func endPlacementMode() {
        isPlacementMode = false
        placementCursor.isHidden = true
        selectedBuildingType = nil
        
        // Reset button states
        for button in buildingButtons {
            button.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
            button.layer.borderWidth = 2
            button.alpha = 1.0
        }
    }
    
    func placeBuildingAt(position: SIMD3<Float>) {
        // Notify delegate about building placement
        delegate?.hudOverlay(self, didPlaceBuildingAt: position)
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Allow touches to pass through except on UI elements
        let hitView = super.hitTest(point, with: event)
        
        // Check if hit view is one of our UI elements
        if hitView == self {
            return nil // Pass through to the game view
        }
        
        return hitView
    }
}