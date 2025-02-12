//
//  FreshtabViewController.swift
//  Client
//
//  Created by Sahakyan on 12/6/16.
//  Copyright © 2016 Mozilla. All rights reserved.
//

import Foundation
import SnapKit
import Storage
import Shared
import Alamofire
import SwiftyJSON

struct FreshtabViewUX {

    static let TopSitesMinHeight: CGFloat = 95.0
    static let TopSitesMaxHeight: CGFloat = 185.0
	static let TopSitesCellSize = CGSize(width: 76, height: 86)
	static let TopSitesCountOnRow = 4
	static let TopSitesOffset = 5.0
	
	static let ForgetModeTextColor = UIColor(rgb: 0x999999)
	static let ForgetModeOffset = 50.0

	static let NewsViewMinHeight: CGFloat = 26.0
	static let NewsCellHeight: CGFloat = 68.0
	static let MinNewsCellsCount = 2
    static let topOffset: CGFloat = 10.0
	static let bottomOffset: CGFloat = 45.0
}

class FreshtabViewController: UIViewController, UIGestureRecognizerDelegate {
    
	var profile: Profile!
	var isForgetMode = false {
		didSet {
			self.updateView()
		}
	}
    fileprivate let configUrl = "https://api.cliqz.com/api/v1/config"
    fileprivate let newsUrl = "https://api.cliqz.com/api/v2/rich-header?"
	fileprivate let breakingNewsKey = "breaking"
	fileprivate let localNewsKey = "local_label"

	// TODO: Change topSitesCollection to optional
	fileprivate var topSitesCollection: UICollectionView?
	fileprivate var newsTableView: UITableView?

	fileprivate lazy var emptyTopSitesHint: UILabel = {
		let lbl = UILabel()
		lbl.text = NSLocalizedString("Empty TopSites hint", tableName: "Cliqz", comment: "Hint on Freshtab when there is no topsites")
		lbl.font = UIFont.systemFont(ofSize: 12)
		lbl.textColor = UIColor.white
		lbl.textAlignment = .center
		return lbl
	}()
    fileprivate var scrollView: UIScrollView!
	fileprivate var normalModeView: UIView!
	fileprivate var normalModeBgImage: UIImageView?

	fileprivate var forgetModeView: UIView!

	static var isNewsExpanded = true
    var expandNewsbutton = UIButton()
	var topSites = [[String: String]]()
    var topSitesIndexesToRemove = [Int]()
	var news = [[String: Any]]()
    var region = SettingsPrefs.shared.getRegionPref()

	weak var delegate: SearchViewDelegate?
    
    var startTime : Double = Date.getCurrentMillis()
    var isLoadCompleted = false
    var scrollCount = 0
    var isScrollable = false

	init(profile: Profile) {
		super.init(nibName: nil, bundle: nil)
		self.profile = profile
        NotificationCenter.default.addObserver(self, selector: #selector(loadTopsites), name: NotificationPrivateDataClearedHistory, object: nil)
	}

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(cancelActions))
		tapGestureRecognizer.delegate = self
		self.view.addGestureRecognizer(tapGestureRecognizer)
        loadRegion()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
        startTime = Date.getCurrentMillis()
        
        isLoadCompleted = false
        region = SettingsPrefs.shared.getRegionPref()
        
        restoreToInitialState()
        updateView()
        if !isForgetMode {
            self.loadNews()
            self.loadTopsites()
        }
		
