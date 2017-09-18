//
//  BSCalendarView.swift
//  blurryssky
//
//  Created by 张亚东 on 16/4/26.
//  Copyright © 2016年 doyen. All rights reserved.
//

import UIKit

private enum UserScrollDirection {
    case left
    case right
}

private struct UIConstants {
    static let bottomMargin: CGFloat = 10
}

public class BSCalendarView: UIView {
    
    // MARK: - Public Properties
    
    public fileprivate(set) var preference = BSCalendarPreference()
    
    // closures
    public var heightDidChangeClosure: ((CGFloat) -> Void)?
    public var didScrollXFractionClosure: ((CGFloat) -> Void)? // range 0.01 ~ 0.99
    public var currentMonthDidChangeClosure: ((Int) -> Void)?
    public var dayDidSelectedClosure: ((BSCalendarDay) -> Void)?
    
    public fileprivate(set) var currentDisplayingMonth: BSCalendarMonth! {
        didSet {
            if oldValue != nil,
            currentDisplayingMonth.date != oldValue.date {
                currentMonthDidChangeClosure?(currentDisplayingMonth.date.month)
            }
        }
    }
    public fileprivate(set) var willDisplayingMonth: BSCalendarMonth?
    /// this item would be different with 'currentDisplayingMonth' only while scrolling
    public fileprivate(set) var didDisplayingMonth: BSCalendarMonth!
    
    public fileprivate(set) var selectedDay: BSCalendarDay?
    
    // MARK: - UI
    public lazy var monthSelectView: BSCalendarMonthSelectView = {
        let msv = BSCalendarMonthSelectView()
        msv.preference = self.preference
        msv.previousMonthButtonClosure = {
            self.handlePreviousMonthButton()
        }
        msv.nextMonthButtonClosure = {
            self.handleNextMonthButton()
        }
        return msv
    }()
    
    public lazy var weekLabels: [UILabel] = {
        return self.preference.weekTitles.map {
            let weekLabel: UILabel = UILabel()
            weekLabel.text = $0
            weekLabel.textAlignment = .center
            weekLabel.font = self.preference.weekTitlesFont
            weekLabel.textColor = self.preference.weekTitlesTextColor
            return weekLabel
        }
    }()
    
    public lazy var collectionView: UICollectionView = {
        
        let flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = 0
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.scrollDirection = .horizontal
        
        let c : UICollectionView = UICollectionView(frame: CGRect.zero, collectionViewLayout: flowLayout)
        c.register(BSCalendarMonthCollectionCell.self, forCellWithReuseIdentifier: "BSCalendarCollectionCell")
        c.dataSource = self
        c.delegate = self
        c.backgroundColor = UIColor.clear
        c.isPagingEnabled = true
        c.showsHorizontalScrollIndicator = false
        return c
    }()
    
    // MARK: - Private Properties
    
    fileprivate var scrollDirection: UserScrollDirection = .left
    
    fileprivate var shouldUpdateFrame = true
    
    fileprivate lazy var calendarManager = BSCalendarManager()
    
    // MARK: - Override

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        guard shouldUpdateFrame == true else {
            return
        }
        updateFrame()
        scrollToCurrentDisplayingMonth()
    }
    
}

extension BSCalendarView {
    
    func setCalendarPreference(_ preference: BSCalendarPreference) {
        self.preference = preference
        
        monthSelectView.preference = preference
        calendarManager.monthRange = preference.monthSelectRange
        setupCurrentDisplayingMonth()
        updateFrame()
        
        monthSelectView.update(month: currentDisplayingMonth)
        
        guard preference.weekTitles.count <= 7 else {
            return
        }
        for (index, title) in preference.weekTitles.enumerated() {
            let weekLabel = weekLabels[index]
            weekLabel.text = title
            weekLabel.textColor = preference.weekTitlesTextColor
            weekLabel.font = preference.weekTitlesFont
        }
    }
}

// MARK: - Initialize
fileprivate extension BSCalendarView {
    
    func setup() {

        backgroundColor = UIColor.white
        
        setupCurrentDisplayingMonth()
        monthSelectView.update(month: currentDisplayingMonth)
        setupSubviews()
    }
    
    func setupCurrentDisplayingMonth() {
        
        if let nowCalendarMonth = calendarManager.nowCalendarMonth {
            currentDisplayingMonth = nowCalendarMonth
        } else {
            currentDisplayingMonth = calendarManager.calendarMonths.first!
        }
        didDisplayingMonth = currentDisplayingMonth
    }
    
    func setupSubviews() {
 
        addSubview(monthSelectView)
        weekLabels.forEach {
            addSubview($0)
        }
        addSubview(collectionView)
    }
    
    func scrollToCurrentDisplayingMonth() {
        
        let optionalIndex = calendarManager.calendarMonths.index {
            $0.date.month == currentDisplayingMonth.date.month
        }
        guard let index = optionalIndex else {
           return
        }
        collectionView.setContentOffset(CGPoint(x: collectionView.bs.width * CGFloat(index), y: 0), animated: false)
    }
}

