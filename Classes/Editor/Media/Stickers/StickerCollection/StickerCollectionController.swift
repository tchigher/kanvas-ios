//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import UIKit
import TMTumblrSDK

/// Protocol for selecting a sticker
protocol StickerCollectionControllerDelegate: class {
    /// Callback for when a sticker is selected
    /// 
    /// - Parameters
    ///  - image: the sticker image
    ///  - size: image view size
    func didSelectSticker(sticker: UIImage, with size: CGSize)
}

/// Constants for StickerCollectionController
private struct Constants {
    static let contentInset: UIEdgeInsets = UIEdgeInsets(top: 0, left: 22, bottom: 0, right: 22)
}

/// Controller for handling the sticker item collection.
final class StickerCollectionController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, StickerCollectionCellDelegate, StaggeredGridLayoutDelegate {
    
    weak var delegate: StickerCollectionControllerDelegate?
    
    private lazy var stickerCollectionView = StickerCollectionView()
    private var stickerType: StickerType? = nil
    private var stickers: [Sticker] = []
    private var cellSizes: [CGSize] = []
    
    // MARK: - View Life Cycle
    
    override func loadView() {
        view = stickerCollectionView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        stickerCollectionView.collectionView.register(cell: StickerCollectionCell.self)
        stickerCollectionView.collectionView.delegate = self
        stickerCollectionView.collectionView.dataSource = self
        stickerCollectionView.collectionViewLayout.delegate = self
    }

    // MARK: - Public interface
    
    /// Loads a new collection of stickers for a selected sticker type
    ///
    /// - Parameter stickerType: the selected sticker type
    func setType(_ stickerType: StickerType) {
        self.stickerType = stickerType
        stickers = stickerType.getStickers()
        resetCellSizes()
        scrollToTop()
        stickerCollectionView.collectionView.reloadData()
    }
    
    // MARK: - Private utilities
    
    private func resetCellSizes() {
        let cellWidth = stickerCollectionView.collectionViewLayout.itemWidth
        cellSizes = .init(repeating: CGSize(width: cellWidth, height: cellWidth), count: stickers.count)
    }
    
    private func scrollToTop() {
        stickerCollectionView.collectionView.contentOffset.y = 0
    }
    
    // MARK: - StaggeredGridLayoutDelegate
    
    func collectionView(_ collectionView: UICollectionView, heightOfCellAtIndexPath indexPath: IndexPath) -> CGFloat {
        let ratio = cellSizes[indexPath.item].height / cellSizes[indexPath.item].width
        return ratio * stickerCollectionView.collectionViewLayout.itemWidth
    }
    
    // MARK: - UICollectionViewDataSource
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return stickers.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: StickerCollectionCell.identifier, for: indexPath)
        if let cell = cell as? StickerCollectionCell, let sticker = stickers.object(at: indexPath.item), let type = stickerType {
            cell.delegate = self
            cell.bindTo(sticker, type: type, index: indexPath.item)
        }
        return cell
    }
        
    // MARK: - StickerCollectionCellDelegate
    
    func didSelect(sticker: UIImage, with size: CGSize) {
        delegate?.didSelectSticker(sticker: sticker, with: size)
    }
    
    func didLoadImage(index: Int, type: StickerType, image: UIImage) {
        guard let currentType = stickerType, type.isEqual(to: currentType) else { return }
        let currentSize = cellSizes[index]
        
        if currentSize != image.size {
            cellSizes[index] = image.size
            
            DispatchQueue.main.async { [weak self] in
                self?.stickerCollectionView.collectionViewLayout.invalidateLayout()
            }
        }
    }
}
