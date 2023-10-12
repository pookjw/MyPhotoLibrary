//
//  CGSize+Ext.swift
//  MyPhotoLibrary
//
//  Created by Jinwoo Kim on 10/12/23.
//

import CoreGraphics

extension CGSize {
    static func *(lhs: CGSize, rhs: CGFloat) -> CGSize {
        .init(width: lhs.width * rhs, height: lhs.height * rhs)
    }
}