        self.updateViewConstraints()
        scrollCount = 0
	}
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        logHideSignal()
        logScrollSignal()
    }

	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
		super.viewWillTransition(to: size, with: coordinator)
		self.topSitesCollection?.collectionViewLayout.invalidateLayout()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
			self?.normalModeBgImage?.image = UIImage.freshtabBackgroundImage()
            self?.updateViewConstraints()
        }
	}

	override func viewWillLayoutSubviews() {
		super.viewWillLayoutSubviews()
		self.topSitesCollection?.collectionViewLayout.invalidateLayout()
	}

	func restoreToInitialState() {
        if !isForgetMode {
            self.newsTableView?.reloadData()
        }
	}

	override func updateViewConstraints() {
		super.updateViewConstraints()
        // topsites hint
        if self.topSites.count == 0 && SettingsPrefs.shared.getShowTopSitesPref() {
            self.emptyTopSitesHint.isHidden = false
        } else {
            self.emptyTopSitesHint.isHidden = true
        }

        // topsites collection
        let topSitesHeight = getTopSitesHeight()
        self.topSitesCollection?.snp.updateConstraints({ (make) in
            make.height.equalTo(topSitesHeight)
        })
        
        // news table
        let newsHeight = getNewsHeight()
        self.newsTableView?.snp.updateConstraints({ (make) in
            make.height.equalTo(newsHeight)
        })
		
        if !isForgetMode {
            // normalModeView height
            let invisibleFreshTabHeight = getInvisibleFreshTabHeight(topSitesHeight: topSitesHeight, newsHeight: newsHeight)
            let normalModeViewHeight = self.view.bounds.height + invisibleFreshTabHeight
           
            self.normalModeView.snp.remakeConstraints({ (make) in
                make.top.left.bottom.right.equalTo(scrollView)
                make.width.equalTo(self.view)
                make.height.equalTo(normalModeViewHeight)
            })
			self.normalModeBgImage?.snp.remakeConstraints({ (make) in
				make.left.right.top.bottom.equalTo(self.view)
			})
        }
	}

    private func getTopSitesHeight() -> CGFloat {
        guard SettingsPrefs.shared.getShowTopSitesPref() else {
            return 0.0
        }
        
        if self.topSites.count > FreshtabViewUX.TopSitesCountOnRow && !UIDevice.current.isSmallIphoneDevice() {
            return FreshtabViewUX.TopSitesMaxHeight
            
        } else {
            return FreshtabViewUX.TopSitesMinHeight
        }
    }

    private func getNewsHeight() -> CGFloat {
        guard SettingsPrefs.shared.getShowNewsPref() && self.news.count != 0 else {
            return 0.0
        }
        
        var newsHeight = FreshtabViewUX.NewsViewMinHeight
        if let newsTableView = self.newsTableView {
            let rowsCount = CGFloat(self.tableView(newsTableView, numberOfRowsInSection: 0))
            newsHeight += rowsCount * FreshtabViewUX.NewsCellHeight
        }
        return newsHeight
    }

    private func getInvisibleFreshTabHeight(topSitesHeight: CGFloat, newsHeight: CGFloat) -> CGFloat {

        let viewHeight = self.view.bounds.height - FreshtabViewUX.bottomOffset
        var freshTabHeight = topSitesHeight + newsHeight + 10.0
        if topSitesHeight > 0 { freshTabHeight += FreshtabViewUX.topOffset }
        if newsHeight > 0 { freshTabHeight += FreshtabViewUX.topOffset}
        if freshTabHeight > viewHeight {
            isScrollable = true
            return freshTabHeight - viewHeight
        } else {
            return 10.0
        }
        
    }

	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
		if gestureRecognizer is UITapGestureRecognizer {
			let location = touch.location(in: self.topSitesCollection)
			if let index = self.topSitesCollection?.indexPathForItem(at: location),
				let cell = self.topSitesCollection?.cellForItem(at: index) as? TopSiteViewCell {
				return cell.isDeleteMode
			}
			return true
		}
		return false
	}

    @objc fileprivate func cancelActions(_ sender: UITapGestureRecognizer) {
		if !isForgetMode {
			self.removeDeletedTopSites()
			
			// fire `didSelectRowAtIndexPath` when user click on a cell in news table
			let p = sender.location(in: self.newsTableView)
			if let selectedIndex = self.newsTableView?.indexPathForRow(at: p) {
				self.tableView(self.newsTableView!, didSelectRowAt: selectedIndex)
			}
		}
		self.delegate?.dismissKeyboard()
	}

    fileprivate func removeDeletedTopSites() {
		if let cells = self.topSitesCollection?.visibleCells as? [TopSiteViewCell] {
			for cell in cells {
				cell.isDeleteMode = false
			}
			
			self.topSitesIndexesToRemove.sort{a,b in a > b} //order in descending order to avoid index mismatches
			for index in self.topSitesIndexesToRemove {
				self.topSites.remove(at: index)
			}
			
            logTopsiteEditModeSignal()
			self.topSitesIndexesToRemove.removeAll()
			self.topSitesCollection?.reloadData()
			self.updateViewConstraints()
		}
    }

	fileprivate func constructForgetModeView() {
		if forgetModeView == nil {
			self.forgetModeView = UIView()
			self.forgetModeView.backgroundColor = UIColor.clear
			let blurEffect = UIVisualEffectView(effect: UIBlurEffect(style: .light))
			self.forgetModeView.addSubview(blurEffect)
			self.forgetModeView.snp.makeConstraints({ (make) in
				make.top.left.right.bottom.equalTo(self.forgetModeView)
			})
			let bgView = UIImageView(image: UIImage(named: "forgetModeFreshtabBgImage"))
			self.forgetModeView.addSubview(bgView)
			bgView.snp.makeConstraints { (make) in
				make.left.right.top.bottom.equalTo(self.forgetModeView)
			}

			self.view.backgroundColor = UIColor.clear
			self.view.addSubview(forgetModeView)
			self.forgetModeView.snp.makeConstraints({ (make) in
				make.top.left.bottom.right.equalTo(self.view)
			})
			let iconImg = UIImage(named: "forgetModeIcon")
			let forgetIcon = UIImageView(image: iconImg!.withRenderingMode(.alwaysTemplate))
			forgetIcon.tintColor = UIColor(white: 1, alpha: 0.57)
			self.forgetModeView.addSubview(forgetIcon)
			forgetIcon.snp.makeConstraints({ (make) in
				make.top.equalTo(self.forgetModeView).offset(FreshtabViewUX.ForgetModeOffset)
				make.centerX.equalTo(self.forgetModeView)
			})

			let title = UILabel()
			title.text = NSLocalizedString("Forget Tab", tableName: "Cliqz", comment: "Title on Freshtab for forget mode")
			title.numberOfLines = 1
			title.textAlignment = .center
			title.font = UIFont.boldSystemFont(ofSize: 19)
			title.textColor = UIColor(white: 1, alpha: 0.57)
			self.forgetModeView.addSubview(title)
			title.snp.makeConstraints({ (make) in
				make.top.equalTo(forgetIcon.snp.bottom).offset(20)
				make.left.right.equalTo(self.forgetModeView)
				make.height.equalTo(20)
			})
			
			let description = UILabel()
			description.text = NSLocalizedString("Forget Tab Description", tableName: "Cliqz", comment: "Description on Freshtab for forget mode")
			self.forgetModeView.addSubview(description)
			description.numberOfLines = 0
			description.textAlignment = .center
			description.font = UIFont.systemFont(ofSize: 13)
			description.textColor = UIColor(white: 1, alpha: 0.57)
			description.textColor = FreshtabViewUX.ForgetModeTextColor
			description.snp.makeConstraints({ (make) in
				make.top.equalTo(title.snp.bottom).offset(FreshtabViewUX.topOffset)
				make.left.equalTo(self.forgetModeView).offset(FreshtabViewUX.ForgetModeOffset)
				make.right.equalTo(self.forgetModeView).offset(-FreshtabViewUX.ForgetModeOffset)
			})
		}
	}
	
	fileprivate func constructNormalModeView() {
		if self.normalModeView == nil {
            self.scrollView = UIScrollView()
            self.scrollView.delegate = self
            self.view.addSubview(self.scrollView)
            self.scrollView.snp.makeConstraints({ (make) in
                make.top.left.bottom.right.equalTo(self.view)
            })
			self.normalModeView = UIView()
			self.normalModeView.backgroundColor = UIColor.clear
			self.scrollView.addSubview(self.normalModeView)
			self.normalModeView.snp.makeConstraints({ (make) in
				make.top.left.bottom.right.equalTo(scrollView)
                make.height.width.equalTo(self.view)
			})
			let bgView = UIImageView(image: UIImage.freshtabBackgroundImage())
			self.view.addSubview(bgView)
            self.view.sendSubview(toBack: bgView)
			bgView.snp.makeConstraints { (make) in
				make.left.right.top.bottom.equalTo(self.view)
			}
			self.normalModeBgImage = bgView

            self.normalModeView.addSubview(self.emptyTopSitesHint)
            self.emptyTopSitesHint.snp.makeConstraints({ (make) in
                make.top.equalTo(self.normalModeView).offset(8)
                make.left.right.equalTo(self.normalModeView)
                make.height.equalTo(14)
            })
		}
		if self.topSitesCollection == nil {
			self.topSitesCollection = UICollectionView(frame: CGRect.zero, collectionViewLayout: UICollectionViewFlowLayout())
			self.topSitesCollection?.delegate = self
			self.topSitesCollection?.dataSource = self
			self.topSitesCollection?.backgroundColor = UIColor.clear
			self.topSitesCollection?.register(TopSiteViewCell.self, forCellWithReuseIdentifier: "TopSite")
			self.topSitesCollection?.isScrollEnabled = false
			self.normalModeView.addSubview(self.topSitesCollection!)
			self.topSitesCollection?.snp.makeConstraints { (make) in
				make.top.equalTo(self.normalModeView).offset(FreshtabViewUX.topOffset)
				make.left.equalTo(self.normalModeView).offset(FreshtabViewUX.TopSitesOffset)
				make.right.equalTo(self.normalModeView).offset(-FreshtabViewUX.TopSitesOffset)
				make.height.equalTo(FreshtabViewUX.TopSitesMinHeight)
			}
            self.topSitesCollection?.accessibilityLabel = "topSites"
		}
		
		if self.newsTableView == nil {
			self.newsTableView = UITableView(frame: CGRect.zero, style: .grouped)
			self.newsTableView?.delegate = self
			self.newsTableView?.dataSource = self
			self.newsTableView?.backgroundColor = UIColor.clear
			self.normalModeView.addSubview(self.newsTableView!)
//			self.newsTableView?.isHidden = true
			self.newsTableView?.tableFooterView = UIView(frame: CGRect.zero)
			self.newsTableView?.layer.cornerRadius = 9.0
			self.newsTableView?.isScrollEnabled = false
			self.newsTableView?.snp.makeConstraints { (make) in
				make.left.equalTo(self.view).offset(21)
				make.right.equalTo(self.view).offset(-21)
				make.height.equalTo(FreshtabViewUX.NewsViewMinHeight)
				make.top.equalTo(self.topSitesCollection!.snp.bottom).offset(FreshtabViewUX.topOffset)
			}
			newsTableView?.register(NewsViewCell.self, forCellReuseIdentifier: "NewsCell")
			newsTableView?.separatorStyle = .singleLine
            self.newsTableView?.accessibilityLabel = "topNews"
		}
	}

	fileprivate func updateView() {
		if isForgetMode {
			self.constructForgetModeView()
			self.forgetModeView.isHidden = false
			self.normalModeView?.isHidden = true
			self.normalModeBgImage?.isHidden = true
		} else {
			self.constructNormalModeView()
			self.normalModeView.isHidden = false
			self.forgetModeView?.isHidden = true
			self.normalModeBgImage?.isHidden = false
		}
	}

	@objc fileprivate func loadTopsites() {
        guard SettingsPrefs.shared.getShowTopSitesPref() else {
            return
        }
        
		let _ = self.loadTopSitesWithLimit(15)
        //self.topSitesCollection?.reloadData()
	}
    
    fileprivate func loadRegion() {
        guard region == nil  else {
            return
        }
        
		Alamofire.request(configUrl, method: .get, parameters: nil, encoding: JSONEncoding.default, headers: nil).responseJSON { (response) in
            if response.result.isSuccess {
				if let data = response.result.value as? [String: Any] {
					if let location = data["location"] as? String, let backends = data["backends"] as? [String], backends.contains(location) {
						self.region = location.uppercased()
						self.loadNews()
					} else {
						self.region = SettingsPrefs.shared.getDefaultRegion()
					}
					SettingsPrefs.shared.updateRegionPref(self.region!)
				}
            }
        }
    }

	fileprivate func loadNews() {
        guard SettingsPrefs.shared.getShowNewsPref() else {
            return
        }
        
		let data = ["q": "",
		            "results": [[ "url": "rotated-top-news.cliqz.com",  "snippet":[String:String]()]]
		] as [String : Any]

        var uri  = "path=/v2/map&q=&lang=N/A&locale=\(Locale.current.identifier)&adult=0&loc_pref=ask&platform=1&sub_platform=11"
		if let r = self.region {
			uri += "&country=\(r)"
		}
		if let coord = LocationManager.sharedInstance.getApproximateUserLocation() {
			uri += "&loc=\(coord.coordinate.latitude),\(coord.coordinate.longitude)"
		}

		Alamofire.request(newsUrl + uri, method: .put, parameters: data, encoding: JSONEncoding.default, headers: nil).responseJSON { (response) in
			if response.result.isSuccess {
				if let data = response.result.value as? [String: Any],
					let result = data["results"] as? [[String: Any]] {
					if let snippet = result[0]["snippet"] as? [String: Any],
						let extra = snippet["extra"] as? [String: Any],
						let articles = extra["articles"] as? [[String: Any]]
						{
                            // remove old news
                            self.news.removeAll()
							// Temporary filter to avoid reuters crashing UIWebview on iOS 10.3.2/10.3.3
							self.news = articles
							self.newsTableView?.reloadData()
                            self.updateViewConstraints()
                            if !self.isLoadCompleted {
                                self.isLoadCompleted = true
                                self.logShowSignal()
                            }
					}
				}
			} else {
//				print(response.result.error)
			}
		}
	}

	fileprivate func loadTopSitesWithLimit(_ limit: Int) -> Success {
		return self.profile.history.getTopSitesWithLimit(limit).bindQueue(DispatchQueue.main) { result in
			//var results = [[String: String]]()
			if let r = result.successValue {
				self.topSites.removeAll()
				var filter = Set<String>()
				for site in r {
					if let url = URL(string: site!.url),
						let host = url.host {
						if !filter.contains(host) {
							var d = Dictionary<String, String>()
							d["url"] = site!.url
							d["title"] = site!.title
							filter.insert(host)
							self.topSites.append(d)
						}
					}
				}
			}
			self.updateViewConstraints()
            self.topSitesCollection?.reloadData()
            
			return succeed()
		}
	}

	@objc fileprivate func toggoleShowMoreNews() {
		self.delegate?.dismissKeyboard()
		FreshtabViewController.isNewsExpanded = !FreshtabViewController.isNewsExpanded
        
        self.updateViewConstraints()
        FreshtabViewController.isNewsExpanded ? showMoreNews() : showLessNews()
        
        if FreshtabViewController.isNewsExpanded {
            expandNewsbutton.setTitle(NSLocalizedString("LessNews", tableName: "Cliqz", comment: "Title to expand news stream"), for: .normal)
        } else {
            expandNewsbutton.setTitle(NSLocalizedString("MoreNews", tableName: "Cliqz", comment: "Title to expand news stream"), for: .normal)
        }
		self.logNewsViewModifiedSignal(isExpanded: FreshtabViewController.isNewsExpanded)
	}

	private func showMoreNews() {
        let indexPaths = getExtraNewsIndexPaths()
        self.newsTableView?.insertRows(at:indexPaths, with: .automatic)
	}
    
    private func showLessNews() {
        let indexPaths = getExtraNewsIndexPaths()
        self.newsTableView?.deleteRows(at:indexPaths, with: .automatic)
    }
    
    private func getExtraNewsIndexPaths() -> [IndexPath] {
        var indexPaths = [IndexPath]()
        for i in FreshtabViewUX.MinNewsCellsCount..<self.news.count {
            indexPaths.append(IndexPath(row: i, section: 0))
        }
        return indexPaths
    }
}

