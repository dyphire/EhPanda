//
//  ListParserTests.swift
//  EhPandaTests
//

import Kanna
import XCTest
@testable import EhPanda

class ListParserTests: XCTestCase, TestHelper {
    func testExample() throws {
        let tuples: [(ListParserTestType, HTMLDocument)] = try ListParserTestType.allCases.compactMap { type in
            (type, try htmlDocument(filename: type.filename))
        }
        XCTAssertEqual(tuples.count, ListParserTestType.allCases.count)

        try tuples.forEach { type, document in
            let galleries = try Parser.parseGalleries(doc: document)
            let uploaders = galleries.compactMap(\.uploader).filter(\.notEmpty)
            XCTAssertEqual(galleries.count, type.assertCount, .init(describing: type))
            XCTAssertTrue(galleries.allSatisfy({ $0.readingProgress == .zero }), .init(describing: type))
            XCTAssertTrue(galleries.allSatisfy({ $0.hasRated == false }), .init(describing: type))
            XCTAssertTrue(galleries.allSatisfy({ $0.isExpunged == false }), .init(describing: type))
            if type.hasUploader {
                XCTAssertEqual(uploaders.count, type.assertCount, .init(describing: type))
            }
        }
    }
}
