import SwiftUI

enum NavigationBarStyle {
    case solid(UIColor)
    case clear
}

protocol SceneViewModel {
    var sceneTitle: String? { get }
    var largeTitleDisplayMode: UINavigationItem.LargeTitleDisplayMode { get }
    var leftBarButtonItem: UIBarButtonItem? { get }
    var rightBarButtonItem: UIBarButtonItem? { get }
    var navigationBarStyle: NavigationBarStyle { get }
    var preferredStatusBarStyle: UIStatusBarStyle { get }
    var isNavigationBarTranslucent: Bool { get }

}

extension SceneViewModel {
    var sceneTitle: String? {
        return nil
    }
    var largeTitleDisplayMode: UINavigationItem.LargeTitleDisplayMode {
        return .never
    }
    var leftBarButtonItem: UIBarButtonItem? {
        return .none
    }
    var rightBarButtonItem: UIBarButtonItem? {
        return .none
    }
    var navigationBarStyle: NavigationBarStyle {
        return .solid(.w_background)
    }
    var preferredStatusBarStyle: UIStatusBarStyle {
        return .default
    }
    var isNavigationBarTranslucent: Bool {
        return true
    }
}

class SceneViewController<ViewModel: SceneViewModel, Content: View>: UIHostingController<Content> {
    private let viewModel: ViewModel

    init(viewModel: ViewModel, content: Content) {
        self.viewModel = viewModel
        super.init(rootView: content)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return viewModel.preferredStatusBarStyle
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupNavigation()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupNavigationBarStyle()
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: Privates
private extension SceneViewController {
    func setupView() {
        view.backgroundColor = .w_background
    }

    func setupNavigation() {
        navigationItem.title = viewModel.sceneTitle
        navigationItem.backButtonTitle = .empty
        navigationItem.largeTitleDisplayMode = viewModel.largeTitleDisplayMode
        navigationItem.rightBarButtonItem = viewModel.rightBarButtonItem
        navigationItem.leftBarButtonItem = viewModel.leftBarButtonItem
    }

    func setupNavigationBarStyle() {
        switch viewModel.navigationBarStyle {
        case .solid(let color):
            navigationController?.navigationBar.setBackgroundImage(color.image(), for: .default)
            navigationController?.navigationBar.isTranslucent = false
            navigationController?.navigationBar.backgroundColor = color
            navigationController?.navigationBar.barTintColor = color
        case .clear:
            navigationController?.navigationBar.setBackgroundImage(UIImage(), for: .default)
            navigationController?.navigationBar.shadowImage = UIImage()
            navigationController?.navigationBar.isTranslucent = true
            navigationController?.navigationBar.backgroundColor = .clear
            navigationController?.navigationBar.barTintColor = .clear
            navigationController?.navigationBar.tintColor = .w_foreground
        }
    }
}