extension FreshtabViewController: UITableViewDataSource, UITableViewDelegate, UIScrollViewDelegate {
	
	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return FreshtabViewController.isNewsExpanded ? self.news.count : FreshtabViewUX.MinNewsCellsCount
	}
	
	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = self.newsTableView?.dequeueReusableCell(withIdentifier: "NewsCell", for: indexPath) as! NewsViewCell
		if indexPath.row < self.news.count {
			var n = self.news[indexPath.row]
			let title = NSMutableAttributedString()
			if let b = n[breakingNewsKey] as? NSNumber,
				let t = n["breaking_label"] as? String, b.boolValue == true {
				title.append(NSAttributedString(string: t.uppercased() + ": ", attributes: [NSForegroundColorAttributeName: UIColor(rgb: 0xE64C66)]))
			} else if let local = n[localNewsKey] as? String {
				title.append(NSAttributedString(string: local.uppercased() + ": ", attributes: [NSForegroundColorAttributeName: UIConstants.CliqzThemeColor]))
			}
			if let t = n["short_title"] as? String {
				title.append(NSAttributedString(string: t))
			} else if let t = n["title"] as? String {
				title.append(NSAttributedString(string: t))
			}
			cell.titleLabel.attributedText = title
			if let domain = n["domain"] as? String {
				cell.URLLabel.text = domain
			} else if let title = n["title"] as? String {
				cell.URLLabel.text =  title
			}
            
            cell.tag = indexPath.row
            
			if let domain = n["domain"] as? String {
                let domainUrl = "http://www.\(domain)"
                LogoLoader.loadLogo(domainUrl, completionBlock: { (image, logoInfo, error) in
					if cell.tag == indexPath.row {
						if let img = image {
							cell.logoImageView.image = img
						}
						else if let info = logoInfo {
							let placeholder = LogoPlaceholder(logoInfo: info)
							cell.fakeLogoView = placeholder
							cell.logoContainerView.addSubview(placeholder)
							placeholder.snp.makeConstraints({ (make) in
								make.top.left.right.bottom.equalTo(cell.logoContainerView)
							})
						}
					}
				})
			}
		}
		cell.selectionStyle = .none
		return cell
	}
	
	func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
		return FreshtabViewUX.NewsCellHeight
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard SettingsPrefs.shared.getShowNewsPref() else { return }
        
		if indexPath.row < self.news.count {
			let selectedNews = self.news[indexPath.row]
			let urlString = selectedNews["url"] as? String
			if let url = URL(string: urlString!) {
				delegate?.didSelectURL(url, searchQuery: nil)
			} else if let url = URL(string: urlString!.escapeURL()) {
				delegate?.didSelectURL(url, searchQuery: nil)
			}
            if let currentCell = tableView.cellForRow(at: indexPath) as? ClickableUITableViewCell {
                let target = getNewsTarget(selectedNews)
                logNewsSignal(target, element: currentCell.clickedElement, index: indexPath.row)
			}
		}
	}
    private func getNewsTarget(_ selectedNews: [String: Any]) -> String {
        var target = "topnews"
        if let isBreakingNews = selectedNews[breakingNewsKey] as? Bool, isBreakingNews == true {
            target  = "breakingnews"
        }
        if let _ = selectedNews[localNewsKey] as? String {
            target = "localnews"
        }
        return target
    }
    
	func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		let headerAlpha: CGFloat = 0.6
		let v = UIView()
