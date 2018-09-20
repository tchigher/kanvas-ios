//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import AVFoundation
import Foundation
import UIKit

/// Protocol for camera preview controller methods

protocol CameraPreviewControllerDelegate: class {
    /// callback when finished exporting video clips.
    func didFinishExportingVideo(url: URL?)

    /// callback when finished exporting image
    func didFinishExportingImage(image: UIImage?)

    /// callback when dismissing controller without exporting
    func dismissButtonPressed()
}

/// A view controller to preview the segments sequentially
/// There are two AVPlayers to reduce loading times and the black screen when replacing player items

final class CameraPreviewViewController: UIViewController {

    private lazy var cameraPreviewView: CameraPreviewView = {
        let previewView = CameraPreviewView()
        previewView.delegate = self
        return previewView
    }()
    private lazy var loadingView: LoadingIndicatorView = LoadingIndicatorView()

    private let settings: CameraSettings
    private let segments: [CameraSegment]
    private let assetsHandler: AssetsHandlerType

    private var currentSegmentIndex: Int = 0
    private var timer: Timer = Timer()

    private var firstPlayer: AVPlayer = AVPlayer()
    private var secondPlayer: AVPlayer = AVPlayer()
    private var currentPlayer: AVPlayer

    weak var delegate: CameraPreviewControllerDelegate?

    @available(*, unavailable, message: "use init(settings:, segments:) instead")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable, message: "use init(settings:, segments:) instead")
    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        fatalError("init(nibName:bundle:) has not been implemented")
    }

    /// The designated initializer for the preview controller
    ///
    /// - Parameters:
    ///   - settings: The CameraSettings instance for export optioins
    ///   - segments: The segments to playback
    ///   - assetsHandler: The assets handler type, for testing.
    init(settings: CameraSettings, segments: [CameraSegment], assetsHandler: AssetsHandlerType) {
        self.settings = settings
        self.segments = segments
        self.assetsHandler = assetsHandler
        self.currentPlayer = firstPlayer

        super.init(nibName: .none, bundle: .none)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        restartPlayback()
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        cameraPreviewView.add(into: view)
        cameraPreviewView.setFirstPlayer(player: firstPlayer)
        cameraPreviewView.setSecondPlayer(player: secondPlayer)
    }

    override public var prefersStatusBarHidden: Bool {
        return true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    // MARK: - playback methods

    private func restartPlayback() {
        currentSegmentIndex = 0
        if let firstSegment = segments.first {
            playSegment(segment: firstSegment)
        }
    }

    private func playSegment(segment: CameraSegment) {
        if let image = segment.image {
            playImage(image: image)
        }
        else if let url = segment.videoURL {
            playVideo(url: url)
        }
        queueNextSegment()
    }

    private func playImage(image: UIImage) {
        cameraPreviewView.setImage(image: image)
        let displayTime = KanvasCameraTimes.StopMotionFrameTimeInterval
        timer = Timer.scheduledTimer(withTimeInterval: displayTime, repeats: false, block: { [weak self] _ in
            self?.playNextSegment()
        })
    }

    private func playVideo(url: URL) {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: nil)
        if currentPlayer == firstPlayer {
            currentPlayer = secondPlayer
            cameraPreviewView.showSecondPlayer()
        }
        else {
            currentPlayer = firstPlayer
            cameraPreviewView.showFirstPlayer()
        }

        if currentPlayer.currentItem == nil {
            currentPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
        }
        currentPlayer.play()

        NotificationCenter.default.addObserver(self, selector: #selector(playNextSegment), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: nil)
    }

    @objc private func queueNextSegment() {
        let nextSegmentIndex = (currentSegmentIndex + 1) % segments.count
        guard nextSegmentIndex < segments.count else { return }
        let nextSegment = segments[nextSegmentIndex]
        var playerItem: AVPlayerItem? = nil
        if let url = nextSegment.videoURL, nextSegment.image == nil {
            playerItem = AVPlayerItem(url: url)
        }
        if currentPlayer == firstPlayer {
            secondPlayer.replaceCurrentItem(with: playerItem)
        }
        else if currentPlayer == secondPlayer {
            firstPlayer.replaceCurrentItem(with: playerItem)
        }
    }

    @objc private func playNextSegment() {
        currentPlayer.pause()
        currentPlayer.seek(to: kCMTimeZero)
        currentSegmentIndex = (currentSegmentIndex + 1) % segments.count
        guard currentSegmentIndex < segments.count else { return }
        playSegment(segment: segments[currentSegmentIndex])
    }

    private func stopPlayback() {
        timer.invalidate()
        currentPlayer.pause()
    }
    
    // MARK: - Loading Indicator
    /// Shows the loading indicator on this view
    func showLoading() {
        loadingView.add(into: view)
        loadingView.startLoading()
    }
    
    /// Removes the loading indicator on this view
    func hideLoading() {
        loadingView.removeFromSuperview()
        loadingView.stopLoading()
    }
}

// MARK: - CameraPreviewView

extension CameraPreviewViewController: CameraPreviewViewDelegate {
    func confirmButtonPressed() {
        stopPlayback()
        showLoading()
        if segments.count == 1, let firstSegment = segments.first, let image = firstSegment.image {
            if settings.exportStopMotionPhotoAsVideo, let videoURL = firstSegment.videoURL {
                performUIUpdate {
                    self.delegate?.didFinishExportingVideo(url: videoURL)
                    self.hideLoading()
                }
            }
            else {
                performUIUpdate {
                    self.delegate?.didFinishExportingImage(image: image)
                    self.hideLoading()
                }
            }
        }
        else {
            createFinalContent()
        }
    }

    private func createFinalContent() {
        assetsHandler.mergeAssets(segments: segments, completion: { url in
            performUIUpdate {
                if let url = url {
                    self.delegate?.didFinishExportingVideo(url: url)
                    self.hideLoading()
                }
                else {
                    self.hideLoading()
                    // TODO: Localize strings
                    let viewModel = ModalViewModel(text: "There was an issue loading your post...",
                                                   confirmTitle: "Try again",
                                                   confirmCallback: {
                                                       self.showLoading()
                                                       self.createFinalContent()
                                                   },
                                                   cancelTitle: "Cancel",
                                                   cancelCallback: { [unowned self] in self.delegate?.didFinishExportingVideo(url: url) },
                                                   buttonsLayout: .oneBelowTheOther)
                    let controller = ModalController(viewModel: viewModel)
                    self.present(controller, animated: true, completion: .none)
                }
            }
        })
    }

    func closeButtonPressed() {
        stopPlayback()
        delegate?.dismissButtonPressed()
    }
}