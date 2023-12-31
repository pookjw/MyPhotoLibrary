//
//  SceneDelegate.swift
//  MyPhotoLibrary
//
//  Created by Jinwoo Kim on 10/11/23.
//

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        let windowScene: UIWindowScene = scene as! UIWindowScene
        let window: UIWindow = .init(windowScene: windowScene)
        let assetsViewController: AssetsViewController = .init()
        let navigationController: UINavigationController = .init(rootViewController: assetsViewController)
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        self.window = window
    }
}