//		v.backgroundColor = UIColor(colorString: "D1D1D2")
		v.backgroundColor = UIColor.white.withAlphaComponent(0.8)
		let logo = UIImageView(image: UIImage(named: "freshtabIcon"))
		v.addSubview(logo)
		logo.snp.makeConstraints { (make) in
			make.top.equalTo(v).offset(4)
			make.left.equalTo(v).offset(7)
			make.height.width.equalTo(20)
		}
		let l = UILabel()
		l.text = NSLocalizedString("NEWS", tableName: "Cliqz", comment: "Title to expand news stream")
		l.textColor = UIColor.black.withAlphaComponent(headerAlpha)
		l.font = UIFont.systemFont(ofSize: 13)
		v.addSubview(l)
		l.snp.makeConstraints { (make) in
			make.left.equalTo(logo.snp.right).offset(7)
			make.top.equalTo(v)
			make.height.equalTo(27)
			make.right.equalTo(v)
		}
		expandNewsbutton = UIButton()
		v.addSubview(expandNewsbutton)
		expandNewsbutton.contentHorizontalAlignment = .right
		expandNewsbutton.snp.makeConstraints { (make) in
			make.top.equalTo(v).offset(-2)
			make.right.equalTo(v).offset(-9)
			make.height.equalTo(30)
			make.width.equalTo(v).dividedBy(2)
		}
        if FreshtabViewController.isNewsExpanded {
            expandNewsbutton.setTitle(NSLocalizedString("LessNews", tableName: "Cliqz", comment: "Title to expand news stream"), for: .normal)
        } else {
            expandNewsbutton.setTitle(NSLocalizedString("MoreNews", tableName: "Cliqz", comment: "Title to expand news stream"), for: .normal)
        }
		expandNewsbutton.titleLabel?.font = UIFont.systemFont(ofSize: 13)
		expandNewsbutton.titleLabel?.textAlignment = .right
		expandNewsbutton.setTitleColor(UIColor.black.withAlphaComponent(headerAlpha), for: .normal)
		expandNewsbutton.addTarget(self, action: #selector(toggoleShowMoreNews), for: .touchUpInside)
		return v
	}

	func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
		return 1.0
	}

	func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
		var rect = CGRect.zero
		rect.size.height = 1
		return UIView(frame: rect)
	}

	func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		return 27.0
	}
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        self.delegate?.dismissKeyboard()
        scrollCount += 1
    }
}

