//
//  FilterDetail.swift
//  Filterpedia
//
//  Created by Simon Gladman on 29/12/2015.
//  Copyright © 2015 Simon Gladman. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.

//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>

import UIKit

class FilterDetail: UIView
{

    var delegate: FilterDetailDelegate?

    let rect640x640 = CGRect(x: 0, y: 0, width: 640, height: 640)
    let activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .whiteLarge)
    
    let compositeOverBlackFilter = CompositeOverBlackFilter()
    
    let shapeLayer: CAShapeLayer =
    {
        let layer = CAShapeLayer()
        
        layer.strokeColor = UIColor.lightGray.cgColor
        layer.fillColor = nil
        layer.lineWidth = 0.5
        
        return layer
    }()
    
    let tableView: UITableView =
    {
        let tableView = UITableView(frame: CGRect.zero,
            style: UITableViewStyle.plain)
        
        tableView.register(FilterInputItemRenderer.self,
            forCellReuseIdentifier: "FilterInputItemRenderer")
        
        return tableView
    }()
    
    let scrollView = UIScrollView()
    
    lazy var histogramToggleSwitch: UISwitch =
    {
        let toggle = UISwitch()
        
        toggle.isOn = !self.histogramDisplayHidden
        toggle.addTarget(
            self,
            action: #selector(FilterDetail.toggleHistogramView),
            for: .valueChanged)
        
        return toggle
    }()

    lazy var shareButton: UIButton = {
        let button = UIButton()
        button.setImage(UIImage(named: "share"), for: .normal)
        button.addTarget(self, action: #selector(shareButtonClicked), for: .touchUpInside)

        return button
    }()
    
    let histogramDisplay = HistogramDisplay()
    
    var histogramDisplayHidden = true
    {
        didSet
        {
            if !histogramDisplayHidden
            {
                self.histogramDisplay.imageRef = imageView.image?.cgImage
            }
            
            UIView.animate(withDuration: 0.25, animations: {
                self.histogramDisplay.alpha = self.histogramDisplayHidden ? 0 : 1
            })
            
        }
    }
    
    let imageView: UIImageView =
    {
        let imageView = UIImageView()
        
        imageView.backgroundColor = UIColor.black
        
        imageView.layer.borderColor = UIColor.gray.cgColor
        imageView.layer.borderWidth = 1
        
        return imageView
    }()
    
    #if !arch(i386) && !arch(x86_64)
    let ciMetalContext = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!)
    #else
        let ciMetalContext = CIContext()
    #endif
    
    let ciOpenGLESContext = CIContext()
  
    /// Whether the user has changed the filter whilst it's
    /// running in the background.
    var pending = false

    /// The next filter to apply as an index of currentFilters
    var nextFilter = 0

    var defaultImage = assets.first!.ciImage

    /// The last image with already applied filters
    var lastImage: CIImage? = nil
    
    /// Whether a filter is currently running in the background
    var busy = false
    {
        didSet
        {
            if busy
            {
                activityIndicator.startAnimating()
            }
            else
            {
                activityIndicator.stopAnimating()
            }
        }
    }
    
    var filterNames: [String] = []
    {
        didSet
        {
            updateFromFilterName()
        }
    }
    
    fileprivate var currentFilters: [(filter: CIFilter, parameters: [String: AnyObject])] = []
    
    /// User defined filter parameter values
    // fileprivate var filterParameterValues: [String: AnyObject] = [kCIInputImageKey: assets.first!.ciImage]
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        tableView.dataSource = self
        tableView.delegate = self
 
        addSubview(tableView)
        
        addSubview(scrollView)
        scrollView.addSubview(imageView)
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 6.0
        scrollView.delegate = self
        
        histogramDisplay.alpha = histogramDisplayHidden ? 0 : 1
        histogramDisplay.layer.shadowOffset = CGSize(width: 0, height: 0)
        histogramDisplay.layer.shadowOpacity = 0.75
        histogramDisplay.layer.shadowRadius = 5
        addSubview(histogramDisplay)
        
        addSubview(histogramToggleSwitch)

        addSubview(shareButton)
        
        imageView.addSubview(activityIndicator)
        
        layer.addSublayer(shapeLayer)
    }
    
    required init?(coder aDecoder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func toggleHistogramView()
    {
       histogramDisplayHidden = !histogramToggleSwitch.isOn
    }

    @objc func shareButtonClicked() {
        var first = true
        var lastFilterName = ""

        // text to share
        var text = ""
        for i in 0..<currentFilters.count {
            let filter = currentFilters[i]

            let name: String
            if i == currentFilters.count - 1 {
                name = "lastFilter"
            } else {
                name = "filter\(filter.filter.name)"
            }
            text += """
            // Filter \(filter.filter.name)
            let \(name) = CIFilter(name: "\(filter.filter.name)")
            """

            let parameters = filter.parameters.filter({ isIncluded in
                if let _ = filter.filter.attributes[isIncluded.key] as? [String : AnyObject] {
                    return true
                } else {
                    return false
                }
            })
            for (key, value) in parameters {
                text.append("\n")
                if key == "inputImage" {
                    if first {
                        text.append("// Please replace originalImage with your own input CIImage")
                        text.append("\(name)?.setValue(originalImage, forKey: \"\(key)\")")
                        first = false
                    } else {
                        text.append("\(name)?.setValue(\(lastFilterName)!.outputImage!, forKey: \"\(key)\")")
                    }
                } else if key == "defaultImage" {
                } else if value is CIImage {
                } else {
                    var value = "\(value)"
                    value = value.replacingOccurrences(of: " ", with: ", ")
                    text.append("\(name)?.setValue(\(value), forKey: \"\(key)\")")
                }
            }

            lastFilterName = name
            text.append("\n\n")
        }

        // set up activity view controller
        let textToShare = [text]
        let activityViewController = UIActivityViewController(activityItems: textToShare, applicationActivities: nil)
        activityViewController.popoverPresentationController?.sourceView = shareButton.imageView

        // present the view controller
        delegate?.present(activityViewController)
    }
    
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
    
    func updateFromFilterName()
    {
        let oldFilters = currentFilters
        currentFilters = []

        // ????????
        // Remove old attributes
        imageView.subviews
            .filter({ $0 is FilterAttributesDisplayable})
            .forEach({ $0.removeFromSuperview() })

        if filterNames.count == 0 {
            imageView.image = nil
        }

        for filterName in filterNames {
            guard let filter = CIFilter(name: filterName) else
            {
                return
            }

            if var widget = OverlayWidgets.getOverlayWidgetForFilter(filterName)
            {
                widget.filterName = filterName
                if let w = widget as? UIView {
                    imageView.addSubview(w)
                    w.frame = imageView.bounds
                }
            }

            var parameters = oldFilters.first(where: { $0.filter.name == filter.name })?.parameters ?? [:]
            parameters["defaultImage"] = defaultImage
            currentFilters.append((filter: filter, parameters: parameters))
        }

        fixFilterParameterValues()

        tableView.reloadData()

        applyFilter()
    }
    
    /// Assign a default image if required and ensure existing
    /// filterParameterValues won't break the new filter.
    func fixFilterParameterValues()
    {
        var newFilters: [(filter: CIFilter, parameters: [String: AnyObject])] = []

        for var currentFilter in currentFilters {
            let attributes = currentFilter.filter.attributes

            for inputKey in currentFilter.filter.inputKeys
            {
                if let attribute = attributes[inputKey] as? [String : AnyObject]
                {
                    // default image
                    if let className = attribute[kCIAttributeClass] as? String, className == "CIImage" && currentFilter.parameters[inputKey] == nil
                    {
                        currentFilter.parameters[inputKey] = assets.first!.ciImage
                    }

                    // ensure previous values don't exceed kCIAttributeSliderMax for this filter
                    if let maxValue = attribute[kCIAttributeSliderMax] as? Float,
                        let filterParameterValue = currentFilter.parameters[inputKey] as? Float, filterParameterValue > maxValue
                    {
                        currentFilter.parameters[inputKey] = maxValue as AnyObject?
                    }

                    // ensure vector is correct length
                    if let defaultVector = attribute[kCIAttributeDefault] as? CIVector,
                        let filterParameterValue = currentFilter.parameters[inputKey] as? CIVector, defaultVector.count != filterParameterValue.count
                    {
                        currentFilter.parameters[inputKey] = defaultVector
                    }
                }
            }

            newFilters.append(currentFilter)
        }

        currentFilters = newFilters
    }

    func applyFilter()
    {
        guard !busy else
        {
            pending = true
            return
        }
        
        guard let currentFilter = self.currentFilters[safe: nextFilter] else
        {
            // For next apply...
            nextFilter = 0
            lastImage = nil
            return
        }
        nextFilter += 1
        
        busy = true
        
        imageView.subviews
            .filter({ view in
                return view is FilterAttributesDisplayable && (view as! FilterAttributesDisplayable).filterName == currentFilter.filter.name
            })
            .forEach({ ($0 as? FilterAttributesDisplayable)?.setFilter(currentFilter.filter) })
        
        let queue = currentFilter is VImageFilter ?
            DispatchQueue.main :
            DispatchQueue.global()
        
        queue.async
        {
            let startTime = CFAbsoluteTimeGetCurrent()
            
            for (key, value) in currentFilter.parameters where currentFilter.filter.inputKeys.contains(key)
            {
                currentFilter.filter.setValue(value, forKey: key)
            }
            // ?????? Last one pls
            let inputImage: CIImage
            if let i = self.lastImage {
                inputImage = i
            } else {
                inputImage = self.defaultImage
            }
            currentFilter.filter.setValue(inputImage, forKey: kCIInputImageKey)
            
            let outputImage = currentFilter.filter.outputImage!
            let finalImage: CGImage
  
            let context = (currentFilter is MetalRenderable) ? self.ciMetalContext : self.ciOpenGLESContext
            
            if outputImage.extent.width == 1 || outputImage.extent.height == 1
            {
                // if a filter's output image height or width is 1,
                // (e.g. a reduction filter) stretch to 640x640
                
                let stretch = CIFilter(name: "CIStretchCrop",
                    withInputParameters: ["inputSize": CIVector(x: 640, y: 640),
                        "inputCropAmount": 0,
                        "inputCenterStretchAmount": 1,
                        kCIInputImageKey: outputImage])!
                
                finalImage = context.createCGImage(stretch.outputImage!,
                    from: self.rect640x640)!
            }
            else if outputImage.extent.width < 640 || outputImage.extent.height < 640
            {
                // if a filter's output image is smaller than 640x640 (e.g. circular wrap or lenticular
                // halo), composite the output over a black background)
                
                self.compositeOverBlackFilter.setValue(outputImage,
                    forKey: kCIInputImageKey)
                
                finalImage = context.createCGImage(self.compositeOverBlackFilter.outputImage!,
                    from: self.rect640x640)!
            }
            else
            {
                finalImage = context.createCGImage(outputImage,
                    from: self.rect640x640)!
            }
            
            let endTime = (CFAbsoluteTimeGetCurrent() - startTime)
            
            DispatchQueue.main.async
            {
                if !self.histogramDisplayHidden
                {
                    self.histogramDisplay.imageRef = finalImage
                }

                let imImage = UIImage(cgImage: finalImage)
                self.imageView.image = imImage
                self.lastImage = CIImage(cgImage: finalImage)
                self.busy = false
                
                if self.pending
                {
                    self.pending = false
                    self.nextFilter = 0
                    self.applyFilter()
                } else {
                    // Apply the next filter. If none it will return
                    self.applyFilter()
                }
            }
        }
    }
    
    override func layoutSubviews()
    {
        let halfWidth = frame.width * 0.5
        let thirdHeight = frame.height * 0.333
        let twoThirdHeight = frame.height * 0.666
        
        scrollView.frame = CGRect(x: halfWidth - thirdHeight,
            y: 0,
            width: twoThirdHeight,
            height: twoThirdHeight)
        
        imageView.frame = CGRect(x: 0,
            y: 0,
            width: scrollView.frame.width,
            height: scrollView.frame.height)
        
        tableView.frame = CGRect(x: 0,
            y: twoThirdHeight,
            width: frame.width,
            height: thirdHeight)
        
        histogramDisplay.frame = CGRect(
            x: 0,
            y: thirdHeight,
            width: frame.width,
            height: thirdHeight).insetBy(dx: 5, dy: 5)
        
        histogramToggleSwitch.frame = CGRect(
            x: frame.width - histogramToggleSwitch.intrinsicContentSize.width,
            y: 0,
            width: intrinsicContentSize.width,
            height: intrinsicContentSize.height)

        shareButton.frame = CGRect(
            x: frame.width - histogramToggleSwitch.intrinsicContentSize.width / 2 - 64 / 2,
            y: histogramToggleSwitch.frame.height,
            width: 64,
            height: 64
        )
        
        tableView.separatorStyle = UITableViewCellSeparatorStyle.none
        
        activityIndicator.frame = imageView.bounds
        
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: frame.height))
        
        shapeLayer.path = path.cgPath
    }
}

