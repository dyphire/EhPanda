//
//  GalleryMO+CoreDataProperties.swift
//  EhPanda
//

import CoreData

extension GalleryMO: GalleryIdentifiable {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<GalleryMO> {
        NSFetchRequest<GalleryMO>(entityName: "GalleryMO")
    }

    @NSManaged public var category: String
    @NSManaged public var coverURL: URL?
    @NSManaged public var galleryURL: URL?
    @NSManaged public var gid: String
    @NSManaged public var hasRated: Bool
    @NSManaged public var isExpunged: Bool
    @NSManaged public var lastOpenDate: Date?
    @NSManaged public var pageCount: Int64
    @NSManaged public var postedDate: Date
    @NSManaged public var rating: Float
    @NSManaged public var tags: Data?
    @NSManaged public var favoriteTagIndex: Int64
    @NSManaged public var favoriteTagName: String?
    @NSManaged public var title: String
    @NSManaged public var token: String
    @NSManaged public var uploader: String?
}