extension FreshtabViewController: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
	
	public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if UIDevice.current.isSmallIphoneDevice() {
            return FreshtabViewUX.TopSitesCountOnRow
        }
		return self.topSites.count > FreshtabViewUX.TopSitesCountOnRow ? 2 * FreshtabViewUX.TopSitesCountOnRow : FreshtabViewUX.TopSitesCountOnRow
	}
	
	public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "TopSite", for: indexPath) as! TopSiteViewCell
		cell.tag = -1
		cell.delegate = self
		if indexPath.row < self.topSites.count {
			cell.tag = indexPath.row
			let s = self.topSites[indexPath.row]
			if let url = s["url"] {
				LogoLoader.loadLogo(url, completionBlock: { (img, logoInfo, error) in
					if cell.tag == indexPath.row {
						if let img = img {
							cell.logoImageView.image = img
						}
						else if let info = logoInfo {
							let placeholder = LogoPlaceholder(logoInfo: info)
							cell.fakeLogoView = placeholder
							cell.logoContainerView.addSubview(placeholder)
							placeholder.snp.makeConstraints({ (make) in
								make.top.left.right.bottom.equalTo(cell.logoContainerView)
							})
						}
						cell.logoHostLabel.text = logoInfo?.hostName
					}
				})
			}
		}
		if cell.gestureRecognizers == nil {
			let longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(deleteTopSites(_:)))
			cell.addGestureRecognizer(longPressGestureRecognizer)
	 	}
        cell.tag = indexPath.row
		return cell
	}

	@objc private func deleteTopSites(_ gestureReconizer: UILongPressGestureRecognizer)  {
		let cells = self.topSitesCollection?.visibleCells
		for cell in cells as! [TopSiteViewCell] {
			cell.isDeleteMode = true
		}
        
        if let index = gestureReconizer.view?.tag {
            logTopsiteSignal(action: "longpress", index: index)
        }
	}

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard SettingsPrefs.shared.getShowTopSitesPref() else { return }
        
		if indexPath.row < self.topSites.count && !self.topSitesIndexesToRemove.contains(indexPath.row) {
			let s = self.topSites[indexPath.row]
			if let urlString = s["url"] {
				if let url = URL(string: urlString) {
					delegate?.didSelectURL(url, searchQuery: nil)
				} else if let url = URL(string: urlString.escapeURL()) {
					delegate?.didSelectURL(url, searchQuery: nil)
				}
                
                logTopsiteSignal(action: "click", index: indexPath.row)
			}
		}
	}
	
	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
		return FreshtabViewUX.TopSitesCellSize
	}
	
	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
		return 3.0
	}

	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
		return UIEdgeInsetsMake(10, sideInset(collectionView), 0, sideInset(collectionView))
	}
	
	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
		return cellSpacing(collectionView)
	}
    
    func sideInset(_ collectionView: UICollectionView) -> CGFloat {
        //Constraint = cellSpacing should never be negative
        let v = collectionView.frame.size.width - CGFloat(FreshtabViewUX.TopSitesCountOnRow) * FreshtabViewUX.TopSitesCellSize.width
        
        if v > 0 {
            let inset = v / 5.0
            return floor(inset)
        }
        
        return 0.0
    }
    
    func cellSpacing(_ collectionView: UICollectionView) -> CGFloat{
        let inset = sideInset(collectionView)
        if inset > 1.0 {
            return inset - 1
        }
        return 0.0
    }
}

