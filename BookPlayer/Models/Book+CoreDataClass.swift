//
//  Book+CoreDataClass.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 5/14/18.
//  Copyright © 2018 Tortuga Power. All rights reserved.
//
//

import AVFoundation
import CoreData
import Foundation

public class Book: LibraryItem {
    var fileURL: URL {
        return DataManager.getProcessedFolderURL().appendingPathComponent(self.identifier)
    }

    var filename: String {
        return self.title + "." + self.ext
    }

    var currentChapter: Chapter?

    var displayTitle: String {
        return self.title
    }

    var progress: Double {
        return self.currentTime / self.duration
    }

    var percentage: Double {
        return round(self.progress * 100)
    }

    var hasChapters: Bool {
        return !(self.chapters?.array.isEmpty ?? true)
    }

    override func info() -> String {
        return self.author
    }

    // TODO: This is a makeshift version of a proper completion property.
    // See https://github.com/TortugaPower/BookPlayer/issues/201
    override var isCompleted: Bool {
        return Int(round(self.currentTime)) == Int(round(self.duration))
    }

    func setChapters(from asset: AVAsset, context: NSManagedObjectContext) {
        for locale in asset.availableChapterLocales {
            let chaptersMetadata = asset.chapterMetadataGroups(withTitleLocale: locale, containingItemsWithCommonKeys: [AVMetadataKey.commonKeyArtwork])

            for (index, chapterMetadata) in chaptersMetadata.enumerated() {
                let chapterIndex = index + 1
                let chapter = Chapter(from: asset, context: context)

                chapter.title = AVMetadataItem.metadataItems(from: chapterMetadata.items,
                                                             withKey: AVMetadataKey.commonKeyTitle,
                                                             keySpace: AVMetadataKeySpace.common).first?.value?.copy(with: nil) as? String ?? ""
                chapter.start = CMTimeGetSeconds(chapterMetadata.timeRange.start)
                chapter.duration = CMTimeGetSeconds(chapterMetadata.timeRange.duration)
                chapter.index = Int16(chapterIndex)

                self.addToChapters(chapter)
            }
        }

        self.currentChapter = self.chapters?.array.first as? Chapter
    }

    convenience init(from bookUrl: FileItem, context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "Book", in: context)!
        self.init(entity: entity, insertInto: context)
        let fileURL = bookUrl.processedUrl!
        self.ext = fileURL.pathExtension
        self.identifier = fileURL.lastPathComponent
        let asset = AVAsset(url: fileURL)

        let titleFromMeta = AVMetadataItem.metadataItems(from: asset.metadata, withKey: AVMetadataKey.commonKeyTitle, keySpace: AVMetadataKeySpace.common).first?.value?.copy(with: nil) as? String
        let authorFromMeta = AVMetadataItem.metadataItems(from: asset.metadata, withKey: AVMetadataKey.commonKeyArtist, keySpace: AVMetadataKeySpace.common).first?.value?.copy(with: nil) as? String

        self.title = titleFromMeta ?? bookUrl.originalUrl.lastPathComponent.replacingOccurrences(of: "_", with: " ")
        self.author = authorFromMeta ?? "Unknown Author"
        self.duration = CMTimeGetSeconds(asset.duration)
        self.originalFileName = bookUrl.originalUrl.lastPathComponent

        var colors: Theme!
        if let data = AVMetadataItem.metadataItems(from: asset.metadata, withKey: AVMetadataKey.commonKeyArtwork, keySpace: AVMetadataKeySpace.common).first?.value?.copy(with: nil) as? NSData {
            self.artworkData = data
            colors = Theme(from: self.artwork, context: context)
        } else {
            colors = Theme(context: context)
            self.usesDefaultArtwork = true
        }

        colors.title = self.title

        self.artworkColors = colors

        self.setChapters(from: asset, context: context)

        let legacyIdentifier = bookUrl.originalUrl.lastPathComponent
        let storedTime = UserDefaults.standard.double(forKey: legacyIdentifier)

        // migration of time
        if storedTime > 0 {
            self.currentTime = storedTime
            UserDefaults.standard.removeObject(forKey: legacyIdentifier)
        }
    }

    public override func awakeFromFetch() {
        super.awakeFromFetch()

        self.updateCurrentChapter()
    }

    func updateCurrentChapter() {
        guard let chapters = self.chapters?.array as? [Chapter], !chapters.isEmpty else {
            return
        }

        guard let currentChapter = (chapters.first { (chapter) -> Bool in
            chapter.start <= self.currentTime && chapter.end > self.currentTime
        }) else { return }

        self.currentChapter = currentChapter
    }

    override func getBookToPlay() -> Book? {
        return self
    }

    func nextBook() -> Book? {
        if
            let playlist = self.playlist,
            let next = playlist.getNextBook(after: self) {
            return next
        }

        guard UserDefaults.standard.bool(forKey: Constants.UserDefaults.autoplayEnabled.rawValue) else {
            return nil
        }

        let item = self.playlist ?? self

        guard let nextItem = item.library?.getNextItem(after: item) else { return nil }

        if let book = nextItem as? Book {
            return book
        } else if let playlist = nextItem as? Playlist, let book = playlist.books?.firstObject as? Book {
            return book
        }

        return nil
    }
}
