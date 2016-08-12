//
//  GameViewController.swift
//  DeltaCore
//
//  Created by Riley Testut on 7/4/16.
//  Happy 4th of July, Everyone! 🎉
//  Copyright © 2016 Riley Testut. All rights reserved.
//

import UIKit

public protocol GameViewControllerDelegate: class
{
    func gameViewControllerShouldPauseEmulation(_ gameViewController: GameViewController) -> Bool
    func gameViewControllerShouldResumeEmulation(_ gameViewController: GameViewController) -> Bool
    
    func gameViewController(_ gameViewController: GameViewController, handleMenuInputFrom gameController: GameController)
    
    func gameViewControllerDidUpdate(_ gameViewController: GameViewController)
}

public extension GameViewControllerDelegate
{
    func gameViewControllerShouldPauseEmulation(_ gameViewController: GameViewController) -> Bool { return true }
    func gameViewControllerShouldResumeEmulation(_ gameViewController: GameViewController) -> Bool { return true }
    
    func gameViewController(_ gameViewController: GameViewController, handleMenuInputFrom gameController: GameController) {}
    
    func gameViewControllerDidUpdate(_ gameViewController: GameViewController) {}
}

private var kvoContext = 0

public class GameViewController: UIViewController, GameControllerReceiver
{
    public var game: GameProtocol?
    {
        didSet
        {
            guard oldValue?.fileURL != self.game?.fileURL else { return }
            
            if let game = self.game
            {
                self.emulatorCore = EmulatorCore(game: game)
            }
            else
            {
                self.emulatorCore = nil
            }
        }
    }
    
    public private(set) var emulatorCore: EmulatorCore?
    {
        didSet
        {
            oldValue?.stop()
            
            self.emulatorCore?.updateHandler = { [weak self] core in
                guard let strongSelf = self else { return }
                strongSelf.delegate?.gameViewControllerDidUpdate(strongSelf)
            }
            
            self.prepareForGame()
        }
    }
    
    public weak var delegate: GameViewControllerDelegate?
    
    public private(set) var gameView: GameView!
    public private(set) var controllerView: ControllerView!
    
    private var controllerViewHeightConstraint: NSLayoutConstraint!
    private var gameViewHeightConstraint: NSLayoutConstraint!
    
    private let emulatorCoreQueue = DispatchQueue(label: "com.rileytestut.DeltaCore.GameViewController.emulatorCoreQueue", qos: .userInitiated)
    
    /// UIViewController
    public override var prefersStatusBarHidden: Bool {
        return true
    }
    
    public required init()
    {
        super.init(nibName: nil, bundle: nil)
        
        self.initialize()
    }
    
    public required init?(coder aDecoder: NSCoder)
    {
        super.init(coder: aDecoder)
        
        self.initialize()
    }
    
    private func initialize()
    {
        NotificationCenter.default.addObserver(self, selector: #selector(GameViewController.willResignActive(with:)), name: .UIApplicationWillResignActive, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(GameViewController.didBecomeActive(with:)), name: .UIApplicationDidBecomeActive, object: nil)
    }
    
    deinit
    {
        self.controllerView.removeObserver(self, forKeyPath: #keyPath(ControllerView.isHidden), context: &kvoContext)
        self.emulatorCore?.stop()
    }
    
    // MARK: - UIViewController -
    /// UIViewController
    // These would normally be overridden in a public extension, but overriding these methods in subclasses of GameViewController segfaults compiler if so
    
    public override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.view.backgroundColor = UIColor.black
        
        self.gameView = GameView(frame: CGRect.zero)
        self.gameView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.gameView)
        
        self.controllerView = ControllerView(frame: CGRect.zero)
        self.controllerView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.controllerView)
        
        self.controllerView.addObserver(self, forKeyPath: #keyPath(ControllerView.isHidden), options: [.old, .new], context: &kvoContext)
        
        self.prepareForGame()
        
        // Auto Layout
        self.gameView.leftAnchor.constraint(equalTo: self.view.leftAnchor).isActive = true
        self.gameView.rightAnchor.constraint(equalTo: self.view.rightAnchor).isActive = true
        self.gameView.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        
        self.controllerView.leftAnchor.constraint(equalTo: self.view.leftAnchor).isActive = true
        self.controllerView.rightAnchor.constraint(equalTo: self.view.rightAnchor).isActive = true
        self.controllerView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
        
        self.gameViewHeightConstraint = self.gameView.heightAnchor.constraint(equalToConstant: 0)
        self.gameViewHeightConstraint.isActive = true
        
        self.controllerViewHeightConstraint = self.controllerView.heightAnchor.constraint(equalToConstant: 0)
        self.controllerViewHeightConstraint.isActive = true
    }
    