extension FreshtabViewController: TopSiteCellDelegate {

	func topSiteHided(_ index: Int) {
		let s = self.topSites[index]
		if let url = s["url"] {
			let _ = self.profile.history.hideTopSite(url)
		}

		self.topSitesIndexesToRemove.append(index)
		logDeleteTopsiteSignal(index)

		if self.topSites.count == self.topSitesIndexesToRemove.count {
			self.removeDeletedTopSites()
        }
	}
}

// extension for telemetry signals
extension FreshtabViewController {
    fileprivate func logTopsiteSignal(action: String, index: Int) {
        guard isForgetMode == false else { return }
        
        let customData: [String: Any] = ["topsite_count": topSites.count, "index": index]
        self.logFreshTabSignal(action, target: "topsite", customData: customData)
    }
    
    fileprivate func logDeleteTopsiteSignal(_ index: Int) {
        guard isForgetMode == false else { return }
        
        let customData: [String: Any] = ["index": index]
        self.logFreshTabSignal("click", target: "delete_topsite", customData: customData)
    }
    
    fileprivate func logTopsiteEditModeSignal() {
        guard isForgetMode == false else { return }
        
        let customData: [String: Any] = ["topsite_count": topSites.count, "delete_count": topSitesIndexesToRemove.count, "view": "topsite_edit_mode"]
        self.logFreshTabSignal("click", target: nil, customData: customData)
    }
    