// MARK: - Private
fileprivate extension BSCalendarView {
    
    func updateFrame() {
        
        if preference.isMonthSelectHidden {
            monthSelectView.isHidden = true
        } else {
            monthSelectView.isHidden = false
            monthSelectView.frame = CGRect(origin: .zero, size: .init(width: bs.width, height: preference.monthSelectRowHeight))
        }
        
        let weekLabelWidth = bs.width/7
        let weekLabelOriginY = preference.isMonthSelectHidden ? 0 : preference.monthSelectRowHeight
        for (index, label) in weekLabels.enumerated() {
            label.frame = CGRect(x: weekLabelWidth * CGFloat(index), y: weekLabelOriginY, width: weekLabelWidth, height: preference.weekRowHeight)
        }
        
        // the calendar max rows is 6
        collectionView.frame = CGRect(x: 0, y: headerHeight , width: bs.width, height: 6 * preference.dayRowHeight)
        
        bs.height = heightForCalendarMonth(currentDisplayingMonth)
        
        heightDidChangeClosure?(bs.height)
        
        collectionView.reloadData()
    }
    
    func updateCurrentDisplayingMonth() {
        
        let offsetX = collectionView.contentOffset.x
        let width = collectionView.bs.width
        var index = Int(round(Float(offsetX/width)))
        index = max(preference.monthSelectRange.lowerBound - 1, min(preference.monthSelectRange.upperBound - 1, index))
        
        currentDisplayingMonth = calendarManager.calendarMonths[index]
    }
    
    func updateHeightContinuous() {
        let scrollView = collectionView
        
        guard scrollView.contentOffset.x < scrollView.contentSize.width,
            scrollView.contentOffset.x > 0 else {
            return
        }
        
        let fraction = scrollView.contentOffset.x / scrollView.bs.width
        var percentage: CGFloat = 0
        if scrollDirection == .right {
            percentage = fraction - floor(fraction)
        } else {
            percentage = 1 - (fraction - floor(fraction))
        }
        
        guard percentage >= 0.01 && percentage <= 0.99 else {
            return
        }
        didScrollXFractionClosure?(percentage)
        
        guard let willDisplayingMonth = willDisplayingMonth else {
            return
        }
        
        let toHeight = heightForCalendarMonth(willDisplayingMonth)
        let fromHeight = heightForCalendarMonth(didDisplayingMonth)
        let subHeight = toHeight - fromHeight
        
        bs.height = fromHeight + subHeight * percentage
        heightDidChangeClosure?(bs.height)
    }
}

fileprivate extension BSCalendarView {
    
    func handlePreviousMonthButton() {
        shouldUpdateFrame = false
        
        let displayingMonth = currentDisplayingMonth.date.month
        let previousMonth = displayingMonth - 1
        let index = CGFloat(previousMonth - preference.monthSelectRange.lowerBound)
        collectionView.setContentOffset(CGPoint(x: collectionView.bs.width * index, y: 0), animated: true)
    }
    
    func handleNextMonthButton() {
        shouldUpdateFrame = false
        
        let displayingMonth = currentDisplayingMonth.date.month
        let nextMonth = displayingMonth + 1
        let index = CGFloat(nextMonth - preference.monthSelectRange.lowerBound)
        collectionView.setContentOffset(CGPoint(x: collectionView.bs.width * index, y: 0), animated: true)
    }
}

// MARK: - Help
fileprivate extension BSCalendarView {
    
    var headerHeight: CGFloat {
        return (preference.isMonthSelectHidden ? 0 : preference.monthSelectRowHeight) + preference.weekRowHeight
    }
    
    func heightForCalendarMonth(_ calendarMonth: BSCalendarMonth) -> CGFloat {
        return CGFloat(ceil(Double(calendarMonth.days.count)/7)) * preference.dayRowHeight + headerHeight + UIConstants.bottomMargin
    }
    
}

extension BSCalendarView: UICollectionViewDataSource {
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return calendarManager.calendarMonths.count
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "BSCalendarCollectionCell", for: indexPath) as! BSCalendarMonthCollectionCell
        
        cell.preference = preference
        cell.calendarMonth = calendarManager.calendarMonths[indexPath.row]
        
        cell.dayDidSelectedClosure = { [unowned self] day in
            self.dayDidSelectedClosure?(day)

            self.selectedDay?.isSelected = false
            self.selectedDay = day
        }
        return cell
    }
}

extension BSCalendarView: UICollectionViewDelegate {

    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        
        willDisplayingMonth = calendarManager.calendarMonths[indexPath.row]
        
        let optionalIndex = calendarManager.calendarMonths.index {
            $0.date.month == currentDisplayingMonth.date.month
        }
        guard let index = optionalIndex else {
            return
        }
        if indexPath.row - index > 0 {
            scrollDirection = .right
        } else {
            scrollDirection = .left
        }
    }
}

extension BSCalendarView: UIScrollViewDelegate {
    
    private func updateAfterScroll() {
        updateCurrentDisplayingMonth()
        monthSelectView.update(month: currentDisplayingMonth)
        bs.height = heightForCalendarMonth(currentDisplayingMonth)
        didDisplayingMonth = currentDisplayingMonth
    }
    
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateAfterScroll()
    }
    
    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        updateAfterScroll()
    }
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateHeightContinuous()
    }
    
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        shouldUpdateFrame = false
    }
}

extension BSCalendarView: UICollectionViewDelegateFlowLayout {
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return collectionView.bs.size
    }
}