    public override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        if let emulatorCore = self.emulatorCore
        {
            self.emulatorCoreQueue.async {
                
                switch emulatorCore.state
                {
                case .stopped: emulatorCore.start()
                case .paused: self.resumeEmulation()
                case .running: break
                }
                
                // Toggle audioManager.enabled to reset the audio buffer and ensure the audio isn't delayed from the beginning
                // This is especially noticeable when peeking a game
                emulatorCore.audioManager.isEnabled = false
                emulatorCore.audioManager.isEnabled = true
                
                self.emulatorCore?.start()
            }
        }
    }
    
    public override func viewDidDisappear(_ animated: Bool)
    {
        super.viewDidDisappear(animated)
        
        if let emulatorCore = self.emulatorCore
        {
            self.emulatorCoreQueue.async {
                emulatorCore.pause()
            }
        }
    }
    
    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator)
    {
        super.viewWillTransition(to: size, with: coordinator)
        
        self.controllerView.beginAnimatingUpdateControllerSkin()
        
        coordinator.animate(alongsideTransition: { (context) in
            if self.emulatorCore?.state == .paused
            {
                // WORKAROUND
                // We need to manually "refresh" the game screen, otherwise the system tries to cache the rendered image, but skews it incorrectly when rotating b/c of UIVisualEffectView
                self.gameView.inputImage = self.gameView.outputImage
            }
        }) { (context) in
            self.controllerView.finishAnimatingUpdateControllerSkin()
        }
    }
    
    public override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        
        if !self.controllerView.isHidden && self.controllerView.controllerSkin != nil
        {
            if self.view.bounds.width > self.view.bounds.height
            {
                self.controllerViewHeightConstraint.constant = self.view.bounds.height
            }
            else
            {
                let scale = self.view.bounds.width / self.controllerView.intrinsicContentSize.width
                self.controllerViewHeightConstraint.constant = self.controllerView.intrinsicContentSize.height * scale
            }
        }
        else
        {
            self.controllerViewHeightConstraint.constant = 0
        }
        
        if self.view.bounds.width > self.view.bounds.height
        {
            self.gameViewHeightConstraint.constant = self.view.bounds.height
        }
        else
        {
            self.gameViewHeightConstraint.constant = self.view.bounds.height - self.controllerViewHeightConstraint.constant
        }
    }
    
    // MARK: - KVO -
    /// KVO
    public override func observeValue(forKeyPath keyPath: String?, of object: AnyObject?, change: [NSKeyValueChangeKey : AnyObject]?, context: UnsafeMutablePointer<Void>?)
    {
        guard context == &kvoContext else { return super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context) }

        // Ensures the value is actually different, or else we might potentially run into an infinite loop if subclasses hide/show controllerView in viewDidLayoutSubviews()
        guard (change?[.newKey] as? Bool) != (change?[.oldKey] as? Bool) else { return }
        
        self.view.setNeedsLayout()
        self.view.layoutIfNeeded()
    }
    
    public override func didReceiveMemoryWarning()
    {
        super.didReceiveMemoryWarning()
    }
    
    // MARK: - GameControllerReceiver -
    /// GameControllerReceiver
    // These would normally be declared in an extension, but non-ObjC compatible methods cannot be overridden if declared in extension :(
    public func gameController(_ gameController: GameController, didActivate input: Input)
    {
        guard let input = input as? ControllerInput, input == .menu else { return }
        self.delegate?.gameViewController(self, handleMenuInputFrom: gameController)
    }
    
    public func gameController(_ gameController: GameController, didDeactivate input: Input)
    {
        // This method intentionally left blank
    }
}

// MARK: - Emulation -
/// Emulation
public extension GameViewController
{
    @discardableResult func pauseEmulation() -> Bool
    {
        guard let emulatorCore = self.emulatorCore, self.delegate?.gameViewControllerShouldPauseEmulation(self) ?? true else { return false }
        return emulatorCore.pause()
    }
    
    @discardableResult func resumeEmulation() -> Bool
    {
        guard let emulatorCore = self.emulatorCore, self.delegate?.gameViewControllerShouldResumeEmulation(self) ?? true else { return false }
        return emulatorCore.resume()
    }
}

// MARK: - Preparation -
private extension GameViewController
{
    func prepareForGame()
    {
        guard
            let gameView = self.gameView,
            let controllerView = self.controllerView,
            let emulatorCore = self.emulatorCore,
            let game = self.game
        else { return }
        
        emulatorCore.add(gameView)
        
        controllerView.addReceiver(self)
        controllerView.addReceiver(emulatorCore)
        
        let controllerSkin = ControllerSkin.standardControllerSkin(for: game.type)
        controllerView.controllerSkin = controllerSkin
    }
}

// MARK: - Notifications - 
private extension GameViewController
{
    @objc func willResignActive(with notification: Notification)
    {
        self.pauseEmulation()
    }
    
    @objc func didBecomeActive(with notification: Notification)
    {
        self.resumeEmulation()
    }
}