    fileprivate func logNewsSignal(_ target: String, element: String, index: Int) {
        guard isForgetMode == false else { return }
        
        let customData: [String: Any] = ["element": element, "index": index]
        self.logFreshTabSignal("click", target: target, customData: customData)
    }

	fileprivate func breakingNewsCount() -> Int {
		let breakingNews = news.filter() {
			if let breaking = ($0 as NSDictionary)[breakingNewsKey] as? Bool {
				return breaking
			}
			return false
		}
		return breakingNews.count
	}

	fileprivate func localNewsCount() -> Int {
		let localNews = news.filter() {
			if let _ = ($0 as NSDictionary)[localNewsKey] as? String {
				return true
			}
			return false
		}
		return localNews.count
	}

    fileprivate func logShowSignal() {
        guard isForgetMode == false else { return }

        let loadDuration = Int(Date.getCurrentMillis() - startTime)
        var customData: [String: Any] = ["topsite_count": topSites.count, "load_duration": loadDuration]
        let breakingNewsCount = self.breakingNewsCount()
        let localNewsCount = self.localNewsCount()
        
        if isLoadCompleted {
            customData["is_complete"] = true
            customData["topnews_available_count"] = news.count - breakingNewsCount - localNewsCount
            customData["topnews_count"] = min(news.count, FreshtabViewUX.MinNewsCellsCount) - breakingNewsCount - localNewsCount
            customData["breakingnews_count"] = breakingNewsCount
			customData["localnews_count"] = localNewsCount
        } else {
            customData["is_complete"] = false
            customData["topnews_available_count"] = 0
            customData["topnews_count"] = 0
            customData["breakingnews_count"] = 0
			customData["localnews_count"] = 0
        }
        customData["is_topsites_on"] = SettingsPrefs.shared.getShowTopSitesPref()
        customData["is_news_on"] = SettingsPrefs.shared.getShowNewsPref()
        logFreshTabSignal("show", target: nil, customData: customData)
    }
    
    fileprivate func logHideSignal() {
        guard isForgetMode == false else { return }
        
        if !isLoadCompleted {
            logShowSignal()
        }
        let showDuration = Int(Date.getCurrentMillis() - startTime)
        logFreshTabSignal("hide", target: nil, customData: ["show_duration": showDuration])
    }

	fileprivate func logNewsViewModifiedSignal(isExpanded expanded: Bool) {
        guard isForgetMode == false else { return }
        
		let target = expanded ? "show_more" : "show_less"
		let customData: [String: Any] = ["view": "news"]
		logFreshTabSignal("click", target: target, customData: customData)
	}

    private func logFreshTabSignal(_ action: String, target: String?, customData: [String: Any]?) {
        guard isForgetMode == false else { return }
        
        TelemetryLogger.sharedInstance.logEvent(.FreshTab(action, target, customData))
    }
    
    fileprivate func logScrollSignal() {
        guard isForgetMode == false else { return }
        
        guard scrollCount > 0 else {
            return
        }
        
        let customData: [String: Any] = ["scroll_count": scrollCount, "is_scrollable" : isScrollable]
        TelemetryLogger.sharedInstance.logEvent(.FreshTab("scroll", nil, customData))

    }

}
