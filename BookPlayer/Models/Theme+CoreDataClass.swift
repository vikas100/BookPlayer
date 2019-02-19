//
//  Theme+CoreDataClass.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 5/14/18.
//  Copyright © 2018 Tortuga Power. All rights reserved.
//
//

import ColorCube
import CoreData
import Foundation

enum ArtworkColorsError: Error {
    case averageColorFailed
}

public class Theme: NSManagedObject {
    var useDarkVariant = false

    func sameColors(as theme: Theme) -> Bool {
        return self.defaultBackgroundHex == theme.defaultBackgroundHex
            && self.defaultPrimaryHex == theme.defaultPrimaryHex
            && self.defaultSecondaryHex == theme.defaultSecondaryHex
            && self.defaultAccentHex == theme.defaultAccentHex
    }

    convenience init(params: [String: String], context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "Theme", in: context)!
        self.init(entity: entity, insertInto: context)

        self.defaultBackgroundHex = params["defaultBackground"]
        self.defaultPrimaryHex = params["defaultPrimary"]
        self.defaultSecondaryHex = params["defaultSecondary"]
        self.defaultAccentHex = params["defaultAccent"]
        self.darkBackgroundHex = params["darkBackground"]
        self.darkPrimaryHex = params["darkPrimary"]
        self.darkSecondaryHex = params["darkSecondary"]
        self.darkAccentHex = params["darkAccent"]
        self.title = params["title"]
    }

    // W3C recommends contrast values larger 4 or 7 (strict), but 3.0 should be fine for our use case
    convenience init(from image: UIImage, context: NSManagedObjectContext, darknessThreshold: CGFloat = 0.2, minimumContrastRatio: CGFloat = 3.0) {
        do {
            let entity = NSEntityDescription.entity(forEntityName: "Theme", in: context)!

            self.init(entity: entity, insertInto: context)

            let colorCube = CCColorCube()
            var colors: [UIColor] = colorCube.extractColors(from: image, flags: CCOnlyDistinctColors, count: 4)!

            guard let averageColor = image.averageColor() else {
                throw ArtworkColorsError.averageColorFailed
            }

            let displayOnDark = averageColor.luminance < darknessThreshold

            colors.sort { (color1: UIColor, color2: UIColor) -> Bool in
                if displayOnDark {
                    return color1.isDarker(than: color2)
                }

                return color1.isLighter(than: color2)
            }

            let backgroundColor: UIColor = colors[0]

            colors = colors.map { (color: UIColor) -> UIColor in
                let ratio = color.contrastRatio(with: backgroundColor)

                if ratio > minimumContrastRatio || color == backgroundColor {
                    return color
                }

                if displayOnDark {
                    return color.overlayWhite
                }

                return color.overlayBlack
            }

            self.setColorsFromArray(colors, displayOnDark: displayOnDark)
        } catch {
            self.setColorsFromArray()
        }
    }

    func setColorsFromArray(_ colors: [UIColor] = [], displayOnDark: Bool = false) {
        var colorsToSet = Array(colors)

        if colorsToSet.isEmpty {
            colorsToSet.append(UIColor(hex: "#FFFFFF")) // background
            colorsToSet.append(UIColor(hex: "#37454E")) // primary
            colorsToSet.append(UIColor(hex: "#3488D1")) // secondary
            colorsToSet.append(UIColor(hex: "#7685B3")) // tertiary
        } else if colorsToSet.count < 4 {
            let placeholder = displayOnDark ? UIColor.white : UIColor.black

            for _ in 1...(4 - colorsToSet.count) {
                colorsToSet.append(placeholder)
            }
        }

        let lightSorted = colorsToSet.sorted { (c1, c2) -> Bool in
            return c2.isDarker(than: c1)
        }

        let darkSorted = colorsToSet.sorted { (c1, c2) -> Bool in
            return c1.isDarker(than: c2)
        }

        // background
        self.darkBackgroundHex = self.getBackgroundColor(from: darkSorted, darkVariant: true) ?? "050505"
        self.defaultBackgroundHex = self.getBackgroundColor(from: lightSorted, darkVariant: false) ?? "FAFAFA"

        // primary
        self.darkPrimaryHex = self.getPrimaryColor(from: darkSorted,
                                                   backgroundColor: self.darkBackgroundColor,
                                                   darkVariant: true) ?? "EEEEEE"
        self.defaultPrimaryHex = self.getPrimaryColor(from: lightSorted,
                                                      backgroundColor: self.defaultBackgroundColor,
                                                      darkVariant: false) ?? "111111"

        // tertiary
        self.darkAccentHex = self.getHighlightColor(from: darkSorted,
                                                    backgroundColor: self.darkBackgroundColor,
                                                    darkVariant: true) ?? "7685B3"
        self.defaultAccentHex = self.getHighlightColor(from: lightSorted,
                                                       backgroundColor: self.defaultBackgroundColor,
                                                       darkVariant: false) ?? "7685B3"

        // secondary
        self.defaultSecondaryHex = self.defaultPrimaryColor.overlayBlack.cssHex
        self.darkSecondaryHex = self.darkPrimaryColor.overlayWhite.cssHex
    }

    // Default colors
    convenience init(context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "Theme", in: context)!
        self.init(entity: entity, insertInto: context)

        self.setColorsFromArray()
    }

    func getBackgroundColor(from colors: [UIColor], darkVariant: Bool) -> String? {
        let color = colors.first { (color) -> Bool in
            //let saturationCondition = color.saturation < 0.5
            let brightnessCondition = darkVariant
                ? color.brightness < 0.3
                : color.brightness > 0.8

            return brightnessCondition // && saturationCondition
        }

        guard color == nil else { return color!.cssHex }

        guard let peakColor = colors.last else { return nil }

        // Handle no color meeting standard conditions

        let overlayedColor = darkVariant
            ? peakColor.overlayBlack
            : peakColor.overlayWhite

        let saturationCondition = overlayedColor.saturation < 0.5

        let brightnessCondition = darkVariant
            ? overlayedColor.brightness < 0.3
            : overlayedColor.brightness > 0.8

        guard saturationCondition && brightnessCondition else { return nil }

        return overlayedColor.cssHex
    }

    func getPrimaryColor(from colors: [UIColor], backgroundColor: UIColor, darkVariant: Bool) -> String? {
        let color = colors.first { (color) -> Bool in
            let contrastCondition = color.contrastRatio(with: backgroundColor) > 13
            let brightnessCondition = darkVariant
                ? color.brightness > 0.8
                : color.brightness < 0.3

            return brightnessCondition && contrastCondition
        }

        guard color == nil else { return color!.cssHex }

        guard let peakColor = colors.last else { return nil }

        // Handle no color meeting standard conditions

        let overlayedColor = darkVariant
            ? peakColor.overlayWhite
            : peakColor.overlayBlack

        let contrastCondition = overlayedColor.contrastRatio(with: backgroundColor) > 13

        let brightnessCondition = darkVariant
            ? overlayedColor.brightness < 0.8
            : overlayedColor.brightness > 0.3

        guard contrastCondition && brightnessCondition else { return nil }

        return overlayedColor.cssHex
    }

    func getHighlightColor(from colors: [UIColor], backgroundColor: UIColor, darkVariant: Bool) -> String? {
        let candidates = colors.compactMap { (color) -> UIColor? in
            if color.brightness < backgroundColor.brightness {
                print(color.cssHex)
                return color
            }

            return nil
        }

        let primaryColor = darkVariant
            ? UIColor(hex: self.darkPrimaryHex)
            : UIColor(hex: self.defaultPrimaryHex)

        let finalSort = colors.sorted { (c1, c2) -> Bool in
            return c2.contrastRatio(with: primaryColor) > c1.contrastRatio(with: primaryColor)
        }

        return finalSort.first?.cssHex
    }
}