// MARK: UITableViewDelegate extension

extension FilterDetail: UITableViewDelegate
{
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat
    {
        return 85
    }
}

// MARK: UITableViewDataSource extension

extension FilterDetail: UITableViewDataSource
{

    func numberOfSections(in tableView: UITableView) -> Int {
        return currentFilters.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
    {
        return currentFilters[section].filter.inputKeys.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
    {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FilterInputItemRenderer",
            for: indexPath) as! FilterInputItemRenderer

        let inputKey = currentFilters[indexPath.section].filter.inputKeys[indexPath.row]
        if let attribute = currentFilters[indexPath.section].filter.attributes[inputKey] as? [String : AnyObject]
        {
            cell.detail = (inputKey: inputKey,
                attribute: attribute,
                filterParameterValues: currentFilters[indexPath.section].parameters)
            cell.section = currentFilters[indexPath.section].filter.name
        }
        
        cell.delegate = self
        
        return cell
    }

    func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        return currentFilters.map({ return $0.filter.name })
    }
}

// MARK: FilterInputItemRendererDelegate extension

extension FilterDetail: FilterInputItemRendererDelegate
{
    func filterInputItemRenderer(_ filterInputItemRenderer: FilterInputItemRenderer, didChangeValue: AnyObject?, forKey: String?)
    {
        if let key = forKey, let value = didChangeValue
        {
            if key == kCIInputImageKey {
                defaultImage = value as! CIImage

                var newFilters: [(filter: CIFilter, parameters: [String: AnyObject])] = []

                for var filter in currentFilters {
                    filter.parameters["defaultImage"] = defaultImage
                    newFilters.append(filter)
                }

                self.currentFilters = newFilters

                applyFilter()
            } else {
                let section = filterInputItemRenderer.section
                var newFilters: [(filter: CIFilter, parameters: [String: AnyObject])] = []

                for i in 0..<currentFilters.count {
                    var filter = currentFilters[i]

                    if filter.filter.name == section {
                        filter.parameters[key] = value
                    }

                    newFilters.append(filter)
                }

                self.currentFilters = newFilters

                applyFilter()
            }
        }
    }
    
    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool
    {
        return false
    }
}

protocol FilterDetailDelegate {

    func present(_ vc: UIViewController)
}

extension Array {

    subscript(safe safe: Int) -> Element? {
        if safe >= count {
            return nil
        }

        return self[safe]
    }
}
