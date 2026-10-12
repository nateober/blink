////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Copyright (C) 2016-2019 Blink Mobile Shell Project
//
// This file is part of Blink.
//
// Blink is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Blink is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Blink. If not, see <http://www.gnu.org/licenses/>.
//
// In addition, Blink is also subject to certain additional terms under
// GNU GPL version 3 section 7.
//
// You should have received a copy of these additional terms immediately
// following the terms and conditions of the GNU General Public License
// which accompanied the Blink Source Code. If not, see
// <http://www.github.com/blinksh/blink>.
//
////////////////////////////////////////////////////////////////////////////////


import UIKit

/// The optional sessions bar: one tab per session across the top, tap to switch.
final class TabStripView: UIView {
  static let enabledKey = "TabStripEnabled"

  static var isEnabled: Bool {
    get { UserDefaults.standard.bool(forKey: enabledKey) }
    set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
  }

  var onSelect: ((Int) -> Void)?

  private let _blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
  private let _scroll = UIScrollView()
  private let _stack = UIStackView()
  private var _labels: [String] = []
  private var _selected: Int = -1

  override init(frame: CGRect) {
    super.init(frame: frame)

    _blur.frame = bounds
    _blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(_blur)

    _scroll.showsHorizontalScrollIndicator = false
    _scroll.showsVerticalScrollIndicator = false
    _scroll.alwaysBounceHorizontal = true
    _scroll.translatesAutoresizingMaskIntoConstraints = false
    addSubview(_scroll)

    _stack.axis = .horizontal
    _stack.spacing = 2
    _stack.translatesAutoresizingMaskIntoConstraints = false
    _scroll.addSubview(_stack)

    NSLayoutConstraint.activate([
      _scroll.topAnchor.constraint(equalTo: topAnchor),
      _scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
      _scroll.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 6),
      _scroll.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -6),
      _stack.topAnchor.constraint(equalTo: _scroll.contentLayoutGuide.topAnchor),
      _stack.bottomAnchor.constraint(equalTo: _scroll.contentLayoutGuide.bottomAnchor),
      _stack.leadingAnchor.constraint(equalTo: _scroll.contentLayoutGuide.leadingAnchor),
      _stack.trailingAnchor.constraint(equalTo: _scroll.contentLayoutGuide.trailingAnchor),
      _stack.heightAnchor.constraint(equalTo: _scroll.frameLayoutGuide.heightAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Rebuilds only when something changed, so a periodic title refresh costs nothing.
  func update(labels: [String], selected: Int) {
    guard labels != _labels || selected != _selected else { return }
    let rebuild = labels.count != _labels.count
    _labels = labels
    _selected = selected

    if rebuild {
      _stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
      for index in labels.indices {
        let button = UIButton(type: .system)
        button.tag = index
        button.addTarget(self, action: #selector(_tapped(_:)), for: .touchUpInside)
        button.isPointerInteractionEnabled = true
        _stack.addArrangedSubview(button)
      }
    }

    for case let button as UIButton in _stack.arrangedSubviews {
      let isCurrent = button.tag == selected
      var config = UIButton.Configuration.plain()
      config.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10)
      config.attributedTitle = AttributedString(labels[button.tag], attributes: AttributeContainer([
        .font: UIFont.systemFont(ofSize: 12, weight: isCurrent ? .semibold : .regular)
      ]))
      config.baseForegroundColor = isCurrent ? .label : .secondaryLabel
      config.background.backgroundColor = isCurrent ? UIColor.label.withAlphaComponent(0.14) : .clear
      config.background.cornerRadius = 7
      config.titleLineBreakMode = .byTruncatingTail
      button.configuration = config
      button.accessibilityLabel = "Session \(labels[button.tag])"
      button.accessibilityTraits = isCurrent ? [.button, .selected] : [.button]
    }

    layoutIfNeeded()
    if let current = _stack.arrangedSubviews.first(where: { $0.tag == selected }) {
      _scroll.scrollRectToVisible(current.frame.insetBy(dx: -24, dy: 0), animated: !rebuild)
    }
  }

  @objc private func _tapped(_ sender: UIButton) {
    onSelect?(sender.tag)
  }
}