// MARK: - Color getters

extension Theme {
    var defaultBackgroundColor: UIColor {
        return UIColor(hex: self.defaultBackgroundHex)
    }

    var darkBackgroundColor: UIColor {
        return UIColor(hex: self.darkBackgroundHex)
    }

    var defaultPrimaryColor: UIColor {
        return UIColor(hex: self.defaultPrimaryHex)
    }

    var darkPrimaryColor: UIColor {
        return UIColor(hex: self.darkPrimaryHex)
    }

    var defaultSecondaryColor: UIColor {
        return UIColor(hex: self.defaultSecondaryHex)
    }

    var defaultAccentColor: UIColor {
        return UIColor(hex: self.defaultAccentHex)
    }

    var backgroundColor: UIColor {
        let hex: String = self.useDarkVariant
            ? self.darkBackgroundHex
            : self.defaultBackgroundHex
        return UIColor(hex: hex)
    }

    var primaryColor: UIColor {
        let hex: String = self.useDarkVariant
            ? self.darkPrimaryHex
            : self.defaultPrimaryHex
        return UIColor(hex: hex)
    }

    var secondaryColor: UIColor {
        let hex: String = self.useDarkVariant
            ? self.darkSecondaryHex
            : self.defaultSecondaryHex
        return UIColor(hex: hex)
    }

    var detailColor: UIColor {
        return self.secondaryColor
    }

    var highlightColor: UIColor {
        let hex: String = self.useDarkVariant
            ? self.darkAccentHex
            : self.defaultAccentHex
        return UIColor(hex: hex)
    }

    var lightHighlightColor: UIColor {
        return self.highlightColor.withAlpha(newAlpha: 0.3)
    }

    var importBackgroundColor: UIColor {
        return self.secondaryColor.overlay(with: self.backgroundColor, using: 0.83)
    }

    var separatorColor: UIColor {
        return self.secondaryColor.overlay(with: self.backgroundColor, using: 0.51)
    }

    var settingsBackgroundColor: UIColor {
        return self.secondaryColor.overlay(with: self.highlightColor, using: 0.17).overlay(with: self.backgroundColor, using: 0.88)
    }

    var pieFillColor: UIColor {
        return self.secondaryColor.overlay(with: self.backgroundColor, using: 0.27)
    }

    var pieBorderColor: UIColor {
        return self.secondaryColor.overlay(with: self.backgroundColor, using: 0.51)
    }

    var pieBackgroundColor: UIColor {
        return self.secondaryColor.overlay(with: self.backgroundColor, using: 0.90)
    }

    var highlightedPieFillColor: UIColor {
        return self.highlightColor.overlay(with: self.backgroundColor, using: 0.27)
    }

    var highlightedPieBorderColor: UIColor {
        return self.highlightColor.overlay(with: self.backgroundColor, using: 0.51)
    }

    var highlightedPieBackgroundColor: UIColor {
        return self.highlightColor.overlay(with: self.backgroundColor, using: 0.90)
    }

    var navigationTitleColor: UIColor {
        return self.primaryColor.overlay(with: self.highlightColor, using: 0.12).overlay(with: self.backgroundColor, using: 0.11)
    }
}
